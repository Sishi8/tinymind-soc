/*
 * Copyright (c) 2026 Sishi
 * SPDX-License-Identifier: Apache-2.0
 *
 * Project: TinyMind Clocked Accelerator
 *
 * Experimental clocked version of TinyMind.
 *
 * Pipeline:
 *
 *   ui_in
 *      |
 *      v
 *   Input Register
 *      |
 *      v
 *   Fixed-weight inference
 *      |
 *      v
 *   Result Register
 *      |
 *      v
 *   Seven-segment display
 *
 * This version is intentionally clocked so that we can experiment
 * with clock frequency, register-to-register timing, and ASIC
 * physical implementation.
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
  // CLASS ENCODING
  // ============================================================

  localparam [1:0] CLASS_AI       = 2'b00;
  localparam [1:0] CLASS_HARDWARE = 2'b01;
  localparam [1:0] CLASS_CREATIVE = 2'b10;


  // ============================================================
  // STAGE 1 — INPUT REGISTER
  // ============================================================
  //
  // ui_in is captured on a rising clock edge.
  //
  // This is our FIRST set of flip-flops.
  //

  reg [7:0] features_reg;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      features_reg <= 8'b0000_0000;
    else
      features_reg <= ui_in;
  end


  // ============================================================
  // CONVERT REGISTERED FEATURES TO SIGNED VALUES
  // ============================================================

  wire signed [5:0] x0;
  wire signed [5:0] x1;
  wire signed [5:0] x2;
  wire signed [5:0] x3;
  wire signed [5:0] x4;
  wire signed [5:0] x5;
  wire signed [5:0] x6;
  wire signed [5:0] x7;

  assign x0 = features_reg[0] ? 6'sd1 : 6'sd0;
  assign x1 = features_reg[1] ? 6'sd1 : 6'sd0;
  assign x2 = features_reg[2] ? 6'sd1 : 6'sd0;
  assign x3 = features_reg[3] ? 6'sd1 : 6'sd0;
  assign x4 = features_reg[4] ? 6'sd1 : 6'sd0;
  assign x5 = features_reg[5] ? 6'sd1 : 6'sd0;
  assign x6 = features_reg[6] ? 6'sd1 : 6'sd0;
  assign x7 = features_reg[7] ? 6'sd1 : 6'sd0;


  // ============================================================
  // COMBINATIONAL INFERENCE
  // ============================================================
  //
  // These are exactly the TinyMind fixed-weight neuron equations.
  //

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


  // ============================================================
  // WINNER + RUNNER-UP COMBINATIONAL LOGIC
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

    end else if (score_hardware >= score_creative) begin

      winner_next = CLASS_HARDWARE;
      winning_score_next = score_hardware;

      if (score_ai >= score_creative)
        second_score_next = score_ai;
      else
        second_score_next = score_creative;

    end else begin

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
  // STAGE 2 — RESULT REGISTER
  // ============================================================
  //
  // The inference result is captured at the NEXT rising edge.
  //
  // This gives us a real timing path:
  //
  // features_reg
  //      |
  //      +--> scoring logic
  //      +--> winner comparison
  //      +--> margin calculation
  //      |
  //      v
  // result registers
  //

  reg [1:0] predicted_class;
  reg [3:0] confidence_digit;
  reg       close_prediction;

  always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

      predicted_class  <= CLASS_AI;
      confidence_digit <= 4'd0;
      close_prediction <= 1'b1;

    end else begin

      predicted_class <= winner_next;

      if (margin_next > 6'sd9)
        confidence_digit <= 4'd9;
      else
        confidence_digit <= margin_next[3:0];

      close_prediction <= (margin_next <= 6'sd1);

    end

  end


  // ============================================================
  // SEVEN-SEGMENT DEFINITIONS
  // ============================================================

  localparam [6:0] SEG_0 = 7'b1111110;
  localparam [6:0] SEG_1 = 7'b0110000;
  localparam [6:0] SEG_2 = 7'b1101101;
  localparam [6:0] SEG_3 = 7'b1111001;
  localparam [6:0] SEG_4 = 7'b0110011;
  localparam [6:0] SEG_5 = 7'b1011011;
  localparam [6:0] SEG_6 = 7'b1011111;
  localparam [6:0] SEG_7 = 7'b1110000;
  localparam [6:0] SEG_8 = 7'b1111111;
  localparam [6:0] SEG_9 = 7'b1111011;

  localparam [6:0] SEG_A = 7'b1110111;
  localparam [6:0] SEG_H = 7'b0110111;
  localparam [6:0] SEG_C = 7'b1001110;


  // ============================================================
  // CLASS DISPLAY
  // ============================================================

  reg [6:0] class_segments;

  always @(*) begin

    case (predicted_class)

      CLASS_AI:
        class_segments = SEG_A;

      CLASS_HARDWARE:
        class_segments = SEG_H;

      CLASS_CREATIVE:
        class_segments = SEG_C;

      default:
        class_segments = SEG_0;

    endcase

  end


  // ============================================================
  // CONFIDENCE DISPLAY
  // ============================================================

  reg [6:0] confidence_segments;

  always @(*) begin

    case (confidence_digit)

      4'd0: confidence_segments = SEG_0;
      4'd1: confidence_segments = SEG_1;
      4'd2: confidence_segments = SEG_2;
      4'd3: confidence_segments = SEG_3;
      4'd4: confidence_segments = SEG_4;
      4'd5: confidence_segments = SEG_5;
      4'd6: confidence_segments = SEG_6;
      4'd7: confidence_segments = SEG_7;
      4'd8: confidence_segments = SEG_8;
      4'd9: confidence_segments = SEG_9;

      default:
        confidence_segments = SEG_0;

    endcase

  end


  // ============================================================
  // OUTPUT
  // ============================================================
  //
  // For this first experiment:
  //
  //   A/H/C is displayed continuously.
  //
  // Decimal point indicates a close prediction.
  //
  // We deliberately removed the old "toggle display every clock"
  // behavior because the clock now drives the accelerator itself.
  //

  assign uo_out = {
      close_prediction,
      class_segments
  };


  // ============================================================
  // UNUSED TinyTapeout BIDIRECTIONAL I/O
  // ============================================================

  assign uio_out = 8'b0000_0000;
  assign uio_oe  = 8'b0000_0000;

  wire _unused = &{
      ena,
      uio_in,
      confidence_segments,
      1'b0
  };

endmodule

`default_nettype wire
