# FreeRTOS on rv_soc (stretch goal)

The core already provides what the FreeRTOS RISC-V port needs:

| Requirement                  | Provided by                                  |
|------------------------------|----------------------------------------------|
| `mtime` / `mtimecmp`         | `rtl/rv_clint.v` at `0x0200BFF8` / `0x02004000` |
| Machine timer interrupt      | `mie.MTIE`, `mstatus.MIE`, `mcause = 0x80000007` |
| `mret`, `mepc`, `mscratch`   | `rtl/rv_csr.v`                               |
| Console                      | UART TX at `0x10000000`                      |

## Steps

1. Clone the kernel: `git clone https://github.com/FreeRTOS/FreeRTOS-Kernel`.
2. Build these into an ELF with `sw/common/common.mk`:
   - `tasks.c queue.c list.c portable/MemMang/heap_4.c`
   - `portable/GCC/RISC-V/port.c portable/GCC/RISC-V/portASM.S`
   - include path `portable/GCC/RISC-V/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions`
   - `FreeRTOSConfig.h` from this directory
3. In `main()`, point `mtvec` at `freertos_risc_v_trap_handler` (instead of
   the `trap_entry` that `crt0.S` installs), create tasks, then call
   `vTaskStartScheduler()`.
4. The port expects `__freertos_irq_stack_top` (or `configISR_STACK_SIZE_WORDS`).
   Use the latter, which is already set here.
5. Run with a big cycle budget: `scripts/run_elf.sh build/freertos.elf +max_cycles=50000000`
   (use `SIM=verilator` for speed).
