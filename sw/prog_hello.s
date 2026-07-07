# prog_hello.s — firmware: print "Hi!\n" over the UART
# The classic embedded pattern: poll the status register until the
# transmitter is free, then write the next byte.

lui  a0, 0x10001      # a0 = UART base (0x1000_1000)

addi t0, zero, 72     # 'H'
jal  ra, putc
addi t0, zero, 105    # 'i'
jal  ra, putc
addi t0, zero, 33     # '!'
jal  ra, putc
addi t0, zero, 10     # '\n'
jal  ra, putc

done:
jal  x0, done         # firmware finished, park

# ---- putc(t0): send one byte, waits until UART is free -------------
putc:
poll:
lw   t1, 4(a0)        # read STATUS (bit 0 = busy)
bne  t1, zero, poll   # spin while busy
sw   t0, 0(a0)        # write byte to TX register
jalr x0, 0(ra)        # return
