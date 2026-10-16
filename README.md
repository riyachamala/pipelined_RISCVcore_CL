# Pipelined RV32IM Core

A 5-stage in-order RISC-V core (RV32IM + Zicsr + Zifencei, M-mode only) with
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
                                   divide holds IF/ID/EX until its result is ready
 Branch predictor in IF: predecode + gshare + return stack + indirect BTB
```

| File                         | Purpose                                         |
|------------------------------|-------------------------------------------------|
| `rtl/rv_core.v`              | Pipeline top: stage registers and datapath      |
| `rtl/rv_decoder.v`           | Instruction decode / control signals            |
| `rtl/rv_hazard_unit.v`       | Load-use stall, flush on redirect               |
| `rtl/rv_forward_unit.v`      | EX operand forwarding                           |
| `rtl/rv_branch_predictor.v`  | IF predecode, gshare (4K × 2-bit, 12-bit history), 8-entry RAS, 32-entry indirect BTB |
| `rtl/rv_csr.v`               | M-mode CSRs, counters, trap entry/`mret`, timer IRQ |
| `rtl/rv_mul.v`, `rtl/rv_div.v` | RV32M: single-cycle multiply, 33-cycle iterative divide |
| `rtl/rv_alu.v`, `rv_branch_unit.v`, `rv_imm_gen.v`, `rv_lsu.v`, `rv_regfile.v` | Datapath blocks |
| `rtl/rv_soc.v`               | Core + RAM + CLINT + simulation I/O            |
| `rtl/rv_ram.v`, `rv_clint.v` | 4 MiB unified RAM, `mtime`/`mtimecmp`           |
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
- For the RISCOF flow: `pip install riscof` and `spike` on `PATH`. `make arch-test`
  needs neither; it checks against reference signatures stored in the suite.

## Usage

```sh
make smoke                    # directed pipeline test, no cross-compiler needed
make smoke SIM=verilator      # same on Verilator (much faster for long runs)
make smoke TRACE=1            # print every retired instruction
make lint                     # Verilator lint

make hello                    # C hello world + fib, prints cycles/instret
make sw-tests                 # self-checking C tests: muldiv, irq, sort
make test                     # smoke + riscv-tests + sw-tests
make run ELF=path/to/prog.elf # any bare-metal ELF linked at 0x80000000
make riscv-tests              # rv32ui/um/mi -p- tests from the official repo
SUITES=rv32ui make riscv-tests
make coremark SIM=verilator   # CoreMark (ITERATIONS=10 by default)

make arch-test                # riscv-arch-test vs golden reference signatures
cd tests/riscof && make setup && make   # RISCOF flow (needs spike)
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

## Performance

CoreMark 1.0, 2K performance run, 10 iterations, GCC 15.2 `-O2 -funroll-loops`,
`-march=rv32im_zicsr_zifencei`. All CRCs match EEMBC's reference values.

| Metric                         | Value          |
|--------------------------------|----------------|
| **CoreMark/MHz**               | **3.26**       |
| CPI                            | 1.096          |
| Branch/jump mispredict rate    | 5.4 % (30.8K of 574K) |
| Load-use stall cycles          | 211K (6.8 % of cycles) |

Predictor development on the same workload:

| Predictor                                     | Mispredicts | CoreMark/MHz |
|-----------------------------------------------|-------------|--------------|
| 64-entry BTB + 2-bit counters                 | 56.7K       | 3.20         |
| + gshare, history updated at EX               | 55.1K       | 3.21         |
| IF predecode + speculative gshare (1K) + RAS  | 38.9K       | 3.24         |
| PHT 4K entries, 12-bit history (current)      | 30.8K       | 3.26         |

CoreMark prints `Errors detected` only because a run must last 10 seconds to
be reportable, and simulated runs are a few million cycles. The figure of merit
for a simulated core is `Iterations × 10⁶ / Total ticks`, and the port prints
it directly. The testbench also reports mispredicts and stall cycles at the
end of every run.

## Status and next steps

- [x] RV32I pipeline: forwarding, load-use stall
- [x] Branch prediction: predecoded direct targets, gshare with speculative
  history and checkpoint repair, return address stack, indirect BTB
- [x] Zicsr, `ecall`/`ebreak`/illegal traps, `mret`, timer interrupt, `fence.i`
- [x] Precise misaligned load/store/fetch exceptions with `mtval`
- [x] Directed smoke test passes on Icarus and Verilator
- [x] RV32M multiply/divide
- [x] riscv-tests: `rv32ui-p-*` 41/41, `rv32um-p-*` 8/8, `rv32mi-p-*` 15/15 passing
  (only `ma_data` and `pmpaddr` are skipped; they need optional features)
- [x] Compiled C runs (`make hello`)
- [x] Self-checking C tests: RV32M against software references, timer
  interrupts mid-workload (including mid-divide), recursion and jump tables
- [x] Architectural compliance (riscv-arch-test 2.7.4 golden signatures):
  I 38/38, M 8/8, Zifencei 1/1, privilege 5/5 applicable
- [x] CoreMark: 3.26 CoreMark/MHz (see Performance)
- [ ] FreeRTOS boot (see `sw/freertos/README.md`)
- [ ] Synchronous BRAM fetch path for FPGA (RAM reads are combinational now)

Known simplifications: misaligned accesses trap rather than being handled in
hardware, and unimplemented CSRs read as zero and ignore writes.

Eleven privilege `misalign-*` arch tests are skipped. Their 2.7.4 reference
signatures come from a platform with the C extension and hardware misaligned
loads, both of which change the expected trap behaviour. This core's trapping
behaviour is checked by riscv-tests `rv32mi` instead.
