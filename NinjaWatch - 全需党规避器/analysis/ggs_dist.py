import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

# Read-only aggregate report of GGS's local player cache.
# No names, GUIDs, realms or account paths are printed.

class LuaParser:
    def __init__(self, text):
        self.s = text
        self.i = 0
        self.n = len(text)

    def skip(self):
        while self.i < self.n:
            c = self.s[self.i]
            if c in " \t\r\n":
                self.i += 1
            elif self.s.startswith("--", self.i):
                j = self.s.find("\n", self.i)
                self.i = self.n if j < 0 else j + 1
            else:
                break

    def value(self):
        self.skip()
        if self.i >= self.n:
            raise ValueError("unexpected end")
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            return self.string()
        if c.isdigit() or c in "+-.":
            return self.number()
        ident = self.ident()
        if ident == "true":
            return True
        if ident == "false":
            return False
        if ident == "nil":
            return None
        raise ValueError("unexpected identifier %r at %d" % (ident, self.i))

    def table(self):
        self.i += 1  # {
        out = {}
        next_index = 1
        while True:
            self.skip()
            if self.i >= self.n:
                raise ValueError("unterminated table")
            if self.s[self.i] == "}":
                self.i += 1
                return out
            if self.s[self.i] == "[":
                self.i += 1
                key = self.value()
                self.skip()
                if self.i >= self.n or self.s[self.i] != "]":
                    raise ValueError("expected ] at %d" % self.i)
                self.i += 1
                self.skip()
                if self.i >= self.n or self.s[self.i] != "=":
                    raise ValueError("expected = at %d" % self.i)
                self.i += 1
                val = self.value()
                if isinstance(key, (str, int, float, bool)) or key is None:
                    out[key] = val
            else:
                # bare key = value or array item
                save = self.i
                if self.s[self.i].isalpha() or self.s[self.i] == "_":
                    ident = self.ident()
                    self.skip()
                    if self.i < self.n and self.s[self.i] == "=":
                        self.i += 1
                        out[ident] = self.value()
                    else:
                        self.i = save
                        out[next_index] = self.value()
                        next_index += 1
                else:
                    out[next_index] = self.value()
                    next_index += 1
            self.skip()
            if self.i < self.n and self.s[self.i] in ",;":
                self.i += 1

    def string(self):
        quote = self.s[self.i]
        self.i += 1
        buf = bytearray()
        while self.i < self.n:
            c = self.s[self.i]
            self.i += 1
            if c == quote:
                return buf.decode("utf-8", "replace")
            if c != "\\":
                buf.extend(c.encode("utf-8"))
                continue
            if self.i >= self.n:
                break
            e = self.s[self.i]
            self.i += 1
            simple = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11,
                      "\\": 92, "\"": 34, "'": 39}
            if e in simple:
                buf.append(simple[e])
            elif e == "x":
                j = self.i
                while self.i < self.n and self.i - j < 2 and self.s[self.i] in "0123456789abcdefABCDEF":
                    self.i += 1
                buf.append(int(self.s[j:self.i], 16))
            elif e.isdigit():
                j = self.i - 1
                while self.i < self.n and self.i - j < 3 and self.s[self.i].isdigit():
                    self.i += 1
                buf.append(int(self.s[j:self.i]) & 0xFF)
            elif e == "z":
                while self.i < self.n and self.s[self.i] in " \t\r\n":
                    self.i += 1
            elif e == "\n":
                buf.append(10)
            else:
                buf.extend(e.encode("utf-8"))
        raise ValueError("unterminated string")

    def number(self):
        m = re.match(r"[-+]?(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d*)?(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)", self.s[self.i:])
        if not m:
            raise ValueError("bad number at %d" % self.i)
        raw = m.group(0)
        self.i += len(raw)
        if raw.lower().startswith(("0x", "+0x", "-0x")):
            return int(raw, 16)
        if any(ch in raw for ch in ".eE"):
            return float(raw)
        return int(raw)

    def ident(self):
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", self.s[self.i:])
        if not m:
            raise ValueError("bad identifier at %d" % self.i)
        self.i += len(m.group(0))
        return m.group(0)


def num(v):
    if isinstance(v, bool) or v is None:
        return None
    if isinstance(v, (int, float)):
        return v
    if isinstance(v, str):
        try:
            return float(v.replace(",", ""))
        except ValueError:
            return None
    return None


def quantile(sorted_vals, q):
    if not sorted_vals:
        return None
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    pos = (len(sorted_vals) - 1) * q
    lo = int(pos)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = pos - lo
    return sorted_vals[lo] * (1 - frac) + sorted_vals[hi] * frac


def pct(n, d):
    return 0.0 if not d else n / d * 100.0


def report(path, label):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        text = f.read()
    m = re.search(r"\bGGSDB\s*=", text)
    if not m:
        print("%s: GGSDB assignment not found" % label)
        return
    p = LuaParser(text[m.end():])
    db = p.value()
    if not isinstance(db, dict):
        print("%s: GGSDB is not a table" % label)
        return
    cache = db.get("cache")
    if not isinstance(cache, dict):
        print("%s: no cache table" % label)
        return

    rows = []
    self_rows = 0
    missing = 0
    missing_reasons = {}
    for guid, row in cache.items():
        if not isinstance(row, dict):
            missing += 1
            missing_reasons["row-not-table"] = missing_reasons.get("row-not-table", 0) + 1
            continue
        if row.get("self") is True:
            self_rows += 1
            continue
        need = num(row.get("need"))
        greed = num(row.get("greed"))
        if need is None or greed is None:
            allstats = row.get("all")
            if isinstance(allstats, dict):
                if need is None:
                    need = num(allstats.get(1044))
                if greed is None:
                    greed = num(allstats.get(1043))
        if need is None or greed is None:
            missing += 1
            quality = row.get("quality")
            if isinstance(quality, dict):
                reason = "need=%s greed=%s" % (quality.get("need"), quality.get("greed"))
            else:
                reason = "no-quality"
            missing_reasons[reason] = missing_reasons.get(reason, 0) + 1
            continue
        if need < 0 or greed < 0:
            missing += 1
            missing_reasons["negative"] = missing_reasons.get("negative", 0) + 1
            continue
        rows.append((need, greed, num(row.get("level")), num(row.get("at"))))

    valid = [(n, g, lv, at) for (n, g, lv, at) in rows if n + g > 0]
    enough = [(n, g, lv, at) for (n, g, lv, at) in valid if n + g >= 20]
    small = len(valid) - len(enough)
    shares = sorted(n / (n + g) for (n, g, lv, at) in enough)

    print("")
    print("=" * 72)
    print(label)
    print("=" * 72)
    print("cache rows: %d" % len(cache))
    print("  self rows excluded: %d" % self_rows)
    print("  rows missing/unreadable Need or Greed: %d" % missing)
    if missing_reasons:
        for reason, count in sorted(missing_reasons.items(), key=lambda kv: (-kv[1], kv[0])):
            print("    %4d  %s" % (count, reason))
    print("  rows with both counters: %d" % len(valid))
    print("  n >= 20 (used for distribution): %d" % len(enough))
    print("  n < 20 (not enough sample): %d" % small)

    if not enough:
        print("No rows with n >= 20; distribution unavailable.")
        return

    print("")
    print("Need share distribution (Need / (Need+Greed)), n >= 20")
    print("  min    %.1f%%" % (shares[0] * 100))
    for q, name in ((0.10, "p10"), (0.25, "p25"), (0.50, "median"), (0.75, "p75"), (0.90, "p90"),
                    (0.95, "p95"), (0.99, "p99")):
        print("  %-6s %.1f%%" % (name, quantile(shares, q) * 100))
    print("  max    %.1f%%" % (shares[-1] * 100))
    print("  mean   %.1f%%" % (sum(shares) / len(shares) * 100))

    print("")
    print("Counts at alternative cut-offs (n >= 20)")
    for cut in (0.30, 0.40, 0.50, 0.60, 0.70):
        c = sum(1 for s in shares if s >= cut)
        print("  >=%2d%%  %4d  %5.1f%%" % (int(cut * 100), c, pct(c, len(shares))))

    print("")
    print("Top 10 shares (share, sample size), anonymized")
    tail = sorted(((n / (n + g), n + g) for (n, g, lv, at) in enough), reverse=True)[:10]
    for s, n in tail:
        print("  %5.1f%%  n=%d" % (s * 100, n))

    bins = [0] * 10
    for s in shares:
        bins[min(9, int(s * 10))] += 1
    print("")
    print("Histogram (10-point bins)")
    for i, c in enumerate(bins):
        lo, hi = i * 10, (i + 1) * 10
        bar = "#" * int(round(c / max(1, max(bins)) * 40))
        print("  %2d-%3d%%  %4d  %5.1f%%  %s" % (lo, hi, c, pct(c, len(shares)), bar))

    # User's proposed bands; boundaries: <10 low, 10-50 normal, >50-<70 high, >=70 extreme.
    low = sum(1 for s in shares if s < 0.10)
    normal = sum(1 for s in shares if 0.10 <= s <= 0.50)
    high = sum(1 for s in shares if 0.50 < s < 0.70)
    extreme = sum(1 for s in shares if s >= 0.70)
    print("")
    print("Proposed bands (n >= 20)")
    print("  low      <10%%      %4d  %5.1f%%" % (low, pct(low, len(shares))))
    print("  normal   10-50%%    %4d  %5.1f%%" % (normal, pct(normal, len(shares))))
    print("  high     >50-<70%%  %4d  %5.1f%%" % (high, pct(high, len(shares))))
    print("  extreme  >=70%%     %4d  %5.1f%%" % (extreme, pct(extreme, len(shares))))

    need_zero = sum(1 for (n, g, lv, at) in enough if n == 0)
    greed_zero = sum(1 for (n, g, lv, at) in enough if g == 0)
    both_zero = sum(1 for (n, g, lv, at) in enough if n == 0 and g == 0)
    print("")
    print("Degenerate cases (n >= 20)")
    print("  Need = 0:  %d (%.1f%%) -> share 0%%" % (need_zero, pct(need_zero, len(enough))))
    print("  Greed = 0: %d (%.1f%%) -> share 100%%" % (greed_zero, pct(greed_zero, len(enough))))
    print("  both = 0:  %d" % both_zero)

    print("")
    print("Sample size (Need+Greed) among n >= 20")
    nvals = sorted(n + g for (n, g, lv, at) in enough)
    for q, name in ((0.10, "p10"), (0.25, "p25"), (0.50, "median"), (0.75, "p75"), (0.90, "p90")):
        print("  %-6s %d" % (name, quantile(nvals, q)))
    print("  max    %d" % nvals[-1])

    print("")
    print("Share by sample-size bucket")
    buckets = [("20-49", 20, 49), ("50-99", 50, 99), ("100-199", 100, 199), ("200+", 200, 10**9)]
    for name, lo, hi in buckets:
        sub = [n / (n + g) for (n, g, lv, at) in enough if lo <= n + g <= hi]
        if sub:
            sub.sort()
            print("  %-8s N=%4d  median %5.1f%%  p10 %5.1f%%  p90 %5.1f%%" % (
                name, len(sub), quantile(sub, 0.5) * 100, quantile(sub, 0.1) * 100, quantile(sub, 0.9) * 100))
        else:
            print("  %-8s N=0" % name)

    print("")
    print("Share by level bucket (n >= 20)")
    lv_buckets = [("1-19", 1, 19), ("20-39", 20, 39), ("40-59", 40, 59), ("60-79", 60, 79),
                  ("80+", 80, 10**9), ("unknown", None, None)]
    for name, lo, hi in lv_buckets:
        if lo is None:
            sub = [n / (n + g) for (n, g, lv, at) in enough if lv is None or lv <= 0]
        else:
            sub = [n / (n + g) for (n, g, lv, at) in enough if lv is not None and lo <= lv <= hi]
        if sub:
            sub.sort()
            print("  %-8s N=%4d  median %5.1f%%  p10 %5.1f%%  p90 %5.1f%%" % (
                name, len(sub), quantile(sub, 0.5) * 100, quantile(sub, 0.1) * 100, quantile(sub, 0.9) * 100))
        else:
            print("  %-8s N=0" % name)

    print("")
    print("Need/Greed by 10-level band (n >= 20)")
    for lo in range(1, 100, 10):
        hi = lo + 9
        sub = [(n, g, lv, at) for (n, g, lv, at) in enough if lv is not None and lo <= lv <= hi]
        if not sub:
            continue
        needs = sorted(n for (n, g, lv, at) in sub)
        greeds = sorted(g for (n, g, lv, at) in sub)
        totals = sorted(n + g for (n, g, lv, at) in sub)
        med = quantile(needs, 0.5)
        mad = quantile(sorted(abs(x - med) for x in needs), 0.5)
        robust = med + 2 * 1.4826 * mad
        print("  %2d-%2d  N=%3d  Need median %3d p90 %3d p95 %3d max %3d  MAD %4.1f  med+2*1.4826*MAD %5.1f  Greed median %3d  n median %3d" % (
            lo, hi, len(sub),
            med, quantile(needs, 0.9), quantile(needs, 0.95), needs[-1], mad, robust,
            quantile(greeds, 0.5), quantile(totals, 0.5)))

    print("")
    print("Greed count among n >= 20 (the 'only Need, never Greed' check)")
    gvals = sorted(g for (n, g, lv, at) in enough)
    for q, name in ((0.10, "p10"), (0.25, "p25"), (0.50, "median"), (0.75, "p75"), (0.90, "p90")):
        print("  %-6s %d" % (name, quantile(gvals, q)))
    print("  min    %d" % gvals[0])
    print("  max    %d" % gvals[-1])
    for cut in (1, 5, 10, 20, 30, 50):
        c = sum(1 for (n, g, lv, at) in enough if g < cut)
        print("  Greed < %2d: %4d  %5.1f%%" % (cut, c, pct(c, len(enough))))

    print("")
    print("Effect of a Greed floor (still n >= 20, share = Need/(Need+Greed))")
    for floor in (5, 10, 20, 30, 50):
        sub = [(n, g) for (n, g, lv, at) in enough if g >= floor]
        if not sub:
            print("  Greed >= %2d: N=0" % floor)
            continue
        ss = sorted(n / (n + g) for (n, g) in sub)
        low = sum(1 for s in ss if s < 0.10)
        normal = sum(1 for s in ss if 0.10 <= s <= 0.50)
        high = sum(1 for s in ss if 0.50 < s < 0.70)
        extreme = sum(1 for s in ss if s >= 0.70)
        print("  Greed >= %2d: N=%3d  median %5.1f%%  p90 %5.1f%%  max %5.1f%%  | low %d normal %d high %d extreme %d" % (
            floor, len(sub), quantile(ss, 0.5) * 100, quantile(ss, 0.9) * 100, ss[-1] * 100,
            low, normal, high, extreme))

    print("")
    print("Candidate activity statistics (IDs from the external Achievement/Statistics table)")
    candidates = {
        1103: "Lich King 5-player dungeons completed (final boss killed)",
        1467: "Lich King 5-player bosses killed",
        4456: "LFG random Lich King normal dungeons completed",
        4556: "LFG random Lich King heroic dungeons completed",
        110: "Lich King 5-player boss killed the most",
        1760: "Lich King 25-player boss killed the most",
        1770: "Lich King 10-player boss killed the most",
    }
    cand_vals = {k: [] for k in candidates}
    for guid, row in cache.items():
        if not isinstance(row, dict):
            continue
        allstats = row.get("all")
        if not isinstance(allstats, dict):
            continue
        for k in candidates:
            v = num(allstats.get(k))
            if v is not None:
                cand_vals[k].append(v)
    for k in sorted(candidates):
        vals = sorted(cand_vals[k])
        if vals:
            print("  id %4d: rows=%3d  min=%s  median=%s  p90=%s  max=%s  | %s" % (
                k, len(vals), vals[0], quantile(vals, 0.5), quantile(vals, 0.9), vals[-1], candidates[k]))
        else:
            print("  id %4d: rows=  0  | %s" % (k, candidates[k]))

    print("")
    print("Observed roll totals vs candidate activity counters (rows with both)")
    activity_rows = []
    for guid, row in cache.items():
        if not isinstance(row, dict):
            continue
        allstats = row.get("all")
        if not isinstance(allstats, dict):
            continue
        need = num(row.get("need"))
        greed = num(row.get("greed"))
        if need is None:
            need = num(allstats.get(1044))
        if greed is None:
            greed = num(allstats.get(1043))
        if need is None or greed is None:
            continue
        total = need + greed
        if total < 20:
            continue
        activity_rows.append((total, need, num(allstats.get(1467)), num(allstats.get(1103))))
    for label, idx in (("bosses", 2), ("dungeons", 3)):
        sub = [r for r in activity_rows if r[idx] is not None and r[idx] > 0]
        if not sub:
            print("  %s > 0: no rows" % label)
            continue
        ratios = sorted(r[0] / r[idx] for r in sub)
        need_ratios = sorted(r[1] / r[idx] for r in sub)
        print("  rows with %s > 0: %d" % (label, len(sub)))
        print("  total rolls / %s: p10=%.2f  median=%.2f  p90=%.2f  max=%.2f" % (
            label, quantile(ratios, 0.1), quantile(ratios, 0.5), quantile(ratios, 0.9), ratios[-1]))
        print("  Need rolls  / %s: p10=%.2f  median=%.2f  p90=%.2f  max=%.2f" % (
            label, quantile(need_ratios, 0.1), quantile(need_ratios, 0.5), quantile(need_ratios, 0.9), need_ratios[-1]))

    print("")
    print("Activity proxy candidates actually present in row.all")
    proxies = {1466: "unknown (not in external CSV)", 1197: "Total kills",
               1198: "Total kills that grant experience or honor",
               95: "Average quests completed per day", 98: "Quests completed"}
    for pid, pname in proxies.items():
        vals = []
        for guid, row in cache.items():
            if not isinstance(row, dict):
                continue
            allstats = row.get("all")
            if not isinstance(allstats, dict):
                continue
            v = num(allstats.get(pid))
            if v is not None:
                vals.append(v)
        if vals:
            vals.sort()
            print("  id %4d: rows=%3d  min=%s  median=%s  p90=%s  max=%s  | %s" % (
                pid, len(vals), vals[0], quantile(vals, 0.5), quantile(vals, 0.9), vals[-1], pname))
        else:
            print("  id %4d: rows=  0  | %s" % (pid, pname))
    print("  Ratios (Need+Greed) / proxy, rows with total>=20 and proxy>0:")
    for pid, pname in proxies.items():
        ratios = []
        need_ratios = []
        for guid, row in cache.items():
            if not isinstance(row, dict):
                continue
            allstats = row.get("all")
            if not isinstance(allstats, dict):
                continue
            need = num(row.get("need"))
            greed = num(row.get("greed"))
            if need is None:
                need = num(allstats.get(1044))
            if greed is None:
                greed = num(allstats.get(1043))
            pv = num(allstats.get(pid))
            if need is None or greed is None or pv is None or pv <= 0:
                continue
            total = need + greed
            if total < 20:
                continue
            ratios.append(total / pv)
            need_ratios.append(need / pv)
        if ratios:
            ratios.sort()
            need_ratios.sort()
            print("    %4d %-45s N=%3d  total/proxy p10=%.3f med=%.3f p90=%.3f  need/proxy p10=%.3f med=%.3f p90=%.3f" % (
                pid, pname, len(ratios),
                quantile(ratios, 0.1), quantile(ratios, 0.5), quantile(ratios, 0.9),
                quantile(need_ratios, 0.1), quantile(need_ratios, 0.5), quantile(need_ratios, 0.9)))
        else:
            print("    %4d %-45s none" % (pid, pname))

    print("")
    print("Size of the stored statistics universe (row.all)")
    id_rows = {}
    for guid, row in cache.items():
        if not isinstance(row, dict):
            continue
        allstats = row.get("all")
        if not isinstance(allstats, dict):
            continue
        for k, v in allstats.items():
            if isinstance(k, (int, float)) and num(v) is not None:
                id_rows[int(k)] = id_rows.get(int(k), 0) + 1
    print("  distinct statistic IDs with a numeric value: %d" % len(id_rows))
    print("  total ID-row pairs: %d" % sum(id_rows.values()))
    top = sorted(id_rows.items(), key=lambda kv: (-kv[1], kv[0]))[:15]
    print("  top 15 IDs by row coverage: " + ", ".join("%d(%d)" % (k, v) for k, v in top))
    mid = [(k, v) for k, v in id_rows.items() if 1000 <= k <= 5000]
    mid.sort(key=lambda kv: (-kv[1], kv[0]))
    print("  IDs 1000-5000 with coverage: " + (", ".join("%d(%d)" % (k, v) for k, v in mid[:20]) if mid else "none"))

    print("")
    print("Statistic IDs in the loot-roll range (from row.all), across cache rows")
    id_counts = {}
    id_vals = {}
    for guid, row in cache.items():
        if not isinstance(row, dict):
            continue
        allstats = row.get("all")
        if not isinstance(allstats, dict):
            continue
        for k, v in allstats.items():
            if isinstance(k, (int, float)) and 1035 <= k <= 1055:
                k = int(k)
                nv = num(v)
                if nv is None:
                    continue
                id_counts[k] = id_counts.get(k, 0) + 1
                id_vals.setdefault(k, []).append(nv)
    for k in sorted(id_counts):
        vals = sorted(id_vals[k])
        print("  id %d: rows=%d  min=%s  median=%s  max=%s" % (
            k, id_counts[k], vals[0], quantile(vals, 0.5), vals[-1]))


def main():
    pattern = r"D:/World of Warcraft/_cn_beta_/WTF/Account/*/SavedVariables/GrimlightGoldScanner.lua"
    paths = sorted(glob.glob(pattern))
    if not paths:
        print("GGS SavedVariables not found.")
        return
    print("files found: %d" % len(paths))
    for i, path in enumerate(paths, 1):
        print("  file %d: %d bytes" % (i, os.path.getsize(path)))
    for i, path in enumerate(paths, 1):
        report(path, "GGS SavedVariables file %d" % i)


if __name__ == "__main__":
    main()
