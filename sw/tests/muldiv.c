// Checks every RV32M instruction against bit-serial software references,
// over corner cases and pseudo-random operands, including back-to-back
// dependent divides (forwarding into/out of the multi-cycle divider).
#include "runtime.h"

#define INT_MIN32 ((int32_t)0x80000000)

static uint32_t rng = 0x12345678u;
static uint32_t xorshift(void) {
    rng ^= rng << 13;
    rng ^= rng >> 17;
    rng ^= rng << 5;
    return rng;
}

// ------------------------------------------------------------ references
static uint64_t ref_mulu(uint32_t a, uint32_t b) {
    uint64_t r = 0, x = a;
    for (int i = 0; i < 32; i++, x <<= 1, b >>= 1)
        if (b & 1) r += x;
    return r;
}
static uint32_t ref_mulh(int32_t a, int32_t b) {
    uint32_t hi = (uint32_t)(ref_mulu(a, b) >> 32);
    if (a < 0) hi -= (uint32_t)b;
    if (b < 0) hi -= (uint32_t)a;
    return hi;
}
static uint32_t ref_mulhsu(int32_t a, uint32_t b) {
    uint32_t hi = (uint32_t)(ref_mulu(a, b) >> 32);
    if (a < 0) hi -= b;
    return hi;
}
static void ref_divu(uint32_t a, uint32_t b, uint32_t *q, uint32_t *r) {
    if (b == 0) { *q = 0xFFFFFFFFu; *r = a; return; }
    uint32_t quo = 0, rem = 0;
    for (int i = 31; i >= 0; i--) {
        rem = (rem << 1) | ((a >> i) & 1);
        if (rem >= b) { rem -= b; quo |= 1u << i; }
    }
    *q = quo; *r = rem;
}
static void ref_div(int32_t a, int32_t b, int32_t *q, int32_t *r) {
    if (b == 0)                     { *q = -1; *r = a; return; }
    if (a == INT_MIN32 && b == -1)  { *q = INT_MIN32; *r = 0; return; }
    uint32_t uq, ur;
    ref_divu(a < 0 ? -(uint32_t)a : (uint32_t)a, b < 0 ? -(uint32_t)b : (uint32_t)b, &uq, &ur);
    *q = ((a < 0) != (b < 0)) ? -(int32_t)uq : (int32_t)uq;
    *r = (a < 0) ? -(int32_t)ur : (int32_t)ur;
}

// ------------------------------------------------------------ hardware
#define HW_OP(name)                                                   \
    static uint32_t hw_##name(uint32_t a, uint32_t b) {               \
        uint32_t r;                                                   \
        __asm__ volatile (#name " %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); \
        return r;                                                     \
    }
HW_OP(mul) HW_OP(mulh) HW_OP(mulhsu) HW_OP(mulhu)
HW_OP(div) HW_OP(divu) HW_OP(rem)    HW_OP(remu)

static int errors;

static void expect(const char *op, uint32_t a, uint32_t b, uint32_t got, uint32_t want) {
    if (got != want) {
        if (errors < 10)
            printf_("  %s(%x, %x) = %x, expected %x\n", op, a, b, got, want);
        errors++;
    }
}

static void check_pair(uint32_t a, uint32_t b) {
    uint32_t uq, ur;
    int32_t  sq, sr;
    ref_divu(a, b, &uq, &ur);
    ref_div((int32_t)a, (int32_t)b, &sq, &sr);

    expect("mul",    a, b, hw_mul(a, b),    (uint32_t)ref_mulu(a, b));
    expect("mulh",   a, b, hw_mulh(a, b),   ref_mulh((int32_t)a, (int32_t)b));
    expect("mulhsu", a, b, hw_mulhsu(a, b), ref_mulhsu((int32_t)a, b));
    expect("mulhu",  a, b, hw_mulhu(a, b),  (uint32_t)(ref_mulu(a, b) >> 32));
    expect("div",    a, b, hw_div(a, b),    (uint32_t)sq);
    expect("divu",   a, b, hw_divu(a, b),   uq);
    expect("rem",    a, b, hw_rem(a, b),    (uint32_t)sr);
    expect("remu",   a, b, hw_remu(a, b),   ur);
}

// Dependent chain: div result forwarded straight into another div, a mul,
// and an add, with no independent instructions in between.
static void check_chain(uint32_t a, uint32_t b, uint32_t c) {
    uint32_t q1, q2, m, s;
    __asm__ volatile (
        "divu %0, %4, %5\n\t"
        "divu %1, %0, %6\n\t"
        "mul  %2, %1, %0\n\t"
        "add  %3, %2, %1\n\t"
        : "=&r"(q1), "=&r"(q2), "=&r"(m), "=&r"(s)
        : "r"(a), "r"(b), "r"(c));
    uint32_t rq1, rq2, r;
    ref_divu(a, b, &rq1, &r);
    ref_divu(rq1, c, &rq2, &r);
    uint32_t rm = (uint32_t)ref_mulu(rq2, rq1);
    expect("chain.q1", a, b, q1, rq1);
    expect("chain.q2", a, c, q2, rq2);
    expect("chain.s",  a, b, s,  rm + rq2);
}

int main(void) {
    static const uint32_t edge[] = {
        0, 1, 2, 3, 7, 0x7FFFFFFF, 0x80000000, 0x80000001,
        0xFFFFFFFF, 0xFFFFFFFE, 0x0000FFFF, 0xFFFF0000, 0x12345678, 0xDEADBEEF,
    };
    const int n = sizeof(edge) / sizeof(edge[0]);

    printf_("muldiv: edge cases\n");
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++)
            check_pair(edge[i], edge[j]);

    printf_("muldiv: random operands\n");
    for (int i = 0; i < 300; i++) {
        uint32_t a = xorshift(), b = xorshift();
        check_pair(a, b);
        check_pair(a, b >> (xorshift() & 31));     // small divisors too
        check_chain(a, (b >> 20) | 1, (xorshift() >> 24) | 1);
    }

    printf_("muldiv: %d errors\n", errors);
    return errors ? 1 : 0;
}
