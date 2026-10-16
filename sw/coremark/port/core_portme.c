#include <stdarg.h>
#include "coremark.h"
#include "runtime.h"

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415;
volatile ee_s32 seed2_volatile = 0x3415;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
#if PROFILE_RUN
volatile ee_s32 seed1_volatile = 0x8;
volatile ee_s32 seed2_volatile = 0x8;
volatile ee_s32 seed3_volatile = 0x8;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

// Nominal clock used only for CoreMark's seconds report. The figure of merit
// for a simulated core is CoreMark/MHz = Iterations * 1e6 / Total ticks.
#ifndef CLOCKS_PER_SEC
#define CLOCKS_PER_SEC 50000000
#endif
#define EE_TICKS_PER_SEC CLOCKS_PER_SEC

static CORETIMETYPE start_time_val, stop_time_val;

void start_time(void) { start_time_val = read_csr(mcycle); }
void stop_time(void)  { stop_time_val  = read_csr(mcycle); }

CORE_TICKS get_time(void) {
    return (CORE_TICKS)(stop_time_val - start_time_val);
}

secs_ret time_in_secs(CORE_TICKS ticks) {
    return ((secs_ret)ticks) / (secs_ret)EE_TICKS_PER_SEC;
}

ee_u32 default_num_contexts = 1;

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! ee_ptr_int must hold a pointer\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! ee_u32 must be 32 bits\n");
    p->portable_id = 1;
}

void portable_fini(core_portable *p) {
    CORE_TICKS t = get_time();
    ee_printf("CoreMark/MHz x1000: %u\n",
              (ee_u32)(((unsigned long long)ITERATIONS * 1000000000ull) / t));
    p->portable_id = 0;
}

int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vprintf_(fmt, ap);
    va_end(ap);
    return 0;
}
