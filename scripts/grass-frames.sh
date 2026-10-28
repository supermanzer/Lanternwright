#!/bin/zsh
# G10.G.1: hashes of extra frames with grass in view, at about 0.3, 1, 5 and 15 m above the meadow (Varrow wind-stone slope and the ground-grass views, and the Glass Wood).
# Same idea as frame-hashes.sh: byte-identical before and after the grass culling. Usage: scripts/grass-frames.sh [binary] > hashes.txt ; PNGs stay in $KEEP if set.
BIN=${1:-.build/release/Lanternwright}
OUT=${KEEP:-${TMPDIR:-/tmp}/lw-grass-frames.$$}
mkdir -p $OUT
one() { local name=$1; shift; $BIN --screenshot $OUT/$name.png --size 800x450 "$@" >/dev/null 2>&1 || { echo "$name RENDER-FAILED"; return; }; echo "$name $(shasum -a 256 $OUT/$name.png | cut -c1-16)"; }
for v in ground-grass ground-grass-1m ground-grass-5m; do one $v --view $v; done
one meadow-1m  --camera 30,35.3,60,2.2,-0.45
one meadow-5m  --camera 30,39.0,60,2.2,-0.30
one meadow-15m --camera 30,49.0,60,2.2,-0.25
one meadow-15m-wind --camera 30,49.0,60,2.2,-0.25 --clock 7 --frames 2
for v in gw-arrival gw-overview; do one $v --view $v; done
[ -n "$KEEP" ] || rm -rf $OUT
