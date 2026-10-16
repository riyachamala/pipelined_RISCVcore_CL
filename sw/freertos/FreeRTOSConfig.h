// Starting-point FreeRTOS configuration for rv_soc (RV32I, CLINT timer).
// Use with the FreeRTOS-Kernel RISC-V port:
//   portable/GCC/RISC-V + chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#define configMTIME_BASE_ADDRESS             (0x0200BFF8UL)
#define configMTIMECMP_BASE_ADDRESS          (0x02004000UL)

#define configCPU_CLOCK_HZ                   (50000000UL)   // nominal
#define configTICK_RATE_HZ                   ((TickType_t)1000)
#define configUSE_PREEMPTION                 1
#define configUSE_IDLE_HOOK                  0
#define configUSE_TICK_HOOK                  0
#define configMAX_PRIORITIES                 5
#define configMINIMAL_STACK_SIZE             ((unsigned short)256)
#define configTOTAL_HEAP_SIZE                ((size_t)(64 * 1024))
#define configMAX_TASK_NAME_LEN              16
#define configUSE_16_BIT_TICKS               0
#define configIDLE_SHOULD_YIELD              1
#define configUSE_MUTEXES                    1
#define configUSE_COUNTING_SEMAPHORES        1
#define configQUEUE_REGISTRY_SIZE            0
#define configCHECK_FOR_STACK_OVERFLOW       0
#define configUSE_MALLOC_FAILED_HOOK         0
#define configSUPPORT_STATIC_ALLOCATION      0
#define configSUPPORT_DYNAMIC_ALLOCATION     1
#define configUSE_TIMERS                     0
#define configISR_STACK_SIZE_WORDS           256

#define INCLUDE_vTaskDelay                   1
#define INCLUDE_vTaskDelete                  1
#define INCLUDE_vTaskSuspend                 1

#define configASSERT(x) if ((x) == 0) { __asm__ volatile ("ebreak"); }

#endif
