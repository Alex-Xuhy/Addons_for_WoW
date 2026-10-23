import json, gzip, sys

with gzip.open(sys.argv[1], 'rt', encoding='utf-8') as f:
    d = json.load(f)

for k in ["usage", "manual", "changes", "protected_globals", "runtime", "source", "built"]:
    v = d.get(k)
    print("=" * 72)
    print("KEY:", k, "| type:", type(v).__name__)
    if isinstance(v, dict):
        print("  subkeys (%d):" % len(v), list(v.keys())[:40])
        # print a small sample
        s = json.dumps(v, ensure_ascii=False)
        print("  sample:", s[:1200])
    elif isinstance(v, list):
        print("  len:", len(v))
        print("  sample:", json.dumps(v[:12], ensure_ascii=False)[:1200])
    else:
        print("  value:", str(v)[:800])
    print()
