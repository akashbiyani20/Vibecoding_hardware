# Memory Map (Phase 1)

All addresses are byte addresses. Each peripheral gets a 4 KB (0x1000) window,
which matches common industry practice (one MMU page per peripheral) and leaves
room for more registers later.

| Base address | Size   | Region             | Notes                          |
|--------------|--------|--------------------|--------------------------------|
| 0x0000_0000  | 4 KB   | Instruction memory | Read-only from CPU fetch       |
| 0x1000_0000  | 4 KB   | GPIO               | AXI4-Lite slave (Stage C)      |
| 0x1000_1000  | 4 KB   | UART               | AXI4-Lite slave (Stage C)      |
| 0x2000_0000  | 4 KB   | Data RAM           | Added in Stage B (LW/SW)       |

## Address decoding rule

The interconnect decodes on address bits `[31:28]` first (region select), then
bits `[15:12]` inside the peripheral region. Simple, fast, and extensible.

## Peripheral register maps

Defined when each peripheral is implemented (Stage C). Reserved so far:

- `GPIO_BASE + 0x0` — GPIO_OUT (R/W): bit 0 drives LED 0
- `UART_BASE + 0x0` — UART_TX (W): write a byte to transmit
- `UART_BASE + 0x4` — UART_STATUS (R): bit 0 = TX busy
