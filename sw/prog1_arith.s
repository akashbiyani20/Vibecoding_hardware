# Program 1: the README's first demo — a=5, b=10, c=a+b
# Expected result: x3 = 15

addi x1, x0, 5        # a = 5
addi x2, x0, 10       # b = 10
add  x3, x1, x2       # c = a + b = 15

done:
jal  x0, done         # park forever (self-loop)
