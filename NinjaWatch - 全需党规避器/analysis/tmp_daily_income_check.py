# Temporary aggregate check for GGS statistic 753 (average gold earned per day).
# Read-only; no names or GUIDs are printed.
import glob
import math
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


def pearson(xs, ys):
    n = len(xs)
    if n < 3:
        return None
    mx = sum(xs) / n
    my = sum(ys) / n
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if sx == 0 or sy == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def fmt_gold(copper):
    return "%.2f" % (copper / 10000.0)


def main():
    paths = sorted(glob.glob(PATTERN))
    print("files: %d" % len(paths))
    rows = []
    for path in paths:
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
            rows.append({
                "level": num(row.get("level")),
                "daily": get(row, "dailyIncome", 753),
                "total": get(row, "total", 328),
                "peak": get(row, "peak", 334),
                "quests": get(row, "quests", 98),
                "qpd": get(row, "questsPerDay", 95),
                "loot": get(row, "loot", 333),
                "vendor": get(row, "vendor", 921),
                "ah": get(row, "ah", 919),
                "questGold": get(row, "quest", 326),
            })

    print("rows: %d" % len(rows))
    for key in ("daily", "total", "peak", "quests", "qpd", "loot", "vendor", "ah", "questGold"):
        values = [r[key] for r in rows if r[key] is not None]
        print("  %-10s readable=%3d" % (key, len(values)))

    daily = sorted(r["daily"] for r in rows if r["daily"] is not None and r["daily"] > 0)
    if daily:
        print("")
        print("daily income (gold/day), readable and >0: %d" % len(daily))
        for q, name in ((0.10, "p10"), (0.25, "p25"), (0.50, "median"), (0.75, "p75"), (0.90, "p90")):
            print("  %-6s %s" % (name, fmt_gold(quantile(daily, q))))
        print("  min    %s" % fmt_gold(daily[0]))
        print("  max    %s" % fmt_gold(daily[-1]))
        print("  mean   %s" % fmt_gold(sum(daily) / len(daily)))

    pairs = []
    for r in rows:
        total, daily_v = r["total"], r["daily"]
        quests, qpd = r["quests"], r["qpd"]
        if all(v is not None and v > 0 for v in (total, daily_v, quests, qpd)):
            days_gold = total / daily_v
            days_quest = quests / qpd
            pairs.append((days_gold, days_quest, total, daily_v, quests, qpd))
    print("")
    print("rows with total,daily,quests,qpd all >0: %d" % len(pairs))
    if pairs:
        days_gold = sorted(p[0] for p in pairs)
        days_quest = sorted(p[1] for p in pairs)
        ratio = sorted(p[0] / p[1] for p in pairs if p[1] > 0)
        print("implied days from total/daily: median %.2f  p10 %.2f  p90 %.2f" % (
            quantile(days_gold, 0.5), quantile(days_gold, 0.1), quantile(days_gold, 0.9)))
        print("implied days from quests/qpd: median %.2f  p10 %.2f  p90 %.2f" % (
            quantile(days_quest, 0.5), quantile(days_quest, 0.1), quantile(days_quest, 0.9)))
        print("ratio gold-days / quest-days: median %.2f  p10 %.2f  p90 %.2f" % (
            quantile(ratio, 0.5), quantile(ratio, 0.1), quantile(ratio, 0.9)))
        for lo, hi in ((0.5, 2.0), (0.25, 4.0), (0.1, 10.0)):
            count = sum(1 for x in ratio if lo <= x <= hi)
            print("  within [%.2f, %.2f]: %d / %d (%.1f%%)" % (lo, hi, count, len(ratio), 100.0 * count / len(ratio)))
        print("corr(log days_gold, log days_quest): %s" % (
            "%.3f" % pearson([math.log(p[0]) for p in pairs], [math.log(p[1]) for p in pairs])
            if pearson([math.log(p[0]) for p in pairs], [math.log(p[1]) for p in pairs]) is not None else "n/a"))

        # Gold per quest, two ways: total/quests and daily/qpd.
        gpq = []
        for p in pairs:
            _, _, total, daily_v, quests, qpd = p
            a = total / quests
            b = daily_v / qpd
            if a > 0 and b > 0:
                gpq.append((a, b, b / a))
        if gpq:
            ratios = sorted(x[2] for x in gpq)
            print("")
            print("gold-per-quest ratio (daily/qpd) / (total/quests): median %.2f  p10 %.2f  p90 %.2f" % (
                quantile(ratios, 0.5), quantile(ratios, 0.1), quantile(ratios, 0.9)))
            count = sum(1 for x in ratios if 0.5 <= x <= 2.0)
            print("  within [0.5, 2.0]: %d / %d (%.1f%%)" % (count, len(ratios), 100.0 * count / len(ratios)))

    from collections import Counter
    qpd_values = [round(r["qpd"], 2) for r in rows if r["qpd"] is not None]
    print("")
    print("questsPerDay value counts (top 10): %s" % Counter(qpd_values).most_common(10))

    top = sorted((r for r in rows if r["daily"] is not None), key=lambda r: r["daily"], reverse=True)[:10]
    print("")
    print("Top 10 daily income rows (anonymized): daily, total, peak, quests, qpd, level")
    for r in top:
        print("  daily=%-8s total=%-8s peak=%-8s quests=%-5s qpd=%-5s level=%s" % (
            fmt_gold(r["daily"]),
            fmt_gold(r["total"]) if r["total"] is not None else "-",
            fmt_gold(r["peak"]) if r["peak"] is not None else "-",
            r["quests"] if r["quests"] is not None else "-",
            r["qpd"] if r["qpd"] is not None else "-",
            r["level"] if r["level"] is not None else "-",
        ))

    # Correlations of daily income with level and total gold.
    for other in ("level", "total", "peak", "quests", "qpd"):
        xs, ys = [], []
        for r in rows:
            a, b = r["daily"], r[other]
            if a is not None and b is not None and a > 0 and b > 0:
                xs.append(math.log(a))
                ys.append(math.log(b))
        corr = pearson(xs, ys)
        print("corr(log daily, log %s): %s (n=%d)" % (other, "%.3f" % corr if corr is not None else "n/a", len(xs)))


if __name__ == "__main__":
    main()
