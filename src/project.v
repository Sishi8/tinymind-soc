/*
 * Copyright (c) 2026 Sishi
 * SPDX-License-Identifier: Apache-2.0
 *
 * TinyMind Memory-Mapped Accelerator
 *
 * TinyMind implemented as a small SoC-style peripheral.
 *
 * Bus interface:
 *
 *   ui_in[7:0]  = write data
 *
 *   uio_in[1:0] = register address
 *   uio_in[2]   = write enable
 *
 *   uo_out[7:0] = read data
 *
 * Address map:
 *
 *   00 = FEATURE register
 *   01 = CONTROL register
 *   10 = STATUS register
 *   11 = RESULT register
 *
 * CONTROL:
 *
 *   bit 0 = START
 *
 * STATUS:
 *
 *   bit 0 = DONE
 *   bit 1 = BUSY
 *
 * RESULT:
 *
 *   bits [1:0] = predicted class
 *                00 = AI
 *                01 = Hardware
 *                10 = Creative
 *
 *   bits [5:2] = confidence margin (0-9)
 *
 *   bit 6 = close prediction
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
    // SIMPLE BUS SIGNALS
    // ============================================================
    //
    // ui_in[7:0]
    //     Data that is being written.
    //
    // uio_in[1:0]
    //     Address of the register.
    //
    // uio_in[2]
    //     Write enable.
    //

    wire [1:0] address;
    wire       write_enable;

    assign address      = uio_in[1:0];
    assign write_enable = uio_in[2];


    // ============================================================
    // FEATURE REGISTER
    // ============================================================
    //
    // This register stores the eight TinyMind input features.
    //

    reg [7:0] feature_reg;


    // ============================================================
    // STATUS REGISTERS
    // ============================================================

    reg busy;
    reg done;


    // ============================================================
    // RESULT REGISTERS
    // ============================================================

    reg [1:0] result_class;
    reg [3:0] result_confidence;
    reg       result_close;


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
    // TINYMIND FIXED-WEIGHT NEURONS
    // ============================================================
    //
    // These are the same equations used by TinyMind.
    //

    wire signed [5:0] score_ai;
    wire signed [5:0] score_hardware;
    wire signed [5:0] score_creative;


    // AI-oriented neuron

    assign score_ai =
        x0 +
        x1 +
        x4 -
        x5 +
        x7 +
        6'sd1;


    // Hardware-oriented neuron

    assign score_hardware =
        x0 +
        x2 +
        x3 +
        x5 -
        x6;


    // Creative-oriented neuron

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

        if ((score_ai >= score_hardware) &&
            (score_ai >= score_creative)) begin

            winner_next = CLASS_AI;

            winning_score_next = score_ai;

            if (score_hardware >= score_creative)
                second_score_next = score_hardware;
            else
                second_score_next = score_creative;

        end

        else if (score_hardware >= score_creative) begin

            winner_next = CLASS_HARDWARE;

            winning_score_next = score_hardware;

            if (score_ai >= score_creative)
                second_score_next = score_ai;
            else
                second_score_next = score_creative;

        end

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
    // CONFIDENCE CALCULATION
    // ============================================================

    wire signed [5:0] margin_next;

    assign margin_next =
        winning_score_next - second_score_next;


    // ============================================================
    // CONTROL / REGISTER LOGIC
    // ============================================================
    //
    // Normal sequence:
    //
    // CLOCK:
    //
    //   Write address 00
    //        |
    //        v
    //   feature_reg gets input
    //
    //   Write address 01 with bit 0 = 1
    //        |
    //        v
    //   busy = 1
    //
    //   next clock
    //        |
    //        v
    //   TinyMind result captured
    //
    //   busy = 0
    //   done = 1
    //

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            feature_reg       <= 8'b0000_0000;

            busy              <= 1'b0;
            done              <= 1'b0;

            result_class      <= CLASS_AI;
            result_confidence <= 4'd0;
            result_close      <= 1'b0;

        end

        else begin

            // ----------------------------------------------------
            // TinyMind is currently running
            // ----------------------------------------------------

            if (busy) begin

                // Capture winner

                result_class <= winner_next;


                // Capture confidence margin

                if (margin_next > 6'sd9)
                    result_confidence <= 4'd9;
                else
                    result_confidence <= margin_next[3:0];


                // Close prediction flag

                result_close <= (margin_next <= 6'sd1);


                // Inference finished

                busy <= 1'b0;
                done <= 1'b1;

            end


            // ----------------------------------------------------
            // Bus write
            // ----------------------------------------------------

            else if (write_enable) begin

                case (address)


                    // --------------------------------------------
                    // FEATURE REGISTER
                    // --------------------------------------------

                    ADDR_FEATURE: begin

                        feature_reg <= ui_in;

                    end


                    // --------------------------------------------
                    // CONTROL REGISTER
                    // --------------------------------------------

                    ADDR_CONTROL: begin

                        // START bit

                        if (ui_in[0]) begin

                            busy <= 1'b1;
                            done <= 1'b0;

                        end

                    end


                    default: begin

                        // STATUS and RESULT are read-only.

                    end

                endcase

            end

        end

    end


    // ============================================================
    // READ MULTIPLEXER
    // ============================================================
    //
    // Whatever register address is selected appears on uo_out.
    //

    reg [7:0] read_data;


    always @(*) begin

        case (address)


            // ----------------------------------------------------
            // FEATURE
            // ----------------------------------------------------

            ADDR_FEATURE: begin

                read_data = feature_reg;

            end


            // ----------------------------------------------------
            // CONTROL
            // ----------------------------------------------------

            ADDR_CONTROL: begin

                read_data = 8'b0000_0000;

            end


            // ----------------------------------------------------
            // STATUS
            //
            // bit 0 = done
            // bit 1 = busy
            // ----------------------------------------------------

            ADDR_STATUS: begin

                read_data = {
                    6'b000000,
                    busy,
                    done
                };

            end


            // ----------------------------------------------------
            // RESULT
            //
            // [1:0] = class
            // [5:2] = confidence
            // [6]   = close prediction
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
    // TinyTapeout OUTPUT
    // ============================================================

    assign uo_out = read_data;


    // ============================================================
    // BIDIRECTIONAL OUTPUTS UNUSED
    // ============================================================
    //
    // uio pins are being used only as INPUTS.
    //

    assign uio_out = 8'b0000_0000;
    assign uio_oe  = 8'b0000_0000;


    // ============================================================
    // UNUSED INPUTS
    // ============================================================

    wire _unused = &{
        ena,
        uio_in[7:3],
        1'b0
    };


endmodule

`default_nettype wire
