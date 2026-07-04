# Program 3: data memory — store, load back, modify, store again
# Data RAM lives at 0x2000_0000 (see docs/memory_map.md)
# Expected result: x3 = 42, x4 = 43, mem[0] = 42, mem[4] = 43

lui  x1, 0x20000      # x1 = 0x2000_0000 (data RAM base)
addi x2, x0, 42
sw   x2, 0(x1)        # mem[0] = 42
lw   x3, 0(x1)        # x3 = 42 (read it back)
addi x4, x3, 1        # x4 = 43
sw   x4, 4(x1)        # mem[4] = 43

done:
jal  x0, done
