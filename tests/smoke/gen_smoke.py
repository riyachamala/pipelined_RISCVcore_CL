#!/usr/bin/env python3
"""Directed smoke test for the pipeline, assembled without a RISC-V toolchain.

Exercises: ALU ops, EX/MEM + MEM/WB forwarding, load-use stall, byte/half
loads and stores, loops (branch predictor), JAL/JALR, AUIPC, CSRs, ECALL/MRET
trap round-trip, illegal-instruction trap, fence.i self-modifying code, timer interrupt, UART.

Pass/fail is reported riscv-tests style via a store to `tohost`:
    1 = pass, (n << 1) | 1 = failed at check n.

    python3 tests/smoke/gen_smoke.py build/smoke.hex   # prints tohost addr
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts"))
from rvasm import Asm  # noqa: E402

BASE   = 0x80000000
TOHOST = 0x80001000
DATA   = 0x80002000
UART   = 0x10000000
CLINT  = 0x02000000

a = Asm(BASE)
check_id = [0]


def check(reg, expected):
    """Branch to fail with test number in s11 if reg != expected."""
    check_id[0] += 1
    a.li("s11", check_id[0])
    a.li("t6", expected)
    a.bne(reg, "t6", "fail")


# ---------------------------------------------------------------- setup
a.la("t0", "trap_handler")
a.csrw("mtvec", "t0")
a.li("s0", DATA)

# ---------------------------------------------------------------- forwarding
a.addi("x1", "zero", 5)
a.addi("x2", "x1", 3)          # EX/MEM -> EX
a.add("x3", "x1", "x2")        # MEM/WB + EX/MEM
a.sub("x4", "x3", "x1")
a.add("x5", "x4", "x4")        # both operands forwarded
check("x2", 8)
check("x3", 13)
check("x4", 8)
check("x5", 16)

# ---------------------------------------------------------------- ALU
a.li("x6", 0xF0F0F0F0)
a.li("x7", 0x0FF00FF0)
a.and_("x30", "x6", "x7");  check("x30", 0x00F000F0)
a.or_("x30", "x6", "x7");   check("x30", 0xFFF0FFF0)
a.xor("x30", "x6", "x7");   check("x30", 0xFF00FF00)
a.srai("x30", "x6", 4);     check("x30", 0xFF0F0F0F)
a.srli("x30", "x6", 4);     check("x30", 0x0F0F0F0F)
a.slli("x30", "x7", 4);     check("x30", 0xFF00FF00)
a.slt("x30", "x6", "x7");   check("x30", 1)
a.sltu("x30", "x6", "x7");  check("x30", 0)
a.sltiu("x30", "x7", -1);   check("x30", 1)
a.lui("x30", 0x12345);      check("x30", 0x12345000)

# ---------------------------------------------------------------- loads / stores
a.li("x9", 0xDEADBEEF)
a.sw("x9", 0, "s0")
a.lw("x10", 0, "s0")
a.addi("x11", "x10", 1)        # load-use stall
check("x11", 0xDEADBEF0)
a.lb("x12", 0, "s0");  check("x12", 0xFFFFFFEF)
a.lbu("x12", 3, "s0"); check("x12", 0xDE)
a.lh("x12", 2, "s0");  check("x12", 0xFFFFDEAD)
a.lhu("x12", 0, "s0"); check("x12", 0xBEEF)
a.li("x13", 0x55)
a.sb("x13", 1, "s0")
a.lw("x12", 0, "s0");  check("x12", 0xDEAD55EF)
a.li("x13", 0x1234)
a.sh("x13", 2, "s0")
a.lw("x12", 0, "s0");  check("x12", 0x123455EF)
a.sw("x12", 4, "s0")   # store data forwarded from load (MEM/WB)
a.lw("x14", 4, "s0");  check("x14", 0x123455EF)

# ---------------------------------------------------------------- loop (predictor)
a.li("x15", 0)
a.li("x16", 0)
a.li("x17", 100)
a.label("loop")
a.addi("x15", "x15", 1)
a.add("x16", "x16", "x15")
a.bne("x15", "x17", "loop")
check("x16", 5050)

# ---------------------------------------------------------------- calls
a.li("x18", 0)
a.jal("ra", "func")
a.label("after_call")
check("x18", 42)
a.la("x19", "after_call")
check_id[0] += 1
a.li("s11", check_id[0])
a.bne("ra", "x19", "fail")
a.la("x20", "func")
a.jalr("ra", "x20", 0)         # indirect call
check("x18", 84)

# ---------------------------------------------------------------- CSRs
a.li("x21", 0x1234)
a.csrw("mscratch", "x21")
a.csrrsi("x22", "mscratch", 0x3)
check("x22", 0x1234)
a.csrr("x22", "mscratch"); check("x22", 0x1237)
a.csrr("x23", "mcycle")
a.csrr("x24", "mcycle")
check_id[0] += 1
a.li("s11", check_id[0])
a.bgeu("x23", "x24", "fail")   # cycle counter must advance

# ---------------------------------------------------------------- traps
a.li("s1", 0)
a.ecall()
check("s1", 1)
a.csrr("x25", "mcause"); check("x25", 11)
a.word(0xFFFFFFFF)             # illegal instruction
check("s1", 2)
a.csrr("x25", "mcause"); check("x25", 2)

# ---------------------------------------------------------------- fence.i (SMC)
a.la("x24", "patch")
a.li("x25", 0x00700E13)        # addi t3, zero, 7
a.sw("x25", 0, "x24")
a.fence_i()
a.label("patch")
a.li("t3", 1)                  # overwritten above
check("t3", 7)

# ---------------------------------------------------------------- timer interrupt
a.li("s2", 0)
a.li("t0", CLINT + 0xBFF8)
a.lw("t1", 0, "t0")            # mtime lo
a.addi("t1", "t1", 100)
a.li("t0", CLINT + 0x4000)
a.sw("zero", 4, "t0")          # mtimecmp hi = 0 first, then lo
a.sw("t1", 0, "t0")
a.li("t2", 0x80)
a.csrw("mie", "t2")            # MTIE
a.csrrsi("zero", "mstatus", 8) # MIE
a.label("wait_irq")
a.beq("s2", "zero", "wait_irq")
check("s2", 1)
a.csrr("t2", "mstatus")
a.andi("t2", "t2", 8)
check("t2", 8)                 # mret restored MIE
a.csrrci("zero", "mstatus", 8)

# ---------------------------------------------------------------- UART
a.li("x28", UART)
for ch in b"smoke ok\n":
    a.li("x29", ch)
    a.sb("x29", 0, "x28")

# ---------------------------------------------------------------- pass / fail
a.li("t0", TOHOST)
a.li("t1", 1)
a.sw("t1", 0, "t0")
a.label("spin_pass")
a.j("spin_pass")

a.label("fail")
a.li("t0", TOHOST)
a.slli("t1", "s11", 1)
a.ori("t1", "t1", 1)
a.sw("t1", 0, "t0")
a.label("spin_fail")
a.j("spin_fail")

# ---------------------------------------------------------------- subroutines
a.label("func")
a.addi("x18", "x18", 42)
a.ret()

a.label("trap_handler")
a.csrr("t5", "mcause")
a.blt("t5", "zero", "irq_handler")
a.addi("s1", "s1", 1)          # exception: count in s1, skip faulting instr
a.csrr("t5", "mepc")
a.addi("t5", "t5", 4)
a.csrw("mepc", "t5")
a.mret()

a.label("irq_handler")         # timer: count in s2, disarm mtimecmp
a.li("t5", CLINT + 0x4000)
a.li("t4", -1)
a.sw("t4", 4, "t5")
a.sw("t4", 0, "t5")
a.addi("s2", "s2", 1)
a.mret()

a.org(TOHOST)
a.word(0)

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "smoke.hex"
    a.write_hex(out)
    print("%08x" % TOHOST)
