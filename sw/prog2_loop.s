# Program 2: loop with a backward branch — sum 1+2+3+4+5
# Expected result: x5 = 15, x6 = 5

addi x5, x0, 0        # sum = 0
addi x6, x0, 0        # i = 0
addi x7, x0, 5        # limit = 5

loop:
addi x6, x6, 1        # i++
add  x5, x5, x6       # sum += i
bne  x6, x7, loop     # repeat until i == 5

done:
jal  x0, done
