import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge,Timer


# ================================================================
# REGISTER ADDRESSES
# ================================================================

ADDR_FEATURE = 0b00
ADDR_CONTROL = 0b01
ADDR_STATUS  = 0b10
ADDR_RESULT  = 0b11


# ================================================================
# CLASS ENCODING
# ================================================================

CLASS_AI       = 0b00
CLASS_HARDWARE = 0b01
CLASS_CREATIVE = 0b10


# ================================================================
# SEVEN-SEGMENT VALUES
# ================================================================

SEG_A = 0b1110111

SEG_H = 0b0110111

SEG_C = 0b1001110


# ================================================================
# SOFTWARE REFERENCE MODEL
# ================================================================

def calculate_prediction(features: int):


    x0 = (features >> 0) & 1
    x1 = (features >> 1) & 1
    x2 = (features >> 2) & 1
    x3 = (features >> 3) & 1

    x4 = (features >> 4) & 1
    x5 = (features >> 5) & 1
    x6 = (features >> 6) & 1
    x7 = (features >> 7) & 1


    # ============================================================
    # TinyMind neuron equations
    # ============================================================

    score_ai = (

        x0 +
        x1 +
        x4 -
        x5 +
        x7 +
        1

    )


    score_hw = (

        x0 +
        x2 +
        x3 +
        x5 -
        x6

    )


    score_cr = (

        -x1 -
        x2 +
        x5 +
        x6 +
        x7 +
        1

    )


    # ============================================================
    # WINNER
    #
    # Tie priority:
    #
    # AI
    # Hardware
    # Creative
    # ============================================================


    if score_ai >= score_hw and score_ai >= score_cr:


        predicted_class = CLASS_AI

        winning_score = score_ai

        second_score = max(

            score_hw,

            score_cr

        )


    elif score_hw >= score_cr:


        predicted_class = CLASS_HARDWARE

        winning_score = score_hw

        second_score = max(

            score_ai,

            score_cr

        )


    else:


        predicted_class = CLASS_CREATIVE

        winning_score = score_cr

        second_score = max(

            score_ai,

            score_hw

        )


    # ============================================================
    # CONFIDENCE
    # ============================================================

    margin = (

        winning_score -
        second_score

    )


    confidence = min(

        margin,

        9

    )


    close_prediction = (

        1
        if margin <= 1
        else
        0

    )


    return (

        predicted_class,

        confidence,

        close_prediction

    )


# ================================================================
# EXPECTED SEVEN SEGMENT OUTPUT
# ================================================================

def expected_display(

    predicted_class,

    close_prediction

):


    if predicted_class == CLASS_AI:

        segments = SEG_A


    elif predicted_class == CLASS_HARDWARE:

        segments = SEG_H


    else:

        segments = SEG_C


    return (

        (close_prediction << 7)

        |

        segments

    )


# ================================================================
# BUS WRITE
# ================================================================

async def bus_write(

    dut,

    address,

    data

):


    # ------------------------------------------------------------
    # BUS MODE
    #
    # uio_in[3] = 0
    #
    # WRITE ENABLE
    #
    # uio_in[2] = 1
    # ------------------------------------------------------------

    control = (

        address

        |

        (1 << 2)

    )


    dut.uio_in.value = control

    dut.ui_in.value = data


    # ------------------------------------------------------------
    # Register captures write here
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)


    # ------------------------------------------------------------
    # Disable write
    # ------------------------------------------------------------

    dut.uio_in.value = address


    # ------------------------------------------------------------
    # Safely move away from rising edge
    # ------------------------------------------------------------

    await FallingEdge(dut.clk)


# ================================================================
# BUS READ
# ================================================================

async def bus_read(

    dut,

    address

):


    # ------------------------------------------------------------
    # uio_in[3] = 0
    #
    # therefore BUS MODE
    # ------------------------------------------------------------

    dut.uio_in.value = address


    # ------------------------------------------------------------
    # Sample between clock edges
    # ------------------------------------------------------------

    await FallingEdge(dut.clk)


    return int(

        dut.uo_out.value

    )


# ================================================================
# DISPLAY READ
# ================================================================

async def display_read(dut):

    # uio_in[3] = 1
    # Select seven-segment display mode

    dut.uio_in.value = (1 << 3)

    # Move safely away from clock edge
    await FallingEdge(dut.clk)

    # Give the gate-level output mux / decoder
    # additional time to propagate
    await Timer(20, unit="ns")

    return int(dut.uo_out.value)


# ================================================================
# MAIN TEST
# ================================================================

@cocotb.test()

async def test_tinymind_final(dut):


    dut._log.info(

        "Starting final TinyMind clocked peripheral + display test"

    )


    # ============================================================
    # CLOCK
    #
    # 100 ns period
    #
    # =
    #
    # 10 MHz
    # ============================================================

    clock = Clock(

        dut.clk,

        100,

        unit="ns"

    )


    cocotb.start_soon(

        clock.start()

    )


    # ============================================================
    # INITIAL STATE
    # ============================================================

    dut.ena.value = 1

    dut.ui_in.value = 0

    dut.uio_in.value = 0


    # ============================================================
    # RESET
    # ============================================================

    dut.rst_n.value = 0


    await RisingEdge(dut.clk)

    await RisingEdge(dut.clk)


    dut.rst_n.value = 1


    await RisingEdge(dut.clk)


    # ============================================================
    # TEST ALL 256 INPUT COMBINATIONS
    # ============================================================

    for features in range(256):


        # --------------------------------------------------------
        # Software expected answer
        # --------------------------------------------------------

        (

            expected_class,

            expected_confidence,

            expected_close

        ) = calculate_prediction(

            features

        )


        expected_seg = expected_display(

            expected_class,

            expected_close

        )


        dut._log.info(

            f"Testing features={features:08b}"

        )


        # ========================================================
        # STEP 1
        #
        # WRITE FEATURE REGISTER
        # ========================================================

        await bus_write(

            dut,

            ADDR_FEATURE,

            features

        )


        # ========================================================
        # STEP 2
        #
        # READ FEATURE REGISTER BACK
        # ========================================================

        feature_readback = await bus_read(

            dut,

            ADDR_FEATURE

        )


        assert feature_readback == features, (

            f"Feature register mismatch "

            f"for {features:08b}: "

            f"read={feature_readback:08b}"

        )


        # ========================================================
        # STEP 3
        #
        # START TINYMIND
        # ========================================================

        await bus_write(

            dut,

            ADDR_CONTROL,

            0b00000001

        )


        # ========================================================
        # STEP 4
        #
        # RESULT CAPTURE CLOCK
        #
        # TinyMind combinational logic evaluates between clocks.
        #
        # At this rising edge, result registers capture:
        #
        # class
        # confidence
        # close flag
        # ========================================================

        await RisingEdge(dut.clk)

        await FallingEdge(dut.clk)


        # ========================================================
        # STEP 5
        #
        # READ STATUS
        # ========================================================

        status = await bus_read(

            dut,

            ADDR_STATUS

        )


        done = (

            status & 1

        )


        busy = (

            (status >> 1)

            &

            1

        )


        assert busy == 0, (

            f"BUSY failed to clear "

            f"for input {features:08b}"

        )


        assert done == 1, (

            f"DONE was not asserted "

            f"for input {features:08b}"

        )


        # ========================================================
        # STEP 6
        #
        # READ RESULT REGISTER
        # ========================================================

        result = await bus_read(

            dut,

            ADDR_RESULT

        )


        # --------------------------------------------------------
        # Decode class
        # --------------------------------------------------------

        actual_class = (

            result

            &

            0b11

        )


        # --------------------------------------------------------
        # Decode confidence
        # --------------------------------------------------------

        actual_confidence = (

            (result >> 2)

            &

            0b1111

        )


        # --------------------------------------------------------
        # Decode close flag
        # --------------------------------------------------------

        actual_close = (

            (result >> 6)

            &

            1

        )


        # ========================================================
        # CHECK MEMORY-MAPPED RESULT
        # ========================================================

        assert actual_class == expected_class, (

            f"Class mismatch "

            f"for {features:08b}: "

            f"expected={expected_class:02b}, "

            f"actual={actual_class:02b}"

        )


        assert actual_confidence == expected_confidence, (

            f"Confidence mismatch "

            f"for {features:08b}: "

            f"expected={expected_confidence}, "

            f"actual={actual_confidence}"

        )


        assert actual_close == expected_close, (

            f"Close prediction mismatch "

            f"for {features:08b}: "

            f"expected={expected_close}, "

            f"actual={actual_close}"

        )


        # ========================================================
        # STEP 7
        #
        # TEST SEVEN-SEGMENT DISPLAY MODE
        # ========================================================

        actual_display = await display_read(

            dut

        )


        assert actual_display == expected_seg, (

            f"Seven-segment mismatch "

            f"for {features:08b}: "

            f"expected={expected_seg:08b}, "

            f"actual={actual_display:08b}"

        )


        # ========================================================
        # UNUSED BIDIRECTIONAL OUTPUTS
        # ========================================================

        assert int(

            dut.uio_out.value

        ) == 0


        assert int(

            dut.uio_oe.value

        ) == 0


        # ========================================================
        # LOG SUCCESS
        # ========================================================

        dut._log.info(

            f"features={features:08b} "

            f"class={actual_class:02b} "

            f"confidence={actual_confidence} "

            f"close={actual_close} "

            f"display={actual_display:08b}"

        )


    # ============================================================
    # FINISHED
    # ============================================================

    dut._log.info(

        "All 256 TinyMind cases passed: "
        "clocked inference + peripheral bus + seven-segment display"

    )
