// FreeRTOS boot demo for rv_soc. Each part checks one kernel feature on top
// of the core's trap/interrupt support:
//
//   producer  (prio 3)  sends 1..8 on a queue, vTaskDelay() between sends
//                       -> timer tick interrupts and delayed wake-ups
//   consumer  (prio 2)  blocks on the queue and sums the values
//                       -> blocking IPC and context switches via ecall
//   spin_a/b  (prio 1)  never yield; both must still make progress
//                       -> preemptive time slicing driven by the tick
//   monitor   (prio 4)  waits on a semaphore with a timeout, then checks
//                       everything and ends the simulation
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "runtime.h"

#define N_ITEMS 8

extern void freertos_risc_v_trap_handler(void);

static QueueHandle_t     queue;
static SemaphoreHandle_t done;
static volatile uint32_t spin_count[2];
static volatile uint32_t received_sum;

// Console output from several tasks: keep each line atomic.
static void log_line(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    taskENTER_CRITICAL();
    printf_("[tick %4u] ", (uint32_t)xTaskGetTickCount());
    vprintf_(fmt, ap);
    taskEXIT_CRITICAL();
    va_end(ap);
}

static void producer(void *arg) {
    (void)arg;
    for (uint32_t i = 1; i <= N_ITEMS; i++) {
        xQueueSend(queue, &i, portMAX_DELAY);
        log_line("producer: sent %u\n", i);
        vTaskDelay(5);
    }
    vTaskDelete(NULL);
}

static void consumer(void *arg) {
    (void)arg;
    uint32_t v, sum = 0;
    for (int i = 0; i < N_ITEMS; i++) {
        xQueueReceive(queue, &v, portMAX_DELAY);
        sum += v;
        log_line("consumer: got %u (sum %u)\n", v, sum);
    }
    received_sum = sum;
    xSemaphoreGive(done);
    vTaskDelete(NULL);
}

static void spinner(void *arg) {
    volatile uint32_t *count = (volatile uint32_t *)arg;
    for (;;) (*count)++;
}

static void monitor(void *arg) {
    (void)arg;
    BaseType_t ok = xSemaphoreTake(done, pdMS_TO_TICKS(500));
    TickType_t ticks = xTaskGetTickCount();

    taskENTER_CRITICAL();
    uint32_t a = spin_count[0], b = spin_count[1];
    taskEXIT_CRITICAL();

    printf_("monitor: ticks=%u sum=%u spin_a=%u spin_b=%u\n",
            (uint32_t)ticks, received_sum, a, b);

    int pass = ok == pdTRUE
            && received_sum == N_ITEMS * (N_ITEMS + 1) / 2
            && ticks >= 5 * (N_ITEMS - 1)     // the delays really elapsed
            && a > 0 && b > 0;                // both spinners were scheduled
    printf_("FreeRTOS demo %s\n", pass ? "PASS" : "FAIL");
    exit(pass ? 0 : 1);
}

int main(void) {
    printf_("Booting FreeRTOS " tskKERNEL_VERSION_NUMBER " on rv_core\n");
    write_csr(mtvec, (uint32_t)freertos_risc_v_trap_handler);

    queue = xQueueCreate(4, sizeof(uint32_t));
    done  = xSemaphoreCreateBinary();
    configASSERT(queue && done);

    xTaskCreate(monitor,  "monitor",  configMINIMAL_STACK_SIZE, NULL, 4, NULL);
    xTaskCreate(producer, "producer", configMINIMAL_STACK_SIZE, NULL, 3, NULL);
    xTaskCreate(consumer, "consumer", configMINIMAL_STACK_SIZE, NULL, 2, NULL);
    xTaskCreate(spinner,  "spin_a",   configMINIMAL_STACK_SIZE, (void *)&spin_count[0], 1, NULL);
    xTaskCreate(spinner,  "spin_b",   configMINIMAL_STACK_SIZE, (void *)&spin_count[1], 1, NULL);

    vTaskStartScheduler();
    printf_("scheduler returned\n");
    return 2;
}

// ------------------------------------------------------------ kernel hooks
void vAssertCalled(const char *file, int line) {
    taskDISABLE_INTERRUPTS();
    printf_("ASSERT %s:%d\n", file, line);
    exit(3);
}

void vApplicationMallocFailedHook(void) {
    printf_("malloc failed\n");
    exit(4);
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name) {
    (void)task;
    printf_("stack overflow in %s\n", name);
    exit(5);
}

// Called by the port for traps other than ecall and the machine timer.
void freertos_risc_v_application_exception_handler(void) {
    printf_("exception: mcause=%x mepc=%x mtval=%x\n",
            read_csr(mcause), read_csr(mepc), read_csr(mtval));
    exit(6);
}

void freertos_risc_v_application_interrupt_handler(void) {
    printf_("unexpected interrupt: mcause=%x\n", read_csr(mcause));
    exit(7);
}
