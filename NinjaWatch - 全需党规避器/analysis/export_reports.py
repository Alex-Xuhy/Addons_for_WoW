#!/usr/bin/env python3
"""BETA(0.2.0): export the tester's "报告全需玩家" samples.

An addon cannot write files. The marks live in SavedVariables, which the client
flushes on /reload or on logout:

    WTF/Account/*/SavedVariables/NinjaWatcher.lua     NinjaWatcherDB.reports

This script turns that table into two plain files under analysis/outputs/:

    reported_players.csv   one row per sample, for threshold work
    reported_players.md    the same table, readable

The Lua file is parsed as text and never executed; nothing is written back to
WTF. No character name and no full GUID is printed or written: a sample is
identified by the first eight hex digits of a SHA-1 of its GUID.

Usage
-----
    py -I analysis/export_reports.py
    py -I analysis/export_reports.py --dry-run
    py -I analysis/export_reports.py --data-dir "D:/.../WTF/Account"
    py -I analysis/export_reports.py --out-dir analysis/outputs
"""

import argparse
import csv
import glob
import hashlib
import os
import re
import statistics
import sys
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

from ggs_dist import LuaParser, num  # noqa: E402

DEFAULT_DATA_DIR = r"D:/World of Warcraft/_cn_beta_/WTF/Account"
DEFAULT_OUT_DIR = os.path.join(SCRIPT_DIR, "outputs")

BAND_NAMES = {
    "green": "正常",
    "darkgreen": "正常",
    "yellow": "偏高",
    "red": "极高",
    "gray": "样本少",
}

CSV_FIELDS = [
    "sample_id", "marked_at_local", "need", "greed", "entries", "rolls",
    "need_share_pct", "rolls_per_entry", "verdict", "threshold", "complete",
]


# ---------------------------------------------------------------- parsing ---
def parse_savedvars(path, var_name):
    """Return the value assigned to var_name, or None. Never raises."""
    with open(path, "rb") as handle:
        text = handle.read().decode("utf-8", "replace")
    match = re.search(r"(?m)^\s*" + re.escape(var_name) + r"\s*=", text)
    if not match:
        match = re.search(r"\b" + re.escape(var_name) + r"\s*=", text)
    if not match:
        return None
    try:
        return LuaParser(text[match.end():]).value()
    except Exception:
        return None


def as_count(value):
    """Counts are non-negative integers; 18.5 is not a count."""
    value = num(value)
    if value is None or value < 0 or value != int(value):
        return None
    return int(value)


def sample_id(guid):
    return hashlib.sha1(guid.encode("utf-8", "replace")).hexdigest()[:8]


def stamp(epoch):
    """Local time: the mark was made on this machine, so show its clock."""
    value = num(epoch)
    if value is None or value <= 0:
        return ""
    return datetime.fromtimestamp(value).strftime("%Y-%m-%d %H:%M")


def verdict(report):
    status = report.get("status")
    if status is None:
        return "待扫描"
    if status == "insufficient":
        return "数据不足"
    if status != "ok":
        return "不可读"
    if report.get("branch") == "pass":
        return "低（放弃型）"
    return BAND_NAMES.get(report.get("band"), "未知")


def build_rows(reports):
    """One dict per marked player. Incomplete marks are kept, flagged."""
    rows = []
    for guid in sorted(reports):
        report = reports.get(guid)
        if not isinstance(report, dict):
            continue
        need = as_count(report.get("need"))
        greed = as_count(report.get("greed"))
        entries = as_count(report.get("entries"))
        rolls = as_count(report.get("rolls"))
        complete = None not in (need, greed, entries, rolls)
        share = (100.0 * need / rolls) if complete and rolls else None
        per_entry = (rolls / entries) if complete and entries else None
        rows.append({
            "sample_id": sample_id(guid),
            "marked_at_local": stamp(report.get("at")),
            "need": "" if need is None else need,
            "greed": "" if greed is None else greed,
            "entries": "" if entries is None else entries,
            "rolls": "" if rolls is None else rolls,
            "need_share_pct": "" if share is None else "%.1f" % share,
            "rolls_per_entry": "" if per_entry is None else "%.2f" % per_entry,
            "verdict": verdict(report),
            "threshold": "" if num(report.get("threshold")) is None
                         else "%.1f" % num(report.get("threshold")),
            "complete": "yes" if complete else "no",
            "_share": share,
        })
    return rows


# ----------------------------------------------------------------- output ---
def write_csv(path, rows):
    with open(path, "w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_markdown(path, rows):
    complete = [row for row in rows if row["complete"] == "yes"]
    shares = [row["_share"] for row in complete if row["_share"] is not None]
    lines = [
        "# 已报告的全需玩家样本",
        "",
        "- 生成时间（本地）：%s" % datetime.now().strftime("%Y-%m-%d %H:%M"),
        "- 数据源：`NinjaWatcherDB.reports`（WTF SavedVariables 快照）",
        "- 样本数：%d（其中 %d 条含完整计数）" % (len(rows), len(complete)),
        "- 样本 ID：GUID 的 SHA-1 前 8 位，不含角色名或完整 GUID",
        "",
    ]
    if shares:
        lines += [
            "需求率（= 需求掷骰次数 ÷ 合计掷骰次数）："
            "最低 %.1f%%、中位 %.1f%%、最高 %.1f%%。" % (
                min(shares), statistics.median(shares), max(shares)),
            "",
        ]
    if not rows:
        lines += ["目前没有任何已报告的玩家。", ""]
    else:
        lines += [
            "| 样本 | 标记时间(本地) | 需求 | 贪婪 | 进入地下城 | 合计 | 需求率 | 当时判定 | 当时门槛 |",
            "|---|---|---|---|---|---|---|---|---|",
        ]
        for row in rows:
            lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                row["sample_id"], row["marked_at_local"] or "–",
                row["need"] if row["need"] != "" else "–",
                row["greed"] if row["greed"] != "" else "–",
                row["entries"] if row["entries"] != "" else "–",
                row["rolls"] if row["rolls"] != "" else "–",
                (row["need_share_pct"] + "%") if row["need_share_pct"] != "" else "–",
                row["verdict"],
                row["threshold"] if row["threshold"] != "" else "–",
            ))
        lines.append("")
    lines += [
        "「当时判定」与「当时门槛」是点击报告那一刻按当时规则冻结的，"
        "以后改 q_lo 或档位边界不会改写老样本。",
        "",
    ]
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", default=DEFAULT_DATA_DIR)
    parser.add_argument("--out-dir", default=DEFAULT_OUT_DIR)
    parser.add_argument("--pattern", default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    pattern = args.pattern or os.path.join(
        args.data_dir, "*", "SavedVariables", "NinjaWatcher.lua")
    paths = sorted(glob.glob(pattern))
    if not paths:
        print("未找到 NinjaWatcher 的 SavedVariables。")
        print("  pattern: %s" % pattern)
        return 1

    reports = {}
    parsed = 0
    for path in paths:
        db = parse_savedvars(path, "NinjaWatcherDB")
        if not isinstance(db, dict):
            continue
        parsed += 1
        table = db.get("reports")
        if isinstance(table, dict):
            reports.update(table)

    rows = build_rows(reports)
    print("读取 %d 个文件、解析 %d 个；已报告样本 %d 条。" % (len(paths), parsed, len(rows)))
    if args.dry_run:
        for row in rows:
            print("  %s  需求率 %s  判定 %s" % (
                row["sample_id"], row["need_share_pct"] or "–", row["verdict"]))
        return 0

    os.makedirs(args.out_dir, exist_ok=True)
    csv_path = os.path.join(args.out_dir, "reported_players.csv")
    md_path = os.path.join(args.out_dir, "reported_players.md")
    write_csv(csv_path, rows)
    write_markdown(md_path, rows)
    print("已写入：%s" % csv_path)
    print("已写入：%s" % md_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
