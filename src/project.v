/*
 * Copyright (c) 2026 Sishi
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMind SoC - Version 4
 *
 * Architecture:
 *
 *          ui_in[7:0]
 *               |
 *               v
 *        +--------------+
 *        |   Tiny CPU   |
 *        | PC + ACC +   |
 *        | Program ROM  |
 *        +------+-------+
 *               |
 *         internal control
 *               |
 *               v
 *        +--------------+
 *        |   TinyMind   |
 *        | Accelerator  |
 *        +------+-------+
 *               |
 *        class/confidence
 *               |
 *               v
 *        +--------------+
 *        |  CPU Result  |
 *        |   Register   |
 *        +------+-------+
 *               |
 *               v
 *        +--------------+
 *        |  7 Segment   |
 *        |    A/H/C     |
 *        +--------------+
 *
 *
 * CPU program:
 *
 *   0  READ_INPUT
 *   1  WRITE_FEATURE
 *   2  START_TINYMIND
 *   3  WAIT_DONE
 *   4  READ_RESULT
 *   5  DISPLAY_RESULT
 *   6  LOOP
 *
 *
 * uio_in[0]:
 *
 *   1 = CPU is allowed to run/repeat inference
 *   0 = CPU waits at beginning
 *
 *
 * ui_in[7:0]:
 *
 *   TinyMind feature vector
 *
 *
 * uo_out[6:0]:
 *
 *   seven-segment A / H / C
 *
 *
 * uo_out[7]:
 *
 *   close-prediction decimal point
 *
 *
 * Target clock:
 *
 *   10 MHz
 */

`default_nettype none


// ============================================================================
// TINYTAPEOUT TOP MODULE
// ============================================================================

module tt_um_sishi888_tinymind (

    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n

);


    // ========================================================================
    // CPU <-> TINYMIND SIGNALS
    // ========================================================================

    wire [7:0] cpu_feature_data;

    wire       cpu_feature_write;

    wire       cpu_start;


    wire       tinymind_busy;

    wire       tinymind_done;

    wire [1:0] tinymind_class;

    wire [3:0] tinymind_confidence;

    wire       tinymind_close;


    // ========================================================================
    // CPU DISPLAY RESULT REGISTERS
    // ========================================================================

    wire [1:0] cpu_display_class;

    wire       cpu_display_close;

    wire [3:0] cpu_display_confidence;


    // ========================================================================
    // CPU
    // ========================================================================

    tiny_cpu cpu (

        .clk                 (clk),

        .rst_n               (rst_n),

        .run_enable          (uio_in[0]),

        .external_features   (ui_in),


        // CPU -> TinyMind

        .feature_data        (cpu_feature_data),

        .feature_write       (cpu_feature_write),

        .start               (cpu_start),


        // TinyMind -> CPU

        .accelerator_busy    (tinymind_busy),

        .accelerator_done    (tinymind_done),

        .accelerator_class   (tinymind_class),

        .accelerator_confidence (
            tinymind_confidence
        ),

        .accelerator_close   (tinymind_close),


        // CPU -> Display

        .display_class       (cpu_display_class),

        .display_confidence  (
            cpu_display_confidence
        ),

        .display_close       (cpu_display_close)

    );


    // ========================================================================
    // TINYMIND ACCELERATOR
    // ========================================================================

    tinymind_core accelerator (

        .clk             (clk),

        .rst_n           (rst_n),

        .feature_write   (cpu_feature_write),

        .feature_data    (cpu_feature_data),

        .start           (cpu_start),

        .busy            (tinymind_busy),

        .done            (tinymind_done),

        .result_class    (tinymind_class),

        .confidence      (tinymind_confidence),

        .close_prediction (
            tinymind_close
        )

    );


    // ========================================================================
    // SEVEN-SEGMENT DISPLAY
    // ========================================================================

    wire [6:0] segments;


    sevenseg display_decoder (

        .class_value (

            cpu_display_class

        ),

        .segments (

            segments

        )

    );


    // ========================================================================
    // OUTPUT
    // ========================================================================
    //
    // [6:0] = seven segment
    //
    // [7] = close-prediction decimal point
    // ========================================================================

    assign uo_out = {

        cpu_display_close,

        segments

    };


    // ========================================================================
    // BIDIRECTIONAL OUTPUTS UNUSED
    // ========================================================================

    assign uio_out = 8'b0000_0000;

    assign uio_oe = 8'b0000_0000;


    // ========================================================================
    // UNUSED
    // ========================================================================

    wire _unused = &{

        ena,

        uio_in[7:1],

        cpu_display_confidence,

        1'b0

    };


endmodule



// ============================================================================
// TINY 8-BIT CPU
// ============================================================================
//
// This is intentionally a very small educational CPU.
//
// Registers:
//
//     PC                Program Counter
//
//     ACC               8-bit accumulator/input register
//
//     result_class_reg  Captured accelerator result
//
//     confidence_reg    Captured confidence
//
//     close_reg         Captured close flag
//
//
// Program ROM:
//
//     PC 0 = WAIT_RUN
//
//     PC 1 = READ_INPUT
//
//     PC 2 = WRITE_FEATURE
//
//     PC 3 = START
//
//     PC 4 = WAIT_DONE
//
//     PC 5 = READ_RESULT
//
//     PC 6 = DISPLAY
//
//     PC 7 = LOOP
//
// ============================================================================

module tiny_cpu (

    input wire clk,

    input wire rst_n,


    // ========================================================================
    // EXTERNAL CONTROL
    // ========================================================================

    input wire run_enable,

    input wire [7:0] external_features,


    // ========================================================================
    // CPU -> ACCELERATOR
    // ========================================================================

    output wire [7:0] feature_data,

    output reg feature_write,

    output reg start,


    // ========================================================================
    // ACCELERATOR -> CPU
    // ========================================================================

    input wire accelerator_busy,

    input wire accelerator_done,

    input wire [1:0] accelerator_class,

    input wire [3:0] accelerator_confidence,

    input wire accelerator_close,


    // ========================================================================
    // CPU -> DISPLAY
    // ========================================================================

    output wire [1:0] display_class,

    output wire [3:0] display_confidence,

    output wire display_close

);


    // ========================================================================
    // CPU REGISTERS
    // ========================================================================


    // ------------------------------------------------------------------------
    // Program Counter
    // ------------------------------------------------------------------------

    reg [3:0] pc;


    // ------------------------------------------------------------------------
    // Accumulator / input data register
    // ------------------------------------------------------------------------

    reg [7:0] acc;


    // ------------------------------------------------------------------------
    // CPU result registers
    // ------------------------------------------------------------------------

    reg [1:0] result_class_reg;

    reg [3:0] confidence_reg;

    reg close_reg;


    // ========================================================================
    // INSTRUCTION ENCODING
    // ========================================================================

    localparam [3:0] INST_WAIT_RUN      = 4'h0;

    localparam [3:0] INST_READ_INPUT    = 4'h1;

    localparam [3:0] INST_WRITE_FEATURE = 4'h2;

    localparam [3:0] INST_START         = 4'h3;

    localparam [3:0] INST_WAIT_DONE     = 4'h4;

    localparam [3:0] INST_READ_RESULT   = 4'h5;

    localparam [3:0] INST_DISPLAY       = 4'h6;

    localparam [3:0] INST_LOOP          = 4'h7;


    // ========================================================================
    // PROGRAM ROM
    // ========================================================================
    //
    // PC -> instruction
    //
    // This is the CPU's tiny software program.
    // ========================================================================

    reg [3:0] instruction;


    always @(*) begin

        case (pc)


            4'd0:
                instruction = INST_WAIT_RUN;


            4'd1:
                instruction = INST_READ_INPUT;


            4'd2:
                instruction = INST_WRITE_FEATURE;


            4'd3:
                instruction = INST_START;


            4'd4:
                instruction = INST_WAIT_DONE;


            4'd5:
                instruction = INST_READ_RESULT;


            4'd6:
                instruction = INST_DISPLAY;


            4'd7:
                instruction = INST_LOOP;


            default:
                instruction = INST_WAIT_RUN;


        endcase

    end


    // ========================================================================
    // CPU OUTPUTS
    // ========================================================================

    assign feature_data = acc;


    assign display_class = result_class_reg;


    assign display_confidence = confidence_reg;


    assign display_close = close_reg;


    // ========================================================================
    // CPU EXECUTION
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin


        // ====================================================================
        // RESET
        // ====================================================================

        if (!rst_n) begin


            pc <= 4'd0;


            acc <= 8'b0000_0000;


            result_class_reg <= 2'b00;


            confidence_reg <= 4'd0;


            close_reg <= 1'b0;


            feature_write <= 1'b0;


            start <= 1'b0;


        end


        else begin


            // ================================================================
            // DEFAULT ONE-CYCLE CONTROL SIGNALS
            // ================================================================

            feature_write <= 1'b0;

            start <= 1'b0;


            // ================================================================
            // EXECUTE CURRENT INSTRUCTION
            // ================================================================

            case (instruction)


                // ============================================================
                // WAIT FOR RUN ENABLE
                // ============================================================

                INST_WAIT_RUN: begin


                    if (run_enable)

                        pc <= 4'd1;

                    else

                        pc <= 4'd0;


                end


                // ============================================================
                // READ EXTERNAL INPUT
                // ============================================================

                INST_READ_INPUT: begin


                    acc <= external_features;


                    pc <= 4'd2;


                end


                // ============================================================
                // WRITE FEATURE REGISTER
                // ============================================================

                INST_WRITE_FEATURE: begin


                    feature_write <= 1'b1;


                    pc <= 4'd3;


                end


                // ============================================================
                // START TINYMIND
                // ============================================================

                INST_START: begin


                    start <= 1'b1;


                    pc <= 4'd4;


                end


                // ============================================================
                // WAIT FOR TINYMIND
                // ============================================================

                INST_WAIT_DONE: begin


                    if (accelerator_done)

                        pc <= 4'd5;

                    else

                        pc <= 4'd4;


                end


                // ============================================================
                // READ RESULT
                // ============================================================

                INST_READ_RESULT: begin


                    result_class_reg <= accelerator_class;


                    confidence_reg <= accelerator_confidence;


                    close_reg <= accelerator_close;


                    pc <= 4'd6;


                end


                // ============================================================
                // DISPLAY
                // ============================================================
                //
                // Result registers already drive display.
                //
                // This instruction gives the architecture an explicit
                // display/program stage.
                // ============================================================

                INST_DISPLAY: begin


                    pc <= 4'd7;


                end


                // ============================================================
                // LOOP
                // ============================================================

                INST_LOOP: begin


                    // --------------------------------------------------------
                    // If RUN is still high, process another input.
                    //
                    // If RUN goes low, return to WAIT_RUN.
                    // --------------------------------------------------------

                    if (run_enable)

                        pc <= 4'd1;

                    else

                        pc <= 4'd0;


                end


                // ============================================================
                // SAFETY
                // ============================================================

                default: begin


                    pc <= 4'd0;


                end


            endcase

        end

    end


    // ========================================================================
    // UNUSED ACCELERATOR BUSY SIGNAL
    // ========================================================================

    wire _unused_cpu = &{

        accelerator_busy,

        1'b0

    };


endmodule



// ============================================================================
// TINYMIND ACCELERATOR
// ============================================================================
//
// Clocked accelerator:
//
//             FEATURE REGISTER
//                    |
//                    v
//             COMBINATIONAL
//              TINYMIND
//                    |
//                    v
//              RESULT REGS
//
// ============================================================================

module tinymind_core (

    input wire clk,

    input wire rst_n,


    // ========================================================================
    // CPU CONTROL
    // ========================================================================

    input wire feature_write,

    input wire [7:0] feature_data,

    input wire start,


    // ========================================================================
    // STATUS
    // ========================================================================

    output reg busy,

    output reg done,


    // ========================================================================
    // RESULTS
    // ========================================================================

    output reg [1:0] result_class,

    output reg [3:0] confidence,

    output reg close_prediction

);


    // ========================================================================
    // CLASS ENCODING
    // ========================================================================

    localparam [1:0] CLASS_AI       = 2'b00;

    localparam [1:0] CLASS_HARDWARE = 2'b01;

    localparam [1:0] CLASS_CREATIVE = 2'b10;


    // ========================================================================
    // FEATURE REGISTER
    // ========================================================================

    reg [7:0] feature_reg;


    // ========================================================================
    // FEATURE VALUES
    // ========================================================================

    wire signed [5:0] x0;

    wire signed [5:0] x1;

    wire signed [5:0] x2;

    wire signed [5:0] x3;

    wire signed [5:0] x4;

    wire signed [5:0] x5;

    wire signed [5:0] x6;

    wire signed [5:0] x7;


    assign x0 = feature_reg[0] ? 6'sd1 : 6'sd0;

    assign x1 = feature_reg[1] ? 6'sd1 : 6'sd0;

    assign x2 = feature_reg[2] ? 6'sd1 : 6'sd0;

    assign x3 = feature_reg[3] ? 6'sd1 : 6'sd0;

    assign x4 = feature_reg[4] ? 6'sd1 : 6'sd0;

    assign x5 = feature_reg[5] ? 6'sd1 : 6'sd0;

    assign x6 = feature_reg[6] ? 6'sd1 : 6'sd0;

    assign x7 = feature_reg[7] ? 6'sd1 : 6'sd0;


    // ========================================================================
    // THREE TINYMIND NEURONS
    // ========================================================================

    wire signed [5:0] score_ai;

    wire signed [5:0] score_hardware;

    wire signed [5:0] score_creative;


    assign score_ai =

        x0 +
        x1 +
        x4 -
        x5 +
        x7 +
        6'sd1;


    assign score_hardware =

        x0 +
        x2 +
        x3 +
        x5 -
        x6;


    assign score_creative =

        -x1 -
        x2 +
        x5 +
        x6 +
        x7 +
        6'sd1;


    // ========================================================================
    // WINNER / SECOND PLACE
    // ========================================================================

    reg [1:0] winner_next;

    reg signed [5:0] winning_score_next;

    reg signed [5:0] second_score_next;


    always @(*) begin


        // ====================================================================
        // AI
        // ====================================================================

        if (

            (score_ai >= score_hardware)

            &&

            (score_ai >= score_creative)

        ) begin


            winner_next = CLASS_AI;


            winning_score_next = score_ai;


            if (score_hardware >= score_creative)

                second_score_next = score_hardware;

            else

                second_score_next = score_creative;


        end


        // ====================================================================
        // HARDWARE
        // ====================================================================

        else if (score_hardware >= score_creative) begin


            winner_next = CLASS_HARDWARE;


            winning_score_next = score_hardware;


            if (score_ai >= score_creative)

                second_score_next = score_ai;

            else

                second_score_next = score_creative;


        end


        // ====================================================================
        // CREATIVE
        // ====================================================================

        else begin


            winner_next = CLASS_CREATIVE;


            winning_score_next = score_creative;


            if (score_ai >= score_hardware)

                second_score_next = score_ai;

            else

                second_score_next = score_hardware;


        end

    end


    // ========================================================================
    // CONFIDENCE MARGIN
    // ========================================================================

    wire signed [5:0] margin_next;


    assign margin_next =

        winning_score_next

        -

        second_score_next;


    // ========================================================================
    // ACCELERATOR SEQUENTIAL LOGIC
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin


        // ====================================================================
        // RESET
        // ====================================================================

        if (!rst_n) begin


            feature_reg <= 8'b0000_0000;


            busy <= 1'b0;


            done <= 1'b0;


            result_class <= CLASS_AI;


            confidence <= 4'd0;


            close_prediction <= 1'b0;


        end


        else begin


            // ================================================================
            // FEATURE WRITE
            // ================================================================

            if (feature_write) begin


                feature_reg <= feature_data;


            end


            // ================================================================
            // START
            // ================================================================

            if (start && !busy) begin


                busy <= 1'b1;


                done <= 1'b0;


            end


            // ================================================================
            // RUN INFERENCE
            // ================================================================

            else if (busy) begin


                // ------------------------------------------------------------
                // Class
                // ------------------------------------------------------------

                result_class <= winner_next;


                // ------------------------------------------------------------
                // Confidence
                // ------------------------------------------------------------

                if (margin_next > 6'sd9)

                    confidence <= 4'd9;

                else

                    confidence <= margin_next[3:0];


                // ------------------------------------------------------------
                // Close prediction
                // ------------------------------------------------------------

                close_prediction <=

                    (margin_next <= 6'sd1);


                // ------------------------------------------------------------
                // Finished
                // ------------------------------------------------------------

                busy <= 1'b0;


                done <= 1'b1;


            end

        end

    end


endmodule



// ============================================================================
// SEVEN SEGMENT DECODER
// ============================================================================
//
// class 00 -> A
//
// class 01 -> H
//
// class 10 -> C
//
// ============================================================================

module sevenseg (

    input wire [1:0] class_value,

    output reg [6:0] segments

);


    // ========================================================================
    // SEGMENT VALUES
    // ========================================================================

    localparam [6:0] SEG_A = 7'b1110111;

    localparam [6:0] SEG_H = 7'b0110111;

    localparam [6:0] SEG_C = 7'b1001110;


    // ========================================================================
    // DECODER
    // ========================================================================

    always @(*) begin


        case (class_value)


            2'b00:

                segments = SEG_A;


            2'b01:

                segments = SEG_H;


            2'b10:

                segments = SEG_C;


            default:

                segments = 7'b0000000;


        endcase

    end


endmodule


`default_nettype wire
