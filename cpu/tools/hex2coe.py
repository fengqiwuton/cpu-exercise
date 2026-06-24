#!/usr/bin/env python3
"""Convert .hex file (one 32-bit word per line) to Xilinx .coe format.
Adjustable ROM/RAM depth — auto-sized or user-specified.
Usage: python3 hex2coe.py input.hex -o output.coe [-d DEPTH] [-w WIDTH]
"""
import sys, argparse, math

def generate(input_hex, output_coe, depth=None, width=32):
    with open(input_hex) as f:
        words = [line.strip() for line in f if line.strip()]

    n_words = len(words)
    if depth is None:
        # Auto-size to next power of 2
        depth = 1 << (n_words - 1).bit_length()
    if depth < n_words:
        depth = n_words

    # Pad with zeros
    words += ['0' * (width // 4)] * (depth - n_words)

    lines = []
    lines.append(f"; Auto-generated from {input_hex}")
    lines.append(f"; {n_words} words, depth={depth}, width={width}")
    lines.append(f"memory_initialization_radix=16;")
    lines.append(f"memory_initialization_vector=")

    for i, w in enumerate(words):
        comma = "," if i < len(words) - 1 else ";"
        lines.append(f"{w}{comma}")

    with open(output_coe, 'w') as f:
        f.write('\n'.join(lines) + '\n')

    print(f"{input_hex} ({n_words} words) -> {output_coe} ({depth} words, {width}-bit)")

if __name__ == '__main__':
    p = argparse.ArgumentParser(description='Hex to Xilinx COE converter')
    p.add_argument('input', help='Input .hex file')
    p.add_argument('-o', '--output', required=True, help='Output .coe file')
    p.add_argument('-d', '--depth', type=int, help='Memory depth (auto if not set)')
    p.add_argument('-w', '--width', type=int, default=32, help='Data width (default 32)')
    a = p.parse_args()
    generate(a.input, a.output, a.depth, a.width)
