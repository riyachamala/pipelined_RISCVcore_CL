// Runs a mixed workload (loads/stores, branches, mul/div) twice: once with
// interrupts off and once with a fast periodic timer interrupt. Interrupts
// land on arbitrary pipeline states, including mid-divide, and must be
// invisible to the program: both runs must produce the same checksum.
#include "runtime.h"

#define PERIOD  397u          // mtime ticks between interrupts (= cycles)
#define N       3000

static volatile uint32_t ticks;
static uint32_t buf[64];

uint32_t trap_handler(uint32_t mcause, uint32_t mepc, uint32_t mtval) {
    if (mcause == 0x80000007u) {
        ticks++;
        mtimecmp_write(mtime_read() + PERIOD);
        return mepc;                      // resume the interrupted instruction
    }
    printf_("unexpected trap mcause=%x mepc=%x mtval=%x\n", mcause, mepc, mtval);
    exit(2);
}

static uint32_t workload(void) {
    uint32_t x = 1, y = 0, z = 0;
    for (int i = 0; i < 64; i++) buf[i] = 0;
    for (uint32_t i = 0; i < N; i++) {
        x = x * 1103515245u + 12345u;
        y += x / (i | 1);
        z ^= (x % 7) << (i & 15);
        buf[x & 63] += y;
        if (buf[i & 63] & 1) z += buf[(i + 7) & 63];
        else                 z -= i;
    }
    for (int i = 0; i < 64; i++) z += buf[i] * (uint32_t)(i + 1);
    return x ^ y ^ z;
}

int main(void) {
    uint32_t golden = workload();

    ticks = 0;
    mtimecmp_write(mtime_read() + PERIOD);
    set_csr(mie, 0x80);                   // MTIE
    set_csr(mstatus, 0x8);                // MIE
    uint32_t got = workload();
    clear_csr(mstatus, 0x8);
    clear_csr(mie, 0x80);

    printf_("irq: golden=%x got=%x interrupts=%u\n", golden, got, ticks);
    if (got != golden)  { printf_("irq: checksum mismatch\n"); return 1; }
    if (ticks < 20)     { printf_("irq: too few interrupts\n"); return 1; }
    return 0;
}
