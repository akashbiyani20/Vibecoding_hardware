# Load-Store Unit (`rtl/core/lsu.sv`)

## Purpose

The bus always moves 32-bit words; C code constantly works with bytes
(char, strings) and halfwords (short). The LSU translates between them.
It's the module that made compiled C possible: gcc emits LBU for every
string character walk and SB for every byte store.

## Stores — byte lanes and strobes

A store smaller than a word must land in the right *byte lane* of its word.
The LSU replicates the value across all lanes and lets the write strobes
decide which lanes the memory actually writes:

```
SB to addr ...10, value 0xAB:  wdata = AB AB AB AB, wstrb = 0100
```

The replication trick means no shifter is needed — the strobe IS the shift.

## Loads — extract and extend

The bus returns the whole word containing the target. The LSU picks the
right byte/half using addr[1:0], then extends to 32 bits: sign-extended for
LB/LH (a char holding -1 must stay -1) or zero-extended for LBU/LHU
(0xFF must become 255). funct3 bit 2 selects which — straight from the ISA.

## Misaligned accesses

LW at a non-multiple-of-4 or LH at an odd address would straddle words.
The LSU flags these (`misaligned_o`), and the core reports them like an
illegal instruction — loud failure instead of silent data corruption.
gcc never emits misaligned accesses for normal C, so hitting this flag
means a firmware bug (usually a bad pointer cast).

## Verification

Exercised by `sw/prog7_bytes.s` on the core (sign/zero extension, lane
placement, all offsets) and by the compiled-C system test, where gcc's
string handling generates thousands of byte accesses. All green.
