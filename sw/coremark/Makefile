# CoreMark on rv_soc. The EEMBC sources are fetched on first build.
#   make ITERATIONS=10

COREMARK_REPO ?= https://github.com/eembc/coremark.git
COREMARK_DIR  ?= coremark-src
ITERATIONS    ?= 10

PROG := coremark
SRCS := $(addprefix $(COREMARK_DIR)/, core_list_join.c core_main.c core_matrix.c core_state.c core_util.c) \
        port/core_portme.c

OPT    ?= -O2 -funroll-loops
CFLAGS += -Iport -I$(COREMARK_DIR) -DITERATIONS=$(ITERATIONS) -DPERFORMANCE_RUN=1 \
          -DCOMPILER_FLAGS='"$(OPT)"'

include ../common/common.mk

$(SRCS): | $(COREMARK_DIR)

$(COREMARK_DIR):
	git clone --depth 1 $(COREMARK_REPO) $@

distclean: clean
	rm -rf $(COREMARK_DIR)
