#!/bin/zsh
# G10.G.1: what the grass costs, old path against the culled path, as paired --bench runs alternated round by round so that other GPU work hits every mode about equally.
# Modes: off (--layers-off grass); old / new (LW_GRASS_CULL=0 / 1, everything rasterised); old-v / new-v (the same with LW_GRASS_VERTEX_ONLY=1: vertex stage only, no fragments).
# Per view, medians over the rounds of the frame average and of the "opaque + sky" pass; "grass costs" is a mode minus off. The cull pass (compute) is inside the frame average but
# not inside the pass row, so the frame average is the figure that includes everything. Usage: scripts/grass-bench.sh [rounds] [binary]. Run it with no other Lanternwright running.
ROUNDS=${1:-5}; BIN=${2:-.build/release/Lanternwright}
T=${TMPDIR:-/tmp}/lw-gb.$$; mkdir -p $T
for r in $(seq $ROUNDS); do
  $BIN --bench 120 --taa --layers-off grass > $T/off.$r 2>&1
  LW_GRASS_CULL=0 $BIN --bench 120 --taa > $T/old.$r 2>&1
  LW_GRASS_CULL=1 $BIN --bench 120 --taa > $T/new.$r 2>&1
  LW_GRASS_CULL=0 LW_GRASS_VERTEX_ONLY=1 $BIN --bench 120 --taa > $T/old-v.$r 2>&1
  LW_GRASS_CULL=1 LW_GRASS_VERTEX_ONLY=1 $BIN --bench 120 --taa > $T/new-v.$r 2>&1
done
python3 - $T $ROUNDS <<'P'
import sys,re,statistics as st
T,R=sys.argv[1],int(sys.argv[2])
modes=['off','old','new','old-v','new-v']
def parse(path):
    d={};view=None
    for l in open(path):
        m=re.match(r'\s+(\w[\w-]*) avg ([\d.]+) ms',l)
        if m: view=m.group(1); d.setdefault(view,{})['avg']=float(m.group(2)); continue
        m=re.match(r'\s+(opaque \+ sky)\s+([\d.]+) ms',l)
        if m and view: d[view]['opaque']=float(m.group(2))
    return d
runs={k:[parse(f'{T}/{k}.{r}') for r in range(1,R+1)] for k in modes}
views=list(runs['off'][0])
def med(k,v,metric): return st.median(x[v][metric] for x in runs[k] if v in x and metric in x[v])
for metric,title in (('opaque','"opaque + sky" pass, ms (median of %d rounds)'%R),('avg','frame average, ms (includes the cull pass)')):
    print(title)
    print(f"  {'view':9}"+''.join(f'{m:>9}' for m in modes)+f"  {'old-off':>8} {'new-off':>8} {'saved':>7} | {'old-v':>6} {'new-v':>6} {'v-off ratio':>12}")
    for v in views:
        o={m:med(m,v,metric) for m in modes}
        vr = (o['old-v']-o['off'])/max(o['new-v']-o['off'],1e-3)
        print(f"  {v:9}"+''.join(f'{o[m]:9.3f}' for m in modes)+f"  {o['old']-o['off']:8.3f} {o['new']-o['off']:8.3f} {o['old']-o['new']:7.3f} | {o['old-v']-o['off']:6.3f} {o['new-v']-o['off']:6.3f} {vr:11.1f}x")
P
rm -rf $T
