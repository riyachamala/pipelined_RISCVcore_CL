// FreeRTOS configuration for rv_soc (RV32IM, CLINT machine timer).
// Used with portable/GCC/RISC-V +
// chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions.
// This header is also included from portASM.S, so C-only content is guarded.
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#define configMTIME_BASE_ADDRESS             ( 0x0200BFF8UL )
#define configMTIMECMP_BASE_ADDRESS          ( 0x02004000UL )

// mtime advances once per core clock in rv_clint, so "CPU clock" is the mtime
// rate. 10 MHz / 1 kHz = one tick every 10,000 cycles, which keeps simulated
// demos short.
#define configCPU_CLOCK_HZ                   ( 10000000UL )
#define configTICK_RATE_HZ                   ( 1000 )

#define configUSE_PREEMPTION                 1
#define configUSE_TIME_SLICING               1
#define configUSE_IDLE_HOOK                  0
#define configUSE_TICK_HOOK                  0
#define configMAX_PRIORITIES                 5
#define configMINIMAL_STACK_SIZE             ( 256 )
#define configTOTAL_HEAP_SIZE                ( 64 * 1024 )
#define configMAX_TASK_NAME_LEN              12
#define configTICK_TYPE_WIDTH_IN_BITS        TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD              1
#define configUSE_MUTEXES                    1
#define configUSE_COUNTING_SEMAPHORES        1
#define configQUEUE_REGISTRY_SIZE            0
#define configCHECK_FOR_STACK_OVERFLOW       2
#define configUSE_MALLOC_FAILED_HOOK         1
#define configSUPPORT_STATIC_ALLOCATION      0
#define configSUPPORT_DYNAMIC_ALLOCATION     1
#define configUSE_TIMERS                     0
#define configISR_STACK_SIZE_WORDS           512

#define INCLUDE_vTaskDelay                   1
#define INCLUDE_vTaskDelete                  1
#define INCLUDE_vTaskSuspend                 1

#ifndef __ASSEMBLER__
void vAssertCalled(const char *file, int line);
#define configASSERT(x) do { if ((x) == 0) vAssertCalled(__FILE__, __LINE__); } while (0)
#endif

#endif
