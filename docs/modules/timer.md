# Timer (`rtl/periph/axi_lite_timer.sv`)

## Purpose

A free-running 64-bit cycle counter at 0x1000_2000. Firmware reads it to
measure time and build accurate delays:

```c
uint32_t start = TIMER_LO;
while (TIMER_LO - start < n) {}   // exact n cycles, wraparound-safe
```

Compare with the delay loops in prog_blink.s: those change speed whenever
the code or clock changes. Timer delays don't — that's why every real MCU
has one.

## Registers

| Offset | Name | Access | Function |
|--------|------|--------|----------|
| 0x00 | MTIME_LO | R | low 32 bits |
| 0x04 | MTIME_HI | R | high 32 bits — returns the LATCHED value |
| any  | (write)  | W | reset counter to 0 |

## The rollover race (the educational heart of this module)

Reading 64 bits takes two bus reads, and the counter runs between them.
If the low word rolls over in that window, naive software is off by 2^32
cycles. Fix implemented here: **reading LO also latches HI into a shadow
register; reading HI returns the shadow.** Read lo-then-hi and the pair is
always coherent. The unit test forces the counter to 0xFFFF_FFF0, reads lo,
waits through the rollover, reads hi — and must get the pre-rollover value.

## Verification

`tb/unit/tb_axi_timer.sv`: counting rate, write-reset, and the shadow-latch
rollover test. Status: PASS.
