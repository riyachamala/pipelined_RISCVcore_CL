#!/usr/bin/env bash
# Print the RISC-V cross-compiler prefix to use (e.g. "riscv64-unknown-elf-").
# Order: $CROSS, ./tools (scripts/install_toolchain.sh), then PATH.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -n "${CROSS:-}" ]; then echo "$CROSS"; exit 0; fi

LOCAL="$ROOT/tools/riscv-none-elf-gcc/bin/riscv-none-elf-"
if [ -x "${LOCAL}gcc" ]; then echo "$LOCAL"; exit 0; fi

for p in riscv64-unknown-elf- riscv32-unknown-elf- riscv-none-elf- riscv64-elf-; do
    if command -v "${p}gcc" >/dev/null 2>&1; then echo "$p"; exit 0; fi
done

echo "error: no RISC-V GCC found; run scripts/install_toolchain.sh" >&2
exit 1
