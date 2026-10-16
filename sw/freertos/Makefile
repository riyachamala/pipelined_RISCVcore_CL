# FreeRTOS boot demo. The kernel is fetched on first build.
#   make            build build/freertos_demo.elf

KERNEL_REPO ?= https://github.com/FreeRTOS/FreeRTOS-Kernel.git
KERNEL_TAG  ?= V11.3.2
KERNEL      ?= FreeRTOS-Kernel
PORT        := $(KERNEL)/portable/GCC/RISC-V

PROG := freertos_demo
SRCS := main.c \
        $(addprefix $(KERNEL)/, tasks.c queue.c list.c portable/MemMang/heap_4.c) \
        $(PORT)/port.c $(PORT)/portASM.S

CFLAGS += -I. -I$(KERNEL)/include -I$(PORT) \
          -I$(PORT)/chip_specific_extensions/RISCV_MTIME_CLINT_no_extensions

include ../common/common.mk

$(SRCS): | $(KERNEL)

$(KERNEL):
	git clone --depth 1 --branch $(KERNEL_TAG) $(KERNEL_REPO) $@

distclean: clean
	rm -rf $(KERNEL)
