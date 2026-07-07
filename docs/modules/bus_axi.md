# The AXI4-Lite Bus (`rtl/bus/`)

## Why a bus at all?

Until Stage C, the core's data port was wired straight to a testbench memory
that answered instantly. Real systems don't work that way: multiple
peripherals share one connection, and each takes its own time to answer.
A bus protocol is the contract that makes this work. We use **AXI4-Lite** —
the simplest member of ARM's AMBA family and probably the most common
peripheral bus in industry.

## AXI4-Lite in five channels

Every access decomposes into handshakes on independent channels:

| Channel | Direction | Carries |
|---------|-----------|---------|
| AW | master → slave | write address |
| W  | master → slave | write data + byte strobes |
| B  | slave → master | write response (OKAY/error) |
| AR | master → slave | read address |
| R  | slave → master | read data + response |

One rule runs the whole protocol: **a transfer happens in the cycle where
`valid` and `ready` are both high**, and once you raise `valid` you must hold
it (payload frozen) until `ready` answers. A write = AW + W then wait for B.
A read = AR then wait for R.

## `axi_lite_master.sv` — the bridge

Translates the core's simple "address + read/write" port into AXI and
**stalls the core** (freezing PC and register writes) until the response
lands. State machine: IDLE → WRITE → RESP_B → IDLE for writes,
IDLE → READ → RESP_R → IDLE for reads. One transaction outstanding at a
time — simple and sufficient for a single-cycle core.

The stall is the educational heart of Stage C: a load instruction now
*stretches over multiple cycles* while the bus works. Watch `stall` in the
tb_soc waveform during any `lw`/`sw` to see it.

## `axi_lite_xbar.sv` — the interconnect

Address decoder + multiplexers: `addr[31:28]` picks the region, then
`addr[15:12]` picks the peripheral (see docs/memory_map.md). Requests are
routed to exactly one slave; responses are muxed back.

Unmapped addresses hit a built-in **default responder** that answers DECERR
instead of letting the bus hang — a wild pointer in firmware produces a
diagnosable error, not a frozen chip.

Honest simplification: the decode follows the currently presented address,
which is safe only because our bridge guarantees one outstanding
transaction. Multi-master interconnects must latch the routing decision.

## Verification

`tb_axi_bridge.sv` (49 checks): bridge + RAM slave over real AXI, write/read-
back, stall timing, 100-op random soak vs a model, plus a cycle-by-cycle AXI
stability invariant (payload must not change while valid is held). The
peripherals' testbenches and tb_soc reuse the same bridge, so every AXI
transfer in the project crosses verified handshake logic.
