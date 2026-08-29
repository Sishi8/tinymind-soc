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

    # Tie priority:
    # AI > Hardware > Creative

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

    confidence = min(margin, 9)

    close_prediction = 1 if margin <= 1 else 0

    return (
        predicted_class,
        confidence,
        close_prediction
    )


# ================================================================
# BUS WRITE
# ================================================================

async def bus_write(dut, address, data):

    # uio_in[1:0] = address
    # uio_in[2]   = write enable

    dut.uio_in.value = address | (1 << 2)
    dut.ui_in.value = data

    # Register captures write here

    await RisingEdge(dut.clk)

    # Remove write enable immediately after capture

    dut.uio_in.value = address

    # Wait until safely between clock edges

    await FallingEdge(dut.clk)


# ================================================================
# BUS READ
# ================================================================

async def bus_read(dut, address):

    # Select address with write enable OFF

    dut.uio_in.value = address

    # Allow combinational read mux to settle

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
    # 100 ns = 10 MHz
    # ============================================================

    clock = Clock(
        dut.clk,
        100,
        unit="ns"
    )

    cocotb.start_soon(clock.start())


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
    # TEST ALL 256 INPUT COMBINATIONS
    # ============================================================

    for features in range(256):

        (
            expected_class,
            expected_confidence,
            expected_close

        ) = calculate_prediction(features)


        dut._log.info(
            f"Testing features = {features:08b}"
        )


        # ========================================================
        # 1. WRITE FEATURES
        # ========================================================

        await bus_write(
            dut,
            ADDR_FEATURE,
            features
        )


        # ========================================================
        # 2. VERIFY FEATURE REGISTER
        # ========================================================

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
        # 3. START TINYMIND
        # ========================================================

        await bus_write(
            dut,
            ADDR_CONTROL,
            0b00000001
        )


        # ========================================================
        # 4. ALLOW RESULT CLOCK EDGE
        #
        # TinyMind combinational logic works between clocks.
        #
        # At this rising edge:
        #
        # result_class
        # result_confidence
        # result_close
        #
        # are captured.
        # ========================================================

        await RisingEdge(dut.clk)

        await FallingEdge(dut.clk)


        # ========================================================
        # 5. READ STATUS
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
        # 6. READ RESULT
        # ========================================================

        result = await bus_read(
            dut,
            ADDR_RESULT
        )


        # ========================================================
        # DECODE RESULT
        # ========================================================

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
        # CHECK CLASS
        # ========================================================

        assert actual_class == expected_class, (

            f"Class mismatch for "
            f"{features:08b}: "
            f"expected={expected_class:02b}, "
            f"actual={actual_class:02b}"

        )


        # ========================================================
        # CHECK CONFIDENCE
        # ========================================================

        assert actual_confidence == expected_confidence, (

            f"Confidence mismatch for "
            f"{features:08b}: "
            f"expected={expected_confidence}, "
            f"actual={actual_confidence}"

        )


        # ========================================================
        # CHECK CLOSE FLAG
        # ========================================================

        assert actual_close == expected_close, (

            f"Close prediction mismatch for "
            f"{features:08b}: "
            f"expected={expected_close}, "
            f"actual={actual_close}"

        )


        # ========================================================
        # UNUSED TinyTapeout BIDIRECTIONAL OUTPUTS
        # ========================================================

        assert int(dut.uio_out.value) == 0
        assert int(dut.uio_oe.value) == 0


    dut._log.info(
        "All 256 TinyMind peripheral cases passed"
    )
