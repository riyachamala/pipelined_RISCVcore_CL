#!/usr/bin/env bash
# Build and run the official riscv-tests ISA suites on the simulated core.
#
#   tests/riscv-tests/run.sh                 # rv32ui, rv32um and rv32mi (-p- env)
#   SUITES=rv32ui tests/riscv-tests/run.sh
#   tests/riscv-tests/run.sh add lw          # selected tests only
#
# Env: CROSS (auto-detected by scripts/find_cross.sh), SIM, RISCV_TESTS_DIR
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CROSS="$("$ROOT/scripts/find_cross.sh")" || exit 1
SUITES="${SUITES:-rv32ui rv32um rv32mi}"
RT_DIR="${RISCV_TESTS_DIR:-$ROOT/build/riscv-tests/src}"
OUT="$ROOT/build/riscv-tests"

# Tests for optional features this core does not implement:
#   ma_data  - requires hardware support for misaligned loads/stores
#              (the core traps instead, which ma_addr/*-misaligned verify)
#   pmpaddr  - requires physical memory protection
SKIP="${SKIP:-ma_data pmpaddr}"

if [ ! -d "$RT_DIR/isa" ]; then
    echo "Cloning riscv-tests into $RT_DIR"
    git clone --recursive --depth 1 https://github.com/riscv-software-src/riscv-tests.git "$RT_DIR" || exit 1
fi
mkdir -p "$OUT"

pass=0; fail=0; failed=()

for suite in $SUITES; do
    for src in "$RT_DIR"/isa/"$suite"/*.S; do
        name="$(basename "$src" .S)"
        if [ $# -gt 0 ] && [[ ! " $* " =~ " $name " ]]; then continue; fi
        if [[ " $SKIP " =~ " $name " ]]; then continue; fi

        elf="$OUT/$suite-p-$name.elf"
        if ! "${CROSS}gcc" -march=rv32im_zicsr_zifencei -mabi=ilp32 -static -mcmodel=medany \
                -fvisibility=hidden -nostdlib -nostartfiles \
                -I"$RT_DIR/env/p" -I"$RT_DIR/isa/macros/scalar" \
                -T"$RT_DIR/env/p/link.ld" "$src" -o "$elf"; then
            echo "BUILD FAIL  $suite-p-$name"; fail=$((fail+1)); failed+=("$suite-p-$name"); continue
        fi

        log="$OUT/$suite-p-$name.log"
        "$ROOT/scripts/run_elf.sh" "$elf" +max_cycles=100000 > "$log" 2>&1
        if grep -q "^\[tb\] PASS" "$log"; then
            printf "PASS  %s\n" "$suite-p-$name"; pass=$((pass+1))
        else
            printf "FAIL  %s   (%s)\n" "$suite-p-$name" "$(grep '^\[tb\]' "$log" | tail -1)"
            fail=$((fail+1)); failed+=("$suite-p-$name")
        fi
    done
done

echo "----------------------------------------"
echo "riscv-tests: $pass passed, $fail failed"
[ $fail -eq 0 ] || { printf '  %s\n' "${failed[@]}"; exit 1; }
