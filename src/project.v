/*
 * Copyright (c) 2026 Sishi
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMind Clocked Memory-Mapped Accelerator
 *
 * Final architecture:
 *
 *              10 MHz CLOCK
 *                    |
 *                    v
 *             FEATURE REGISTER
 *                    |
 *                    v
 *              TinyMind Logic
 *                    |
 *                    v
 *             RESULT REGISTERS
 *              /     |      \
 *          class  confidence  close
 *              \     |      /
 *                    v
 *              OUTPUT SELECT
 *              /           \
 *       BUS/DEBUG MODE   DISPLAY MODE
 *            |                |
 *        read_data          A/H/C
 *            |                |
 *            +------ uo_out ---+
 *
 *
 * TinyTapeout interface
 * ---------------------
 *
 * ui_in[7:0]
 *      write data
 *
 * uio_in[1:0]
 *      register address
 *
 * uio_in[2]
 *      write enable
 *
 * uio_in[3]
 *      output mode
 *
 *      0 = register/bus read mode
 *      1 = seven-segment display mode
 *
 *
 * Register map
 * ------------
 *
 * 00 = FEATURE
 * 01 = CONTROL
 * 10 = STATUS
 * 11 = RESULT
 *
 *
 * CONTROL
 * -------
 *
 * bit 0 = START
 *
 *
 * STATUS
 * ------
 *
 * bit 0 = DONE
 * bit 1 = BUSY
 *
 *
 * RESULT
 * ------
 *
 * bits [1:0] = class
 *
 *      00 = AI
 *      01 = Hardware
 *      10 = Creative
 *
 * bits [5:2] = confidence margin
 *
 * bit 6 = close prediction
 *
 *
 * DISPLAY MODE
 * ------------
 *
 * uio_in[3] = 1
 *
 * uo_out[6:0] = seven-segment A/H/C
 * uo_out[7]   = decimal point
 *
 * decimal point = 1 when prediction is close
 *
 */

`default_nettype none


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


    // ============================================================
    // REGISTER ADDRESS MAP
    // ============================================================

    localparam [1:0] ADDR_FEATURE = 2'b00;
    localparam [1:0] ADDR_CONTROL = 2'b01;
    localparam [1:0] ADDR_STATUS  = 2'b10;
    localparam [1:0] ADDR_RESULT  = 2'b11;


    // ============================================================
    // CLASS ENCODING
    // ============================================================

    localparam [1:0] CLASS_AI       = 2'b00;
    localparam [1:0] CLASS_HARDWARE = 2'b01;
    localparam [1:0] CLASS_CREATIVE = 2'b10;


    // ============================================================
    // SEVEN-SEGMENT ENCODING
    // ============================================================
    //
    // uo_out[6:0]
    //
    // Same segment encoding as the original TinyMind project.
    //

    localparam [6:0] SEG_A = 7'b1110111;
    localparam [6:0] SEG_H = 7'b0110111;
    localparam [6:0] SEG_C = 7'b1001110;


    // ============================================================
    // BUS SIGNALS
    // ============================================================

    wire [1:0] address;
    wire       write_enable;
    wire       display_mode;


    assign address      = uio_in[1:0];
    assign write_enable = uio_in[2];

    // ------------------------------------------------------------
    // 0 = bus / debug mode
    // 1 = seven-segment display mode
    // ------------------------------------------------------------

    assign display_mode = uio_in[3];


    // ============================================================
    // FEATURE REGISTER
    // ============================================================
    //
    // Stores all 8 TinyMind input features.
    //
    // This is real sequential storage.
    // Data changes only on a rising clock edge.
    //

    reg [7:0] feature_reg;


    // ============================================================
    // CONTROL / STATUS REGISTERS
    // ============================================================

    reg busy;
    reg done;


    // ============================================================
    // RESULT REGISTERS
    // ============================================================

    reg [1:0] result_class;

    reg [3:0] result_confidence;

    reg result_close;


    // ============================================================
    // CONVERT FEATURES TO SIGNED VALUES
    // ============================================================

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


    // ============================================================
    // TINYMIND NEURONS
    // ============================================================
    //
    // Fixed-weight TinyMind equations.
    //
    // This section is COMBINATIONAL LOGIC.
    //
    // It operates between clock edges.
    // ============================================================


    wire signed [5:0] score_ai;

    wire signed [5:0] score_hardware;

    wire signed [5:0] score_creative;


    // ------------------------------------------------------------
    // AI-oriented score
    // ------------------------------------------------------------

    assign score_ai =

        x0 +
        x1 +
        x4 -
        x5 +
        x7 +
        6'sd1;


    // ------------------------------------------------------------
    // Hardware-oriented score
    // ------------------------------------------------------------

    assign score_hardware =

        x0 +
        x2 +
        x3 +
        x5 -
        x6;


    // ------------------------------------------------------------
    // Creative-oriented score
    // ------------------------------------------------------------

    assign score_creative =

        -x1 -
        x2 +
        x5 +
        x6 +
        x7 +
        6'sd1;


    // ============================================================
    // WINNER SELECTION
    // ============================================================

    reg [1:0] winner_next;

    reg signed [5:0] winning_score_next;

    reg signed [5:0] second_score_next;


    always @(*) begin


        // --------------------------------------------------------
        // AI wins
        //
        // AI receives highest tie priority.
        // --------------------------------------------------------

        if (
            (score_ai >= score_hardware) &&
            (score_ai >= score_creative)
        ) begin


            winner_next = CLASS_AI;

            winning_score_next = score_ai;


            if (score_hardware >= score_creative)

                second_score_next = score_hardware;

            else

                second_score_next = score_creative;

        end


        // --------------------------------------------------------
        // Hardware wins
        // --------------------------------------------------------

        else if (score_hardware >= score_creative) begin


            winner_next = CLASS_HARDWARE;

            winning_score_next = score_hardware;


            if (score_ai >= score_creative)

                second_score_next = score_ai;

            else

                second_score_next = score_creative;

        end


        // --------------------------------------------------------
        // Creative wins
        // --------------------------------------------------------

        else begin


            winner_next = CLASS_CREATIVE;

            winning_score_next = score_creative;


            if (score_ai >= score_hardware)

                second_score_next = score_ai;

            else

                second_score_next = score_hardware;

        end

    end


    // ============================================================
    // CONFIDENCE
    // ============================================================
    //
    // confidence =
    //
    //     winning score
    //          -
    //     second-best score
    //
    // ============================================================

    wire signed [5:0] margin_next;


    assign margin_next =

        winning_score_next -
        second_score_next;


    // ============================================================
    // CLOCKED CONTROL LOGIC
    // ============================================================
    //
    //
    // FEATURE WRITE
    //
    //        rising edge
    //             |
    //             v
    //       feature_reg
    //
    //
    // START WRITE
    //
    //        rising edge
    //             |
    //             v
    //          busy = 1
    //
    //
    // TinyMind combinational logic operates
    //
    //
    //        next rising edge
    //             |
    //             v
    //       RESULT REGISTERS
    //
    //       busy = 0
    //       done = 1
    //
    // ============================================================


    always @(posedge clk or negedge rst_n) begin


        // ========================================================
        // RESET
        // ========================================================

        if (!rst_n) begin


            feature_reg <= 8'b0000_0000;


            busy <= 1'b0;

            done <= 1'b0;


            result_class <= CLASS_AI;

            result_confidence <= 4'd0;

            result_close <= 1'b0;


        end


        else begin


            // ====================================================
            // INFERENCE IS RUNNING
            // ====================================================

            if (busy) begin


                // -----------------------------------------------
                // Capture predicted class
                // -----------------------------------------------

                result_class <= winner_next;


                // -----------------------------------------------
                // Capture confidence
                //
                // Clamp at 9.
                // -----------------------------------------------

                if (margin_next > 6'sd9)

                    result_confidence <= 4'd9;

                else

                    result_confidence <= margin_next[3:0];


                // -----------------------------------------------
                // Close prediction
                //
                // Margin 0 or 1 means two classes were close.
                // -----------------------------------------------

                result_close <=

                    (margin_next <= 6'sd1);


                // -----------------------------------------------
                // Inference finished
                // -----------------------------------------------

                busy <= 1'b0;

                done <= 1'b1;


            end


            // ====================================================
            // REGISTER WRITE
            // ====================================================

            else if (write_enable) begin


                case (address)


                    // ============================================
                    // FEATURE REGISTER
                    // ============================================

                    ADDR_FEATURE: begin


                        feature_reg <= ui_in;


                    end


                    // ============================================
                    // CONTROL REGISTER
                    // ============================================

                    ADDR_CONTROL: begin


                        // START command

                        if (ui_in[0]) begin


                            busy <= 1'b1;

                            done <= 1'b0;


                        end


                    end


                    // ============================================
                    // STATUS / RESULT
                    //
                    // Read only.
                    // ============================================

                    default: begin

                    end


                endcase

            end

        end

    end


    // ============================================================
    // BUS READ MULTIPLEXER
    // ============================================================

    reg [7:0] read_data;


    always @(*) begin


        case (address)


            // ----------------------------------------------------
            // FEATURE REGISTER
            // ----------------------------------------------------

            ADDR_FEATURE: begin


                read_data = feature_reg;


            end


            // ----------------------------------------------------
            // CONTROL REGISTER
            // ----------------------------------------------------

            ADDR_CONTROL: begin


                read_data = 8'b0000_0000;


            end


            // ----------------------------------------------------
            // STATUS REGISTER
            //
            // bit 0 = DONE
            // bit 1 = BUSY
            // ----------------------------------------------------

            ADDR_STATUS: begin


                read_data = {

                    6'b000000,

                    busy,

                    done

                };


            end


            // ----------------------------------------------------
            // RESULT REGISTER
            //
            // bit 7       unused
            // bit 6       close prediction
            // bits [5:2]  confidence
            // bits [1:0]  class
            // ----------------------------------------------------

            ADDR_RESULT: begin


                read_data = {

                    1'b0,

                    result_close,

                    result_confidence,

                    result_class

                };


            end


            default: begin


                read_data = 8'b0000_0000;


            end


        endcase

    end


    // ============================================================
    // SEVEN-SEGMENT DECODER
    // ============================================================

    reg [6:0] class_segments;


    always @(*) begin


        case (result_class)


            CLASS_AI: begin

                class_segments = SEG_A;

            end


            CLASS_HARDWARE: begin

                class_segments = SEG_H;

            end


            CLASS_CREATIVE: begin

                class_segments = SEG_C;

            end


            default: begin

                class_segments = 7'b0000000;

            end


        endcase

    end


    // ============================================================
    // DISPLAY OUTPUT
    // ============================================================
    //
    // uo_out[6:0] = A/H/C
    //
    // uo_out[7] = decimal point
    //
    // Decimal point lights for a close prediction.
    // ============================================================

    wire [7:0] display_data;


    assign display_data = {

        result_close,

        class_segments

    };


    // ============================================================
    // FINAL OUTPUT SELECT
    // ============================================================
    //
    // uio_in[3] = 0
    //
    //      BUS MODE
    //
    //      uo_out = selected register
    //
    //
    // uio_in[3] = 1
    //
    //      DISPLAY MODE
    //
    //      uo_out = A / H / C
    //
    // ============================================================

    assign uo_out =

        display_mode
            ?
        display_data
            :
        read_data;


    // ============================================================
    // BIDIRECTIONAL PINS
    // ============================================================
    //
    // We use uio pins as INPUTS only.
    // ============================================================

    assign uio_out = 8'b00000000;

    assign uio_oe = 8'b00000000;


    // ============================================================
    // UNUSED SIGNALS
    // ============================================================

    wire _unused = &{

        ena,

        uio_in[7:4],

        1'b0

    };


endmodule


`default_nettype wire
