/* ============================================================================
 * link.ld — linker script matching docs/memory_map.md
 * ----------------------------------------------------------------------------
 * The linker's job: decide the ADDRESS of every function and variable.
 * This script tells it about our two memories:
 *   IMEM 4 KB at 0x00000000 — code (the CPU fetches from here)
 *   RAM  4 KB at 0x20000000 — constants, globals, and the stack
 *
 * Constants (.rodata — string literals!) must live in RAM, not IMEM,
 * because our Harvard-style core cannot LOAD from instruction memory —
 * the data bus doesn't reach it. Both memories are preloaded at "flash"
 * time (hex files -> $readmemh in sim, BRAM init on FPGA).
 * ==========================================================================*/

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
  RAM  (rwx) : ORIGIN = 0x20000000, LENGTH = 4K
}

ENTRY(_start)

SECTIONS
{
  .text : {
    KEEP(*(.text.start))        /* crt0 first — the CPU boots at 0x0 */
    *(.text*)
  } > IMEM

  .data : {
    *(.rodata*) *(.srodata*)    /* constants + string literals */
    *(.data*)  *(.sdata*)       /* initialized globals */
  } > RAM

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss*) *(.sbss*) *(COMMON)
    __bss_end = .;
  } > RAM

  /* linker relaxation anchor (gp-relative addressing optimization) */
  __global_pointer$ = ADDR(.data) + 0x800;

  /* stack grows DOWN from the top of RAM */
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
