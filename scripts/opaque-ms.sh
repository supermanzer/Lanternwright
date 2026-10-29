#!/bin/zsh
# G10 stream 3: 'opaque + sky' GPU ms per bench view (varrow dock/overview/shore/summit) at 2560x1440 with TAA. Usage: scripts/opaque-ms.sh [label] [extra bench args]
cd "$(dirname $0)/.."
label=${1:-run}; shift
.build/release/Lanternwright --bench 40 --taa --size 2560x1440 "$@" 2>&1 | awk -v l="$label" '/^  [a-z-]+ +avg/ {v=$1; f=$3} /opaque \+ sky/ {printf "%s %s: frame %s ms, opaque+sky %s ms\n", l, v, f, $4}'
