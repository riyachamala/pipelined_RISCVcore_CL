# RISCOF architectural compliance run.
#   pip install riscof         (plus spike on PATH as the reference model)
#   make setup                 one-time: fetch arch tests + spike plugin
#   make                       run the suite; report in riscof_work/report.html

ARCH_TEST_DIR := riscv-arch-test
SUITE         := $(ARCH_TEST_DIR)/riscv-test-suite
ENV           := $(ARCH_TEST_DIR)/riscv-test-suite/env

.PHONY: run setup clean

run: | $(ARCH_TEST_DIR) spike
	riscof run --config=config.ini --suite=$(SUITE) --env=$(ENV)

setup: $(ARCH_TEST_DIR) spike

$(ARCH_TEST_DIR):
	riscof arch-test --clone --dir $(ARCH_TEST_DIR)

# Generate the stock spike reference plugin from riscof's templates.
spike:
	tmp=$$(mktemp -d) && (cd $$tmp && riscof setup --refname=spike --dutname=dummy >/dev/null) && \
	cp -r $$tmp/spike . && rm -rf $$tmp

clean:
	rm -rf riscof_work
