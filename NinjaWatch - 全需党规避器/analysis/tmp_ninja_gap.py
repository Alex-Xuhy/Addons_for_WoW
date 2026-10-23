# Temporary sensitivity: does the gap change the greed-type N/R tail at p10?
# Read-only; no names or GUIDs are printed.
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tmp_ninja_line import load_rows, qlist, hist

rows = load_rows()


def run(qlo, use_gap):
    greed = []
    for need, greed_, entries, r, q in rows:
        if entries < 4:
            continue
        qeff = qlo
        if use_gap:
            qeff = qlo - max(3.0 / entries, 0.15 * qlo)
        if q >= qeff:
            greed.append((need, greed_, entries, r, q))
    vals = sorted(x[0] / x[3] for x in greed if x[3] >= 30)
    print("q_lo=%.3f gap=%s: greed n=%d, R>=30 n=%d" % (qlo, use_gap, len(greed), len(vals)))
    if vals:
        qs = qlist(vals, (0.50, 0.90, 0.95, 0.99))
        print("  med=%.1f%% p90=%.1f%% p95=%.1f%% p99=%.1f%% max=%.1f%%" % (
            100 * qs[0], 100 * qs[1], 100 * qs[2], 100 * qs[3], 100 * vals[-1]))
        print("  hist: " + " ".join("%d" % c for c in hist(vals)))
        top = sorted(greed, key=lambda x: x[0] / x[3], reverse=True)[:3]
        for need, g, e, r, q in top:
            print("    N=%3d G=%3d E=%3d R=%3d N/R=%5.1f%% N/E=%.2f G/E=%.2f R/E=%.2f" % (
                need, g, e, r, 100.0 * need / r, need / e, g / e, q))
    print("")


for qlo in (3.117, 3.819, 5.4):
    for use_gap in (False, True):
        run(qlo, use_gap)
