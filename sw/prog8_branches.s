# prog8_branches.s — BLT/BGE/BLTU/BGEU with the classic signed/unsigned trap
# x1 = -5 (= 0xFFFFFFFB, a HUGE unsigned number), x2 = 3
# Each correct branch decision increments x10. Expected: x10 = 6.
# Any wrong decision lands on fail: and x10 becomes -1.

addi x1, x0, -5
addi x2, x0, 3
addi x10, x0, 0

blt  x1, x2, l1        # signed: -5 < 3, must take
j    fail
l1:
addi x10, x10, 1
bltu x1, x2, fail      # unsigned: 0xFFFFFFFB < 3 is FALSE, must not take
addi x10, x10, 1
bge  x2, x1, l2        # signed: 3 >= -5, must take
j    fail
l2:
addi x10, x10, 1
bgeu x1, x2, l3        # unsigned: 0xFFFFFFFB >= 3, must take
j    fail
l3:
addi x10, x10, 1
blt  x2, x1, fail      # signed: 3 < -5 false, must not take
addi x10, x10, 1
bge  x1, x2, fail      # signed: -5 >= 3 false, must not take
addi x10, x10, 1
j    done

fail:
addi x10, x0, -1
done:
j    done
