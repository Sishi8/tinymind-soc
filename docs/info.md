<!---
# TinyMind Clocked Accelerator

TinyMind is an 8-input, 3-class fixed-weight neural-network inference accelerator implemented in Verilog.

The clocked version adds registers around the inference logic so the design has a real synchronous register-to-register timing path.

## How it works

TinyMind accepts eight binary input features through `ui_in[7:0]`.

The inputs represent:

- `ui_in[0]` - Likes mathematics
- `ui_in[1]` - Likes programming
- `ui_in[2]` - Likes electronics
- `ui_in[3]` - Likes physics
- `ui_in[4]` - Likes data and patterns
- `ui_in[5]` - Likes building things
- `ui_in[6]` - Likes design and creativity
- `ui_in[7]` - Likes experimentation and research

On a rising edge of the clock, the eight inputs are captured into an input register.

The registered inputs are then processed by three fixed-weight neurons:

- AI-oriented neuron
- Hardware-oriented neuron
- Creative-oriented neuron

The three scores are calculated in parallel using fixed ternary weights of +1, 0, and -1.

The class with the highest score is selected as the prediction. In the event of an exact tie, the priority is AI, then Hardware, then Creative.

The design also calculates a confidence margin:

`confidence = winning score - second-highest score`

On the next rising clock edge, the predicted class and confidence information are captured into result registers.

Therefore, the main synchronous datapath is:

`Input Register -> Score Logic -> Winner Selection -> Result Register`

This creates a real register-to-register timing path that can be used to experiment with clock frequency and ASIC timing.

The prediction is displayed on the TinyTapeout seven-segment output as:

- `A` - AI-oriented
- `H` - Hardware-oriented
- `C` - Creative-oriented

The decimal point turns on when the confidence margin is 0 or 1, indicating a close prediction.

## How to test

Set `ui_in[7:0]` to the desired combination of binary features.

Apply a rising clock edge to capture the inputs into the input register.

The inference logic calculates the three class scores during the following clock cycle.

Apply the next rising clock edge to capture the prediction into the result register.

The predicted class will then appear on `uo_out[6:0]` using the seven-segment display encoding.

`uo_out[7]` is the decimal-point output and indicates a close prediction.

The automated cocotb testbench checks all 256 possible combinations of the eight binary input features.

## External hardware

No external hardware is required.

The design uses the TinyTapeout input pins, clock, reset, and output pins. The output is intended for a seven-segment display.
