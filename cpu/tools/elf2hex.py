#!/usr/bin/env python3
"""Convert RISC-V ELF to separate code (.text) and data (.data) hex files.
Usage: python3 elf2hex.py program.elf --code program.hex --data data.hex
"""
import sys, struct, argparse

def read_elf(path):
    with open(path, 'rb') as f:
        ident = f.read(16)
        if ident[:4] != b'\x7fELF':
            raise ValueError("Not an ELF file")
        is_32bit = ident[4] == 1
        is_little = ident[5] == 1
        endian = '<' if is_little else '>'

        # Read ELF header
        if is_32bit:
            f.seek(0)
            hdr = f.read(52)
            entry, phoff, shoff, flags, ehsize = struct.unpack_from(endian + 'IIIII', hdr, 24)
            phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from(endian + 'HHHHH', hdr, 42)
        else:
            f.seek(0)
            hdr = f.read(64)
            entry, phoff, shoff, flags, ehsize = struct.unpack_from(endian + 'QQIIII', hdr, 24)
            phentsize, phnum, shentsize, shnum, shstrndx = struct.unpack_from(endian + 'HHHHHH', hdr, 52)

        # Read program headers to find loadable segments
        segments = []
        for i in range(phnum):
            f.seek(phoff + i * phentsize)
            if is_32bit:
                ph = f.read(phentsize)
                p_type, p_offset, p_vaddr, p_paddr = struct.unpack_from(endian + 'IIII', ph, 0)
                filesz, memsz, flags, align = struct.unpack_from(endian + 'IIII', ph, 16)
            else:
                ph = f.read(phentsize)
                p_type, p_flags, p_offset, p_vaddr, p_paddr = struct.unpack_from(endian + 'IIQQQ', ph, 0)
                filesz, memsz, flags, align = struct.unpack_from(endian + 'QQII', ph, 32)

            if p_type == 1:  # PT_LOAD
                f.seek(p_offset)
                data = f.read(filesz)
                segments.append((p_vaddr, data, memsz, flags))

        return segments

def write_hex(segments, vaddr_min, vaddr_max, output_path):
    """Write hex file for address range [vaddr_min, vaddr_max)."""
    size = vaddr_max - vaddr_min
    mem = bytearray(size)

    for vaddr, data, memsz, flags in segments:
        start = vaddr - vaddr_min
        end = start + len(data)
        if start >= 0 and start < size:
            copy_end = min(end, size)
            mem[start:copy_end] = data[:copy_end - start]
        # Zero-fill beyond file data up to memsz
        if memsz > len(data):
            bss_start = vaddr + len(data) - vaddr_min
            bss_end = vaddr + memsz - vaddr_min
            if bss_start >= 0 and bss_end <= size:
                mem[bss_start:bss_end] = b'\x00' * (bss_end - bss_start)

    # Write as 32-bit little-endian words
    lines = []
    for i in range(0, len(mem), 4):
        if i + 4 <= len(mem):
            word = struct.unpack_from('<I', mem, i)[0]
            lines.append(f'{word:08X}')

    with open(output_path, 'w') as f:
        f.write('\n'.join(lines) + '\n')

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('elf', help='Input ELF file')
    p.add_argument('--code', help='Output code (text) hex file')
    p.add_argument('--data', help='Output data hex file')
    p.add_argument('--code-base', default='0x00000000', help='Code base address')
    p.add_argument('--code-size', default='0x1000', help='Code region size')
    p.add_argument('--data-base', default='0x00001000', help='Data base address')
    p.add_argument('--data-size', default='0x1000', help='Data region size')
    args = p.parse_args()

    segments = read_elf(args.elf)
    code_base = int(args.code_base, 16)
    code_size = int(args.code_size, 16)
    data_base = int(args.data_base, 16)
    data_size = int(args.data_size, 16)

    if args.code:
        write_hex(segments, code_base, code_base + code_size, args.code)
        print(f"Code hex -> {args.code}")
    if args.data:
        write_hex(segments, data_base, data_base + data_size, args.data)
        print(f"Data hex -> {args.data}")
