#!/usr/bin/env python3
"""hex2mif.py — $readmemh hex -> Quartus .mif (fallback if Quartus refuses
to initialize inferred RAM from $readmemh; Intel tools natively prefer MIF).
Usage: python3 hex2mif.py in.hex out.mif [depth_words=1024]"""
import sys

words = [int(l, 16) for l in open(sys.argv[1]) if l.strip()]
depth = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
with open(sys.argv[2], "w") as f:
    f.write(f"WIDTH=32;\nDEPTH={depth};\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\n"
            "CONTENT BEGIN\n")
    for i, w in enumerate(words):
        f.write(f"  {i:x} : {w:08x};\n")
    if len(words) < depth:
        f.write(f"  [{len(words):x}..{depth-1:x}] : 00000000;\n")
    f.write("END;\n")
print(f"{sys.argv[1]}: {len(words)} words -> {sys.argv[2]}")
