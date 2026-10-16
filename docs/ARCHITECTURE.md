# Architecture

This document walks through the microarchitecture of `rv_core`, a 5-stage
in-order RV32IM core with Zicsr and Zifencei. It runs in machine mode only.

## Block diagram

```
          ┌───────────────── redirect (mispredict / trap / mret / fence.i) ─────────────────┐
          │                                                                                  │
          ▼                                                                                  │
   ┌────────────┐   ┌────────────┐   ┌──────────────────────────────┐   ┌────────┐   ┌──────┴─┐
   │     IF     │──►│     ID     │──►│              EX              │──►│  MEM   │──►│   WB   │
   │ pc, fetch  │   │ decode     │   │ ALU, branch unit, mul, div,  │   │ LSU    │   │ regfile│
   │ predictor  │   │ regfile rd │   │ CSRs, trap/redirect logic    │   │ load/  │   │ write  │
   └─────┬──────┘   │ hazard det │   └──────────────▲───────────────┘   │ store  │   └───┬────┘
         │          └────────────┘                  │ forwarding         └───┬────┘       │
         │                                          ├────────────────────────┘ MEM→EX     │
         │                                          └─────────────────────────────────────┘ WB→EX
         ▼                                                                       (WB→ID via regfile bypass)
   instruction port ──────────────── rv_ram (4 MiB, 2 read ports) ──────────── data port
                                                                                   │
                                                                     CLINT (mtime/mtimecmp), UART, sim exit
```

| Stage | Work                                                                  | RTL |
|-------|-----------------------------------------------------------------------|-----|
| IF    | PC register, instruction fetch, next-PC selection, branch prediction  | `rv_core.v`, `rv_branch_predictor.v` |
| ID    | Decode, immediate generation, register read, load-use detection       | `rv_decoder.v`, `rv_imm_gen.v`, `rv_regfile.v`, `rv_hazard_unit.v` |
| EX    | Forwarding muxes, ALU, branch resolution, mul/div, CSRs, traps        | `rv_alu.v`, `rv_branch_unit.v`, `rv_mul.v`, `rv_div.v`, `rv_csr.v`, `rv_forward_unit.v` |
| MEM   | Store alignment and byte enables, load extraction and sign extension  | `rv_lsu.v` |
| WB    | Register-file write and retirement                                    | `rv_core.v` |

Each pipeline register carries a `valid` bit. Squashing an instruction means
clearing its `valid`, and every side effect (register write, store, CSR
write, trap) is gated by it.

## Hazards

### Data hazards

| Producer in | Consumer in EX gets the value from | Cost |
|-------------|-------------------------------------|------|
| MEM (ALU, CSR, mul/div, link address) | `mem_result` via the forward unit | 0 |
| WB (anything, including loads)        | `wb_data` via the forward unit    | 0 |
| WB, when the consumer is in ID        | write-before-read bypass in `rv_regfile` | 0 |
| EX is a load, consumer is in ID       | stall 1 cycle, then forward from WB | 1 cycle |

Forwarding prefers the youngest producer (MEM over WB). Source register
indices are zeroed in ID/EX for instructions that do not read them, so
garbage fields in, for example, U-type immediates never trigger forwarding
or stalls.

### Structural hazard: the divider

`rv_div` is a radix-2 restoring divider: one setup cycle plus 32 iterations,
or one cycle for division by zero. While it runs, the hazard unit raises
`stall_ex`. IF, ID and EX hold and MEM receives bubbles. The forwarding
sources that fed the divide drain out of MEM/WB during the stall, so the
divider latches its operands on the first cycle. An interrupt can be taken on
a divide in progress. The divide is aborted (`kill`) and re-executed after
`mret`, because `mepc` points at it.

Multiplication is single-cycle (a 33×33 signed multiply that maps onto DSP
blocks on an FPGA).

### Control hazards

All redirects come from EX, which leaves a two-cycle penalty: IF/ID is
flushed and ID/EX receives a bubble. Redirect sources, in priority order:

1. Trap (exception or interrupt): go to `mtvec` (vectored for interrupts if `mtvec[0]`)
2. `mret`: go to `mepc`
3. `fence.i`: go to `pc + 4`, refetching after older stores have landed
4. Branch/jump mispredict: go to the resolved target, or `pc + 4`

## Branch prediction

The fetched instruction is available combinationally in IF, so the predictor
**predecodes** it instead of only guessing from the PC:

| Instruction            | Prediction |
|------------------------|------------|
| `jal`                  | taken, target `pc + immJ` computed in IF |
| conditional branch     | gshare direction, target `pc + immB` computed in IF |
| `jalr` return (`rs1 ∈ {ra, t0}`, `rd` not a link register) | 8-entry return address stack |
| other `jalr`           | 32-entry tagged BTB of last targets, else fall-through |
| anything else          | not taken |

**gshare.** 4096 two-bit counters are indexed by `pc[13:2] XOR GHR`, where
GHR holds 12 bits of global history.

**Speculative history and repair.** GHR and the RAS pointer update
speculatively as each instruction leaves IF. Each instruction carries the
GHR and RAS pointer it saw *before* its own update. On a redirect from EX,
all younger instructions are squashed. The predictor therefore restores the
redirecting instruction's snapshot and re-applies that instruction's own
effect, provided it executed and did not trap. Training uses the same
snapshot, so it updates exactly the counter that made the prediction.

Why the design ended up here (CoreMark, 574K branches and jumps):

| Predictor | Mispredicts |
|-----------|-------------|
| 64-entry BTB + 2-bit counters | 56.7K |
| + gshare with history updated at resolution | 55.1K (history lags by a variable 0–2 branches, so it aliases badly) |
| IF predecode + speculative gshare (1K) + RAS | 38.9K (returns: 4,800 → 1) |
| 4K-entry PHT, 12-bit history | 30.8K |

## Traps and CSRs

All traps are taken in EX. Instructions in MEM and WB cannot fault, so every
older instruction has already completed and every younger one is squashed,
which makes traps precise without a reorder buffer.

| Cause | Code | `mtval` |
|-------|------|---------|
| Instruction address misaligned (taken jump/branch to `target[1:0] != 0`) | 0 | target |
| Illegal instruction | 2 | instruction bits |
| Breakpoint (`ebreak`) | 3 | pc |
| Load address misaligned | 4 | address |
| Store address misaligned | 6 | address |
| Environment call from M-mode | 11 | 0 |
| Machine timer interrupt | `0x8000_0007` | 0 |

On trap entry the core writes `mepc`, `mcause` and `mtval`, copies `MIE` to
`MPIE`, and clears `MIE`. `mret` reverses this. Interrupts are checked on the
instruction in EX and win over that instruction's own exception.

Implemented CSRs: `mstatus` (MIE, MPIE; MPP reads as M), `misa`, `mie`
(MTIE), `mip` (MTIP), `mtvec` (direct and vectored), `mscratch`, `mepc`,
`mcause`, `mtval`, `mcycle[h]`, `minstret[h]`, and the user aliases `cycle`,
`time` and `instret` (with `h`). Other CSRs read as zero and ignore writes.

`minstret` counts instructions as they leave EX, because nothing after EX can
fail. An explicit write to `minstret` or `minstreth` suppresses that
instruction's own increment, as the privileged spec requires.

## SoC

```
0x0200_4000  mtimecmp (lo, hi)      rv_clint: mtime increments every cycle
0x0200_BFF8  mtime    (lo, hi)
0x1000_0000  UART TX                 a write prints a byte (simulation)
0x1000_0004  UART status             reads 1 (always ready)
0x1000_0008  SIM exit                write an exit code to end the simulation
0x8000_0000  RAM, 4 MiB              reset vector
```

The RAM model has two combinational read ports and one synchronous,
byte-maskable write port. That keeps the pipeline simple and is fine for
simulation and for small distributed-RAM FPGA builds. A block-RAM
implementation needs the address presented a cycle early, which means an
extra fetch stage and a registered load path. That is the main change
required to target hardware.

## Verification

| Layer | What it covers | Command |
|-------|----------------|---------|
| Directed smoke test | Forwarding, load-use, traps, `fence.i` self-modifying code, timer IRQ; assembled in Python, no toolchain needed | `make smoke` |
| riscv-tests | rv32ui (41), rv32um (8), rv32mi (15) | `make riscv-tests` |
| riscv-arch-test 2.7.4 | Signatures compared with golden references: I 38, M 8, Zifencei 1, privilege 5 | `make arch-test` |
| C test suite | RV32M vs. bit-serial references; about 600 interrupts mid-workload (including mid-divide) with an identical checksum; recursion, function pointers, jump tables | `make sw-tests` |
| FreeRTOS V11.3.2 | Tick interrupts, delays, blocking queues, semaphores, preemptive time slicing | `make freertos` |
| CoreMark | Performance; CRCs match EEMBC's reference values | `make coremark` |

`make test` runs everything except CoreMark, and CI runs all of it on every
push.

Issues found and fixed by these layers during development:

- The first riscv-tests run of `rv32mi` showed that misaligned loads and
  stores were not trapped. The core now raises causes 4, 6 and 0 with `mtval`.
- `instret_overflow` showed that counting `minstret` at WB let in-flight
  older instructions increment it after an explicit write. Counting moved to
  EX, with write suppression.
- Predictor experiments (table above) showed that non-speculative global
  history can be worse than none at all.

## Performance

CoreMark 1.0 (2K performance run), GCC 15.2 `-O2 -funroll-loops`:

| Metric | Value |
|--------|-------|
| CoreMark/MHz | 3.26 |
| CPI | 1.097 |
| Mispredict penalty | 31.3K × 2 cycles ≈ 2.2 % of cycles |
| Load-use stalls | 211K cycles ≈ 6.8 % of cycles |
| Divide stalls | 165 cycles |

Load-use stalls are now the largest overhead. Removing them would need a
load-to-use path in the same cycle (shortening the MEM stage) or scheduling
help from the compiler.
