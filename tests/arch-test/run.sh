#!/usr/bin/env bash
# RISC-V architectural compliance tests, checked against the golden
# reference signatures shipped with riscv-arch-test 2.x. This needs no
# reference simulator, unlike RISCOF (tests/riscof), which generates
# references with Spike or Sail.
#
#   tests/arch-test/run.sh                      # I M Zifencei privilege
#   SUITES=I tests/arch-test/run.sh
#   tests/arch-test/run.sh add-01 sub-01        # selected tests only
#
# Env: CROSS (auto-detected), SIM, ARCH_TEST_DIR
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CROSS="$("$ROOT/scripts/find_cross.sh")" || exit 1
SUITES="${SUITES:-I M Zifencei privilege}"
AT_DIR="${ARCH_TEST_DIR:-$ROOT/build/arch-test/src}"
AT_TAG="${ARCH_TEST_TAG:-2.7.4}"
OUT="$ROOT/build/arch-test"
MODEL_ENV="$ROOT/tests/riscof/rvcore/env"      # model_test.h + link.ld

if [ ! -d "$AT_DIR/riscv-test-suite" ]; then
    echo "Cloning riscv-arch-test $AT_TAG into $AT_DIR"
    git clone -q --depth 1 --branch "$AT_TAG" \
        https://github.com/riscv-non-isa/riscv-arch-test.git "$AT_DIR" || exit 1
fi
SUITE_DIR="$AT_DIR/riscv-test-suite/rv32i_m"

# The 2.x harness uses "la x0, <label>" (in TEST_JALR_OP), which current
# binutils rejects. A write to x0 is discarded anyway, so build against a
# copy of the env whose LA macro emits two NOPs for x0 (same code size).
ENV_DIR="$OUT/env"
rm -rf "$ENV_DIR" && mkdir -p "$ENV_DIR"
cp "$AT_DIR"/riscv-test-suite/env/* "$ENV_DIR/"
{
    printf '.macro LA_SAFE r, v\n.ifc \\r, x0\nnop\nnop\n.else\nla \\r, \\v\n.endif\n.endm\n'
    sed 's/la reg,val;/LA_SAFE reg,val;/' "$AT_DIR/riscv-test-suite/env/arch_test.h"
} > "$ENV_DIR/arch_test.h"

# The 2.7.4 reference signatures for these privilege tests were generated
# for a platform with the C extension (IALIGN=16: a branch/jump to pc+2 does
# not trap) and hardware misaligned loads. This core has IALIGN=32 and traps
# on misaligned loads, which riscv-tests rv32mi ma_addr / ma_fetch /
# *-misaligned verify, so these references do not apply.
SKIP="${SKIP:-misalign-beq-01 misalign-bge-01 misalign-bgeu-01 misalign-blt-01
               misalign-bltu-01 misalign-bne-01 misalign-jal-01 misalign2-jalr-01
               misalign-lh-01 misalign-lhu-01 misalign-lw-01}"

pass=0; fail=0; failed=()

for suite in $SUITES; do
    mkdir -p "$OUT/$suite"
    for src in "$SUITE_DIR/$suite"/src/*.S; do
        name="$(basename "$src" .S)"
        if [ $# -gt 0 ] && [[ ! " $* " =~ " $name " ]]; then continue; fi
        if [ $# -eq 0 ] && [[ " $(echo $SKIP) " =~ " $name " ]]; then continue; fi

        # Macros the test asks for, e.g. "def TEST_CASE_1=True;"
        defs=$(grep -o 'def [A-Za-z0-9_]*=[A-Za-z0-9_]*' "$src" | sort -u | sed 's/^def /-D/')

        elf="$OUT/$suite/$name.elf"
        sig="$OUT/$suite/$name.signature"
        log="$OUT/$suite/$name.log"
        ref="$SUITE_DIR/$suite/references/$name.reference_output"

        if ! "${CROSS}gcc" -march=rv32im_zicsr_zifencei -mabi=ilp32 -static -mcmodel=medany \
                -fvisibility=hidden -nostdlib -nostartfiles -DXLEN=32 $defs \
                -I"$MODEL_ENV" -I"$ENV_DIR" \
                -T"$MODEL_ENV/link.ld" "$src" -o "$elf" 2> "$log"; then
            echo "BUILD FAIL  $suite/$name"; fail=$((fail+1)); failed+=("$suite/$name"); continue
        fi

        read -r begin end < <("$ROOT/scripts/elf2hex.py" "$elf" \
            --sym begin_signature --sym end_signature | tr '\n' ' ')
        rm -f "$sig"
        "$ROOT/scripts/run_elf.sh" "$elf" +signature="$sig" \
            +sig_begin="$begin" +sig_end="$end" +max_cycles=2000000 >> "$log" 2>&1

        if [ -f "$sig" ] && diff -q -i -w "$sig" "$ref" > /dev/null; then
            printf "PASS  %s/%s\n" "$suite" "$name"; pass=$((pass+1))
        else
            printf "FAIL  %s/%s\n" "$suite" "$name"; fail=$((fail+1)); failed+=("$suite/$name")
        fi
    done
done

echo "----------------------------------------"
echo "arch-test: $pass passed, $fail failed"
[ $fail -eq 0 ] || { printf '  %s\n' "${failed[@]}"; exit 1; }
