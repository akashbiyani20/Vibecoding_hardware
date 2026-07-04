# RISC-V SoC From Scratch (Minimal Version)

> **Goal:** Build a minimal but industry-style RISC-V System-on-Chip completely from scratch using AI-assisted development (Claude Opus 5), while understanding every component in depth instead of simply generating code.

This project is intended to be **educational first** and **resume-worthy second**.

The philosophy is simple:

> **Every module should be understood before it is implemented.**

---

# Project Vision

The final long-term goal is to build a complete embedded SoC that includes:

- Custom RISC-V CPU
- Bus architecture
- GPIO
- UART 
- Power gating (UPF-inspired concepts)
- FPGA implementation
- Verification
- Documentation

However,

**we are NOT building everything at once.**

Instead, we will build the SoC incrementally.

---

# Phase 1 (Current Goal)

The first milestone consists of only four major blocks.

```
                   +----------------------+
                   |     RISC-V CPU       |
                   +----------+-----------+
                              |
                        AXI4-Lite Bus
                              |
                +-------------+-------------+
                |                           |
             GPIO Peripheral          UART Peripheral
                |                           |
             LEDs / Switches         Serial Terminal
```

This is intentionally minimal.

Once this is stable and verified, we will extend the architecture.

---

# Future Extensions

These modules are **NOT** part of Phase 1.

They will be added later.

- Data Memory
- Timer
- Interrupt Controller
- SPI
- Flash Controller
- DMA
- Performance Counters
- Clock Gating
- Sleep Controller
- Power Gating Concepts
- UPF-inspired architecture
- FPGA optimization

---

# Development Philosophy

The purpose of this repository is **not simply to generate RTL**.

Instead:

- understand every module
- document every module
- verify every module
- synthesize every module
- integrate step by step

Every block should be readable and understandable by someone learning digital design.

Avoid unnecessary complexity.

Use clean architecture.

Use industry coding style.

---

# CPU Overview

The CPU will be a small in-order RISC-V processor.

Initially we are targeting RV32I.

No caches.

No branch prediction.

No superscalar execution.

No out-of-order execution.

The goal is understanding.

---

# CPU Pipeline

The CPU will contain the following blocks.

```
                 +-------------------+
                 | Program Counter   |
                 +---------+---------+
                           |
                           V
                  Instruction Memory
                           |
                           V
                  Instruction Fetch
                           |
                           V
                         Decode
                           |
          +----------------+----------------+
          |                                 |
          V                                 V
    Register File                    Control Unit
          |                                 |
          +----------------+----------------+
                           |
                           V
                          ALU
                           |
                           V
                     Memory Access
                           |
                           V
                       Write Back
```

Each block should be implemented as an independent Verilog module wherever practical.

---

# Program Counter

Responsibilities:

- Hold current instruction address
- Increment normally
- Support branch targets
- Support jump targets
- Reset correctly
- Handle sequential execution cleanly

Design should be simple and modular.

---

# Instruction Memory

Initially:

Instruction Memory may be modeled using Verilog memory arrays.

Later this may become:

- ROM
- Block RAM
- External Memory

Instruction Memory should support:

- instruction fetch
- reset
- initialization using memory files if appropriate

---

# Instruction Fetch

Responsibilities:

- Read instruction from Program Counter
- Pass instruction to Decode stage
- Handle reset properly

---

# Instruction Decode

Decode should identify:

- opcode
- source register(s)
- destination register
- immediate values
- instruction format
- ALU operation
- memory operation
- branch operation

Control signals should be generated cleanly.

Avoid monolithic code.

---

# Register File

Implement RV32I register file.

Requirements:

- 32 registers
- 32-bit width
- x0 always reads as zero
- dual read ports
- single write port
- synchronous write
- combinational read

---

# Control Unit

Generate control signals for:

- ALU
- Register Write
- Memory Read
- Memory Write
- Branch
- Jump
- Immediate selection
- Write-back selection

The control logic should remain easy to understand.

---

# ALU

The ALU should initially support at least:

Arithmetic

- ADD
- SUB

Logical

- AND
- OR
- XOR

Shift

- SLL
- SRL
- SRA

Comparison

- SLT
- SLTU

Pass-through if necessary for immediate operations.

Design should allow easy extension later.

---

# Memory Access Stage

Initially support:

- Load Word (LW)
- Store Word (SW)

Later extensions:

- LB
- LH
- LBU
- LHU
- SB
- SH

For Phase 1 only implement the minimum necessary functionality.

---

# Write Back Stage

Support writing results back into:

- Register File

Sources may include:

- ALU Result
- Memory Result

---

# Supported Instructions

Initially implement a small subset of RV32I.

Suggested minimum:

Arithmetic

- ADD
- SUB
- ADDI

Logical

- AND
- OR
- XOR

Shift

- SLL
- SRL
- SRA

Comparison

- SLT
- SLTU

Memory

- LW
- SW

Control Flow

- BEQ
- BNE
- JAL

This instruction set may be expanded later.

---

# Bus Architecture

The CPU should communicate with peripherals through a standard bus.

Preferred option:

**AXI4-Lite**

Reason:

- widely used in industry
- simple enough for learning
- good documentation
- scalable
- easy to integrate with future peripherals

If Claude believes another bus (such as Wishbone) is significantly more appropriate for a learning-first architecture, it may propose that alternative **with clear justification** before implementation.

---

# Memory Map

A simple memory map should be created.

Example:

```
0x00000000   Instruction Memory

0x10000000   GPIO

0x10001000   UART
```

Claude may adjust addresses if needed, but the memory map should remain clean, documented, and extensible.

---

# GPIO Peripheral

Responsibilities:

- Memory-mapped peripheral
- Output LEDs
- Future support for input switches

Minimum functionality:

CPU writes:

```
GPIO_REGISTER = 1
```

LED turns ON.

CPU writes:

```
GPIO_REGISTER = 0
```

LED turns OFF.

---

# UART Peripheral

Responsibilities:

- Memory mapped
- Simple transmit path initially
- Optional receive path later

Goal:

Allow CPU firmware to print messages over serial.

Eventually something like:

```
Hello World

Counter = 10

LED ON

Done
```

UART implementation should remain intentionally simple.

---

# Software Demonstrations

The CPU should eventually execute simple programs such as:

Example 1

```
a = 5
b = 10
c = a + b
```

Example 2

```
Blink LED forever
```

Example 3

```
Print over UART
```

Example 4

```
Loop counter
```

Example 5

```
Multiply two numbers

(software implementation initially)

Later this may become a hardware multiplier.
```

---

# Verification Strategy

Verification is extremely important.

Every module should include:

## Unit Testing

Examples:

- ALU tests
- Register File tests
- Program Counter tests
- Decoder tests

---

## Integration Testing

Examples:

CPU + ALU

CPU + Register File

CPU + AXI

CPU + GPIO

CPU + UART

---

## System Testing

Run complete programs.

Examples:

- arithmetic
- LED blinking
- UART output
- branch instructions

---

## Black Box Testing

Verify expected external behavior without looking inside implementation.

---

## White Box Testing

Verify internal signals, pipeline states, control signals, registers, and data paths.

---

# Testbench Requirements

Develop self-checking testbenches wherever practical.

Waveforms should be generated.

Expected outputs should be compared automatically.

Testbench code should be clean and documented.

---

# FPGA Support

Currently available hardware:

**NXP FRDM-MCXN947 development board**

If this board is suitable for implementing this project, please adapt the project accordingly.

Otherwise,

keep the RTL vendor-neutral so it can later be synthesized for a common FPGA platform such as:

- Digilent Arty
- Basys 3
- Nexys A7
- Intel DE10-Lite
- or similar educational FPGA boards

The RTL should avoid unnecessary vendor-specific IP unless absolutely required.

---

# Synthesis Flow

After functional verification:

1. Lint RTL
2. Simulate
3. Pass all testbenches
4. Synthesize
5. Generate netlist
6. Review utilization
7. Review timing
8. Generate FPGA bitstream
9. Program FPGA
10. Demonstrate hardware functionality

---

# Documentation Requirements

Documentation quality is a major objective of this project.

Every module should include:

- Purpose
- Inputs
- Outputs
- Timing behavior
- Internal architecture
- Block diagrams where appropriate
- Design decisions
- Future improvements

Documentation should be written for someone who is learning digital design.

Assume the reader is new to CPU architecture.

Avoid unnecessary jargon.

Explain concepts clearly.

---

# Coding Guidelines

- Use clean Verilog/SystemVerilog.
- Keep modules small and modular.
- Prefer readability over clever optimizations.
- Comment important logic.
- Follow consistent naming conventions.
- Keep interfaces simple.
- Avoid large monolithic modules.

---

# AI Collaboration Instructions

This project is intended to be developed collaboratively.

Please do **not** generate the entire project in a single response.

Instead:

1. Propose an implementation plan.
2. Explain design choices before coding.
3. Build one module at a time.
4. Verify each module before moving to the next.
5. Keep documentation updated as the project evolves.

If you believe a different architectural decision would produce a cleaner, more educational, or more industry-relevant design, explain your reasoning before implementing it.

If any requirement in this README is unclear, **ask questions before making assumptions**. It is better to clarify the design than to proceed with an incorrect implementation.