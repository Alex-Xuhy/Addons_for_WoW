# Temporary probe: show how GGS stores quests, questsPerDay and statistic 95/98/753.
# Read-only; anonymized: no GUIDs or names are printed.
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ggs_dist import LuaParser, num

PATTERN = r"D:/World of Warcraft/_cn_beta_/WTF/Account/*/SavedVariables/GrimlightGoldScanner.lua"

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
    print("rows:", len(cache))
    shown = 0
    for _guid, row in cache.items():
        if not isinstance(row, dict) or row.get("self") is True:
            continue
        allstats = row.get("all") if isinstance(row.get("all"), dict) else {}
        raw = row.get("raw") if isinstance(row.get("raw"), dict) else {}
        quality = row.get("quality") if isinstance(row.get("quality"), dict) else {}
        print("---")
        print("level:", row.get("level"))
        print("quests field:", repr(row.get("quests")), "raw:", repr(raw.get("quests")), "quality:", quality.get("quests"))
        print("questsPerDay field:", repr(row.get("questsPerDay")), "raw:", repr(raw.get("questsPerDay")), "quality:", quality.get("questsPerDay"))
        print("all[95]:", repr(allstats.get(95)), "all[98]:", repr(allstats.get(98)), "all[753]:", repr(allstats.get(753)), "all[328]:", repr(allstats.get(328)))
        print("dailyIncome field:", repr(row.get("dailyIncome")), "raw:", repr(raw.get("dailyIncome")), "quality:", quality.get("dailyIncome"))
        print("all[95] num:", num(allstats.get(95)), "all[98] num:", num(allstats.get(98)), "all[753] num:", num(allstats.get(753)), "all[328] num:", num(allstats.get(328)))
        shown += 1
        if shown >= 6:
            break
    break
