import cocotb

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


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


    # TinyMind neurons

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


    # ------------------------------------------------------------
    # Winner selection
    #
    # Tie priority:
    #
    # AI
    # Hardware
    # Creative
    # ------------------------------------------------------------

    if score_ai >= score_hw and score_ai >= score_cr:

        predicted_class = CLASS_AI

        winning_score = score_ai
        second_score = max(score_hw, score_cr)


    elif score_hw >= score_cr:

        predicted_class = CLASS_HARDWARE

        winning_score = score_hw
        second_score = max(score_ai, score_cr)


    else:

        predicted_class = CLASS_CREATIVE

        winning_score = score_cr
        second_score = max(score_ai, score_hw)


    margin = winning_score - second_score


    # Hardware clamps confidence at 9

    confidence = min(margin, 9)


    close_prediction = 1 if margin <= 1 else 0


    return (
        predicted_class,
        confidence,
        close_prediction
    )


# ================================================================
# HELPER:
# SET REGISTER ADDRESS
# ================================================================

def set_address(dut, address):

    current = int(dut.uio_in.value)

    # Clear address bits [1:0]

    current &= ~0b11

    # Set new address

    current |= address

    dut.uio_in.value = current


# ================================================================
# HELPER:
# WRITE A REGISTER
# ================================================================

async def bus_write(dut, address, data):

    # ------------------------------------------------------------
    # Address
    # ------------------------------------------------------------

    value = address


    # ------------------------------------------------------------
    # uio_in[2] = write enable
    # ------------------------------------------------------------

    value |= (1 << 2)


    dut.uio_in.value = value

    dut.ui_in.value = data


    # ------------------------------------------------------------
    # Register captures on rising edge
    # ------------------------------------------------------------

    await RisingEdge(dut.clk)


    # ------------------------------------------------------------
    # Remove write enable
    # ------------------------------------------------------------

    dut.uio_in.value = address


    # Give signals some settling time

    await FallingEdge(dut.clk)


# ================================================================
# HELPER:
# READ A REGISTER
# ================================================================

async def bus_read(dut, address):

    # Write enable = 0

    dut.uio_in.value = address


    # Read combinational output safely between clock edges

    await FallingEdge(dut.clk)


    return int(dut.uo_out.value)


# ================================================================
# MAIN TEST
# ================================================================

@cocotb.test()
async def test_tinymind_peripheral(dut):

    dut._log.info(
        "Starting TinyMind memory-mapped accelerator test"
    )


    # ============================================================
    # CLOCK
    #
    # 100 ns period = 10 MHz
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
    # INITIAL VALUES
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
    # TEST ALL 256 POSSIBLE FEATURE INPUTS
    # ============================================================

    for features in range(256):


        # --------------------------------------------------------
        # Calculate expected result using Python
        # --------------------------------------------------------

        (
            expected_class,
            expected_confidence,
            expected_close

        ) = calculate_prediction(features)


        dut._log.info(
            f"Testing features = {features:08b}"
        )


        # ========================================================
        # STEP 1
        #
        # WRITE FEATURE REGISTER
        #
        # address 00
        # ========================================================

        await bus_write(
            dut,
            ADDR_FEATURE,
            features
        )


        # --------------------------------------------------------
        # Optional verification:
        #
        # Read feature register back
        # --------------------------------------------------------

        feature_readback = await bus_read(
            dut,
            ADDR_FEATURE
        )


        assert feature_readback == features, (

            f"Feature register failed: "
            f"wrote {features:08b}, "
            f"read {feature_readback:08b}"

        )


        # ========================================================
        # STEP 2
        #
        # START TINYMIND
        #
        # CONTROL register:
        #
        # bit 0 = 1
        # ========================================================

        await bus_write(
            dut,
            ADDR_CONTROL,
            0b00000001
        )


        # ========================================================
        # STEP 3
        #
        # CHECK BUSY
        #
        # STATUS:
        #
        # bit 0 = done
        # bit 1 = busy
        # ========================================================

        status = await bus_read(
            dut,
            ADDR_STATUS
        )


        busy = (status >> 1) & 1


        assert busy == 1, (

            f"BUSY was not asserted "
            f"for input {features:08b}"

        )


        # ========================================================
        # STEP 4
        #
        # NEXT CLOCK:
        #
        # Result register captures output
        # ========================================================

        await RisingEdge(dut.clk)

        await FallingEdge(dut.clk)


        # ========================================================
        # STEP 5
        #
        # CHECK STATUS
        # ========================================================

        status = await bus_read(
            dut,
            ADDR_STATUS
        )


        done = status & 1

        busy = (status >> 1) & 1


        assert busy == 0, (

            f"BUSY did not clear "
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
        # Decode result byte
        # --------------------------------------------------------

        actual_class = result & 0b11


        actual_confidence = (
            result >> 2
        ) & 0b1111


        actual_close = (
            result >> 6
        ) & 1


        dut._log.info(

            f"features={features:08b} "

            f"class={actual_class:02b} "

            f"confidence={actual_confidence} "

            f"close={actual_close}"

        )


        # ========================================================
        # VERIFY RESULT
        # ========================================================

        assert actual_class == expected_class, (

            f"Class mismatch for "
            f"{features:08b}: "

            f"expected={expected_class:02b}, "

            f"actual={actual_class:02b}"

        )


        assert actual_confidence == expected_confidence, (

            f"Confidence mismatch for "
            f"{features:08b}: "

            f"expected={expected_confidence}, "

            f"actual={actual_confidence}"

        )


        assert actual_close == expected_close, (

            f"Close prediction mismatch for "
            f"{features:08b}: "

            f"expected={expected_close}, "

            f"actual={actual_close}"

        )


        # ========================================================
        # TINYTAPEOUT BIDIRECTIONAL OUTPUTS
        # ========================================================

        assert int(dut.uio_out.value) == 0

        assert int(dut.uio_oe.value) == 0


    dut._log.info(
        "All 256 TinyMind peripheral cases passed"
    )
