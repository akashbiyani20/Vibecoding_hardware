# GPIO Peripheral (`rtl/periph/axi_lite_gpio.sv`)

## Purpose

The simplest peripheral, and the moment software touches the physical world:
a memory-mapped register whose bits drive output pins (LEDs). `sw x2, 0(x1)`
with x1 = 0x1000_0000 turns LEDs on or off — exactly the README's Phase 1
GPIO goal.

## Register map (base 0x1000_0000)

| Offset | Name     | Access | Function                              |
|--------|----------|--------|----------------------------------------|
| 0x00   | GPIO_OUT | R/W    | bit N drives led_o[N]; reads current  |
| 0x04   | (reserved) | —    | future GPIO_IN for switches           |

Unmapped offsets: writes ignored, reads return 0.

## Design notes

- Pins reset to 0 (LEDs off) — peripherals with physical outputs should
  power up in a known, harmless state.
- The AXI slave handshake is the same pattern as axi_lite_ram — accept
  AW+W together, hold B until taken; register read data, hold R until taken.
  Learn it once, read every slave in the project.

## Verification (`tb/unit/tb_axi_gpio.sv`, 261 checks)

Driven through the verified AXI bridge: reset state, write→pins, read-back,
all 256 patterns, unmapped-offset behavior. Status: **PASS**.
