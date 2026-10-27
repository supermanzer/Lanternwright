#!/bin/zsh
# G10 stream 1 gate: build, 0 FAIL selftest, every frame hash identical to docs/shots/frame-hashes-baseline.txt, and the bench frame times.
cd "$(dirname $0)/.."
swift build -c release 2>&1 | grep -E "error:|Build complete" || exit 1
.build/release/Lanternwright --selftest > /tmp/s1-selftest.txt 2>&1
echo "selftest: PASS $(grep -c '^PASS' /tmp/s1-selftest.txt) FAIL $(grep -c '^FAIL' /tmp/s1-selftest.txt)"
# Some frames (the TAA ones, an ambient debug view) are, rarely, not reproducible even on the pre-refactor build (a pre-existing intermittent race, seen at g10-s0).
# A frame counts as identical if it matches the baseline in any of up to 3 runs; the number of retries is reported so a real regression (never matches) cannot hide.
cp docs/shots/frame-hashes-baseline.txt /tmp/s1-missing.txt
for run in 1 2 3; do
  scripts/frame-hashes.sh > /tmp/s1-hashes.txt
  grep -Fxf /tmp/s1-hashes.txt /tmp/s1-missing.txt > /tmp/s1-matched.txt
  grep -Fxvf /tmp/s1-matched.txt /tmp/s1-missing.txt > /tmp/s1-next.txt; mv /tmp/s1-next.txt /tmp/s1-missing.txt
  [ -s /tmp/s1-missing.txt ] || break
  echo "run $run: $(wc -l < /tmp/s1-missing.txt | tr -d ' ') frame(s) not yet matching: $(cut -d' ' -f1 /tmp/s1-missing.txt | tr '\n' ' ')"
done
if [ -s /tmp/s1-missing.txt ]; then echo "frames: DIFFER: $(cut -d' ' -f1 /tmp/s1-missing.txt | tr '\n' ' ')"; else echo "frames: all $(wc -l < docs/shots/frame-hashes-baseline.txt | tr -d ' ') byte-identical to the baseline (after $run run(s))"; fi
.build/release/Lanternwright --bench 120 --taa 2>&1 | grep -E "avg"
.build/release/Lanternwright --bench 120 --taa --world glass 2>&1 | grep -E "avg"
