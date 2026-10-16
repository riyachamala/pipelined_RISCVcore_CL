# Pipelined RV32I Core

A 5-stage in-order RISC-V core (RV32I + Zicsr + Zifencei, M-mode only) with
hazard detection, full forwarding, and dynamic branch prediction. It also
includes the infrastructure to run compiled C, the official riscv-tests,
RISCOF compliance, and CoreMark.

## Microarchitecture

```
 IF ──► ID ──► EX ──► MEM ──► WB
 │      │      │ ▲     │       │
 │      │      │ └─fwd─┴───────┘   MEM→EX, WB→EX forwarding; WB→ID via regfile bypass
 │      └─stall┘                   1-cycle load-use stall
 └◄──── redirect ┘                 mispredict / trap / mret / fence.i resolved in EX
 BTB+2-bit predictor (IF lookup, EX update)
```

| File                         | Purpose                                         |
|------------------------------|-------------------------------------------------|
| `rtl/rv_core.v`              | Pipeline top: stage registers and datapath      |
| `rtl/rv_decoder.v`           | Instruction decode / control signals            |
| `rtl/rv_hazard_unit.v`       | Load-use stall, flush on redirect               |
| `rtl/rv_forward_unit.v`      | EX operand forwarding                           |
| `rtl/rv_branch_predictor.v`  | 64-entry BTB with 2-bit saturating counters     |
| `rtl/rv_csr.v`               | M-mode CSRs, counters, trap entry/`mret`, timer IRQ |
| `rtl/rv_alu.v`, `rv_branch_unit.v`, `rv_imm_gen.v`, `rv_lsu.v`, `rv_regfile.v` | Datapath blocks |
| `rtl/rv_soc.v`               | Core + RAM + CLINT + simulation I/O            |
| `rtl/rv_ram.v`, `rv_clint.v` | 1 MiB unified RAM, `mtime`/`mtimecmp`           |
| `tb/tb_top.v`                | Testbench (Icarus and Verilator)                |

### Memory map

| Address        | Device                                 |
|----------------|----------------------------------------|
| `0x0200_4000`  | CLINT `mtimecmp` (lo/hi)               |
| `0x0200_BFF8`  | CLINT `mtime` (lo/hi)                  |
| `0x1000_0000`  | UART TX (write a byte → console)       |
| `0x1000_0008`  | Sim exit (write code; 0 = PASS)        |
| `0x8000_0000`  | RAM, reset vector                      |

## Prerequisites

- `iverilog` (≥ 11) and/or `verilator` (≥ 5), plus `python3`
- For C, riscv-tests, and CoreMark: a RISC-V GCC. `scripts/install_toolchain.sh`
  downloads a prebuilt xPack `riscv-none-elf-gcc` into `./tools`, and the build
  finds it automatically. Any `riscv64-unknown-elf-` or similar compiler on `PATH`
  also works; force one with `CROSS=<prefix>`.
- For RISCOF: `pip install riscof` and `spike` on `PATH`

## Usage

```sh
make smoke                    # directed pipeline test, no cross-compiler needed
make smoke SIM=verilator      # same on Verilator (much faster for long runs)
make smoke TRACE=1            # print every retired instruction
make lint                     # Verilator lint

make hello                    # C hello world + fib, prints cycles/instret
make run ELF=path/to/prog.elf # any bare-metal ELF linked at 0x80000000
make riscv-tests              # rv32ui-p-* from the official riscv-tests repo
SUITES="rv32ui rv32mi" make riscv-tests
make coremark SIM=verilator   # CoreMark (ITERATIONS=10 by default)

cd tests/riscof && make setup && make   # RISCOF architectural tests
```

Testbench plusargs (see the header of `tb/tb_top.v`): `+hex=`, `+max_cycles=`,
`+tohost=`, `+signature=`/`+sig_begin=`/`+sig_end=`, `+trace`, `+vcd`.

## Writing software

`sw/common` contains `crt0.S`, `link.ld`, a tiny `printf_`, counter helpers,
and a weak `trap_handler()` you can override. A new program needs only:

```make
PROG := myprog
SRCS := main.c
include ../common/common.mk
```

CoreMark/MHz = `Iterations × 10⁶ / Total ticks` (the port prints it ×1000).

## Status and next steps

- [x] RV32I pipeline: forwarding, load-use stall, BTB/2-bit prediction
- [x] Zicsr, `ecall`/`ebreak`/illegal traps, `mret`, timer interrupt, `fence.i`
- [x] Directed smoke test passes on Icarus and Verilator
- [x] riscv-tests `rv32ui-p-*`: 41/41 passing
- [x] Compiled C runs (`make hello`)
- [ ] RISCOF `rv32i_m/I` passing
- [ ] CoreMark score
- [ ] RV32M (hook marked `TODO(RV32M)` in `rtl/rv_decoder.v`)
- [ ] FreeRTOS boot (see `sw/freertos/README.md`)
- [ ] Synchronous BRAM fetch path for FPGA (RAM reads are combinational now)

Known simplifications: misaligned loads and stores are not trapped, and
unimplemented CSRs read as zero and ignore writes.
