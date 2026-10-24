#!/usr/bin/env python3
"""Pop metrics from `Lanternwright --approach` contact sheets (10 columns of 128 px cells, 3 px gaps, far to near, row by row).
Usage: sheet_metrics.py before after target [target ...]   (sheet files are shots/r09/<before|after>-<target>.png)
Per sheet: steps, largest luma step between neighbouring crops, largest high-frequency (mean |Laplacian|) ratio, number of steps where the
high-frequency energy falls by more than 15 % while approaching, and the diff spike (largest neighbour-to-neighbour mean absolute luma
difference divided by the median one: 1 = even, a pop shows as a large number)."""
import sys
from PIL import Image
CELL, GAP, COLS = 128, 3, 10

def cells(path):
    im = Image.open(path).convert("L")
    w, h = im.size
    rows = (h + GAP) // (CELL + GAP)
    out = []
    for r in range(rows):
        for c in range(COLS):
            x, y = c * (CELL + GAP), r * (CELL + GAP)
            if x + CELL > w or y + CELL > h: continue
            tile = im.crop((x, y, x + CELL, y + CELL))
            px = list(tile.getdata())
            if all(v == 30 for v in px): continue          # unused cell (background fill)
            out.append(px)
    return out

def metrics(path):
    cs = cells(path)
    luma = [sum(c) / len(c) for c in cs]
    hf = []
    for c in cs:
        e = 0
        for y in range(1, CELL - 1):
            row = y * CELL
            for x in range(1, CELL - 1):
                i = row + x
                e += abs(4 * c[i] - c[i - 1] - c[i + 1] - c[i - CELL] - c[i + CELL])
        hf.append(e / ((CELL - 2) ** 2))
    diffs = [sum(abs(a - b) for a, b in zip(cs[k - 1], cs[k])) / len(cs[k]) for k in range(1, len(cs))]
    ls = max(abs(b - a) / max(a, 1) for a, b in zip(luma, luma[1:])) * 100
    hr = max(max(b, 1e-3) / max(a, 1e-3) for a, b in zip(hf, hf[1:]))
    hr = max(hr, max(max(a, 1e-3) / max(b, 1e-3) for a, b in zip(hf, hf[1:])))
    drops = sum(1 for a, b in zip(hf, hf[1:]) if b < a * 0.85)
    d = sorted(diffs)
    spike = d[-1] / max(d[len(d) // 2], 0.25)
    return len(cs), ls, hr, drops, spike

if __name__ == "__main__":
    a, b = sys.argv[1], sys.argv[2]
    print(f"{'target':13} | {'luma step %':>16} | {'HF ratio':>14} | {'HF drops':>10} | {'diff spike':>14}")
    for t in sys.argv[3:]:
        m1 = metrics(f"shots/r09/{a}-{t}.png"); m2 = metrics(f"shots/r09/{b}-{t}.png")
        print(f"{t:13} | {m1[1]:7.1f} -> {m2[1]:6.1f} | {m1[2]:6.2f} -> {m2[2]:5.2f} | {m1[3]:4d} -> {m2[3]:3d} | {m1[4]:6.2f} -> {m2[4]:5.2f}")
