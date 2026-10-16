#!/usr/bin/env bash
# Run an ELF on the simulated SoC.
#   scripts/run_elf.sh prog.elf [+plusargs...]
# Env: SIM=iverilog|verilator, PYTHON=python3
# If the ELF defines `tohost` (riscv-tests / riscof), it is monitored for pass/fail.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
SIM="${SIM:-iverilog}"

ELF="$1"; shift
HEX="${ELF%.elf}.hex"

if [ "$SIM" = "verilator" ]; then
    SIM_CMD=("$ROOT/build/verilator/Vtb_top")
else
    SIM_CMD=(vvp -n "$ROOT/build/iverilog/sim.vvp")
fi

# Rebuild the simulator if the RTL or testbench changed (no-op otherwise).
make -s -C "$ROOT" sim SIM="$SIM" > /dev/null

"$PYTHON" "$ROOT/scripts/elf2hex.py" "$ELF" "$HEX"

ARGS=("+hex=$HEX")
if TOHOST=$("$PYTHON" "$ROOT/scripts/elf2hex.py" "$ELF" --sym tohost 2>/dev/null); then
    ARGS+=("+tohost=$TOHOST")
fi

exec "${SIM_CMD[@]}" "${ARGS[@]}" "$@"
