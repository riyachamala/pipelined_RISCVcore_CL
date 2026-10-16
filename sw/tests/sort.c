// Control-flow stress: recursive quicksort through a comparator function
// pointer (JALR with varying targets), a jump-table switch, and data-
// dependent branches. Self-checks ordering and content.
#include "runtime.h"

#define N 400

static int32_t data[N];
static uint32_t rng = 0xC0FFEEu;

static uint32_t next(void) {
    rng = rng * 1664525u + 1013904223u;
    return rng;
}

static int cmp_asc(int32_t a, int32_t b)  { return a < b ? -1 : a > b; }
static int cmp_desc(int32_t a, int32_t b) { return cmp_asc(b, a); }

static void quicksort(int32_t *v, int lo, int hi, int (*cmp)(int32_t, int32_t)) {
    while (lo < hi) {
        int32_t pivot = v[(lo + hi) / 2];
        int i = lo, j = hi;
        while (i <= j) {
            while (cmp(v[i], pivot) < 0) i++;
            while (cmp(v[j], pivot) > 0) j--;
            if (i <= j) {
                int32_t t = v[i]; v[i] = v[j]; v[j] = t;
                i++; j--;
            }
        }
        // Recurse on the smaller side to bound stack depth.
        if (j - lo < hi - i) { quicksort(v, lo, j, cmp); lo = i; }
        else                 { quicksort(v, i, hi, cmp); hi = j; }
    }
}

static uint32_t classify(uint32_t x) {
    switch (x & 7) {                 // dense switch -> jump table
        case 0: return x + 3;
        case 1: return x ^ 0x55;
        case 2: return x << 1;
        case 3: return x >> 2;
        case 4: return x * 3;
        case 5: return ~x;
        case 6: return x - 17;
        default: return x | 0x100;
    }
}

int main(void) {
    int errors = 0;
    uint32_t sum0 = 0, sum1 = 0;

    for (int i = 0; i < N; i++) {
        data[i] = (int32_t)(next() >> 8) - (1 << 23);
        sum0 += (uint32_t)data[i];
    }

    for (int pass = 0; pass < 2; pass++) {
        int (*cmp)(int32_t, int32_t) = pass ? cmp_desc : cmp_asc;
        quicksort(data, 0, N - 1, cmp);
        for (int i = 1; i < N; i++)
            if (cmp(data[i - 1], data[i]) > 0) errors++;
    }

    for (int i = 0; i < N; i++) sum1 += (uint32_t)data[i];
    if (sum0 != sum1) errors++;

    uint32_t h = 0;
    for (uint32_t i = 0; i < 2000; i++) h = classify(h + i) ^ (h >> 3);
    // Same computation, written so the compiler cannot reuse the first loop.
    uint32_t h2 = 0;
    for (volatile uint32_t i = 0; i < 2000; i++) h2 = classify(h2 + i) ^ (h2 >> 3);
    if (h != h2) errors++;

    printf_("sort: %d errors (hash %x)\n", errors, h);
    return errors ? 1 : 0;
}
