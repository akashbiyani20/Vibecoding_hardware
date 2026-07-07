# ============================================================================
# crt0.S — the C runtime's "moment zero"
# ----------------------------------------------------------------------------
# The CPU wakes up at address 0 knowing nothing about C. Before main() can
# run, three promises of the C language must be made true by hand:
#   1. there is a stack           -> point sp at the top of RAM
#   2. gp-relative addressing     -> point gp at __global_pointer$
#   3. uninitialized globals == 0 -> zero the .bss region
# Then call main. If main ever returns, park in a harmless loop.
# (.rodata/.data need no copying here — they're preloaded into RAM at
#  flash time, see link.ld.)
# ============================================================================

    .section .text.start
    .globl _start
_start:
    # 1. stack pointer
    la   sp, __stack_top

    # 2. global pointer (relaxation must be off while setting gp itself)
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    # 3. zero .bss
    la   t0, __bss_start
    la   t1, __bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    # into C
    call main

    # main returned — park forever
3:  j    3b
