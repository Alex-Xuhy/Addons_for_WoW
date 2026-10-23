# Temporary read-only check: the player's own (self=true) GGS rows and N/E.
# Privacy: never prints names, GUIDs, or server names.
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ggs_dist import LuaParser, num

PATTERN = r"D:/World of Warcraft/_cn_beta_/WTF/Account/*/SavedVariables/GrimlightGoldScanner.lua"


def get(row, key, sid):
    value = num(row.get(key))
    if value is None:
        allstats = row.get("all")
        if isinstance(allstats, dict):
            value = num(allstats.get(sid))
    return value


def q(row, key):
    quality = row.get("quality")
    if isinstance(quality, dict):
        return quality.get(key)
    return None


def main():
    paths = sorted(glob.glob(PATTERN))
    print("files: %d" % len(paths))
    shown = 0
    for path in paths:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        match = re.search(r"\bGGSDB\s*=", text)
        if not match:
            continue
        db = LuaParser(text[match.end():]).value()
        if not isinstance(db, dict):
            continue
        cache = db.get("cache")
        if not isinstance(cache, dict):
            continue
        self_rows = []
        for _guid, row in cache.items():
            if isinstance(row, dict) and row.get("self") is True:
                self_rows.append(row)
        print("")
        print("cache rows: %d   self rows: %d" % (len(cache), len(self_rows)))
        for idx, row in enumerate(self_rows):
            need = get(row, "need", 1044)
            greed = get(row, "greed", 1043)
            entries = get(row, "dungeons", 932)
            name = row.get("name")
            name_match = isinstance(name, str) and "角色A" in name
            print("  self #%d: level=%s  N=%s  G=%s  E=%s  name_match=%s" % (
                idx + 1, row.get("level"), need, greed, entries, name_match))
            print("    quality: need=%s greed=%s dungeons=%s" % (
                q(row, "need"), q(row, "greed"), q(row, "dungeons")))
            if None not in (need, greed, entries) and entries > 0:
                r = need + greed
                print("    R=%d  N/E=%.3f  R/E=%.3f  N/R=%s" % (
                    r, need / entries, r / entries,
                    ("%.1f%%" % (100.0 * need / r)) if r else "n/a"))
            else:
                print("    cannot compute N/E: need/greed/entries not all readable and E>0")
            shown += 1
            if shown > 40:
                print("  ... stopping after 40 self rows")
                return


if __name__ == "__main__":
    main()
