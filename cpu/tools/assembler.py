#!/usr/bin/env python3
"""Minimal RV32I assembler for the CPU project.

Supports: add, sub, and, or, lw, sw, beq, blt, bge, bltu, bgeu
Registers: x0-x31
Labels: alphanumeric identifiers ending with ':'
Comments: '#' to end of line
"""

import sys
import os
import re

# ── opcode / funct ──────────────────────────────────────────────────
OP_RTYPE  = 0b0110011
OP_LOAD   = 0b0000011
OP_STORE  = 0b0100011
OP_BRANCH = 0b1100011

F3 = {
    'add':  0b000, 'sub':  0b000, 'and':  0b111, 'or':   0b110,
    'lw':   0b010, 'sw':   0b010,
    'beq':  0b000, 'blt':  0b100, 'bge':  0b101, 'bltu': 0b110, 'bgeu': 0b111,
}

F7 = {
    'add': 0b0000000,
    'sub': 0b0100000,
    'and': 0b0000000,
    'or':  0b0000000,
}

# ── parse helpers ───────────────────────────────────────────────────
def parse_reg(s):
    """Return register number from string like 'x1' or 'x0'."""
    assert s.startswith('x'), f"Expected register, got {s}"
    n = int(s[1:])
    assert 0 <= n <= 31, f"Register out of range: {s}"
    return n

def parse_imm(s):
    """Parse immediate: decimal or hex (0x...)."""
    s = s.strip()
    if s.startswith('0x') or s.startswith('0X'):
        return int(s, 16)
    # handle negative decimal
    return int(s, 0)

def sext12(val):
    """Sign-extend a 12-bit value to 32-bit."""
    val = val & 0xFFF
    if val & 0x800:
        val |= ~0xFFF
    return val

# ── encode functions ────────────────────────────────────────────────
def encode_rtype(mnem, rd, rs1, rs2):
    funct7 = F7[mnem]
    funct3 = F3[mnem]
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | OP_RTYPE

def encode_itype(rd, rs1, imm):
    """lw rd, imm(rs1)"""
    imm12 = sext12(imm) & 0xFFF
    return (imm12 << 20) | (rs1 << 15) | (F3['lw'] << 12) | (rd << 7) | OP_LOAD

def encode_stype(rs2, rs1, imm):
    """sw rs2, imm(rs1)"""
    imm12 = sext12(imm) & 0xFFF
    imm_11_5 = (imm12 >> 5) & 0x7F
    imm_4_0  = imm12 & 0x1F
    return (imm_11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (F3['sw'] << 12) | (imm_4_0 << 7) | OP_STORE

def encode_btype(mnem, rs1, rs2, offset):
    """Branch: offset is byte offset from PC (must be even)."""
    assert offset % 2 == 0, f"Branch offset must be even, got {offset}"
    # 13-bit signed offset (bit 0 is always 0 and not stored)
    off = offset
    # Extract bits for RV32I B-type encoding
    # instr[31]    = imm[12]
    # instr[30:25] = imm[10:5]
    # instr[11:8]  = imm[4:1]
    # instr[7]     = imm[11]
    instr_31    = (off >> 12) & 0x1        # imm[12]
    instr_30_25 = (off >> 5) & 0x3F        # imm[10:5]
    instr_11_8  = (off >> 1) & 0xF         # imm[4:1]
    instr_7     = (off >> 11) & 0x1        # imm[11]

    funct3 = F3[mnem]
    return (instr_31 << 31) | (instr_30_25 << 25) | (rs2 << 20) | (rs1 << 15) | \
           (funct3 << 12) | (instr_11_8 << 8) | (instr_7 << 7) | OP_BRANCH

# ── parsing a single instruction line ───────────────────────────────
def parse_instruction(line):
    """Return (label_or_None, mnem_or_None, operands_list_or_None)."""
    line = line.strip()
    # remove comment
    if '#' in line:
        line = line[:line.index('#')]
    line = line.strip()
    if not line:
        return None, None, None  # empty line

    label = None
    # label?
    if ':' in line:
        parts = line.split(':', 1)
        label = parts[0].strip()
        rest = parts[1].strip()
        if not rest:
            return label, None, None  # label only
        line = rest

    # tokenize
    # Replace commas with spaces for splitting
    line = line.replace(',', ' ')
    tokens = line.split()
    if not tokens:
        return label, None, None

    mnem = tokens[0].lower()
    operands = tokens[1:] if len(tokens) > 1 else []
    return label, mnem, operands

# ── assemble ────────────────────────────────────────────────────────
def assemble(lines):
    """Two-pass assembler. Returns list of 32-bit instruction words."""
    # Pass 1: collect labels and instructions
    instructions = []  # (addr, mnem, operands)
    labels = {}        # label -> address

    addr = 0
    for line in lines:
        label, mnem, ops = parse_instruction(line)
        if label:
            labels[label] = addr
        if mnem:
            instructions.append((addr, mnem, ops))
            addr += 4

    # Pass 2: encode
    encoded = []
    for addr, mnem, ops in instructions:
        if mnem in ('add', 'sub', 'and', 'or'):
            assert len(ops) == 3, f"R-type needs 3 operands, got {ops}"
            rd  = parse_reg(ops[0])
            rs1 = parse_reg(ops[1])
            rs2 = parse_reg(ops[2])
            word = encode_rtype(mnem, rd, rs1, rs2)

        elif mnem == 'lw':
            # lw rd, imm(rs1)
            assert len(ops) == 2, f"lw needs 2 operands, got {ops}"
            rd = parse_reg(ops[0])
            # parse offset(rs1)
            m = re.match(r'([-]?\d+|0x[0-9a-fA-F]+)\(x(\d+)\)', ops[1])
            assert m, f"lw operand format: offset(rs1), got {ops[1]}"
            imm = parse_imm(m.group(1))
            rs1 = int(m.group(2))
            word = encode_itype(rd, rs1, imm)

        elif mnem == 'sw':
            # sw rs2, imm(rs1)
            assert len(ops) == 2, f"sw needs 2 operands, got {ops}"
            rs2 = parse_reg(ops[0])
            m = re.match(r'([-]?\d+|0x[0-9a-fA-F]+)\(x(\d+)\)', ops[1])
            assert m, f"sw operand format: offset(rs1), got {ops[1]}"
            imm = parse_imm(m.group(1))
            rs1 = int(m.group(2))
            word = encode_stype(rs2, rs1, imm)

        elif mnem in ('beq', 'blt', 'bge', 'bltu', 'bgeu'):
            # branch rs1, rs2, label
            assert len(ops) == 3, f"Branch needs 3 operands, got {ops}"
            rs1 = parse_reg(ops[0])
            rs2 = parse_reg(ops[1])
            label = ops[2]
            assert label in labels, f"Undefined label: {label}"
            target = labels[label]
            offset = target - addr
            word = encode_btype(mnem, rs1, rs2, offset)

        else:
            raise ValueError(f"Unknown mnemonic: {mnem}")

        encoded.append(word)

    return encoded

# ── main ────────────────────────────────────────────────────────────
def main():
    import argparse
    parser = argparse.ArgumentParser(description='RV32I subset assembler')
    parser.add_argument('input', help='Assembly source file')
    parser.add_argument('-o', '--output', help='Output hex file')
    args = parser.parse_args()

    with open(args.input, 'r') as f:
        lines = f.readlines()

    words = assemble(lines)

    if args.output:
        with open(args.output, 'w') as f:
            for w in words:
                f.write(f'{w:08X}\n')
        print(f"Assembled {len(words)} instructions -> {args.output}")
    else:
        for w in words:
            print(f'{w:08X}')

if __name__ == '__main__':
    main()
