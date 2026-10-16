#include "runtime.h"

static uint32_t fib(uint32_t n) {
    return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

int main(void) {
    printf_("Hello from RV32I!\n");

    uint64_t c0 = rdcycle64(), i0 = rdinstret64();
    uint32_t f = fib(15);
    uint64_t c1 = rdcycle64(), i1 = rdinstret64();

    printf_("fib(15) = %u\n", f);
    printf_("cycles=%u instret=%u\n", (uint32_t)(c1 - c0), (uint32_t)(i1 - i0));

    return f == 610 ? 0 : 1;
}
