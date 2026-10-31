#!/bin/bash
# Offline check of the game's Metal source with Xcode's compiler (optional; the game itself still compiles its shaders at runtime).
# Needs full Xcode with the Metal toolchain installed (`xcodebuild -downloadComponent MetalToolchain`). The default developer
# directory on this machine is the Command Line Tools, so the compiler is reached through DEVELOPER_DIR without switching it.
# Usage: scripts/validate-shaders.sh [path/to/Lanternwright binary]   (default .build/release/Lanternwright)
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${1:-.build/release/Lanternwright}"
export DEVELOPER_DIR="${DEVELOPER_DIR_FOR_METAL:-/Applications/Xcode.app/Contents/Developer}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
  echo "validate-shaders: Metal compiler not available under $DEVELOPER_DIR (install Xcode + 'xcodebuild -downloadComponent MetalToolchain'); skipped" >&2
  exit 2
fi
"$BIN" --dump-shaders "$OUT/all.metal" >/dev/null
# -ffast-math matches MTLCompileOptions.mathMode = .fast in ShaderLibrary.make
xcrun -sdk macosx metal -c -ffast-math -Wall "$OUT/all.metal" -o "$OUT/all.air" 2> "$OUT/diag.txt" || { cat "$OUT/diag.txt"; echo "validate-shaders: FAILED"; exit 1; }
xcrun -sdk macosx metallib "$OUT/all.air" -o "$OUT/all.metallib"
WARN=$(grep -c "warning:" "$OUT/diag.txt" || true)
echo "validate-shaders: OK ($(wc -l < "$OUT/all.metal") lines of MSL, $WARN warnings; metallib $(stat -f%z "$OUT/all.metallib") bytes)"
[ "$WARN" -gt 0 ] && sed -n '1,40p' "$OUT/diag.txt"
exit 0
