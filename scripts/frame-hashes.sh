#!/bin/zsh
# G10 stream 1: a hash of the PNG bytes of a fixed set of frames, so a refactor of the frame graph can be checked as byte-identical (not "close").
# Usage: scripts/frame-hashes.sh [binary] > hashes.txt ; diff two such files. Every frame is rendered headless with the default fixed exposure and clock.
BIN=${1:-.build/release/Lanternwright}
OUT=${TMPDIR:-/tmp}/lw-frame-hashes.$$
mkdir -p $OUT
one() { # name, args...
  local name=$1; shift
  $BIN --screenshot $OUT/$name.png --size 800x450 "$@" >/dev/null 2>&1 || { echo "$name RENDER-FAILED"; return; }
  echo "$name $(shasum -a 256 $OUT/$name.png | cut -c1-16)"
}
for v in dock overview shore summit islet lh-glass lh-door tree-at-14 ground-grass-5m ground-sand-1m dock-top; do one $v --view $v; done
for v in gw-arrival gw-overview gw-court gw-altar gw-mirrors; do one $v --view $v; done
one dock-taa --view dock --taa --frames 8
one shore-taa --view shore --taa --frames 8
one gw-court-taa --view gw-court --taa --frames 8
one summit-beams --view summit --state both --clock 20 --frames 3
one dock-auto --view dock --auto-exposure
for d in depth albedo ambient noao shadow cascade ao; do one dbg-$d --view shore --debug $d; done
rm -rf $OUT
