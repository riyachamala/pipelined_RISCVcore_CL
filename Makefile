# Top-level build for the RV32I pipelined core.
#
#   make lint                    Verilator lint of the RTL
#   make smoke                   directed pipeline test (no RISC-V toolchain needed)
#   make run ELF=prog.elf        run any ELF on the SoC
#   make hello                   build + run sw/hello (needs riscv gcc)
#   make sw-tests                self-checking C tests (sw/tests)
#   make test                    smoke, riscv-tests, arch-test, sw-tests, freertos
#   make riscv-tests             official riscv-tests (rv32ui-p-*)
#   make arch-test               riscv-arch-test vs golden reference signatures
#   make riscof                  RISCOF architectural compliance (needs spike)
#   make coremark                build + run CoreMark
#   make freertos                boot the FreeRTOS demo
#
#   SIM=iverilog (default) | verilator     -- choose simulator
#   TRACE=1                                -- per-instruction retire trace
#   VCD=1                                  -- dump waves

SIM        ?= iverilog
BUILD      ?= build
PYTHON     ?= python3
MAX_CYCLES ?= 2000000

RTL_SRCS := $(wildcard rtl/*.v)
TB_SRCS  := tb/tb_top.v

IVERILOG_BIN  := $(BUILD)/iverilog/sim.vvp
VERILATOR_BIN := $(BUILD)/verilator/Vtb_top

ifeq ($(SIM),verilator)
  SIM_BIN := $(VERILATOR_BIN)
  SIM_RUN := $(VERILATOR_BIN)
else
  SIM_BIN := $(IVERILOG_BIN)
  SIM_RUN := vvp -n $(IVERILOG_BIN)
endif

PLUSARGS := +max_cycles=$(MAX_CYCLES)
ifeq ($(TRACE),1)
  PLUSARGS += +trace
endif
ifeq ($(VCD),1)
  PLUSARGS += +vcd
endif

export SIM SIM_RUN PYTHON BUILD

.PHONY: all sim lint smoke run hello sw-tests test coremark riscv-tests arch-test freertos riscof clean

all: smoke

sim: $(SIM_BIN)

$(IVERILOG_BIN): $(RTL_SRCS) $(TB_SRCS)
	@mkdir -p $(dir $@)
	iverilog -g2012 -Wall -Wno-timescale -Irtl -s tb_top -o $@ $(RTL_SRCS) $(TB_SRCS)

$(VERILATOR_BIN): $(RTL_SRCS) $(TB_SRCS)
	@mkdir -p $(dir $@)
	verilator --binary --timing -O2 -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-TIMESCALEMOD \
		-Irtl --top-module tb_top -Mdir $(dir $@) -o Vtb_top $(RTL_SRCS) $(TB_SRCS)

lint:
	verilator --lint-only -Wall -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY -Irtl --top-module rv_soc $(RTL_SRCS)

# ---------------------------------------------------------------- tests
smoke: $(SIM_BIN)
	@mkdir -p $(BUILD)/smoke
	@TOHOST=$$($(PYTHON) tests/smoke/gen_smoke.py $(BUILD)/smoke/smoke.hex) && \
	$(SIM_RUN) +hex=$(BUILD)/smoke/smoke.hex +tohost=$$TOHOST $(PLUSARGS)

run: $(SIM_BIN)
	@test -n "$(ELF)" || (echo "usage: make run ELF=path/to/prog.elf" && exit 1)
	scripts/run_elf.sh $(ELF) $(PLUSARGS)

hello: $(SIM_BIN)
	$(MAKE) -C sw/hello
	scripts/run_elf.sh sw/hello/build/hello.elf $(PLUSARGS)

sw-tests: $(SIM_BIN)
	$(MAKE) -C sw/tests run

test: smoke riscv-tests arch-test sw-tests freertos

coremark: $(SIM_BIN)
	$(MAKE) -C sw/coremark
	scripts/run_elf.sh sw/coremark/build/coremark.elf +max_cycles=200000000

freertos: $(SIM_BIN)
	$(MAKE) -C sw/freertos
	scripts/run_elf.sh sw/freertos/build/freertos_demo.elf +max_cycles=20000000

riscv-tests: $(SIM_BIN)
	tests/riscv-tests/run.sh

arch-test: $(SIM_BIN)
	tests/arch-test/run.sh

riscof: $(SIM_BIN)
	$(MAKE) -C tests/riscof

clean:
	rm -rf $(BUILD) tb_top.vcd
	$(MAKE) -C sw/hello clean
	$(MAKE) -C sw/tests clean
	$(MAKE) -C sw/coremark clean
	$(MAKE) -C sw/freertos clean
