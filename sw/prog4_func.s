# Program 4: a real function call — JAL to call, JALR to return
# double(a0) returns a0*2. Expected: a0 (x10) = 14, t1 (x6) = 14

addi a0, zero, 7      # argument = 7
jal  ra, double       # call double(7); ra = return address
addi t1, a0, 0        # t1 = result (proves we came back)

done:
jal  x0, done

double:               # the function
add  a0, a0, a0       # a0 *= 2
jalr x0, 0(ra)        # return (this is what `ret` means)
