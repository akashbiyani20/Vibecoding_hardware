# Program 5: shifts, comparisons, upper immediates
# Expected: x1=0xFFFFF000 x2=0xFFFFFFFF x3=0x000FFFFF
#           x4=0x00FFFFF0 x5=1 x6=0 x7=0xFFF00000

lui  x1, 0xFFFFF      # x1 = 0xFFFFF000 (a negative number)
srai x2, x1, 12       # arithmetic shift: sign fills -> 0xFFFFFFFF
srli x3, x1, 12       # logical shift: zero fills   -> 0x000FFFFF
slli x4, x3, 4        #                              -> 0x00FFFFF0
slt  x5, x1, x0       # signed:   0xFFFFF000 < 0 -> 1
sltu x6, x1, x0       # unsigned: huge > 0       -> 0
xor  x7, x2, x3       # 0xFFFFFFFF ^ 0x000FFFFF  -> 0xFFF00000

done:
jal  x0, done
