# Memory Map (Phase 1)

All addresses are byte addresses. Each peripheral gets a 4 KB (0x1000) window,
which matches common industry practice (one MMU page per peripheral) and leaves
room for more registers later.

| Base address | Size   | Region             | Notes                          |
|--------------|--------|--------------------|--------------------------------|
| 0x0000_0000  | 4 KB   | Instruction memory | Read-only from CPU fetch       |
| 0x1000_0000  | 4 KB   | GPIO               | AXI4-Lite slave (Stage C)      |
| 0x1000_1000  | 4 KB   | UART               | AXI4-Lite slave (Stage C)      |
| 0x1000_2000  | 4 KB   | Timer              | AXI4-Lite slave (Stage E)      |
| 0x2000_0000  | 4 KB   | Data RAM           | AXI4-Lite slave                |

## Address decoding rule

The interconnect decodes on address bits `[31:28]` first (region select), then
bits `[15:12]` inside the peripheral region. Simple, fast, and extensible.

## Peripheral register maps

### GPIO (0x1000_0000)

| Offset | Name | Access | Function |
|--------|------|--------|----------|
| 0x00 | GPIO_OUT | R/W | bit N drives LED N |

### UART (0x1000_1000)

| Offset | Name | Access | Function |
|--------|------|--------|----------|
| 0x00 | TX | W | byte to transmit (ignored while TX busy) |
| 0x04 | STATUS | R | bit0 = TX busy, bit1 = RX data available |
| 0x08 | RX | R | received byte; reading pops it (clears bit1) |

### Timer (0x1000_2000)

| Offset | Name | Access | Function |
|--------|------|--------|----------|
| 0x00 | MTIME_LO | R | free-running 64-bit cycle counter, low word |
| 0x04 | MTIME_HI | R | high word |
| 0x08 | (any write) | W | resets the counter to zero |
