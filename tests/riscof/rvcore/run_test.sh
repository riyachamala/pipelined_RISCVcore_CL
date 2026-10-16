#!/usr/bin/env bash
# Called by the RISCOF plugin for each test, from inside the test's work dir:
#   run_test.sh <elf> <signature-file>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PYTHON="${PYTHON:-python3}"
ELF="$1"
SIG="$2"

read -r BEGIN END < <("$PYTHON" "$ROOT/scripts/elf2hex.py" "$ELF" \
    --sym begin_signature --sym end_signature | tr '\n' ' ')

"$ROOT/scripts/run_elf.sh" "$ELF" \
    +signature="$SIG" +sig_begin="$BEGIN" +sig_end="$END" \
    +max_cycles=5000000 > sim.log 2>&1 || true
