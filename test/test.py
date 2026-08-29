import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


SEG_A = 0b1110111
SEG_H = 0b0110111
SEG_C = 0b1001110


def calculate_prediction(features: int):
    x0 = (features >> 0) & 1
    x1 = (features >> 1) & 1
    x2 = (features >> 2) & 1
    x3 = (features >> 3) & 1
    x4 = (features >> 4) & 1
    x5 = (features >> 5) & 1
    x6 = (features >> 6) & 1
    x7 = (features >> 7) & 1

    score_ai = x0 + x1 + x4 - x5 + x7 + 1
    score_hw = x0 + x2 + x3 + x5 - x6
    score_cr = -x1 - x2 + x5 + x6 + x7 + 1

    if score_ai >= score_hw and score_ai >= score_cr:
        predicted_class = "A"
        winning_score = score_ai
        second_score = max(score_hw, score_cr)

    elif score_hw >= score_cr:
        predicted_class = "H"
        winning_score = score_hw
        second_score = max(score_ai, score_cr)

    else:
        predicted_class = "C"
        winning_score = score_cr
        second_score = max(score_ai, score_hw)

    margin = winning_score - second_score

    return predicted_class, margin


def expected_output(predicted_class: str, margin: int):
    if predicted_class == "A":
        segments = SEG_A
    elif predicted_class == "H":
        segments = SEG_H
    else:
        segments = SEG_C

    decimal_point = 1 if margin <= 1 else 0

    return (decimal_point << 7) | segments


@cocotb.test()
async def test_clocked_tinymind(dut):

    dut._log.info("Starting clocked TinyMind test")

    # 100 ns period = 10 MHz
    clock = Clock(dut.clk, 100, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # ------------------------------------------------------------
    # RESET
    # ------------------------------------------------------------

    dut.rst_n.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    # ------------------------------------------------------------
    # TEST ALL 256 INPUT COMBINATIONS
    # ------------------------------------------------------------

    for features in range(256):

        dut.ui_in.value = features

        expected_class, margin = calculate_prediction(features)
        expected = expected_output(expected_class, margin)

        # --------------------------------------------------------
        # PIPELINE BEHAVIOR
        #
        # Rising Edge 1:
        #   ui_in is captured into features_reg
        #
        # Between Edge 1 and Edge 2:
        #   TinyMind calculates:
        #     - AI score
        #     - Hardware score
        #     - Creative score
        #     - Winner
        #     - Confidence margin
        #
        # Rising Edge 2:
        #   predicted_class,
        #   confidence_digit,
        #   close_prediction
        #   are captured into the result registers
        #
        # We then wait until the FALLING edge before checking
        # the outputs. This gives the gate-level circuit time
        # to settle after the result registers change.
        # --------------------------------------------------------

        await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)

        await FallingEdge(dut.clk)

        actual = int(dut.uo_out.value)

        dut._log.info(
            f"features={features:08b} "
            f"class={expected_class} "
            f"margin={margin} "
            f"expected={expected:08b} "
            f"actual={actual:08b}"
        )

        assert actual == expected, (
            f"Failed for input {features:08b}: "
            f"expected {expected:08b}, "
            f"received {actual:08b}"
        )

        assert int(dut.uio_out.value) == 0
        assert int(dut.uio_oe.value) == 0

    dut._log.info("All 256 clocked TinyMind cases passed")
