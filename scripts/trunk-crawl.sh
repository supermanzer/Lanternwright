#!/bin/zsh
# G10.2.0: trunk-only crawl energy (slow step) in woods and grove: the tree scenes without foliage. Usage: scripts/trunk-crawl.sh <label> [extra args]
cd "$(dirname $0)/.."
echo "== $1"; shift
SHIMMER_STEP=0.003 SHIMMER_SCENES=woods,grove .build/release/Lanternwright --shimmer-layers 40 --size 960x540 --no-foliage --hide needles_ "$@" 2>/dev/null | grep "energy per" | sed 's/ surface .*energy/ energy/'
