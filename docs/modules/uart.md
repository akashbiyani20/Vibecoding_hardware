# UART TX Peripheral (`rtl/periph/axi_lite_uart.sv`)

## Purpose

Lets firmware print text to a serial terminal — the embedded world's
"printf". CPU writes a byte to the TX register; this module serializes it
onto one wire in the 8N1 format every terminal understands.

## The 8N1 frame

```
idle(1) → start(0) → d0 d1 d2 d3 d4 d5 d6 d7 → stop(1) → idle(1)
                     LSB first
```

Each bit lasts `CLKS_PER_BIT` clocks. 100 MHz / 115200 baud = 868.
Testbenches use 16 so simulations stay fast — same logic, faster wall clock.

Implementation trick worth reading: the 10-bit frame {stop, data, start}
sits in a shift register that shifts 1s in from the top, so when the frame
ends, the line is already back at idle level with zero extra logic.

## Register map (base 0x1000_1000)

| Offset | Name   | Access | Function                                 |
|--------|--------|--------|-------------------------------------------|
| 0x00   | TX     | W      | byte to transmit (ignored while busy)     |
| 0x04   | STATUS | R      | bit 0 = busy                              |

## The software contract

```asm
poll:  lw   t1, 4(a0)      # read STATUS
       bne  t1, zero, poll # spin while busy
       sw   t0, 0(a0)      # write next byte
```

This poll-then-write loop (see sw/prog_hello.s) is the universal pattern for
slow peripherals without interrupts. Interrupts are a future extension —
they replace the spinning, not the register interface.

## Verification (`tb/unit/tb_axi_uart.sv`, 19 checks)

Black-box: the testbench contains an independent 8N1 receiver that samples
the wire mid-bit like a real terminal. Checks framing (start/stop bits),
bit order (0x55 alternating pattern), busy flag timing, write-while-busy
rejection, and a polled 3-byte stream. Status: **PASS**.
