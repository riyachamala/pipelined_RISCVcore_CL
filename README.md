# Pipelined RV32IM Core

[![CI](https://github.com/riyachamala/pipelined_RISCVcore_CL/actions/workflows/ci.yml/badge.svg)](https://github.com/riyachamala/pipelined_RISCVcore_CL/actions/workflows/ci.yml)

A 5-stage in-order RISC-V core in Verilog: RV32IM with Zicsr and Zifencei,
machine mode. It has full forwarding, hazard detection, a predecoding gshare
branch predictor with a return address stack, and precise traps and timer
interrupts. It runs compiled C, passes the official riscv-tests and the
riscv-arch-test compliance signatures, boots FreeRTOS, and scores
**3.26 CoreMark/MHz**.

| Result | |
|--------|---|
| riscv-tests | rv32ui 41/41, rv32um 8/8, rv32mi 15/15 |
| riscv-arch-test 2.7.4 | I 38/38, M 8/8, Zifencei 1/1, privilege 5/5 applicable |
| FreeRTOS V11.3.2 | Boots; delays, queues, semaphores and preemption checked |
| CoreMark 1.0 | 3.26 CoreMark/MHz, CPI 1.10, EEMBC CRCs match |

## Microarchitecture

```
 IF ──► ID ──► EX ──► MEM ──► WB
 │      │      │ ▲     │       │
 │      │      │ └─fwd─┴───────┘   MEM→EX and WB→EX forwarding; WB→ID via regfile bypass
 │      └─stall┘                   1-cycle load-use stall; divide holds IF/ID/EX
 └◄──── redirect ┘                 mispredict / trap / mret / fence.i resolved in EX
 Branch prediction in IF: predecode + gshare (4K, 12-bit history) + 8-entry RAS + indirect BTB
```

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) covers the design in detail:
hazards, prediction with speculative history repair, trap handling,
verification, and the performance breakdown.

| File | Purpose |
|------|---------|
| `rtl/rv_core.v` | Pipeline top: stage registers, forwarding muxes, trap/redirect logic |
| `rtl/rv_decoder.v`, `rv_imm_gen.v` | Instruction decode and immediates |
| `rtl/rv_hazard_unit.v`, `rv_forward_unit.v` | Stalls, flushes, operand forwarding |
| `rtl/rv_branch_predictor.v` | Predecode, gshare, return address stack, indirect BTB |
| `rtl/rv_csr.v` | Machine-mode CSRs, counters, trap entry and `mret` |
| `rtl/rv_alu.v`, `rv_branch_unit.v`, `rv_mul.v`, `rv_div.v`, `rv_lsu.v`, `rv_regfile.v` | Datapath |
| `rtl/rv_soc.v`, `rv_ram.v`, `rv_clint.v` | SoC: 4 MiB RAM, CLINT timer, UART, sim exit |
| `tb/tb_top.v` | Testbench for Icarus Verilog and Verilator |

## Getting started

Prerequisites: `iverilog` (≥ 11) and/or `verilator` (≥ 5), `python3`, `make`
and `git`.

```sh
make smoke                      # directed pipeline test; no cross-compiler needed
scripts/install_toolchain.sh    # prebuilt RISC-V GCC (xPack) into ./tools
make test                       # smoke, riscv-tests, arch-test, C tests, FreeRTOS
make coremark SIM=verilator     # benchmark
```

The build finds the compiler in `./tools` automatically. Any
`riscv64-unknown-elf-` or similar compiler on `PATH` also works, or force one
with `CROSS=<prefix>`. The external test suites, CoreMark and the FreeRTOS
kernel are cloned at pinned versions on first use.

| Command | Description |
|---------|-------------|
| `make smoke` | Directed test assembled by `scripts/rvasm.py` |
| `make riscv-tests` | Official riscv-tests; `SUITES=rv32ui` for a subset |
| `make arch-test` | riscv-arch-test signatures vs. golden references |
| `make sw-tests` | Self-checking C tests (`sw/tests`) |
| `make hello` | C hello world with cycle counts |
| `make freertos` | Boot the FreeRTOS demo |
| `make coremark` | CoreMark, `ITERATIONS=10` by default |
| `make run ELF=prog.elf` | Run any bare-metal ELF linked at `0x80000000` |
| `make lint` | Verilator lint |
| `cd tests/riscof && make setup && make` | RISCOF flow (needs `riscof` and `spike`) |

Options: `SIM=verilator` (much faster for long runs), `TRACE=1` (print each
retired instruction), `VCD=1` (dump waves). Every run ends with cycle count,
instret, CPI, branch mispredicts, and load-use and divide stall cycles.

## Writing software

`sw/common` provides `crt0.S`, a linker script, `printf_`, counter and timer
helpers, and a weak `trap_handler()` you can override. A new program is a
three-line Makefile:

```make
PROG := myprog
SRCS := main.c
include ../common/common.mk
```

Memory map: RAM at `0x8000_0000` (reset vector), UART TX at `0x1000_0000`,
sim exit at `0x1000_0008` (write 0 to pass), CLINT `mtimecmp` at `0x0200_4000`
and `mtime` at `0x0200_BFF8`. `mtime` advances once per cycle.

## Performance

CoreMark 1.0, 2K performance run, GCC 15.2 `-O2 -funroll-loops`,
`-march=rv32im_zicsr_zifencei`:

| Metric | Value |
|--------|-------|
| **CoreMark/MHz** | **3.26** |
| CPI | 1.097 |
| Branch/jump mispredict rate | 5.4 % |
| Load-use stalls | 6.8 % of cycles |

| Branch predictor | Mispredicts | CoreMark/MHz |
|------------------|-------------|--------------|
| 64-entry BTB + 2-bit counters | 56.7K | 3.20 |
| + gshare, history updated at EX | 55.1K | 3.21 |
| IF predecode + speculative gshare (1K) + RAS | 38.9K | 3.24 |
| 4K-entry PHT, 12-bit history (final) | 30.8K | 3.26 |

CoreMark prints `Errors detected` because it rejects any run shorter than 10
seconds, and a simulated run is a few million cycles. The seed and CRC values
all match EEMBC's references. The port prints CoreMark/MHz directly.

## Scope and limitations

- Machine mode only. There is no S/U mode, PMP or virtual memory.
- Misaligned loads and stores trap; they are not split in hardware. The
  `rv32ui ma_data` and `rv32mi pmpaddr` riscv-tests are skipped for that
  reason.
- Eleven privilege `misalign-*` arch tests are skipped. Their 2.7.4 reference
  signatures were generated for a platform with the C extension and hardware
  misaligned loads. This core's trap behaviour is checked by riscv-tests
  `rv32mi` instead.
- RAM reads are combinational, which suits simulation and small FPGA builds.
  Block RAM needs an extra fetch stage and a registered load path.
- Unimplemented CSRs read as zero and ignore writes.
