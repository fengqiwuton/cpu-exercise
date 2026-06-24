#!/usr/bin/env python3
"""Convert .hex file (one 32-bit word per line) to raw binary with header.
Header: 4 bytes (word count, little-endian), then N*4 bytes of program data.
Output: raw binary file for UART transfer to bootloader.
"""
import sys, struct, argparse

def convert(hex_path, bin_path):
    with open(hex_path) as f:
        words = [int(line.strip(), 16) for line in f if line.strip()]

    with open(bin_path, 'wb') as f:
        # Header: word count (u32 LE)
        f.write(struct.pack('<I', len(words)))
        # Program data
        for w in words:
            f.write(struct.pack('<I', w))

    print(f"{hex_path} ({len(words)} words) -> {bin_path} ({4 + len(words)*4} bytes)")

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('hex', help='Input .hex file')
    p.add_argument('bin', help='Output .bin file')
    a = p.parse_args()
    convert(a.hex, a.bin)
