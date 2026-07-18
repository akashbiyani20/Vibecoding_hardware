addi x1, x0, 10       # a = 10
addi x2, x0, 7        # counter = 7
addi x3, x0, 0        # result = 0
loop:
add  x3, x3, x1       # result += a
addi x2, x2, -1       # counter--
bne  x2, x0, loop
done:
jal  x0, done