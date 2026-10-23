#!/usr/bin/env python3
"""Read-only calibration report for NinjaWatcher's pass-type cutoff.

Data sources
------------
GGS  : WTF/Account/*/SavedVariables/GrimlightGoldScanner.lua  (GGSDB.cache)
NW   : WTF/Account/*/SavedVariables/NinjaWatcher.lua         (NinjaWatcherDB.players)

The script never writes to WTF and never prints names, GUIDs, realms or account
folder names. It writes only under analysis/calibration/:

    pass_ratio_history.csv   one row per snapshot
    latest.md                human-readable report
    latest.json              machine-readable report
    latest.lua               review-only return table (never auto-applied)

It never edits src/Config.lua. Applying a new q_lo is a manual edit after review.

Usage
-----
    py -I analysis/calibrate_pass_ratio.py
    py -I analysis/calibrate_pass_ratio.py --dry-run
    py -I analysis/calibrate_pass_ratio.py --force
    py -I analysis/calibrate_pass_ratio.py --self-test

The GGS/NW SavedVariables are untrusted data: this script parses them as text
and never executes them. Run it with ``py -I`` so the current directory cannot
inject modules.
"""

import argparse
import bisect
import csv
import glob
import hashlib
import json
import os
import re
import sys
from collections import namedtuple
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from ggs_dist import LuaParser, num, quantile  # noqa: E402

DEFAULT_DATA_DIR = r"D:/World of Warcraft/_cn_beta_/WTF/Account"
DEFAULT_OUT_DIR = os.path.join(SCRIPT_DIR, "calibration")

CURRENT_Q_LO = 5.4
GAP_PCT = 0.15
GAP_MIN = 3.0
GRAY_BELOW_ENTRIES = 4
RATIO_GRAY_BELOW_ROLLS = 20
RED_MIN_ROLLS = 30
BAND_DARKGREEN = 0.10
BAND_GREEN = 0.50
BAND_YELLOW = 0.70
LOW_G_CUTS = (0.0, 0.10, 0.20, 0.30)
MIN_MAIN = 30
MIN_LOWG = 20
OK_QUALITY = {"readable", "zero"}
CSV_VERSION = "1"

Row = namedtuple("Row", "guid n g e at level source")


# ---------------------------------------------------------------- parsing ---

def parse_savedvars(path, var_name):
    """Return (table-or-None, size, sha1). Never raises for bad data."""
    with open(path, "rb") as handle:
        raw = handle.read()
    size = len(raw)
    digest = hashlib.sha1(raw).hexdigest()
    text = raw.decode("utf-8", "replace")
    match = re.search(r"(?m)^\s*" + re.escape(var_name) + r"\s*=", text)
    if not match:
        match = re.search(r"\b" + re.escape(var_name) + r"\s*=", text)
    if not match:
        return None, size, digest
    try:
        value = LuaParser(text[match.end():]).value()
    except Exception:
        return None, size, digest
    return value, size, digest


def as_count(value):
    """Counts must be non-negative integers. 18.0 is accepted; 18.5 is not."""
    value = num(value)
    if value is None or value < 0:
        return None
    if value != int(value):
        return None
    return int(value)


def allstat(row, sid):
    stats = row.get("all")
    if not isinstance(stats, dict):
        return None
    value = num(stats.get(sid))
    if value is None:
        value = num(stats.get(str(sid)))
    return value


def first_count(row, keys, sid):
    for key in keys:
        value = as_count(row.get(key))
        if value is not None:
            return value
    return as_count(allstat(row, sid))


def quality_ok(quality):
    """Accept missing quality; reject a field explicitly marked unreadable."""
    if not isinstance(quality, dict):
        return True
    for key in ("need", "greed", "entries", "dungeons"):
        value = quality.get(key)
        if isinstance(value, str) and value not in OK_QUALITY:
            return False
    return True


def valid_counts(n, g, e):
    return n is not None and g is not None and e is not None and n >= 0 and g >= 0 and e >= 0


def extract_ggs(db):
    records = []
    self_excluded = 0
    invalid = 0
    if not isinstance(db, dict):
        return records, self_excluded, invalid
    cache = db.get("cache")
    if not isinstance(cache, dict):
        return records, self_excluded, invalid
    for guid, row in cache.items():
        if not isinstance(guid, str) or not isinstance(row, dict):
            invalid += 1
            continue
        if row.get("self") is True or row.get("source") == "self":
            self_excluded += 1
            continue
        n = first_count(row, ("need",), 1044)
        g = first_count(row, ("greed",), 1043)
        e = first_count(row, ("dungeons", "entries"), 932)
        if not valid_counts(n, g, e) or not quality_ok(row.get("quality")):
            invalid += 1
            continue
        records.append(Row(guid, n, g, e, num(row.get("at")) or 0.0,
                           num(row.get("level")), "ggs"))
    return records, self_excluded, invalid


def extract_nw(db):
    records = []
    self_excluded = 0
    invalid = 0
    if not isinstance(db, dict):
        return records, self_excluded, invalid
    players = db.get("players")
    if not isinstance(players, dict):
        return records, self_excluded, invalid
    for guid, row in players.items():
        if not isinstance(guid, str) or not isinstance(row, dict):
            invalid += 1
            continue
        if row.get("self") is True or row.get("source") == "self":
            self_excluded += 1
            continue
        n = as_count(row.get("need"))
        g = as_count(row.get("greed"))
        e = as_count(row.get("entries"))
        if not valid_counts(n, g, e) or not quality_ok(row.get("quality")):
            invalid += 1
            continue
        records.append(Row(guid, n, g, e, num(row.get("at")) or 0.0,
                           num(row.get("level")), "nw"))
    return records, self_excluded, invalid


def dedup(records):
    """One row per GUID; newer timestamp wins, NW wins a tie."""
    by_guid = {}
    conflicts = 0
    for rec in records:
        old = by_guid.get(rec.guid)
        if old is None:
            by_guid[rec.guid] = rec
            continue
        if (old.n, old.g, old.e) != (rec.n, rec.g, rec.e):
            conflicts += 1
        if rec.at > old.at or (rec.at == old.at and rec.source == "nw" and old.source != "nw"):
            by_guid[rec.guid] = rec
    return list(by_guid.values()), conflicts


def snapshot_id(rows):
    digest = hashlib.sha1()
    for row in sorted(rows, key=lambda r: r.guid):
        digest.update(("%s|%d|%d|%d|%.0f|%s\n" % (
            row.guid, row.n, row.g, row.e, row.at, row.source)).encode("utf-8"))
    return digest.hexdigest()


# ---------------------------------------------------------------- metrics ---

def threshold(q_lo, entries):
    lower = q_lo * entries
    gap = max(GAP_MIN, GAP_PCT * lower)
    return lower, gap, lower - gap


def ratio(n, g):
    return n / (n + g) if (n + g) > 0 else None


def band(n, g):
    rolls = n + g
    share = ratio(n, g)
    if rolls < RATIO_GRAY_BELOW_ROLLS:
        return "gray"
    if share >= BAND_YELLOW:
        return "red" if rolls >= RED_MIN_ROLLS else "yellow_capped"
    if share >= BAND_GREEN:
        return "yellow"
    if share >= BAND_DARKGREEN:
        return "green"
    return "darkgreen"


def classify(row, q_lo, use_gap=True):
    rolls = row.n + row.g
    lower, _gap, cutoff = threshold(q_lo, row.e)
    return "pass" if rolls < (cutoff if use_gap else lower) else "greed"


def percentile_below(value, sorted_values):
    if not sorted_values:
        return None
    return bisect.bisect_left(sorted_values, value) / len(sorted_values)


def fmt(value, digits=3):
    return "–" if value is None else ("%." + str(digits) + "f") % value


def fmt_pct(value, digits=1):
    return "–" if value is None else ("%." + str(digits) + "f%%") % (value * 100)


def candidate_stats(rows, q_lo):
    out = {
        "q_lo": q_lo,
        "pass_nogap": 0,
        "pass_gap": 0,
        "greed_gap": 0,
        "pass_high_nr": 0,
        "pass_lowg": 0,
        "greed_lowg": 0,
        "max_nr_greed": None,
        "max_re_pass": None,
        "bands": {key: 0 for key in
                  ("gray", "darkgreen", "green", "yellow", "yellow_capped", "red")},
    }
    for row in rows:
        rolls = row.n + row.g
        share = ratio(row.n, row.g)
        if classify(row, q_lo, True) == "pass":
            out["pass_gap"] += 1
            if share >= BAND_GREEN:
                out["pass_high_nr"] += 1
            if share is not None and row.g / rolls <= 0.10:
                out["pass_lowg"] += 1
            value = rolls / row.e
            if out["max_re_pass"] is None or value > out["max_re_pass"]:
                out["max_re_pass"] = value
        else:
            out["greed_gap"] += 1
            out["bands"][band(row.n, row.g)] += 1
            if share is not None and row.g / rolls <= 0.10:
                out["greed_lowg"] += 1
            if out["max_nr_greed"] is None or share > out["max_nr_greed"]:
                out["max_nr_greed"] = share
        if classify(row, q_lo, False) == "pass":
            out["pass_nogap"] += 1
    out["moved_by_gap"] = out["pass_nogap"] - out["pass_gap"]
    return out


def lowg_stats(rows, cut):
    subset = [r for r in rows if r.g / (r.n + r.g) <= cut + 1e-12]
    out = {"cut": cut, "n": len(subset)}
    if not subset:
        return out
    ne = sorted(r.n / r.e for r in subset)
    re = sorted((r.n + r.g) / r.e for r in subset)
    out.update({
        "ne_p50": quantile(ne, 0.50),
        "ne_p90": quantile(ne, 0.90),
        "ne_p95": quantile(ne, 0.95),
        "ne_max": ne[-1],
        "re_p50": quantile(re, 0.50),
        "re_p95": quantile(re, 0.95),
        "re_max": re[-1],
        "over_current": sum(1 for r in subset
                            if (r.n + r.g) >= threshold(CURRENT_Q_LO, r.e)[2]),
        "nr50": sum(1 for r in subset if ratio(r.n, r.g) >= BAND_GREEN),
    })
    return out


def high_nr_stats(rows, cut):
    subset = [r for r in rows if ratio(r.n, r.g) >= cut]
    out = {"cut": cut, "n": len(subset)}
    if not subset:
        return out
    ne = sorted(r.n / r.e for r in subset)
    re = sorted((r.n + r.g) / r.e for r in subset)
    out.update({
        "ne_p50": quantile(ne, 0.50),
        "ne_p90": quantile(ne, 0.90),
        "ne_p95": quantile(ne, 0.95),
        "ne_max": ne[-1],
        "re_p50": quantile(re, 0.50),
        "re_p95": quantile(re, 0.95),
        "re_max": re[-1],
        "nr_max": max(ratio(r.n, r.g) for r in subset),
        "pass_current": sum(1 for r in subset
                            if classify(r, CURRENT_Q_LO, True) == "pass"),
    })
    return out


def build_report(records, ggs_meta, nw_meta, parse_errors, min_main, min_lowg):
    unique, conflicts = dedup(records)
    zero_e = [r for r in unique if r.e == 0]
    zero_r = [r for r in unique if r.e > 0 and (r.n + r.g) == 0]
    usable = [r for r in unique if r.e > 0 and (r.n + r.g) > 0]
    gray = [r for r in usable if r.e < GRAY_BELOW_ENTRIES]
    main = [r for r in usable if r.e >= GRAY_BELOW_ENTRIES]

    re_values = sorted((r.n + r.g) / r.e for r in main)
    g_values = sorted(r.g / (r.n + r.g) for r in main)
    quantiles = {q: quantile(re_values, q) for q in (0.05, 0.10, 0.15, 0.18, 0.20, 0.50, 0.90)}
    g_quantiles = {q: quantile(g_values, q) for q in (0.0, 0.05, 0.10, 0.25, 0.50)} if g_values else {}
    current_below = percentile_below(CURRENT_Q_LO, re_values)
    current_at_or_below = (bisect.bisect_right(re_values, CURRENT_Q_LO) / len(re_values)
                           if re_values else None)

    candidates = []
    seen = set()
    for label, value in (("current_5.4", CURRENT_Q_LO),
                         ("p10", quantiles[0.10]),
                         ("p15", quantiles[0.15]),
                         ("p18", quantiles[0.18]),
                         ("p20", quantiles[0.20])):
        if value is None:
            continue
        key = round(value, 6)
        if key in seen:
            continue
        seen.add(key)
        candidates.append((label, candidate_stats(main, value)))

    lowg = {cut: lowg_stats(main, cut) for cut in LOW_G_CUTS}
    high_nr = {cut: high_nr_stats(main, cut) for cut in (0.50, 0.60, 0.70)}
    lowg10 = lowg[0.10]
    separation = None
    if lowg10.get("ne_p95") is not None and quantiles[0.10] is not None:
        separation = quantiles[0.10] - lowg10["ne_p95"]

    flags = []
    if len(main) < min_main:
        flags.append("主样本 n=%d < %d，分位不稳定；不建议据此调整 q_lo。" % (len(main), min_main))
    if lowg10["n"] < min_lowg:
        flags.append("低 G 样本（G/R≤10%%）n=%d < %d，放弃派上界无法由数据确定；继续使用 5.4 先验。"
                     % (lowg10["n"], min_lowg))
    if current_below is not None:
        if current_below < 0.10:
            flags.append("5.4 低于主样本 p10（严格小于占 %.1f%%），偏激进，会判较多玩家为放弃派。"
                         % (current_below * 100))
        elif current_below > 0.50:
            flags.append("5.4 高于主样本中位数（严格小于占 %.1f%%），可能偏松，存在漏报。"
                         % (current_below * 100))
    if len(main) >= min_main and lowg10["n"] >= min_lowg and separation is not None:
        if separation > 0:
            flags.append("低 G 组 N/E p95=%.3f 低于主样本 p10=%.3f，存在数据分界区间。"
                         % (lowg10["ne_p95"], quantiles[0.10]))
        else:
            flags.append("低 G 组 N/E p95=%.3f 不低于主样本 p10=%.3f，分布重叠；p10 规则会产生误报。"
                         % (lowg10["ne_p95"], quantiles[0.10]))
    current = candidate_stats(main, CURRENT_Q_LO)
    if current["pass_high_nr"]:
        flags.append("当前规则把 %d 名 N/R≥50%% 的玩家判为放弃派；若其中有人是全需党，属于漏报。"
                     % current["pass_high_nr"])
    if current["greed_lowg"]:
        flags.append("当前规则把 %d 名低 G 玩家判为贪婪派；若其中有人是放弃派，属于误报。"
                     % current["greed_lowg"])
    if current["bands"]["red"]:
        flags.append("当前规则红档 %d 人（N/R≥70%% 且 R≥30）。" % current["bands"]["red"])

    if len(main) < min_main or lowg10["n"] < min_lowg:
        suggestion = "维持 q_lo=5.4 + gap；本轮样本不足以支持数据驱动的替换。"
    elif separation is not None and separation > 0:
        suggestion = ("可考虑 q_lo ∈ [%.3f, %.3f]（低 G 组 p95 到主样本 p10），"
                      "取 0.1 的整数倍后人工复核。" % (lowg10["ne_p95"], quantiles[0.10]))
    else:
        suggestion = "分布重叠，维持 q_lo=5.4 + gap；不要降到主样本 p10。"

    return {
        "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "snapshot_id": snapshot_id(unique),
        "sources": ggs_meta + nw_meta,
        "parse_errors": parse_errors,
        "counts": {
            "cache_rows": len(records)
            + sum(m.get("self_excluded", 0) for m in ggs_meta + nw_meta)
            + sum(m.get("invalid", 0) for m in ggs_meta + nw_meta),
            "records": len(records),
            "unique": len(unique),
            "dedup_conflicts": conflicts,
            "zero_entries": len(zero_e),
            "zero_rolls": len(zero_r),
            "usable": len(usable),
            "gray": len(gray),
            "main": len(main),
            "self_excluded": sum(m.get("self_excluded", 0) for m in ggs_meta + nw_meta),
            "invalid": sum(m.get("invalid", 0) for m in ggs_meta + nw_meta),
        },
        "quantiles": {("p%02d" % int(q * 100)): v for q, v in quantiles.items()},
        "g_quantiles": {("p%02d" % int(q * 100)): v for q, v in g_quantiles.items()},
        "current_q_lo": CURRENT_Q_LO,
        "current_percentile_below": current_below,
        "current_percentile_at_or_below": current_at_or_below,
        "candidates": [{"label": label, **stats} for label, stats in candidates],
        "low_g": {("cut_%02d" % int(cut * 100)): value for cut, value in lowg.items()},
        "high_nr": {("cut_%02d" % int(cut * 100)): value for cut, value in high_nr.items()},
        "separation": separation,
        "current": current,
        "flags": flags,
        "suggestion": suggestion,
    }


# ---------------------------------------------------------------- output ----

def markdown(report, ggs_meta, nw_meta):
    c = report["counts"]
    q = report["quantiles"]
    lines = []
    lines.append("# NinjaWatcher 放弃派门槛标定报告")
    lines.append("")
    lines.append("- 生成时间（UTC）：%s" % report["generated_at_utc"])
    lines.append("- 快照：`%s`" % report["snapshot_id"])
    lines.append("- 数据源：GGS %d 个文件；NinjaWatcher %d 个文件"
                 % (len(ggs_meta), len(nw_meta)))
    for i, meta in enumerate(report["sources"], 1):
        lines.append("- 源 %d（%s）：%s 字节，sha1 `%s`"
                     % (i, meta["kind"].upper(), format(meta["size"], ","), meta["sha1"]))
    if report["parse_errors"]:
        lines.append("- 解析失败：源 %s（已跳过）"
                     % ", ".join(str(i) for i in report["parse_errors"]))
    lines.append("")
    lines.append("## 1. 样本")
    lines.append("")
    lines.append("| 项 | 数量 |")
    lines.append("|---|---:|")
    lines.append("| 缓存行总数 | %d |" % c["cache_rows"])
    lines.append("| 有效原始记录（去重前） | %d |" % c["records"])
    lines.append("| 去重后 | %d |" % c["unique"])
    lines.append("| 本人行（排除） | %d |" % c["self_excluded"])
    lines.append("| 字段不可读/非整数（排除） | %d |" % c["invalid"])
    lines.append("| 去重冲突（同 GUID 不同计数） | %d |" % c["dedup_conflicts"])
    lines.append("| E=0（排除） | %d |" % c["zero_entries"])
    lines.append("| E>0 但 R=0（排除） | %d |" % c["zero_rolls"])
    lines.append("| 可用（E>0, R>0） | %d |" % c["usable"])
    lines.append("| 主样本（E≥%d） | %d |" % (GRAY_BELOW_ENTRIES, c["main"]))
    lines.append("| 灰区（E=1..%d） | %d |" % (GRAY_BELOW_ENTRIES - 1, c["gray"]))
    lines.append("")
    lines.append("## 2. 主样本 R/E 分布（E≥%d）" % GRAY_BELOW_ENTRIES)
    lines.append("")
    lines.append("| 分位 | R/E |")
    lines.append("|---|---:|")
    for key in ("p05", "p10", "p15", "p18", "p20", "p50", "p90"):
        lines.append("| %s | %s |" % (key, fmt(q[key])))
    lines.append("")
    lines.append("- 当前 q_lo = %.1f；严格小于它的主样本占 %s，即约 p%s。"
                 % (CURRENT_Q_LO, fmt_pct(report["current_percentile_below"]),
                    fmt(report["current_percentile_below"] * 100, 1)))
    lines.append("- 小于等于它的占 %s。" % fmt_pct(report["current_percentile_at_or_below"]))
    lines.append("")
    lines.append("## 3. 候选门槛：放弃派/贪婪派计数")
    lines.append("")
    lines.append("| 候选 | q_lo | 放弃派（无 gap） | 放弃派（gap） | gap 移入贪婪 | 放弃派中 N/R≥50% | 放弃派中低 G | 贪婪派中低 G | 贪婪派 max N/R |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for item in report["candidates"]:
        lines.append("| %s | %.3f | %d | %d | %d | %d | %d | %d | %s |" % (
            item["label"], item["q_lo"], item["pass_nogap"], item["pass_gap"],
            item["moved_by_gap"], item["pass_high_nr"], item["pass_lowg"],
            item["greed_lowg"], fmt_pct(item["max_nr_greed"])))
    lines.append("")
    lines.append("低 G 定义为 G/R ≤ 10%。`放弃派中 N/R≥50%` 是当前门槛下最可能漏报的组；"
                 "`贪婪派中低 G` 是最可能误报的组。")
    lines.append("")
    lines.append("## 4. 候选门槛：贪婪分支档位分布")
    lines.append("")
    lines.append("| 候选 | 灰（R<20） | 深绿 <10% | 绿 10–50% | 黄 50–70% | 黄（R<30 封顶） | 红（≥70% 且 R≥30） |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for item in report["candidates"]:
        b = item["bands"]
        lines.append("| %s | %d | %d | %d | %d | %d | %d |" % (
            item["label"], b["gray"], b["darkgreen"], b["green"],
            b["yellow"], b["yellow_capped"], b["red"]))
    lines.append("")
    lines.append("## 5. 低 G 子集（疑似放弃派）的 N/E")
    lines.append("")
    lines.append("| 低 G 定义 | n | N/E p50 | p90 | p95 | max | R/E p95 | max | 当前规则判贪婪 | N/R≥50% |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for cut in LOW_G_CUTS:
        item = report["low_g"]["cut_%02d" % int(cut * 100)]
        label = "G=0" if cut == 0 else "G/R≤%d%%" % int(cut * 100)
        if item["n"] == 0:
            lines.append("| %s | 0 | – | – | – | – | – | – | – | – |" % label)
            continue
        lines.append("| %s | %d | %s | %s | %s | %s | %s | %s | %d | %d |" % (
            label, item["n"], fmt(item["ne_p50"]), fmt(item["ne_p90"]),
            fmt(item["ne_p95"]), fmt(item["ne_max"]), fmt(item["re_p95"]),
            fmt(item["re_max"]), item["over_current"], item["nr50"]))
    lines.append("")
    lines.append("`当前规则判贪婪` 指 R ≥ 5.4E − max(3, 0.81E)。低 G 组越像放弃派，"
                 "这个数越大，误报风险越高。")
    lines.append("")
    gq = report["g_quantiles"]
    if gq:
        lines.append("主样本 G/R 分布：最小值 %s，p05 %s，p10 %s，p25 %s，中位数 %s。"
                     % (fmt_pct(gq.get("p00")), fmt_pct(gq.get("p05")),
                        fmt_pct(gq.get("p10")), fmt_pct(gq.get("p25")),
                        fmt_pct(gq.get("p50"))))
        lines.append("")
    lines.append("## 5b. 高 N/R 子集（潜在全需党/高需求）")
    lines.append("")
    lines.append("| 定义 | n | N/E p50 | p95 | max | R/E p50 | p95 | max | N/R max | 当前规则判放弃 |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for cut in (0.50, 0.60, 0.70):
        item = report["high_nr"]["cut_%02d" % int(cut * 100)]
        label = "N/R≥%d%%" % int(cut * 100)
        if item["n"] == 0:
            lines.append("| %s | 0 | – | – | – | – | – | – | – | – |" % label)
            continue
        lines.append("| %s | %d | %s | %s | %s | %s | %s | %s | %s | %d |" % (
            label, item["n"], fmt(item["ne_p50"]), fmt(item["ne_p95"]),
            fmt(item["ne_max"]), fmt(item["re_p50"]), fmt(item["re_p95"]),
            fmt(item["re_max"]), fmt_pct(item["nr_max"]), item["pass_current"]))
    lines.append("")
    lines.append("`当前规则判放弃` 是漏报风险：这些行 N/R 很高，但 R 低于放弃派门槛。")
    lines.append("")
    lines.append("## 6. 当前规则（src/Config.lua）")
    lines.append("")
    lines.append("- q_lo = %.1f" % CURRENT_Q_LO)
    lines.append("- L(E) = q_lo × E")
    lines.append("- gap = max(%.0f, %.2f × L(E)) = max(%.0f, %.2f × E)"
                 % (GAP_MIN, GAP_PCT, GAP_MIN, GAP_PCT * CURRENT_Q_LO))
    lines.append("- T(E) = L(E) − gap；R < T(E) → 放弃派")
    lines.append("- E < %d → 样本不足" % GRAY_BELOW_ENTRIES)
    lines.append("- N/R：<10% 深绿；10–50% 绿；50–70% 黄（仅本地）；≥70% 红（且 R≥30）；R<20 灰；"
                 "≥70% 但 R<30 封顶为黄")
    lines.append("")
    current = report["current"]
    lines.append("当前主样本：放弃派 %d，贪婪派 %d；其中红档 %d，黄档 %d，"
                 "低 G 贪婪派 %d。"
                 % (current["pass_gap"], current["greed_gap"], current["bands"]["red"],
                    current["bands"]["yellow"] + current["bands"]["yellow_capped"],
                    current["greed_lowg"]))
    lines.append("")
    lines.append("## 7. 复核提示")
    lines.append("")
    if report["flags"]:
        for flag in report["flags"]:
            lines.append("- %s" % flag)
    else:
        lines.append("- 本轮没有触发复核标记。")
    lines.append("")
    lines.append("**建议：%s**" % report["suggestion"])
    lines.append("")
    lines.append("本报告不会修改 `src/Config.lua`，也不会被插件自动读取。"
                 "确认后再手动修改；改完在游戏内 `/nw test` 并重启界面。")
    lines.append("")
    return "\n".join(lines)


def csv_row(report):
    c = report["counts"]
    q = report["quantiles"]
    gq = report["g_quantiles"]
    lowg10 = report["low_g"]["cut_10"]
    high50 = report["high_nr"]["cut_50"]
    high70 = report["high_nr"]["cut_70"]
    current = report["current"]
    row = {
        "csv_version": CSV_VERSION,
        "generated_at_utc": report["generated_at_utc"],
        "snapshot_id": report["snapshot_id"],
        "sources": len(report["sources"]),
        "ggs_files": sum(1 for s in report["sources"] if s["kind"] == "ggs"),
        "nw_files": sum(1 for s in report["sources"] if s["kind"] == "nw"),
        "cache_rows": c["cache_rows"],
        "records": c["records"],
        "unique": c["unique"],
        "self_excluded": c["self_excluded"],
        "invalid": c["invalid"],
        "dedup_conflicts": c["dedup_conflicts"],
        "zero_entries": c["zero_entries"],
        "zero_rolls": c["zero_rolls"],
        "usable": c["usable"],
        "main_n": c["main"],
        "gray_n": c["gray"],
        "q05": q["p05"], "q10": q["p10"], "q15": q["p15"],
        "q18": q["p18"], "q20": q["p20"], "q50": q["p50"], "q90": q["p90"],
        "g_p00": gq.get("p00"), "g_p05": gq.get("p05"),
        "g_p10": gq.get("p10"), "g_p50": gq.get("p50"),
        "current_q": CURRENT_Q_LO,
        "current_pct_below": report["current_percentile_below"],
        "current_pct_at_or_below": report["current_percentile_at_or_below"],
        "pass_current_nogap": current["pass_nogap"],
        "pass_current_gap": current["pass_gap"],
        "moved_by_gap": current["moved_by_gap"],
        "greed_current": current["greed_gap"],
        "pass_current_high_nr": current["pass_high_nr"],
        "pass_current_lowg": current["pass_lowg"],
        "greed_current_lowg": current["greed_lowg"],
        "band_gray": current["bands"]["gray"],
        "band_darkgreen": current["bands"]["darkgreen"],
        "band_green": current["bands"]["green"],
        "band_yellow": current["bands"]["yellow"],
        "band_yellow_capped": current["bands"]["yellow_capped"],
        "band_red": current["bands"]["red"],
        "lowg10_n": lowg10["n"],
        "lowg10_ne_p50": lowg10.get("ne_p50"),
        "lowg10_ne_p90": lowg10.get("ne_p90"),
        "lowg10_ne_p95": lowg10.get("ne_p95"),
        "lowg10_ne_max": lowg10.get("ne_max"),
        "lowg10_re_p95": lowg10.get("re_p95"),
        "lowg10_over_current": lowg10.get("over_current"),
        "lowg10_nr50": lowg10.get("nr50"),
        "highnr50_n": high50["n"],
        "highnr50_pass_current": high50.get("pass_current"),
        "highnr50_ne_p95": high50.get("ne_p95"),
        "highnr50_re_max": high50.get("re_max"),
        "highnr70_n": high70["n"],
        "highnr70_pass_current": high70.get("pass_current"),
        "highnr70_ne_p95": high70.get("ne_p95"),
        "highnr70_re_max": high70.get("re_max"),
        "separation": report["separation"],
        "suggestion": report["suggestion"],
    }
    return row


def write_history(path, row):
    fieldnames = list(row.keys())
    exists = os.path.exists(path) and os.path.getsize(path) > 0
    if exists:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames != fieldnames:
                raise RuntimeError("历史 CSV 表头不一致；未追加。请备份或删除旧文件后重试。")
    with open(path, "a", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        if not exists:
            writer.writeheader()
        writer.writerow(row)


def last_snapshot(path):
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    with open(path, "r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    return rows[-1].get("snapshot_id") if rows else None


def lua_snippet(report):
    q = report["quantiles"]
    c = report["current"]
    lines = [
        "-- Generated by analysis/calibrate_pass_ratio.py",
        "-- Review-only. This file is NOT loaded by the addon and is NOT applied automatically.",
        "-- Snapshot: %s" % report["snapshot_id"],
        "-- Generated (UTC): %s" % report["generated_at_utc"],
        "--",
        "-- Current constants in src/Config.lua:",
        "--   qLo = 5.4",
        "--   gapPct = 0.15",
        "--   gapMin = 3",
        "--",
        "-- Candidates from this snapshot:",
        "--   p10 R/E = %s" % fmt(q["p10"]),
        "--   p15 R/E = %s" % fmt(q["p15"]),
        "--   p18 R/E = %s" % fmt(q["p18"]),
        "--   p20 R/E = %s" % fmt(q["p20"]),
        "--   5.4 percentile (strictly below) = %s" % fmt_pct(report["current_percentile_below"]),
        "--   low-G (G/R<=10%%) n = %d" % report["low_g"]["cut_10"]["n"],
        "--",
        "-- Current rule counts:",
        "--   pass = %d, greed = %d, red = %d, yellow = %d"
        % (c["pass_gap"], c["greed_gap"], c["bands"]["red"],
           c["bands"]["yellow"] + c["bands"]["yellow_capped"]),
        "--",
        "-- Suggestion: %s" % report["suggestion"],
        "--",
        "-- To apply manually, edit src/Config.lua (NW.RULE), then run /nw test.",
        "",
        "return {",
        '    snapshot = "%s",' % report["snapshot_id"],
        '    generated_at_utc = "%s",' % report["generated_at_utc"],
        "    current_q_lo = %.1f," % CURRENT_Q_LO,
    ]
    for key in ("p05", "p10", "p15", "p18", "p20", "p50", "p90"):
        lines.append("    %s = %s," % (key, fmt(q[key]) if q[key] is not None else "nil"))
    lines.append("    main_n = %d," % report["counts"]["main"])
    lines.append("    low_g_n = %d," % report["low_g"]["cut_10"]["n"])
    lines.append("    separation = %s," % (fmt(report["separation"]) if report["separation"] is not None else "nil"))
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# ------------------------------------------------------------------ self ----

def self_test():
    failures = []
    checks = []

    def check(name, got, want):
        ok = got == want
        checks.append((name, got, want, ok))
        if not ok:
            failures.append(name)

    lower, gap, cutoff = threshold(5.4, 10)
    check("threshold E=10 L", round(lower, 6), 54.0)
    check("threshold E=10 gap", round(gap, 6), 8.1)
    check("threshold E=10 T", round(cutoff, 6), 45.9)
    lower, gap, cutoff = threshold(5.4, 3)
    check("threshold E=3 L", round(lower, 6), 16.2)
    check("threshold E=3 gap", round(gap, 6), 3.0)
    check("threshold E=3 T", round(cutoff, 6), 13.2)
    check("band R=19 gray", band(19, 0), "gray")
    check("band 100% R=20 capped", band(20, 0), "yellow_capped")
    check("band 70% R=30 red", band(21, 9), "red")
    check("band 50% R=30 yellow", band(15, 15), "yellow")
    check("band 49% R=100 green", band(49, 51), "green")
    check("band 9% R=100 darkgreen", band(9, 91), "darkgreen")
    check("classify pass", classify(Row("g", 18, 0, 5, 0, 1, "t"), 5.4, True), "pass")
    check("classify greed", classify(Row("g", 30, 0, 5, 0, 1, "t"), 5.4, True), "greed")
    check("classify no-gap pass", classify(Row("g", 20, 0, 5, 0, 1, "t"), 5.4, False), "pass")
    check("percentile", percentile_below(3.0, [1.0, 2.0, 3.0, 4.0]), 0.5)
    print("Self-test:")
    for name, got, want, ok in checks:
        print("  %s %-28s got=%r want=%r" % ("PASS" if ok else "FAIL", name, got, want))
    print("  %d / %d passed" % (len(checks) - len(failures), len(checks)))
    return 0 if not failures else 1


# ------------------------------------------------------------------- main ---

def main(argv=None):
    parser = argparse.ArgumentParser(description="NinjaWatcher pass-type cutoff calibration")
    parser.add_argument("--dry-run", action="store_true", help="print only; write nothing")
    parser.add_argument("--force", action="store_true", help="write even if the snapshot is unchanged")
    parser.add_argument("--quiet", action="store_true", help="print a one-line summary")
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    parser.add_argument("--ggs-pattern", default=None)
    parser.add_argument("--nw-pattern", default=None)
    parser.add_argument("--min-main", type=int, default=MIN_MAIN)
    parser.add_argument("--min-lowg", type=int, default=MIN_LOWG)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    ggs_pattern = args.ggs_pattern or os.path.join(
        args.data_dir, "*", "SavedVariables", "GrimlightGoldScanner.lua")
    nw_pattern = args.nw_pattern or os.path.join(
        args.data_dir, "*", "SavedVariables", "NinjaWatcher.lua")

    sources = []
    records = []
    ggs_meta = []
    nw_meta = []
    parse_errors = []

    def load(kind, pattern, var_name, extractor, meta_list):
        paths = sorted(glob.glob(pattern))
        for index, path in enumerate(paths, 1):
            db, size, digest = parse_savedvars(path, var_name)
            meta = {"kind": kind, "size": size, "sha1": digest,
                    "self_excluded": 0, "invalid": 0}
            if db is None:
                parse_errors.append("%s:%d" % (kind, index))
                meta_list.append(meta)
                continue
            part, self_excluded, invalid = extractor(db)
            meta["self_excluded"] = self_excluded
            meta["invalid"] = invalid
            records.extend(part)
            meta_list.append(meta)
        return len(paths)

    ggs_files = load("ggs", ggs_pattern, "GGSDB", extract_ggs, ggs_meta)
    nw_files = load("nw", nw_pattern, "NinjaWatcherDB", extract_nw, nw_meta)
    sources = ggs_meta + nw_meta

    if ggs_files + nw_files == 0:
        print("未找到数据源。")
        print("  GGS pattern: %s" % ggs_pattern)
        print("  NW  pattern: %s" % nw_pattern)
        return 1
    if not records:
        print("数据源存在，但没有可用记录。")
        return 1

    report = build_report(records, ggs_meta, nw_meta, parse_errors,
                          args.min_main, args.min_lowg)
    text = markdown(report, ggs_meta, nw_meta)

    history_path = os.path.join(args.out_dir, "pass_ratio_history.csv")
    latest_md = os.path.join(args.out_dir, "latest.md")
    latest_json = os.path.join(args.out_dir, "latest.json")
    latest_lua = os.path.join(args.out_dir, "latest.lua")

    if args.dry_run:
        print(text)
        return 0

    unchanged = (last_snapshot(history_path) == report["snapshot_id"])
    outputs_exist = all(os.path.exists(p) for p in (latest_md, latest_json, latest_lua))
    if unchanged and outputs_exist and not args.force:
        if not args.quiet:
            print(text)
        print("快照未变化，跳过写入（--force 可强制）。")
        return 0

    os.makedirs(args.out_dir, exist_ok=True)
    write_history(history_path, csv_row(report))
    with open(latest_md, "w", encoding="utf-8") as handle:
        handle.write(text)
    with open(latest_json, "w", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    with open(latest_lua, "w", encoding="utf-8") as handle:
        handle.write(lua_snippet(report))

    if args.quiet:
        c = report["counts"]
        print("snapshot=%s main=%d lowg10=%d pass=%d greed=%d -> %s"
              % (report["snapshot_id"][:12], c["main"],
                 report["low_g"]["cut_10"]["n"], report["current"]["pass_gap"],
                 report["current"]["greed_gap"],
                 os.path.relpath(latest_md, SCRIPT_DIR)))
    else:
        print(text)
        print("")
        print("已写入：")
        for path in (history_path, latest_md, latest_json, latest_lua):
            print("  %s" % os.path.relpath(path, SCRIPT_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
