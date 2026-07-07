# prog_blink.s — firmware: blink the LED forever
# Writes alternating 1/0 to GPIO_OUT with a delay loop in between.
# On FPGA with a real clock the delay constant becomes millions;
# in simulation we keep it small so the waveform shows many blinks.

lui  x1, 0x10000      # x1 = GPIO base (0x1000_0000)
addi x2, x0, 0        # LED state

blink:
xori x2, x2, 1        # toggle state
sw   x2, 0(x1)        # write it to the LED register
addi x3, x0, 6        # delay counter
delay:
addi x3, x3, -1
bne  x3, x0, delay
jal  x0, blink        # forever
