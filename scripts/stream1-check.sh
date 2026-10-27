#!/bin/zsh
# G10 stream 1 gate: build, 0 FAIL selftest, every frame hash identical to docs/shots/frame-hashes-baseline.txt, and the bench frame times.
cd "$(dirname $0)/.."
swift build -c release 2>&1 | grep -E "error:|Build complete" || exit 1
.build/release/Lanternwright --selftest > /tmp/s1-selftest.txt 2>&1
echo "selftest: PASS $(grep -c '^PASS' /tmp/s1-selftest.txt) FAIL $(grep -c '^FAIL' /tmp/s1-selftest.txt)"
scripts/frame-hashes.sh > /tmp/s1-hashes.txt
if diff docs/shots/frame-hashes-baseline.txt /tmp/s1-hashes.txt; then echo "frames: all $(wc -l < /tmp/s1-hashes.txt | tr -d ' ') byte-identical"; else echo "frames: DIFFER (above)"; fi
.build/release/Lanternwright --bench 120 --taa 2>&1 | grep -E "avg"
.build/release/Lanternwright --bench 120 --taa --world glass 2>&1 | grep -E "avg"
