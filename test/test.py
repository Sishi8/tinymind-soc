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
#
# This is the Python version of TinyMind.
#
# The hardware result must match this model.
#
# ============================================================================

def tinymind_reference(features):

    x = [
        (features >> i) & 1
        for i in range(8)
    ]

    # ------------------------------------------------------------------------
    # Three TinyMind neuron scores
    # ------------------------------------------------------------------------

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


    # ------------------------------------------------------------------------
    # Winner selection
    #
    # Tie priority:
    #
    # AI > Hardware > Creative
    # ------------------------------------------------------------------------

    if (
        score_ai >= score_hardware
        and
        score_ai >= score_creative
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


    # ------------------------------------------------------------------------
    # Confidence
    # ------------------------------------------------------------------------

    margin = winning_score - second_score

    confidence = min(
        margin,
        9
    )


    # ------------------------------------------------------------------------
    # Close prediction
    # ------------------------------------------------------------------------

    close_prediction = (
        margin <= 1
    )


    return (
        winner,
        confidence,
        close_prediction
    )


# ============================================================================
# EXPECTED SEVEN SEGMENT VALUE
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

    # ------------------------------------------------------------------------
    # Initial inputs
    # ------------------------------------------------------------------------

    dut.ena.value = 1

    dut.ui_in.value = 0

    dut.uio_in.value = 0


    # ------------------------------------------------------------------------
    # Assert active-low reset
    # ------------------------------------------------------------------------

    dut.rst_n.value = 0


    for _ in range(3):

        await RisingEdge(dut.clk)


    # ------------------------------------------------------------------------
    # Release reset
    # ------------------------------------------------------------------------

    dut.rst_n.value = 1


    await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)


# ============================================================================
# RUN ONE INFERENCE
# ============================================================================

async def run_inference(
    dut,
    features,
    max_cycles=30
):

    # ------------------------------------------------------------------------
    # Stop CPU first.
    #
    # uio_in[0] = RUN ENABLE
    # ------------------------------------------------------------------------

    dut.uio_in.value = 0


    # ------------------------------------------------------------------------
    # Give CPU time to return to WAIT_RUN.
    # ------------------------------------------------------------------------

    for _ in range(3):

        await RisingEdge(dut.clk)


    # ------------------------------------------------------------------------
    # Put feature vector on TinyTapeout input pins.
    # ------------------------------------------------------------------------

    dut.ui_in.value = features


    # ------------------------------------------------------------------------
    # RUN ENABLE = 1
    #
    # CPU will now execute:
    #
    # WAIT_RUN
    # READ_INPUT
    # WRITE_FEATURE
    # START
    # WAIT_DONE
    # READ_RESULT
    # DISPLAY
    # LOOP
    #
    # ------------------------------------------------------------------------

    dut.uio_in.value = 0b00000001


    # ------------------------------------------------------------------------
    # Wait enough CPU cycles for one complete program iteration.
    #
    # We intentionally do not inspect internal CPU signals here.
    #
    # We test the SoC from its external pins.
    # ------------------------------------------------------------------------

    for _ in range(max_cycles):

        await RisingEdge(dut.clk)


    # ------------------------------------------------------------------------
    # Stop CPU.
    #
    # This prevents it from continuously starting new inferences while
    # we inspect the output.
    # ------------------------------------------------------------------------

    dut.uio_in.value = 0


    # ------------------------------------------------------------------------
    # Allow output logic to settle.
    #
    # FallingEdge + Timer is useful for both RTL and gate-level simulation.
    # ------------------------------------------------------------------------

    await FallingEdge(dut.clk)

    await Timer(20, unit="ns")


    # ------------------------------------------------------------------------
    # Read physical TinyTapeout output pins.
    # ------------------------------------------------------------------------

    return int(dut.uo_out.value)


# ============================================================================
# MAIN TEST
# ============================================================================

@cocotb.test()
async def test_tinymind_soc(dut):

    # ========================================================================
    # START 10 MHz CLOCK
    #
    # 10 MHz:
    #
    # period = 100 ns
    # ========================================================================

    clock = Clock(
        dut.clk,
        100,
        unit="ns"
    )

    cocotb.start_soon(
        clock.start()
    )


    # ========================================================================
    # RESET SOC
    # ========================================================================

    await reset_dut(dut)


    # ========================================================================
    # CHECK UNUSED BIDIRECTIONAL OUTPUTS
    # ========================================================================

    assert int(dut.uio_out.value) == 0, (
        "uio_out should remain zero"
    )

    assert int(dut.uio_oe.value) == 0, (
        "uio_oe should remain zero"
    )


    # ========================================================================
    # TEST ALL 256 POSSIBLE FEATURE VECTORS
    # ========================================================================

    for features in range(256):


        # --------------------------------------------------------------------
        # Calculate expected answer in Python
        # --------------------------------------------------------------------

        (
            expected_class,
            expected_confidence,
            expected_close

        ) = tinymind_reference(features)


        # --------------------------------------------------------------------
        # Let the SoC itself process the input.
        # --------------------------------------------------------------------

        actual_output = await run_inference(
            dut,
            features
        )


        # --------------------------------------------------------------------
        # Expected seven-segment output
        #// --------------------------------------------------------------------

        expected_seg = expected_segments(
            expected_class
        )


        # --------------------------------------------------------------------
        # uo_out[7] = decimal point / close prediction
        #
        # uo_out[6:0] = seven segment
        # --------------------------------------------------------------------

        expected_output = (
            (int(expected_close) << 7)
            |
            expected_seg
        )


        # --------------------------------------------------------------------
        # Compare
        # --------------------------------------------------------------------

        assert actual_output == expected_output, (

            f"\nTinyMind SoC mismatch\n"

            f"features          = {features:08b}\n"

            f"expected class    = {expected_class}\n"

            f"expected confidence = {expected_confidence}\n"

            f"expected close    = {expected_close}\n"

            f"expected output   = {expected_output:08b}\n"

            f"actual output     = {actual_output:08b}\n"

        )


        # --------------------------------------------------------------------
        # Check unused bidirectional outputs again
        # --------------------------------------------------------------------

        assert int(dut.uio_out.value) == 0

        assert int(dut.uio_oe.value) == 0


    # ========================================================================
    # SUCCESS
    # ========================================================================

    dut._log.info(
        "TinyMind SoC passed all 256 feature combinations!"
    )
