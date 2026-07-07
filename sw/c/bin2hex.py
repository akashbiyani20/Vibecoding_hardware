#!/usr/bin/env python3
"""bin2hex.py — raw binary -> $readmemh format (32-bit little-endian words)"""
import sys

data = open(sys.argv[1], "rb").read()
data += b"\x00" * (-len(data) % 4)          # pad to word boundary
with open(sys.argv[2], "w") as f:
    for i in range(0, len(data), 4):
        w = int.from_bytes(data[i:i+4], "little")
        f.write(f"{w:08x}\n")
print(f"{sys.argv[1]}: {len(data)//4} words -> {sys.argv[2]}")
