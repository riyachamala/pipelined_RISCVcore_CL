#include "runtime.h"

// ------------------------------------------------------------------ console
void putchar_(char c) { UART_TX = (uint8_t)c; }

void puts_(const char *s) {
    while (*s) putchar_(*s++);
}

static void print_num(uint32_t v, unsigned base, int neg, int width, char pad, int upper) {
    char buf[12];
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int n = 0;
    do {
        buf[n++] = digits[v % base];
        v /= base;
    } while (v);
    if (neg) {
        if (pad == '0') { putchar_('-'); width--; }
        else            buf[n++] = '-';
    }
    while (width-- > n) putchar_(pad);
    while (n) putchar_(buf[--n]);
}

// Supports %d %i %u %x %X %p %s %c %% with optional '0' flag, width and 'l'.
int vprintf_(const char *fmt, va_list ap) {
    for (; *fmt; fmt++) {
        if (*fmt != '%') { putchar_(*fmt); continue; }
        fmt++;
        char pad = ' ';
        int width = 0;
        if (*fmt == '0') { pad = '0'; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');
        while (*fmt == 'l') fmt++;
        switch (*fmt) {
            case 'd': case 'i': {
                int32_t v = va_arg(ap, int32_t);
                print_num(v < 0 ? -(uint32_t)v : (uint32_t)v, 10, v < 0, width, pad, 0);
                break;
            }
            case 'u': print_num(va_arg(ap, uint32_t), 10, 0, width, pad, 0); break;
            case 'x': print_num(va_arg(ap, uint32_t), 16, 0, width, pad, 0); break;
            case 'X': print_num(va_arg(ap, uint32_t), 16, 0, width, pad, 1); break;
            case 'p': puts_("0x"); print_num(va_arg(ap, uint32_t), 16, 0, 8, '0', 0); break;
            case 's': { const char *s = va_arg(ap, const char *); puts_(s ? s : "(null)"); break; }
            case 'c': putchar_((char)va_arg(ap, int)); break;
            case '%': putchar_('%'); break;
            default:  putchar_('%'); putchar_(*fmt); break;
        }
    }
    return 0;
}

int printf_(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vprintf_(fmt, ap);
    va_end(ap);
    return 0;
}

// ------------------------------------------------------------------ exit
void exit(int code) {
    SIM_EXIT = (uint32_t)code;
    for (;;) ;
}

// ------------------------------------------------------------------ counters
uint64_t rdcycle64(void) {
    uint32_t hi, lo, hi2;
    do {
        hi  = read_csr(mcycleh);
        lo  = read_csr(mcycle);
        hi2 = read_csr(mcycleh);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

uint64_t rdinstret64(void) {
    uint32_t hi, lo, hi2;
    do {
        hi  = read_csr(minstreth);
        lo  = read_csr(minstret);
        hi2 = read_csr(minstreth);
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

uint64_t mtime_read(void) {
    volatile uint32_t *p = (volatile uint32_t *)CLINT_MTIME;
    uint32_t hi, lo;
    do {
        hi = p[1];
        lo = p[0];
    } while (hi != p[1]);
    return ((uint64_t)hi << 32) | lo;
}

void mtimecmp_write(uint64_t v) {
    volatile uint32_t *p = (volatile uint32_t *)CLINT_MTIMECMP;
    p[0] = 0xFFFFFFFFu;          // avoid a spurious match while updating
    p[1] = (uint32_t)(v >> 32);
    p[0] = (uint32_t)v;
}

// ------------------------------------------------------------------ traps
__attribute__((weak))
uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval) {
    printf_("\n*** unhandled trap: mcause=%x mepc=%x mtval=%x\n", mcause, mepc, mtval);
    exit(0x100 | (mcause & 0xFF));
}

// ------------------------------------------------------------------ libc bits
// GCC may emit calls to these even with -ffreestanding.
void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = dst;
    const uint8_t *s = src;
    while (n--) *d++ = *s++;
    return dst;
}

void *memset(void *dst, int c, size_t n) {
    uint8_t *d = dst;
    while (n--) *d++ = (uint8_t)c;
    return dst;
}

int memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y) return *x - *y;
    return 0;
}

size_t strlen(const char *s) {
    size_t n = 0;
    while (s[n]) n++;
    return n;
}
