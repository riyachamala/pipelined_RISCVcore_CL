# Shared build rules for bare-metal programs.
#
# A program Makefile sets PROG and SRCS, then includes this file:
#     PROG := hello
#     SRCS := main.c
#     include ../common/common.mk

ARCH    ?= rv32i_zicsr_zifencei
ABI     ?= ilp32
OPT     ?= -O2

COMMON_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
ROOT_DIR   := $(abspath $(COMMON_DIR)/../..)
BUILD_DIR  ?= build

CROSS   ?= $(shell $(ROOT_DIR)/scripts/find_cross.sh)
CC      := $(CROSS)gcc
OBJDUMP := $(CROSS)objdump
PYTHON  ?= python3

CFLAGS  += -march=$(ARCH) -mabi=$(ABI) -mcmodel=medany $(OPT) -g \
           -ffreestanding -fno-builtin -ffunction-sections -fdata-sections \
           -Wall -I$(COMMON_DIR)
LDFLAGS += -T $(COMMON_DIR)/link.ld -nostartfiles -nostdlib -static -Wl,--gc-sections
LIBS    += -lgcc

ALL_SRCS := $(COMMON_DIR)/crt0.S $(COMMON_DIR)/runtime.c $(SRCS)

ELF := $(BUILD_DIR)/$(PROG).elf

.PHONY: all clean
all: $(ELF) $(BUILD_DIR)/$(PROG).dis $(BUILD_DIR)/$(PROG).hex

$(ELF): $(ALL_SRCS) $(COMMON_DIR)/link.ld
	@mkdir -p $(BUILD_DIR)
	$(CC) $(CFLAGS) $(LDFLAGS) $(ALL_SRCS) -o $@ $(LIBS)

$(BUILD_DIR)/$(PROG).dis: $(ELF)
	$(OBJDUMP) -d $< > $@

$(BUILD_DIR)/$(PROG).hex: $(ELF)
	$(PYTHON) $(ROOT_DIR)/scripts/elf2hex.py $< $@

clean:
	rm -rf $(BUILD_DIR)
