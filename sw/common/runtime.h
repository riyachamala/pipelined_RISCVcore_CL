// Minimal freestanding runtime: console I/O, exit, timers, string helpers.
#ifndef RUNTIME_H
#define RUNTIME_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include "platform.h"

void putchar_(char c);
void puts_(const char *s);
int  printf_(const char *fmt, ...);
int  vprintf_(const char *fmt, va_list ap);
void exit(int code) __attribute__((noreturn));

uint64_t rdcycle64(void);
uint64_t rdinstret64(void);
uint64_t mtime_read(void);
void     mtimecmp_write(uint64_t v);

void  *memcpy(void *dst, const void *src, size_t n);
void  *memset(void *dst, int c, size_t n);
int    memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);

// Override in your program to handle traps/interrupts. Returns the PC to
// resume at (mepc for interrupts, mepc + 4 to skip a faulting instruction).
uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval);

#endif
