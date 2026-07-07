# prog7_bytes.s — byte/halfword loads and stores (what C string code emits)
# Expected: x3=0xFFFFFFEF x4=0xEF x5=0xFFFFFFDE x6=0xFFFFBEEF x7=0xDEAD
#           x9=0x4241 x11=0x5678, mem[4]=0x00004241, mem[8]=0x00005678

lui  x1, 0x20000       # RAM base
lui  x2, 0xDEADC       # build 0xDEADBEEF
addi x2, x2, -273      # 0xDEADC000 - 0x111 = 0xDEADBEEF
sw   x2, 0(x1)

lb   x3, 0(x1)         # byte 0xEF, signed  -> 0xFFFFFFEF
lbu  x4, 0(x1)         # byte 0xEF, unsigned-> 0x000000EF
lb   x5, 3(x1)         # byte 3 = 0xDE      -> 0xFFFFFFDE
lh   x6, 0(x1)         # half 0xBEEF signed -> 0xFFFFBEEF
lhu  x7, 2(x1)         # half 0xDEAD        -> 0x0000DEAD

addi x8, x0, 0x41      # 'A'
sb   x8, 4(x1)         # single byte into word 1, lane 0
addi x8, x0, 0x42      # 'B'
sb   x8, 5(x1)         # lane 1
lhu  x9, 4(x1)         # reads back 0x4241 ("AB" little-endian)

lui  x10, 0x12345
addi x10, x10, 0x678   # x10 = 0x12345678
sh   x10, 8(x1)        # halfword store: only 0x5678 lands
lw   x11, 8(x1)        # 0x00005678 (upper half untouched zeros)

done:
j    done
