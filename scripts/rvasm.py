"""Tiny RV32I + Zicsr assembler embedded in Python.

Used to build directed tests (tests/smoke) without a RISC-V toolchain:

    a = Asm(base=0x80000000)
    a.label("loop")
    a.addi("t0", "t0", 1)
    a.bne("t0", "t1", "loop")
    words = a.assemble()
"""

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
       "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
       "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
       "t3", "t4", "t5", "t6"]

CSRS = {"mstatus": 0x300, "misa": 0x301, "mie": 0x304, "mtvec": 0x305,
        "mscratch": 0x340, "mepc": 0x341, "mcause": 0x342, "mtval": 0x343,
        "mip": 0x344, "mcycle": 0xB00, "minstret": 0xB02, "mcycleh": 0xB80,
        "minstreth": 0xB82, "cycle": 0xC00, "time": 0xC01, "instret": 0xC02,
        "mhartid": 0xF14}


def reg(r):
    if isinstance(r, int):
        return r
    if r == "fp":
        return 8
    if r in ABI:
        return ABI.index(r)
    if r.startswith("x"):
        return int(r[1:])
    raise ValueError(f"bad register {r!r}")


def csr(c):
    return CSRS[c] if isinstance(c, str) else c


def _r(f7, f3, op, rd, rs1, rs2):
    return (f7 << 25) | (reg(rs2) << 20) | (reg(rs1) << 15) | (f3 << 12) | (reg(rd) << 7) | op


def _i(imm, f3, op, rd, rs1):
    return ((imm & 0xFFF) << 20) | (reg(rs1) << 15) | (f3 << 12) | (reg(rd) << 7) | op


def _s(imm, f3, op, rs1, rs2):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (reg(rs2) << 20) | (reg(rs1) << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def _b(off, f3, rs1, rs2):
    assert -4096 <= off < 4096 and off % 2 == 0, f"branch offset {off} out of range"
    o = off & 0x1FFF
    return (((o >> 12) & 1) << 31) | (((o >> 5) & 0x3F) << 25) | (reg(rs2) << 20) | (reg(rs1) << 15) | \
           (f3 << 12) | (((o >> 1) & 0xF) << 8) | (((o >> 11) & 1) << 7) | 0x63


def _u(imm20, op, rd):
    return ((imm20 & 0xFFFFF) << 12) | (reg(rd) << 7) | op


def _j(off, rd):
    assert -(1 << 20) <= off < (1 << 20) and off % 2 == 0
    o = off & 0x1FFFFF
    return (((o >> 20) & 1) << 31) | (((o >> 1) & 0x3FF) << 21) | (((o >> 11) & 1) << 20) | \
           (((o >> 12) & 0xFF) << 12) | (reg(rd) << 7) | 0x6F


def _hi_lo(v):
    lo = ((v & 0xFFF) ^ 0x800) - 0x800
    hi = ((v - lo) >> 12) & 0xFFFFF
    return hi, lo


class Asm:
    def __init__(self, base=0x80000000):
        self.base = base
        self.items = []      # int or callable(pc, labels) -> int
        self.labels = {}

    @property
    def pc(self):
        return self.base + 4 * len(self.items)

    def label(self, name):
        assert name not in self.labels, f"duplicate label {name}"
        self.labels[name] = self.pc

    def word(self, value):
        self.items.append(value & 0xFFFFFFFF)

    def org(self, addr):
        assert addr >= self.pc, "org moves backwards"
        while self.pc < addr:
            self.word(0)

    def _target(self, t, pc):
        return self.labels[t] - pc if isinstance(t, str) else t

    def assemble(self):
        out = []
        for i, it in enumerate(self.items):
            pc = self.base + 4 * i
            out.append(it(pc, self.labels) if callable(it) else it)
        return out

    def write_hex(self, path):
        with open(path, "w") as f:
            for w in self.assemble():
                f.write("%08x\n" % w)

    # ------------------------------------------------------------- R-type
    def add(self, rd, a, b):  self.word(_r(0x00, 0, 0x33, rd, a, b))
    def sub(self, rd, a, b):  self.word(_r(0x20, 0, 0x33, rd, a, b))
    def sll(self, rd, a, b):  self.word(_r(0x00, 1, 0x33, rd, a, b))
    def slt(self, rd, a, b):  self.word(_r(0x00, 2, 0x33, rd, a, b))
    def sltu(self, rd, a, b): self.word(_r(0x00, 3, 0x33, rd, a, b))
    def xor(self, rd, a, b):  self.word(_r(0x00, 4, 0x33, rd, a, b))
    def srl(self, rd, a, b):  self.word(_r(0x00, 5, 0x33, rd, a, b))
    def sra(self, rd, a, b):  self.word(_r(0x20, 5, 0x33, rd, a, b))
    def or_(self, rd, a, b):  self.word(_r(0x00, 6, 0x33, rd, a, b))
    def and_(self, rd, a, b): self.word(_r(0x00, 7, 0x33, rd, a, b))

    # ------------------------------------------------------------- I-type ALU
    def addi(self, rd, a, i):  self.word(_i(i, 0, 0x13, rd, a))
    def slti(self, rd, a, i):  self.word(_i(i, 2, 0x13, rd, a))
    def sltiu(self, rd, a, i): self.word(_i(i, 3, 0x13, rd, a))
    def xori(self, rd, a, i):  self.word(_i(i, 4, 0x13, rd, a))
    def ori(self, rd, a, i):   self.word(_i(i, 6, 0x13, rd, a))
    def andi(self, rd, a, i):  self.word(_i(i, 7, 0x13, rd, a))
    def slli(self, rd, a, s):  self.word(_i(s, 1, 0x13, rd, a))
    def srli(self, rd, a, s):  self.word(_i(s, 5, 0x13, rd, a))
    def srai(self, rd, a, s):  self.word(_i(0x400 | s, 5, 0x13, rd, a))

    # ------------------------------------------------------------- loads / stores
    def lb(self, rd, off, base):  self.word(_i(off, 0, 0x03, rd, base))
    def lh(self, rd, off, base):  self.word(_i(off, 1, 0x03, rd, base))
    def lw(self, rd, off, base):  self.word(_i(off, 2, 0x03, rd, base))
    def lbu(self, rd, off, base): self.word(_i(off, 4, 0x03, rd, base))
    def lhu(self, rd, off, base): self.word(_i(off, 5, 0x03, rd, base))
    def sb(self, rs, off, base):  self.word(_s(off, 0, 0x23, base, rs))
    def sh(self, rs, off, base):  self.word(_s(off, 1, 0x23, base, rs))
    def sw(self, rs, off, base):  self.word(_s(off, 2, 0x23, base, rs))

    # ------------------------------------------------------------- branches / jumps
    def _br(self, f3, a, b, t):
        self.items.append(lambda pc, L: _b(self._target(t, pc), f3, a, b))

    def beq(self, a, b, t):  self._br(0, a, b, t)
    def bne(self, a, b, t):  self._br(1, a, b, t)
    def blt(self, a, b, t):  self._br(4, a, b, t)
    def bge(self, a, b, t):  self._br(5, a, b, t)
    def bltu(self, a, b, t): self._br(6, a, b, t)
    def bgeu(self, a, b, t): self._br(7, a, b, t)

    def jal(self, rd, t):
        self.items.append(lambda pc, L: _j(self._target(t, pc), rd))

    def jalr(self, rd, base, off=0): self.word(_i(off, 0, 0x67, rd, base))

    # ------------------------------------------------------------- upper imm
    def lui(self, rd, imm20):   self.word(_u(imm20, 0x37, rd))
    def auipc(self, rd, imm20): self.word(_u(imm20, 0x17, rd))

    # ------------------------------------------------------------- system
    def ecall(self):   self.word(0x00000073)
    def ebreak(self):  self.word(0x00100073)
    def mret(self):    self.word(0x30200073)
    def fence(self):   self.word(0x0FF0000F)
    def fence_i(self): self.word(0x0000100F)

    def csrrw(self, rd, c, rs):   self.word(_i(csr(c), 1, 0x73, rd, rs))
    def csrrs(self, rd, c, rs):   self.word(_i(csr(c), 2, 0x73, rd, rs))
    def csrrc(self, rd, c, rs):   self.word(_i(csr(c), 3, 0x73, rd, rs))
    def csrrwi(self, rd, c, imm): self.word(_i(csr(c), 5, 0x73, rd, imm))
    def csrrsi(self, rd, c, imm): self.word(_i(csr(c), 6, 0x73, rd, imm))
    def csrrci(self, rd, c, imm): self.word(_i(csr(c), 7, 0x73, rd, imm))

    # ------------------------------------------------------------- pseudo-instructions
    def nop(self):          self.addi("zero", "zero", 0)
    def mv(self, rd, rs):   self.addi(rd, rs, 0)
    def j(self, t):         self.jal("zero", t)
    def ret(self):          self.jalr("zero", "ra", 0)
    def csrr(self, rd, c):  self.csrrs(rd, c, "zero")
    def csrw(self, c, rs):  self.csrrw("zero", c, rs)

    def li(self, rd, v):
        v &= 0xFFFFFFFF
        sv = v - (1 << 32) if v & 0x80000000 else v
        if -2048 <= sv < 2048:
            self.addi(rd, "zero", sv)
        else:
            hi, lo = _hi_lo(v)
            self.lui(rd, hi)
            if lo:
                self.addi(rd, rd, lo)

    def la(self, rd, t):
        """auipc + addi to a label (PC-relative)."""
        self.items.append(lambda pc, L: _u(_hi_lo(L[t] - pc)[0], 0x17, rd))
        self.items.append(lambda pc, L: _i(_hi_lo(L[t] - (pc - 4))[1], 0, 0x13, rd, rd))
