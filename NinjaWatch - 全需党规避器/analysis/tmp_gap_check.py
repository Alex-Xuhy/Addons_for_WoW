# Temporary aggregate check: where 5.4 comes from and what the gap changes.
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


def main():
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

    print("analyzable rows (E>0, R>0): %d" % len(rows))
    qs = sorted(x[4] for x in rows)
    for q, name in ((0.05, "p05"), (0.10, "p10"), (0.15, "p15"), (0.25, "p25"),
                    (0.50, "median"), (0.75, "p75"), (0.90, "p90")):
        print("  %-6s %.3f" % (name, quantile(qs, q)))

    non_gray = sorted(x[4] for x in rows if 5.4 * x[2] >= 20)
    print("")
    print("non-gray rows (5.4E >= 20): %d" % len(non_gray))
    for q, name in ((0.05, "p05"), (0.10, "p10"), (0.15, "p15"), (0.20, "p20"), (0.50, "median")):
        print("  %-6s %.3f" % (name, quantile(non_gray, q)))

    print("")
    print("tail around p10 (R/E):")
    for i, value in enumerate(qs[:max(20, int(len(qs) * 0.12))]):
        print("  rank %3d  q=%.3f" % (i + 1, value))

    for qlo in (5.4, 6.0):
        print("")
        print("=" * 60)
        print("q_lo = %.1f" % qlo)
        gray = 0
        pass_no_gap = 0
        pass_gap = 0
        switches = []
        for need, greed, entries, r, _q in rows:
            base = qlo * entries
            if base < 20:
                gray += 1
                continue
            gap = max(3.0, 0.15 * base)
            t_no = base
            t_gap = base - gap
            p_no = r < t_no
            p_gap = r < t_gap
            if p_no:
                pass_no_gap += 1
            if p_gap:
                pass_gap += 1
            if p_no and not p_gap:
                switches.append((need, greed, entries, r, r / entries, base, gap, t_gap))
        print("gray (L<20): %d" % gray)
        print("pass-type without gap (R < %.1fE): %d" % (qlo, pass_no_gap))
        print("pass-type with gap (R < %.1fE - gap): %d" % (qlo, pass_gap))
        print("switches (pass without gap, greed with gap): %d" % len(switches))
        for s in sorted(switches, key=lambda x: x[4]):
            need, greed, entries, r, q, base, gap, t_gap = s
            print("  N=%3d G=%3d E=%3d R=%3d R/E=%5.2f L=%6.1f gap=%5.1f T_gap=%6.1f N/R=%5.1f%%" % (
                need, greed, entries, r, q, base, gap, t_gap,
                100.0 * need / r if r else 0.0))


if __name__ == "__main__":
    main()
