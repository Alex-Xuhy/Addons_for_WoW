import csv
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")

BASE = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(BASE, "external", "achievement.csv")
WANTED = [
    95, 98, 931, 1199, 1200, 1201, 1202, 1466, 1467, 1103, 110,
    339, 328, 334, 753, 921, 1197, 1198, 1487, 1488, 1337, 1146,
    1524, 1745, 1748, 1501, 1519, 1541, 1536, 1043, 1044, 1045,
    4456, 4556, 1760, 1770,
]

rows = {}
with open(PATH, "r", encoding="utf-8", errors="replace", newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            rid = int(row["ID"])
        except (KeyError, TypeError, ValueError):
            continue
        rows[rid] = row

print("Wanted IDs:")
for rid in WANTED:
    row = rows.get(rid)
    if not row:
        print("  %4d  <not in CSV>" % rid)
        continue
    desc = (row.get("Description_lang") or "").strip()
    title = (row.get("Title_lang") or "").strip()
    cat = (row.get("Category") or "").strip()
    flags = (row.get("Flags") or "").strip()
    print("  %4d  cat=%s flags=%s  title=%r  desc=%r" % (rid, cat, flags, title, desc))

print("")
print("CSV rows mentioning 5-player, with IDs in the stored universe candidates:")
for rid in sorted(rows):
    row = rows[rid]
    text = ((row.get("Description_lang") or "") + " " + (row.get("Title_lang") or "")).lower()
    if "5-player" in text or "5 player" in text:
        if 1000 <= rid <= 2000 or 4000 <= rid <= 5000:
            desc = (row.get("Description_lang") or "").strip()
            title = (row.get("Title_lang") or "").strip()
            print("  %4d  title=%r  desc=%r" % (rid, title, desc))
