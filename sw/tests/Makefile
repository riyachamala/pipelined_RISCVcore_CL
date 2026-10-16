# Self-checking C tests. Each <name>.c becomes build/<name>.elf; a test
# passes when main() returns 0.
#   make            build all
#   make run        build and run all on the simulator

TESTS := $(basename $(wildcard *.c))
ROOT  := $(abspath ../..)

.PHONY: all run clean
all: $(TESTS:%=build/%.elf)

build/%.elf: %.c ../common/runtime.c ../common/crt0.S ../common/link.ld
	@$(MAKE) --no-print-directory -f ../common/common.mk PROG=$* SRCS=$*.c

run: all
	@pass=0; fail=0; \
	for t in $(TESTS); do \
	    if $(ROOT)/scripts/run_elf.sh build/$$t.elf +max_cycles=5000000 > build/$$t.log 2>&1 && \
	       grep -q '^\[tb\] PASS' build/$$t.log; then \
	        echo "PASS  $$t"; pass=$$((pass+1)); \
	    else \
	        echo "FAIL  $$t"; grep -v readmem build/$$t.log | tail -5; fail=$$((fail+1)); \
	    fi; \
	done; \
	echo "sw tests: $$pass passed, $$fail failed"; [ $$fail -eq 0 ]

clean:
	rm -rf build
