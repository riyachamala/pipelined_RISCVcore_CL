// Memory map of rv_soc (see rtl/rv_soc.v).
#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>

#define RAM_BASE        0x80000000u

#define UART_TX         (*(volatile uint32_t *)0x10000000u)
#define UART_STATUS     (*(volatile uint32_t *)0x10000004u)
#define SIM_EXIT        (*(volatile uint32_t *)0x10000008u)

#define CLINT_BASE      0x02000000u
#define CLINT_MTIMECMP  (CLINT_BASE + 0x4000u)
#define CLINT_MTIME     (CLINT_BASE + 0xBFF8u)

#define read_csr(reg) ({ uint32_t __v; \
    __asm__ volatile ("csrr %0, " #reg : "=r"(__v)); __v; })
#define write_csr(reg, val) \
    __asm__ volatile ("csrw " #reg ", %0" :: "rK"(val))
#define set_csr(reg, bits) \
    __asm__ volatile ("csrs " #reg ", %0" :: "rK"(bits))
#define clear_csr(reg, bits) \
    __asm__ volatile ("csrc " #reg ", %0" :: "rK"(bits))

#endif
