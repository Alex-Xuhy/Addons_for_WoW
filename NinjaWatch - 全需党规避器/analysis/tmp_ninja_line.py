# Temporary aggregate check: where to put the N/R line for ninja detection.
# Read-only; no names or GUIDs are printed.
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ggs_dist import LuaParser, num, quantile

PATTERN = r"D:/World of Warcraft/_cn_beta_/WTF/Account/*/SavedVariables/GrimlightGoldScanner.lua"


def get(row, key, sid):
    value = num(row.get(key))
    if value is None:
        allstats = row.get("all")
        if isinstance(allstats, dict):
            value = num(allstats.get(sid))
    return value


def load_rows():
    rows = []
    for path in sorted(glob.glob(PATTERN)):
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        match = re.search(r"\bGGSDB\s*=", text)
        if not match:
            continue
        db = LuaParser(text[match.end():]).value()
        cache = db.get("cache") if isinstance(db, dict) else None
        if not isinstance(cache, dict):
            continue
        for _guid, row in cache.items():
            if not isinstance(row, dict) or row.get("self") is True:
                continue
            need = get(row, "need", 1044)
            greed = get(row, "greed", 1043)
            entries = get(row, "dungeons", 932)
            if None in (need, greed, entries) or need < 0 or greed < 0 or entries <= 0:
                continue
            r = need + greed
            if r <= 0:
                continue
            rows.append((need, greed, entries, r, r / entries))
    return rows


def qlist(values, qs):
    values = sorted(values)
    return [quantile(values, q) for q in qs]


def hist(values, edges=(0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100)):
    counts = [0] * (len(edges) - 1)
    for v in values:
        pct = 100.0 * v
        for i in range(len(edges) - 1):
            if edges[i] <= pct < edges[i + 1]:
                counts[i] += 1
                break
        else:
            if pct >= edges[-1]:
                counts[-1] += 1
    return counts


def describe(label, vals):
    if not vals:
        print("  %s: n=0" % label)
        return
    qs = qlist(vals, (0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99))
    print("  %-12s n=%3d  p10=%5.1f  p25=%5.1f  med=%5.1f  p75=%5.1f  p90=%5.1f  p95=%5.1f  p99=%5.1f" % (
        label, len(vals), 100 * qs[0], 100 * qs[1], 100 * qs[2], 100 * qs[3],
        100 * qs[4], 100 * qs[5], 100 * qs[6]))


def main():
    rows = load_rows()
    print("analyzable non-self rows: %d" % len(rows))

    all_q = sorted(x[4] for x in rows)
    nongray_q = sorted(x[4] for x in rows if x[2] >= 4)
    q10_all = quantile(all_q, 0.10)
    q10_ng = quantile(nongray_q, 0.10)
    print("R/E p10: all=%.3f  non-gray(E>=4)=%.3f" % (q10_all, q10_ng))

    for qlabel, qlo in (("p10_non-gray", q10_ng), ("p10_all", q10_all), ("5.4", 5.4)):
        greed = [x for x in rows if x[2] >= 4 and x[4] >= qlo]
        print("")
        print("=" * 72)
        print("pass-type cutoff q_lo=%.3f (%s); greed universe E>=4, R/E>=q_lo: n=%d" % (
            qlo, qlabel, len(greed)))
        for min_r in (0, 20, 30, 50):
            vals = [x[0] / x[3] for x in greed if x[3] >= min_r]
            describe("R>=%d" % min_r, vals)
            if min_r == 30 and vals:
                counts = hist(vals)
                print("    histogram N/R (%): 0-10 10-20 20-30 30-40 40-50 50-60 60-70 70-80 80-90 90-100")
                print("                       " + "  ".join("%5d" % c for c in counts))
                gaps = []
                sv = sorted(vals)
                for i in range(1, len(sv)):
                    gaps.append((sv[i] - sv[i - 1], sv[i - 1], sv[i]))
                gaps.sort(reverse=True)
                print("    largest N/R gaps: " + "; ".join(
                    "%.1f%%->%.1f%% (%.1fpp)" % (100 * a, 100 * b, 100 * g)
                    for g, a, b in gaps[:3]))
                # Candidate lines and the composition above them.
                print("    candidate lines (R>=30):")
                for line in (0.40, 0.50, 0.60, 0.70, 0.80):
                    above = [x for x in greed if x[3] >= 30 and x[0] / x[3] >= line]
                    if above:
                        med_r = quantile(sorted(x[3] for x in above), 0.50)
                        med_n = quantile(sorted(x[0] for x in above), 0.50)
                        med_g = quantile(sorted(x[1] for x in above), 0.50)
                        med_ne = quantile(sorted(x[0] / x[2] for x in above), 0.50)
                        med_ge = quantile(sorted(x[1] / x[2] for x in above), 0.50)
                        print("      >=%2d%%: n=%2d (%.1f%%)  med R=%.0f  med N=%.0f  med G=%.0f  med N/E=%.2f  med G/E=%.2f" % (
                            100 * line, len(above), 100.0 * len(above) / len(vals),
                            med_r, med_n, med_g, med_ne, med_ge))
                    else:
                        print("      >=%2d%%: n=0" % (100 * line))

    # Top high-N/R rows in the primary greed universe, R>=30, anonymized.
    greed = [x for x in rows if x[2] >= 4 and x[4] >= q10_ng and x[3] >= 30]
    top = sorted(greed, key=lambda x: x[0] / x[3], reverse=True)[:12]
    print("")
    print("=" * 72)
    print("top N/R rows (q_lo=p10_non-gray, R>=30), anonymized:")
    print("  N    G    E    R    N/R     N/E    G/E   N+G/E")
    for need, greed_, entries, r, q in top:
        print("  %3d  %3d  %3d  %3d  %5.1f%%  %5.2f  %5.2f  %5.2f" % (
            need, greed_, entries, r, 100.0 * need / r, need / entries, greed_ / entries, q))

    # A simple binomial lower bound at the 70% line, R>=30: lower = p - 1.96*sqrt(p(1-p)/R).
    print("")
    print("70%% line, R>=30, 95%% binomial lower bound examples:")
    for r in (20, 30, 50, 100):
        p = 0.70
        se = (p * (1 - p) / r) ** 0.5
        print("  R=%3d: 95%% lower=%.1f%%" % (r, 100 * (p - 1.96 * se)))


if __name__ == "__main__":
    main()
