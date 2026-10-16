#!/usr/bin/env bash
# Download a prebuilt RISC-V GCC (xPack riscv-none-elf-gcc) into ./tools.
# The Makefiles pick it up automatically when no other cross-compiler is
# found on PATH.
#
#   scripts/install_toolchain.sh            # default version
#   XPACK_VERSION=14.2.0-3 scripts/install_toolchain.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${XPACK_VERSION:-15.2.0-1}"
DEST="$ROOT/tools"

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  PLAT=darwin-arm64 ;;
    Darwin-x86_64) PLAT=darwin-x64 ;;
    Linux-x86_64)  PLAT=linux-x64 ;;
    Linux-aarch64) PLAT=linux-arm64 ;;
    *) echo "unsupported host $(uname -s)-$(uname -m)"; exit 1 ;;
esac

NAME="xpack-riscv-none-elf-gcc-$VERSION-$PLAT.tar.gz"
URL="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v$VERSION/$NAME"

if [ -x "$DEST/riscv-none-elf-gcc/bin/riscv-none-elf-gcc" ]; then
    echo "toolchain already installed in $DEST/riscv-none-elf-gcc"
    exit 0
fi

mkdir -p "$DEST"
cd "$DEST"
echo "Downloading $URL"
curl -fL --retry 3 -o "$NAME" "$URL"
curl -fL --retry 3 -o "$NAME.sha" "$URL.sha"
shasum -a 256 -c "$NAME.sha"

tar -xzf "$NAME"
rm -rf riscv-none-elf-gcc
mv "xpack-riscv-none-elf-gcc-$VERSION" riscv-none-elf-gcc
rm -f "$NAME" "$NAME.sha"
# macOS quarantines downloaded binaries; clear it so they can run.
xattr -dr com.apple.quarantine riscv-none-elf-gcc 2>/dev/null || true

echo "Installed: $("$DEST/riscv-none-elf-gcc/bin/riscv-none-elf-gcc" --version | head -1)"
