# 分析脚本说明

本目录只做**只读聚合分析**，不参与插件运行。所有输出已脱敏：不含玩家名、GUID、服务器名、账号路径。

## 文件

| 路径 | 作用 |
|---|---|
| `calibrate_pass_ratio.py` | **主标定脚本**：读 GGS + NinjaWatcher SavedVariables，算 R/E 分位、5.4 的位置、候选 q_lo 的判定结果、低 G / 高 N/R 子集 |
| `ggs_dist.py` | 旧版分布脚本（`n>=20` 口径）；保留用于回看 Phase 0 数字，当前结论以标定脚本为准 |
| `map_ids.py` | 读 `external/achievement.csv`，把统计 ID 映射到名称，列出 5 人相关条目 |
| `calibration/pass_ratio_history.csv` | 每次快照一行；标定脚本自动追加 |
| `calibration/latest.md` | 最近一次可读报告 |
| `calibration/latest.json` | 最近一次机器可读结果 |
| `calibration/latest.lua` | 复核用 Lua 表（插件**不读取**） |
| `outputs/ggs_dist_report.txt` | `ggs_dist.py` 的旧输出（154 行） |
| `outputs/id_map.txt` | `map_ids.py` 的输出（148 行） |
| `external/achievement.csv` | 外部成就/统计表（wago.tools），只读参考 |

## 运行

```bash
cd "D:/Users/MLTZ/Desktop/Addons of WoW/NinjaWatch - 全需党规避器"
py -I analysis/calibrate_pass_ratio.py            # 新快照才写
py -I analysis/calibrate_pass_ratio.py --dry-run  # 只打印，不写
py -I analysis/calibrate_pass_ratio.py --force    # 强制重写
py -I analysis/calibrate_pass_ratio.py --self-test
```

- 需要 Python 3；无第三方依赖。
- 用 `-I` 隔离环境，避免当前目录/用户 site-packages 里的同名模块被误加载。
- 默认输入路径：
  - `D:/World of Warcraft/_cn_beta_/WTF/Account/*/SavedVariables/GrimlightGoldScanner.lua`
  - 同目录 `NinjaWatcher.lua`（尚不存在）
- 换机器/换客户端目录时用 `--ggs-pattern` / `--nw-pattern` 覆盖，或改脚本顶部常量。

## `calibrate_pass_ratio.py` 做了什么

1. 用自带的 `LuaParser` 解析 `GGSDB = {...}` / `NinjaWatcherDB = {...}`（**不执行 Lua**）。
2. 取 `GGSDB.cache` 与 `NinjaWatcherDB.players`；排除 `self=true` 的行。
3. Need/Greed 优先取 `row.need`/`row.greed`；缺失时回退 `row.all[1044]`/`row.all[1043]`。
4. 只接受 `quality` 为 `readable`/`zero`（或字段缺失但数值合法）的行；负数/小数/非数值按不可读处理。
5. 按 GUID 去重：`at` 新者优先；同时间 NinjaWatcher 优先。
6. 主样本 `E≥4`；分别算全员与主样本的 `R/E` 分位（p05/p10/p15/p18/p20/p50/p90）。
7. 算 5.4 的严格百分位；对候选 q_lo（3.117/3.841/4.754/4.934/5.4）算放弃派/贪婪派计数、gap 改判数、放弃派中 N/R≥50% 人数、贪婪派低 G 人数、贪婪派最大 N/R。
8. 算低 G 子集（G/R≤0/10/20/30%）的 N/E 分位；样本不足时明确报 `n=0`。
9. 算高 N/R 子集（≥50/60/70%）的 N/E、R/E、当前判放弃派人数。
10. 输出档位分布（灰/深绿/绿/黄/封顶/红）。

## 输出与隐私

- `pass_ratio_history.csv`：一行一个快照；字段含时间、源文件 sha1/大小、样本漏斗、分位、候选 q_lo 结果。
- `latest.md`：人读版，含“当前建议”（维持 5.4 / 样本不足）。
- `latest.json`：机器可读。
- `latest.lua`：`return { ... }`，仅复核；**插件不会加载它**。
- **不修改 `Config.lua`**；确认后手动改 `NW.RULE`，再 `/nw test`。
- 不打印 `GGSDB.cache` 的键（GUID）、角色名、服务器名；输出只有聚合计数与匿名分位数。
- 不要把原始 `GrimlightGoldScanner.lua` / `NinjaWatcher.lua` 复制进本目录；它们含账号/角色数据。

## 快照未变化时

- 脚本计算快照哈希；若与 `pass_ratio_history.csv` 最后一行相同且 `latest.*` 都在，则只打印报告并提示“快照未变化，跳过写入”，退出码 0。
- `--force` 可强制再写一行（用于口径变更后留档）。

## `ggs_dist.py`（旧）

- 仍可跑：`py -3 -I analysis/ggs_dist.py > analysis/outputs/ggs_dist_report.txt`。
- 它用 `n>=20` 口径，**不含放弃派筛查**；其“需求率/档位”数字已被 `calibrate_pass_ratio.py` 取代，仅作历史对照。
- 输入路径写死在脚本内；换客户端目录需改 `pattern`。

## `map_ids.py`

- 读 `external/achievement.csv` 的 `ID`、`Title_lang`、`Description_lang`、`Category`、`Flags`。
- 打印 `WANTED` 列表里每个 ID 的映射；CSV 中没有的显示 `<not in CSV>`。
- 只做名称映射，不访问游戏、不访问网络。

## 复跑注意

- GGS 缓存会随使用变化；复跑数字会变，`calibration/latest.*` 是最近一次快照。
- 若 `files found` 为 0，先确认客户端路径和账号目录。
- 若 GGS 改变缓存字段（例如不再写 `need`/`greed`），脚本会回退 `row.all`；两者都没有就计入缺失。
- 任何新分析脚本都应保持“只读、聚合、脱敏”三条；不要新增会打印名字/GUID 的调试输出。
