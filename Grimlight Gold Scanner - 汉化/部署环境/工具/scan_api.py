import json, gzip, sys, re

KW = ["wealth", "econom", "money", "gold", "coin", "trade", "market",
      "auction", "transact", "ledger", "wallet", "income", "earn", "spend",
      "profit", "fortune", "treasure", "commerce", "bank", "fund",
      "currenc", "asset", "balance", "cash", "statistic", "comparison",
      "source", "revenue", "networth", "flow", "pay"]

with gzip.open(sys.argv[1], 'rt', encoding='utf-8') as f:
    d = json.load(f)

ns_list = d.get("namespaces", [])
total_fn = sum(len(n.get("functions", [])) for n in ns_list)
print("PACK:", d.get("pack"), d.get("version"), "| client", d.get("client"), "| interface", d.get("interface"))
print("NAMESPACES:", len(ns_list), "| FUNCTIONS:", total_fn)

print("\n=== 顶层键 ===")
print(list(d.keys()))

# namespaces whose name matches
print("\n=== 命中关键词的命名空间 ===")
seen = set()
for n in ns_list:
    nm = (n.get("ns", "") or "") + (n.get("name", "") or "")
    low = nm.lower()
    for k in KW:
        if k in low:
            if nm not in seen:
                seen.add(nm)
                print("  %-40s file=%s" % (nm, n.get("file")))
            break

# all function names matching
print("\n=== 命中关键词的函数名 ===")
hits = []
for n in ns_list:
    for f in n.get("functions", []):
        nm = f.get("name", "") or ""
        low = nm.lower()
        for k in KW:
            if k in low:
                hits.append(((n.get("ns", "") or "") + "." + nm, n.get("file")))
                break
for h, fl in sorted(set(hits)):
    print("  %-55s %s" % (h, fl))
print("  共", len(set(hits)))
