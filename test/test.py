import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer


# ============================================================================
# SEVEN SEGMENT VALUES
# ============================================================================

SEG_A = 0b1110111
SEG_H = 0b0110111
SEG_C = 0b1001110


# ============================================================================
# CLASS VALUES
# ============================================================================

CLASS_AI = 0
CLASS_HARDWARE = 1
CLASS_CREATIVE = 2


# ============================================================================
# SOFTWARE REFERENCE MODEL
# ============================================================================

def tinymind_reference(features):

    x = [
        (features >> i) & 1
        for i in range(8)
    ]

    score_ai = (
        x[0]
        + x[1]
        + x[4]
        - x[5]
        + x[7]
        + 1
    )

    score_hardware = (
        x[0]
        + x[2]
        + x[3]
        + x[5]
        - x[6]
    )

    score_creative = (
        -x[1]
        - x[2]
        + x[5]
        + x[6]
        + x[7]
        + 1
    )

    # Tie priority:
    # AI > Hardware > Creative

    if (
        score_ai >= score_hardware
        and score_ai >= score_creative
    ):

        winner = CLASS_AI
        winning_score = score_ai
        second_score = max(
            score_hardware,
            score_creative
        )

    elif score_hardware >= score_creative:

        winner = CLASS_HARDWARE
        winning_score = score_hardware
        second_score = max(
            score_ai,
            score_creative
        )

    else:

        winner = CLASS_CREATIVE
        winning_score = score_creative
        second_score = max(
            score_ai,
            score_hardware
        )

    margin = winning_score - second_score

    confidence = min(
        margin,
        9
    )

    close_prediction = (
        margin <= 1
    )

    return (
        winner,
        confidence,
        close_prediction
    )


# ============================================================================
# SEVEN-SEGMENT REFERENCE
# ============================================================================

def expected_segments(class_value):

    if class_value == CLASS_AI:
        return SEG_A

    elif class_value == CLASS_HARDWARE:
        return SEG_H

    elif class_value == CLASS_CREATIVE:
        return SEG_C

    else:
        return 0


# ============================================================================
# RESET
# ============================================================================

async def reset_dut(dut):

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    dut.rst_n.value = 0

    for _ in range(3):
        await RisingEdge(dut.clk)

    dut.rst_n.value = 1

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)
    await Timer(20, unit="ns")


# ============================================================================
# RUN ONE SOC INFERENCE
# ============================================================================

async def run_inference(
    dut,
    features,
    max_cycles=20
):

    # ------------------------------------------------------------------------
    # Make sure CPU RUN is low first.
    # ------------------------------------------------------------------------

    dut.uio_in.value = 0

    # Give CPU time to return to WAIT_RUN.
    for _ in range(3):
        await RisingEdge(dut.clk)

    # ------------------------------------------------------------------------
    # Put feature vector on external TinyTapeout inputs.
    # ------------------------------------------------------------------------

    dut.ui_in.value = features

    # ------------------------------------------------------------------------
    # Enable CPU.
    #
    # uio_in[0] = RUN
    # ------------------------------------------------------------------------

    dut.uio_in.value = 0b00000001

    # ------------------------------------------------------------------------
    # CPU program:
    #
    # PC 0 -> WAIT_RUN
    # PC 1 -> READ_INPUT
    # PC 2 -> WRITE_FEATURE
    # PC 3 -> START
    # PC 4 -> WAIT_DONE
    # PC 5 -> READ_RESULT
    # PC 6 -> DISPLAY
    # PC 7 -> LOOP
    #
    # Allow enough cycles for at least one full pass.
    # ------------------------------------------------------------------------

    for _ in range(max_cycles):
        await RisingEdge(dut.clk)

    # ------------------------------------------------------------------------
    # Stop CPU before inspecting output.
    # ------------------------------------------------------------------------

    dut.uio_in.value = 0

    # Give CPU time to settle back toward WAIT_RUN.
    for _ in range(3):
        await RisingEdge(dut.clk)

    # ------------------------------------------------------------------------
    # Sample away from the active clock edge.
    # This is especially useful for gate-level simulation.
    # ------------------------------------------------------------------------

    await FallingEdge(dut.clk)
    await Timer(20, unit="ns")

    return int(dut.uo_out.value)


# ============================================================================
# MAIN TEST
# ============================================================================

@cocotb.test()
async def test_tinymind_soc(dut):

    # ------------------------------------------------------------------------
    # 10 MHz clock
    #
    # 100 ns period
    # ------------------------------------------------------------------------

    clock = Clock(
        dut.clk,
        100,
        unit="ns"
    )

    cocotb.start_soon(
        clock.start()
    )

    # ------------------------------------------------------------------------
    # Reset whole SoC
    # ------------------------------------------------------------------------

    await reset_dut(dut)

    # ------------------------------------------------------------------------
    # Bidirectional TinyTapeout outputs are unused.
    # ------------------------------------------------------------------------

    assert int(dut.uio_out.value) == 0, (
        "uio_out should remain zero"
    )

    assert int(dut.uio_oe.value) == 0, (
        "uio_oe should remain zero"
    )

    # ========================================================================
    # TEST ALL 256 FEATURE COMBINATIONS
    # ========================================================================

    for features in range(256):

        (
            expected_class,
            expected_confidence,
            expected_close

        ) = tinymind_reference(features)

        # --------------------------------------------------------------------
        # Let the SoC process the feature vector.
        # --------------------------------------------------------------------

        actual_output = await run_inference(
            dut,
            features
        )

        # --------------------------------------------------------------------
        # Determine expected seven-segment output.
        # --------------------------------------------------------------------

        expected_seg = expected_segments(
            expected_class
        )

        # --------------------------------------------------------------------
        # uo_out[7]   = close prediction / decimal point
        #
        # uo_out[6:0] = A / H / C segments
        # --------------------------------------------------------------------

        expected_output = (
            (int(expected_close) << 7)
            |
            expected_seg
        )

        # --------------------------------------------------------------------
        # Compare physical output pins.
        # --------------------------------------------------------------------

        assert actual_output == expected_output, (

            f"\nTinyMind SoC mismatch\n"
            f"features            = {features:08b}\n"
            f"expected class      = {expected_class}\n"
            f"expected confidence = {expected_confidence}\n"
            f"expected close      = {expected_close}\n"
            f"expected output     = {expected_output:08b}\n"
            f"actual output       = {actual_output:08b}\n"

        )

        # --------------------------------------------------------------------
        # These should always remain zero.
        # --------------------------------------------------------------------

        assert int(dut.uio_out.value) == 0

        assert int(dut.uio_oe.value) == 0

    dut._log.info(
        "TinyMind SoC passed all 256 feature combinations!"
    )
