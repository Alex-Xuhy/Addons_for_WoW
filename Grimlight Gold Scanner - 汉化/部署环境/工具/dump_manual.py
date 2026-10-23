import json, gzip, sys, io

with gzip.open(sys.argv[1], 'rt', encoding='utf-8') as f:
    d = json.load(f)

out = io.open(sys.argv[2], 'w', encoding='utf-8')
m = d.get("manual", [])
out.write("MANUAL ENTRIES: %d\n\n" % len(m))
for e in m:
    out.write("=" * 78 + "\n")
    out.write("ID: %s\n" % e.get("id"))
    out.write("TITLE: %s | %s\n" % (e.get("title"), e.get("title_en")))
    out.write("-" * 78 + "\n")
    out.write((e.get("md_en") or "(no en)") + "\n\n")
out.write("\n\n" + "#" * 78 + "\n# 中文原文\n" + "#" * 78 + "\n\n")
for e in m:
    out.write("=" * 78 + "\n")
    out.write("ID: %s | TITLE: %s\n" % (e.get("id"), e.get("title")))
    out.write("-" * 78 + "\n")
    out.write((e.get("md") or "") + "\n\n")
out.close()
print("written")
