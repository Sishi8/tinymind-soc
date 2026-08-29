![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# TinyMind SoC

### From a Tiny Inference Equation to a Processor-Controlled Accelerator in Silicon

**TinyMind SoC** is a small educational System-on-Chip that combines a custom CPU, program ROM, clocked inference accelerator, control logic, result registers, and a seven-segment display interface.

The design is written in Verilog, runs at **10 MHz**, and is physically implemented for **TinyTapeout using SKY130**.

The goal of this project is not to build a high-performance AI processor. Instead, TinyMind is designed as a transparent case study for understanding how a simple algorithm evolves into a clocked hardware accelerator, becomes part of a processor-controlled system, and eventually becomes physical digital logic.

- [TinyTapeout project documentation](docs/info.md)

---

# Why This Project?

TinyMind started with a simple question:

> **What actually happens when we take an algorithm and turn it into hardware?**

Rather than starting with a large CPU or complicated machine-learning accelerator, TinyMind uses a deliberately small inference problem that can be understood from beginning to end.

The project evolved through several stages:

```text
Inference Equations
        │
        ▼
Combinational RTL
        │
        ▼
Clocked RTL
        │
        ▼
Input / Result Registers
        │
        ▼
START / BUSY / DONE
        │
        ▼
TinyMind Accelerator
        │
        ▼
Tiny CPU + Program ROM
        │
        ▼
TinyMind SoC
        │
        ▼
Synthesis
        │
        ▼
SKY130 Standard Cells
        │
        ▼
Placement
        │
        ▼
Clock Tree Synthesis
        │
        ▼
Routing
        │
        ▼
GDS
        │
        ▼
Silicon
```

This allows the project to be studied not just as Verilog code, but as the complete journey:

```text
Algorithm → RTL → Architecture → Gates → Timing → Physical Design
```

---

# What Does TinyMind Do?

TinyMind receives **8 binary input features**.

Each feature is either:

```text
0 = No
1 = Yes
```

The input features are:

| Input | Feature |
|---|---|
| `ui_in[0]` | Likes mathematics |
| `ui_in[1]` | Likes programming |
| `ui_in[2]` | Likes electronics |
| `ui_in[3]` | Likes physics |
| `ui_in[4]` | Likes data and patterns |
| `ui_in[5]` | Likes building things |
| `ui_in[6]` | Likes design and creativity |
| `ui_in[7]` | Likes experimentation and research |

TinyMind evaluates three fixed-weight scoring functions in hardware.

### AI-oriented score

```text
score_ai =
x0 + x1 + x4 - x5 + x7 + 1
```

### Hardware-oriented score

```text
score_hardware =
x0 + x2 + x3 + x5 - x6
```

### Creative-oriented score

```text
score_creative =
-x1 - x2 + x5 + x6 + x7 + 1
```

The class with the highest score wins.

The internal class encoding is:

```text
00 = AI-oriented
01 = Hardware-oriented
10 = Creative-oriented
```

If two classes have the same score, the priority is:

```text
AI > Hardware > Creative
```

---

# Confidence

TinyMind also calculates a confidence margin:

```text
confidence =
winning score - second-highest score
```

The confidence value is limited to a maximum of 9.

A prediction is considered **close** when:

```text
confidence margin <= 1
```

This close-prediction condition is displayed using the decimal point on the seven-segment output.

---

# TinyMind SoC Architecture

The final version places the TinyMind accelerator inside a small processor-controlled system.

```text
                     10 MHz CLOCK
                          │
                          ▼
                  ┌───────────────┐
                  │   Tiny CPU    │
                  │               │
ui_in[7:0] ──────►│ Program       │
                  │ Counter       │
                  │               │
                  │ ACC Register  │
                  │               │
                  │ Program ROM   │
                  └───────┬───────┘
                          │
                          │
                          ▼
                  ┌───────────────┐
                  │   TinyMind    │
                  │  Accelerator  │
                  │               │
                  │ Feature Reg   │
                  │               │
                  │ 3 Parallel    │
                  │ Score Paths   │
                  │               │
                  │ Winner Logic  │
                  │               │
                  │ Result Regs   │
                  └───────┬───────┘
                          │
                          ▼
                  ┌───────────────┐
                  │  CPU Result   │
                  │   Registers   │
                  └───────┬───────┘
                          │
                          ▼
                  ┌───────────────┐
                  │ Seven-Segment │
                  │    Decoder    │
                  └───────┬───────┘
                          │
                          ▼
                     uo_out[7:0]
```

The basic synchronous idea throughout the design is:

```text
REGISTER
   │
   ▼
COMBINATIONAL LOGIC
   │
   ▼
REGISTER
```

---

# The Tiny CPU

The SoC contains a deliberately small custom CPU/controller.

The CPU includes:

- Program Counter (PC)
- 8-bit accumulator/input register
- result registers
- control logic
- small program ROM

This is **not a RISC-V processor** and does not implement a standard instruction-set architecture.

It is intentionally small so the basic processor concept can be understood clearly:

```text
Program Counter
      │
      ▼
Read Instruction
      │
      ▼
Execute Instruction
      │
      ▼
Update Registers
      │
      ▼
Next Program Counter
```

---

# Program ROM

The CPU executes a small fixed program.

| PC | Instruction | Purpose |
|---:|---|---|
| 0 | `WAIT_RUN` | Wait for CPU run enable |
| 1 | `READ_INPUT` | Capture `ui_in[7:0]` |
| 2 | `WRITE_FEATURE` | Write features to TinyMind |
| 3 | `START` | Start the accelerator |
| 4 | `WAIT_DONE` | Wait for TinyMind to finish |
| 5 | `READ_RESULT` | Capture the inference result |
| 6 | `DISPLAY` | Present the captured result |
| 7 | `LOOP` | Return for another inference |

The program flow is:

```text
WAIT_RUN
    │
    ▼
READ_INPUT
    │
    ▼
WRITE_FEATURE
    │
    ▼
START
    │
    ▼
WAIT_DONE
    │
    ▼
READ_RESULT
    │
    ▼
DISPLAY
    │
    ▼
LOOP
    │
    └──────────────► READ_INPUT
```

---

# CPU ↔ TinyMind Accelerator

One inference operation follows this sequence:

```text
External Input
     │
     ▼
CPU READ_INPUT
     │
     ▼
CPU ACC Register
     │
     ▼
WRITE_FEATURE
     │
     ▼
TinyMind Feature Register
     │
     ▼
START
     │
     ▼
BUSY
     │
     ▼
TinyMind Inference
     │
     ▼
Result Registers
     │
     ▼
DONE
     │
     ▼
CPU READ_RESULT
     │
     ▼
CPU Result Registers
     │
     ▼
Seven-Segment Decoder
     │
     ▼
   A / H / C
```

This demonstrates a simple accelerator control handshake:

```text
START
  │
  ▼
BUSY
  │
  ▼
COMPUTE
  │
  ▼
DONE
```

---

# Clocking

TinyMind SoC runs at:

```text
10 MHz
```

A 10 MHz clock has a period of:

```text
100 ns
```

Registers capture their inputs on rising clock edges.

Conceptually:

```text
Rising Edge                           Rising Edge
     │                                    │
     ▼                                    ▼
┌─────────┐                          ┌─────────┐
│Register │                          │Register │
│captures │                          │captures │
└────┬────┘                          └─────────┘
     │
     │
     │     Combinational Logic
     │
     ├────► Score AI ───────────┐
     │                          │
     ├────► Score Hardware ─────┼──► Winner
     │                          │       │
     └────► Score Creative ─────┘       ▼
                                      Result

     <----------- 100 ns ------------>
```

This register-to-register behavior is also the foundation of static timing analysis.

---

# How to Operate TinyMind SoC

## 1. Reset the SoC

The design uses an active-low reset.

Assert reset:

```text
rst_n = 0
```

Then release it:

```text
rst_n = 1
```

The CPU returns to the beginning of its program.

---

## 2. Set the Input Features

Place the feature vector on:

```text
ui_in[7:0]
```

For example:

```text
ui_in = 10100101
```

The eight bits represent the eight yes/no features.

---

## 3. Enable the CPU

Set:

```text
uio_in[0] = 1
```

This enables CPU execution.

---

## 4. The CPU Takes Over

Once enabled, the CPU automatically performs:

```text
READ_INPUT
    ↓
WRITE_FEATURE
    ↓
START
    ↓
WAIT_DONE
    ↓
READ_RESULT
    ↓
DISPLAY
```

The external user does not need to manually control TinyMind's internal accelerator registers.

---

## 5. Read the Prediction

The prediction is presented on:

```text
uo_out[6:0]
```

The seven-segment patterns represent:

```text
A = AI-oriented

H = Hardware-oriented

C = Creative-oriented
```

The decimal-point signal is:

```text
uo_out[7]
```

When:

```text
uo_out[7] = 1
```

the winning score and second-highest score were separated by a margin of 1 or less.

---

# Pin Interface

## Dedicated Inputs

| Pin | Description |
|---|---|
| `ui_in[0]` | Likes mathematics |
| `ui_in[1]` | Likes programming |
| `ui_in[2]` | Likes electronics |
| `ui_in[3]` | Likes physics |
| `ui_in[4]` | Likes data and patterns |
| `ui_in[5]` | Likes building things |
| `ui_in[6]` | Likes design and creativity |
| `ui_in[7]` | Likes experimentation and research |

## Bidirectional Inputs

| Pin | Description |
|---|---|
| `uio_in[0]` | CPU run enable |
| `uio_in[7:1]` | Unused |

The bidirectional outputs are disabled:

```text
uio_out = 0
uio_oe  = 0
```

## Dedicated Outputs

| Pin | Description |
|---|---|
| `uo_out[0]` | Seven-segment g |
| `uo_out[1]` | Seven-segment f |
| `uo_out[2]` | Seven-segment e |
| `uo_out[3]` | Seven-segment d |
| `uo_out[4]` | Seven-segment c |
| `uo_out[5]` | Seven-segment b |
| `uo_out[6]` | Seven-segment a |
| `uo_out[7]` | Close-prediction decimal point |

---

# Verification

The project uses a cocotb verification environment.

There are eight binary input features, giving:

```text
2^8 = 256
```

possible input combinations.

The testbench checks **all 256 combinations**.

For each feature vector:

```text
Python Reference Model
          │
          │ expected result
          ▼
        Compare
          ▲
          │ actual result
          │
      TinyMind SoC
```

The test does not manually perform the accelerator transaction.

Instead:

```text
cocotb
   │
   │ feature vector
   ▼
Tiny CPU
   │
   ▼
TinyMind
   │
   ▼
CPU Result Register
   │
   ▼
Seven-Segment Output
```

This verifies the behavior of the complete SoC from its external interface.

---

# Physical Implementation

TinyMind SoC is implemented using the SKY130 technology through the TinyTapeout digital design flow.

The final successful implementation produced approximately:

| Item | Result |
|---|---:|
| Clock frequency | 10 MHz |
| Clock period | 100 ns |
| TinyTapeout tile | 1 × 1 |
| Utilization | 13.871% |
| Routed wire length | 3784 µm |
| Flip-Flops | 29 |
| Multiplexers | 25 |
| Combinational Logic | 36 |
| NOR | 24 |
| Buffers | 15 |
| Clock Cells | 14 |
| AND | 10 |
| NAND | 10 |
| Inverters | 9 |
| OR | 9 |
| Fill / Decap | 3812 |
| Tap Cells | 225 |

The exact physical cell implementation is determined by synthesis and physical-design optimization.

RTL constructs do not necessarily map one-to-one to physical cells.

For example:

```text
RTL

reg [7:0] acc
       │
       ▼
SYNTHESIS
       │
       ▼
Physical Flip-Flops
```

while an RTL expression such as:

```text
if / else
case
comparison
addition
subtraction
```

may become combinations of:

```text
MUX
AND
OR
NAND
NOR
INV
other standard cells
```

---

# Physical Design Flow

The design progresses through:

```text
Verilog RTL
     │
     ▼
RTL Simulation
     │
     ▼
Synthesis
     │
     ▼
SKY130 Standard Cells
     │
     ▼
Floorplanning
     │
     ▼
Placement
     │
     ▼
Clock Tree Synthesis
     │
     ▼
Routing
     │
     ▼
Timing / Physical Checks
     │
     ▼
Gate-Level Simulation
     │
     ▼
GDS
```

The final SoC successfully completed:

```text
GDS                 PASS
Precheck            PASS
Gate-Level Test     PASS
GDS Viewer          PASS
```

---

# What This Project Is — and Is Not

TinyMind is a **small fixed-weight neural-style inference accelerator**.

It is not intended to be a competitive machine-learning accelerator.

It does not:

- train a neural network
- execute an LLM
- contain a high-performance AI processor
- implement a standard general-purpose CPU such as RISC-V

Instead, the simplicity is intentional.

It makes it possible to follow a computation through the entire hardware stack:

```text
Mathematical Equation
        ↓
Verilog
        ↓
Combinational Logic
        ↓
Registers
        ↓
Clock Cycles
        ↓
CPU Instructions
        ↓
Accelerator Control
        ↓
Synthesis
        ↓
Standard Cells
        ↓
Timing
        ↓
Placement
        ↓
Clock Tree
        ↓
Routing
        ↓
GDS
        ↓
Silicon
```

---

# Learning Goals

TinyMind SoC can be used as a practical introduction to:

- Boolean and combinational logic
- sequential logic
- flip-flops
- registers
- clocks
- clock periods
- register-to-register paths
- static timing analysis
- simple inference hardware
- fixed-weight computation
- accelerator architecture
- START/BUSY/DONE handshakes
- program counters
- instruction ROMs
- CPU control
- hardware/software interaction
- synthesis
- standard cells
- placement
- clock-tree synthesis
- routing
- gate-level simulation
- GDS
- ASIC implementation

---

# The Bigger Learning Story

TinyMind is designed so that each architectural step answers a question.

```text
How does an equation become hardware?
              │
              ▼
       Combinational RTL


Why do we need registers?
              │
              ▼
        Clocked TinyMind


How does another block control it?
              │
              ▼
      START / BUSY / DONE


How does it become an accelerator?
              │
              ▼
      Feature + Result Registers


Who controls the accelerator?
              │
              ▼
            CPU


How does the CPU know what to do?
              │
              ▼
       Program Counter + ROM


How does RTL become a chip?
              │
              ▼
 Synthesis → P&R → CTS → GDS
```

The long-term goal is to use the project as a reproducible case study where each of these stages can be explored independently.

---

# Repository Structure

```text
TinyMind SoC
│
├── src/
│   └── project.v
│       ├── TinyTapeout top module
│       ├── tiny CPU
│       ├── program ROM
│       ├── TinyMind accelerator
│       └── seven-segment decoder
│
├── test/
│   └── test.py
│       └── cocotb verification
│
├── docs/
│   └── info.md
│       └── TinyTapeout project documentation
│
└── info.yaml
    └── project configuration and pinout
```

---

# Future Experiments

The working TinyMind SoC provides a foundation for future educational experiments such as:

- inspecting the synthesized netlist
- tracing individual flip-flops back to RTL
- studying the CPU program counter physically
- identifying accelerator registers
- tracing the clock tree
- studying the critical timing path
- changing the clock frequency
- comparing synthesis results
- adding a small RAM
- exploring SRAM macros
- adding UART communication
- experimenting with a larger processor architecture

These can be developed separately while preserving the known-working TinyMind SoC implementation.

---

# TinyMind in One Sentence

> **TinyMind is a tiny clocked SoC in which a custom CPU executes a small program that controls a fixed-weight inference accelerator and displays the resulting class on a seven-segment output, implemented from Verilog through SKY130 physical design.**

---

# TinyTapeout

This project is designed for TinyTapeout, an educational project that makes it possible to manufacture small digital and analog designs on real silicon.

To learn more:

- [TinyTapeout](https://tinytapeout.com/)
- [TinyTapeout FAQ](https://tinytapeout.com/faq/)
- [Digital Design Lessons](https://tinytapeout.com/digital_design/)
- [Learn How Semiconductors Work](https://tinytapeout.com/siliwiz/)
- [TinyTapeout Community](https://tinytapeout.com/discord)
- [Local Hardening Guide](https://www.tinytapeout.com/guides/local-hardening/)

For project-specific operating instructions, see:

**[docs/info.md](docs/info.md)**tapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
