#!/usr/bin/env python3
"""Full RV32I assembler for the CPU project. Supports all 37 base integer instructions."""
import sys, argparse, re

# ── opcodes ──────────────────────────────────────────────────
OP_RTYPE  = 0b0110011
OP_IALU   = 0b0010011
OP_LOAD   = 0b0000011
OP_STORE  = 0b0100011
OP_BRANCH = 0b1100011
OP_JAL    = 0b1101111
OP_JALR   = 0b1100111
OP_LUI    = 0b0110111
OP_AUIPC  = 0b0010111

# ── funct3 ──────────────────────────────────────────────────
F3 = {
    'add':0,'sub':0,'addi':0,
    'sll':1,'slli':1,
    'slt':2,'slti':2,
    'sltu':3,'sltiu':3,
    'xor':4,'xori':4,
    'srl':5,'srli':5,'sra':5,'srai':5,
    'or':6,'ori':6,
    'and':7,'andi':7,
    'lb':0,'lh':1,'lw':2,'lbu':4,'lhu':5,
    'sb':0,'sh':1,'sw':2,
    'beq':0,'bne':1,'blt':4,'bge':5,'bltu':6,'bgeu':7,
}

# ── funct7 ──────────────────────────────────────────────────
F7 = {
    'add':0x00,'sub':0x20,'sll':0x00,'slt':0x00,'sltu':0x00,
    'xor':0x00,'srl':0x00,'sra':0x20,'or':0x00,'and':0x00,
    'addi':0x00,'slli':0x00,'slti':0x00,'sltiu':0x00,
    'xori':0x00,'srli':0x00,'srai':0x20,'ori':0x00,'andi':0x00,
}

R_INSTRS  = {'add','sub','sll','slt','sltu','xor','srl','sra','or','and'}
I_ALU     = {'addi','slli','slti','sltiu','xori','srli','srai','ori','andi'}
LOADS     = {'lb','lh','lw','lbu','lhu'}
STORES    = {'sb','sh','sw'}
BRANCHES  = {'beq','bne','blt','bge','bltu','bgeu'}
JUMPS     = {'jal','jalr'}
UPPERS    = {'lui','auipc'}
PSEUDO    = {'la','nop','li','mv','call','ret','j'}  # expanded in pass 1

# ── helpers ─────────────────────────────────────────────────
def parse_reg(s):
    s = s.strip()
    if s.startswith('x'): return int(s[1:])
    regs = {'zero':0,'ra':1,'sp':2,'gp':3,'tp':4,
            't0':5,'t1':6,'t2':7,'s0':8,'fp':8,'s1':9,
            'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,'a6':16,'a7':17,
            's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,
            's8':24,'s9':25,'s10':26,'s11':27,
            't3':28,'t4':29,'t5':30,'t6':31}
    assert s in regs, f"Unknown register: {s}"
    return regs[s]

def parse_imm(s):
    s = s.strip()
    if s.startswith('0x') or s.startswith('0X'): return int(s,16)
    return int(s)

def parse_mem(ops):
    """Parse 'imm(rs1)' or 'rs2, imm(rs1)' → (rs1, rs2, imm)."""
    op = ops[-1]
    m = re.match(r'([-]?\w+)\((\w+)\)', op)
    assert m, f"Bad mem operand: {op}"
    return parse_reg(m.group(2)), parse_imm(m.group(1))

def imm_mask(val, bits, signed=False):
    """Truncate + optionally sign-extend."""
    mask = (1 << bits) - 1
    val = val & mask
    if signed and (val >> (bits - 1)):
        val |= ~mask
    return val

# ── encoders ────────────────────────────────────────────────
def enc_r(mnem, rd, rs1, rs2):
    return (F7[mnem] << 25) | (rs2 << 20) | (rs1 << 15) | (F3[mnem] << 12) | (rd << 7) | OP_RTYPE

def enc_ialu(mnem, rd, rs1, imm):
    if mnem in ('slli','srli','srai'):
        upper = ((F7[mnem] << 5) | (imm & 0x1F)) & 0xFFF
    else:
        upper = imm & 0xFFF
    return (upper << 20) | (rs1 << 15) | (F3[mnem] << 12) | (rd << 7) | OP_IALU

def enc_load(mnem, rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (F3[mnem] << 12) | (rd << 7) | OP_LOAD

def enc_store(mnem, rs1, rs2, imm):
    im = imm & 0xFFF
    return ((im >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (F3[mnem] << 12) | ((im & 0x1F) << 7) | OP_STORE

def enc_branch(mnem, rs1, rs2, offset):
    assert offset % 2 == 0, f"Branch offset must be even"
    return (((offset >> 12) & 1) << 31) | (((offset >> 5) & 0x3F) << 25) | \
           (rs2 << 20) | (rs1 << 15) | (F3[mnem] << 12) | \
           (((offset >> 1) & 0xF) << 8) | (((offset >> 11) & 1) << 7) | OP_BRANCH

def enc_jal(rd, offset):
    """J-type: 21-bit signed offset, bit 0 = 0."""
    return (((offset >> 20) & 1) << 31) | (((offset >> 1) & 0x3FF) << 21) | \
           (((offset >> 11) & 1) << 20) | (((offset >> 12) & 0xFF) << 12) | \
           (rd << 7) | OP_JAL

def enc_jalr(rd, rs1, imm):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | OP_JALR

def enc_upper(mnem, rd, imm):
    """LUI/AUIPC: imm = 20-bit upper immediate, stored in instr[31:12]."""
    return (imm & 0xFFFFF) << 12 | (rd << 7) | (OP_LUI if mnem == 'lui' else OP_AUIPC)

def expand_pseudo(mnem, ops, addr, labels):
    """Expand pseudo-instructions into real RV32I instructions.
    Returns list of (mnem, ops) tuples."""
    if mnem == 'la':
        # la rd, symbol → auipc rd, hi20 + addi rd, rd, lo12
        rd = ops[0]
        sym = ops[1]
        if sym in labels:
            offset = labels[sym] - addr
        else:
            offset = parse_imm(sym)
        hi = (offset + 0x800) & 0xFFFFF000
        lo = offset - hi
        return [('auipc', [rd, str(hi)]), ('addi', [rd, rd, str(lo)])]
    elif mnem == 'li':
        # li rd, imm → addi rd, x0, imm (if imm fits 12-bit)
        return [('addi', [ops[0], 'x0', ops[1]])]
    elif mnem == 'mv':
        # mv rd, rs → addi rd, rs, 0
        return [('addi', [ops[0], ops[1], '0'])]
    elif mnem == 'call':
        # call symbol → auipc x1, hi + jalr x1, x1, lo
        sym = ops[0]
        if sym in labels: offset = labels[sym] - addr
        else: offset = parse_imm(sym)
        hi = (offset + 0x800) & 0xFFFFF000
        lo = offset - hi
        return [('auipc', ['x1', str(hi)]), ('jalr', ['x1', 'x1', str(lo)])]
    elif mnem == 'ret':
        return [('jalr', ['x0', 'x1', '0'])]
    elif mnem == 'j':
        # j label → jal x0, label
        return [('jal', ['x0', ops[0]])]
    return [(mnem, ops)]

# ── assemble ────────────────────────────────────────────────
def assemble(lines):
    # Pass 1: collect labels (pseudo-instructions count as their expanded size)
    labels = {}
    addr = 0
    for raw in lines:
        line = raw.split('#')[0].strip()
        if not line: continue
        if ':' in line:
            lab, _, rest = line.partition(':')
            labels[lab.strip()] = addr
            line = rest.strip()
            if not line: continue
        parts = line.replace(',', ' ').split()
        mnem = parts[0].lower()
        # Count expanded instruction slots (2 for la/call, 1 for others)
        addr += 8 if mnem in ('la','call') else 4

    # Pass 2: expand + encode
    instrs = []
    addr = 0
    for raw in lines:
        line = raw.split('#')[0].strip()
        if not line: continue
        if ':' in line:
            _, _, rest = line.partition(':')
            line = rest.strip()
            if not line: continue
        parts = line.replace(',', ' ').split()
        mnem = parts[0].lower()
        expanded = expand_pseudo(mnem, parts[1:], addr, labels)
        for exp_mnem, exp_ops in expanded:
            instrs.append((addr, exp_mnem, exp_ops))
            addr += 4

    # Pass 2: encode
    code = []
    for addr, mnem, ops in instrs:
        if mnem in R_INSTRS:
            word = enc_r(mnem, parse_reg(ops[0]), parse_reg(ops[1]), parse_reg(ops[2]))
        elif mnem in I_ALU:
            rd, rs1, imm = parse_reg(ops[0]), parse_reg(ops[1]), parse_imm(ops[2])
            if mnem in ('slli','srli','srai'):
                imm = imm & 0x1F  # shift amount is 5 bits
            word = enc_ialu(mnem, rd, rs1, imm)
        elif mnem in LOADS:
            rd = parse_reg(ops[0])
            rs1, imm = parse_mem(ops[1:])
            word = enc_load(mnem, rd, rs1, imm)
        elif mnem in STORES:
            rs2 = parse_reg(ops[0])
            rs1, imm = parse_mem(ops[1:])
            word = enc_store(mnem, rs1, rs2, imm)
        elif mnem in BRANCHES:
            rs1, rs2 = parse_reg(ops[0]), parse_reg(ops[1])
            tgt = ops[2]
            if tgt in labels: offset = labels[tgt] - addr
            else: offset = parse_imm(tgt)
            word = enc_branch(mnem, rs1, rs2, offset)
        elif mnem == 'jal':
            rd = parse_reg(ops[0])
            tgt = ops[1]
            if tgt in labels: offset = labels[tgt] - addr
            else: offset = parse_imm(tgt)
            word = enc_jal(rd, offset)
        elif mnem == 'jalr':
            rd = parse_reg(ops[0])
            if '(' in str(ops[1:]):
                rs1, imm = parse_mem(ops[1:])
            else:
                rs1 = parse_reg(ops[1])
                imm = parse_imm(ops[2]) if len(ops) > 2 else 0
            word = enc_jalr(rd, rs1, imm)
        elif mnem in UPPERS:
            rd = parse_reg(ops[0])
            imm = parse_imm(ops[1])
            word = enc_upper(mnem, rd, imm)
        elif mnem == 'nop':
            word = enc_ialu('addi', 0, 0, 0)
        else:
            raise ValueError(f"Unknown instruction at 0x{addr:08x}: {mnem}")
        code.append(word)
    return code

def main():
    p = argparse.ArgumentParser()
    p.add_argument('input'); p.add_argument('-o','--output')
    a = p.parse_args()
    with open(a.input, encoding='utf-8') as f: words = assemble(f.readlines())
    out = a.output or a.input.rsplit('.',1)[0] + '.hex'
    with open(out,'w',encoding='utf-8') as f: f.write('\n'.join(f'{w:08X}' for w in words) + '\n')
    print(f"{a.input} -> {out} ({len(words)} instrs)")

if __name__ == '__main__': main()
