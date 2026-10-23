# NinjaWatcher - 全需党规避器

**阶段：v0.2.0（测试版）；静态检查 0 错误，已在国服 1.60.1（camelot）游戏内实测。**
（档案目录名沿用 `NinjaWatch`；插件显示名 0.1.2 起为 **NinjaWatch - 全需党规避器**，安装文件夹与 `.toc` 仍须叫 `NinjaWatcher`。）

`src/` 已经是完整插件源码，但不要直接把档案根目录放进 `Interface/AddOns`；只复制 `src/`，并改名为 `NinjaWatcher`。

## 现在的规则

数据源只有三个公开成就统计（游戏内一律显示中文名）：

- `需求掷骰次数 = 1044`
- `贪婪掷骰次数 = 1043`
- `进入地下城次数 = 932`（5 人本）
- `合计掷骰次数 = 需求 + 贪婪`

**放弃型（「低」档）筛查**

```
L(E) = 5.4 × E
gap  = max(3, 0.15 × L(E)) = max(3, 0.81 × E)
T(E) = L(E) − gap
E < 4        → 数据不足（灰）
R < T(E)     → 低档（放弃型，不评估需求率、不报警）
R ≥ T(E)     → 进入需求率档位
```

`q_lo=5.4` 是**掷骰次数/次进入**的保守下界，不是掉落件数，也不是 p10。当前主样本（E≥4）p10≈3.12、p15≈3.84，5.4 约在 p23。gap 是政策缓冲，不是置信区间。

**需求率档位（需求/合计）**

| 需求率 | 档位 | 行为 |
|---|---|---|
| 放弃型（合计 < 门槛） | 低（深绿） | 不评估需求率、不报警 |
| <50% | 正常（绿） | 仅提示 |
| 50–70% | 偏高（黄） | 本地聊天框；**不发队伍** |
| ≥70% 且 合计≥30 | 极高（红） | 本地提示；开关开启时 5 人队 `/p` 一次 |
| ≥70% 但 合计<30 | 封顶为黄 | 仅本地 |
| 合计<20 | 样本少（灰） | 不判档 |

> 0.1.1 把原来的 `<10% 低（深绿）` 并入「正常」，把「放弃派」改称「低」，可见档位顺序为 低 / 正常 / 偏高 / 极高。

## 变更记录

### 0.2.0（2026-10-23）·测试版

- 版本定为**测试版**（`NW.BETA = true`，设置页显示「版本 0.2.0 · 测试版」）。
- 右键玩家头像的菜单新增 **「报告全需玩家」**（仅测试版）：把你自己判定为全需的玩家标出来，供以后调整档位阈值。再点一次变成「取消报告」。
  - 标记时**冻结当时的快照**：需求 / 贪婪 / 进入地下城 / 合计 / 需求率 / 当时判定 / 当时门槛 / 标记时间。以后改 `q_lo` 或档位边界不会改写老样本。
  - 玩家目录里，已报告的玩家名字后面带一个 `★`。
  - 若标记时这名玩家还没被扫描过，会顺带发起一次扫描，扫描回来后自动补记计数。
- 新增 `analysis/export_reports.py`：把 `NinjaWatcherDB.reports` 导成 `analysis/outputs/reported_players.csv` 与 `reported_players.md`（样本 ID 用 GUID 的 SHA-1 前 8 位，不含角色名/完整 GUID）。
- 「清除全部记录」现在连已报告样本一起清空（副本会先提醒）。
- 机制说明：插件没有写任意文件的能力，「上传到本机」= 写进 SavedVariables，再由上面的脚本导出；全程无网络请求。

### 0.1.2（2026-10-23）

- 鼠标提示的前缀「需求掷骰行为」改为 **粉色 #f58cba**（与 GGS 同色）。
- 鼠标提示**不再显示第二行的计数样本**（需求/贪婪/进入地下城/合计，四个中文标签拼起来比提示本身还宽）；只保留 `需求率 xx% · 档位`，黄档封顶时另起一行短注。
- 右键玩家头像框的菜单新增一项「详细掷骰行为」，点击打开设置页的「玩家」目录，并把该玩家所在行加上**与鼠标悬停同款的金色高光**（`UI-QuestTitleHighlight`，叠加混合；名字保持白色，避免和金色表头混在一起）、自动滚到可见处；若此玩家还没有记录，会顺带发起一次扫描。
- 玩家表格的「进入」列改称「进入地下城」（列宽同步加宽，表头不再折行）。
- 设置页的「玩家 / 选项」两个标签不再用半透明表示未选中（看起来像没做完），改为两者都正常显示、当前页加金色下划线。
- 修「选项」页「隐私」标题压住上方规则正文的问题（改为跟随正文实际高度往下排）。
- 显示名由 `NinjaWatcher - 全需党规避器` 改为 `NinjaWatch - 全需党规避器`（TOC Title 与设置页标题）。

### 0.1.1（2026-10-23）

- 灰档「样本不足」改称「数据不足」。
- 游戏内 N/G/E/R 全部换成中文：需求掷骰次数 / 贪婪掷骰次数 / 进入地下城次数 / 合计掷骰次数；N/R 改称需求率。
- 表格列头同步中文，玩家页加一行列含义说明；悬停表格行时附「需求率 = 需求掷骰次数/合计掷骰次数，用以提供需求行为的参考」。
- 取消「低」档（并入正常），「放弃派」并入「低」档。
- 修「最后扫描」列：列宽加宽到能放下一整行时间，并给行内文字设固定高度，长文本不再压到下一行。
- 鼠标提示里的前缀由 `NinjaWatcher` 改为「需求掷骰行为」。
- 修 1.60.1 客户端 `GameTooltip:GetUnit()` 返回 `(单位名, 单位 token)` 导致提示行永远不出现的问题（取能被 `UnitExists` 命中的那个返回值）。

## 目录

| 路径 | 内容 |
|---|---|
| [src/](src/) | **可安装插件源码**（10 个 Lua + `.toc`） |
| [src/README.md](src/README.md) | 文件职责、规则、扫描/隐私、安装测试步骤 |
| [docs/SPEC.md](docs/SPEC.md) | 设计规格 v0.2（与现行代码一致） |
| [docs/DECISIONS.md](docs/DECISIONS.md) | 已接受/待定的决策记录 |
| [docs/PROGRESS.md](docs/PROGRESS.md) | 开发进度 |
| [docs/TODO.md](docs/TODO.md) | 待办清单 |
| [docs/DATA-NOTES.md](docs/DATA-NOTES.md) | 数据接口与样本分布 |
| [docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md) | 仍需拍板的项 |
| [docs/GLOSSARY.md](docs/GLOSSARY.md) | 指标/术语表 |
| [analysis/calibrate_pass_ratio.py](analysis/calibrate_pass_ratio.py) | 数据驱动标定脚本（只读 SavedVariables） |
| [analysis/export_reports.py](analysis/export_reports.py) | **测试版**：导出「报告全需玩家」样本 → `analysis/outputs/reported_players.csv` / `.md` |
| [analysis/calibration/latest.md](analysis/calibration/latest.md) | 最近一次标定报告 |
| [analysis/calibration/pass_ratio_history.csv](analysis/calibration/pass_ratio_history.csv) | 每次快照一行 |
| [analysis/ggs_dist.py](analysis/ggs_dist.py) | GGS 缓存聚合脚本（含 Lua 解析器） |
| [analysis/outputs/](analysis/outputs/) | 历史聚合报告（无玩家名/GUID） |
| [analysis/external/](analysis/external/) | 外部统计表快照与来源说明 |

## 数据驱动标定

```bash
py -I analysis/calibrate_pass_ratio.py            # 新快照才写
py -I analysis/calibrate_pass_ratio.py --dry-run  # 只打印
py -I analysis/calibrate_pass_ratio.py --self-test
```

脚本只读 GGS/NinjaWatcher 的 SavedVariables，排除本人行，按 GUID 去重（新时间戳优先，NinjaWatcher 优先），计算主样本 R/E 分位、当前 5.4 的百分位、各候选 q_lo 的放弃派/贪婪派计数、低 G 子集 N/E、高 N/R 子集。输出 `pass_ratio_history.csv`、`latest.md`、`latest.json`、`latest.lua`；**不修改 `Config.lua`**，确认后手动改 `NW.RULE`。

当前样本：GGS 170 缓存行 → 107 可用 → 68 主样本（E≥4）。`G/R≤10%` 的低 G 行为 0，因此本轮无法从数据估计放弃派上界，报告建议维持 5.4。

## 下一步

1. 剩余游戏内检查：真实悬停队友（需要队里有别人）、右键头像的两个菜单项、5 人队黄档本地提示、红档 `/p`（手动开启）、设置页两页签到。
2. **测试版期**：遇到真正的全需玩家时右键「报告全需玩家」，攒够样本后跑 `export_reports.py`，再讨论档位边界与 `q_lo` 是否调整。
3. 上线后定期跑标定脚本；数据足够时再讨论 q_lo 是否替换。低 G 样本 <20 时继续用 5.4。

## 隐私与边界

- 归档只含聚合数据；不含账号文件、角色名、GUID、完整 SavedVariables。
- 分析脚本只读 SavedVariables，不写 WTF；标定输出不含名字/GUID/账号路径。
- 插件数据库 `NinjaWatcherDB` 只存本机，不上传；设置页提供两次确认的清除入口。
- 测试版的「报告全需玩家」只写本机 `NinjaWatcherDB.reports`（无名字、无网络请求）；导出脚本产出的样本 ID 是 GUID 的 SHA-1 前 8 位。
- 红档 `/p` 默认关闭；开启后只在 5 人小队发送，按玩家冷却去重。
- GGS 为 All Rights Reserved；本项目只使用公开统计 ID 与 API 事实，未复制其代码。
- 开发期通过无限工坊操作时，遵守“不发聊天、不打开暴雪面板、不注册受限事件”等规则。

## 本步没有做

- 没有做 `Locale_enUS.lua`。
- 没有做头像/常驻 HUD；目前只有鼠标提示行 + 本地聊天提示。
- 没有自动应用标定结果；`latest.lua` 只是复核用。
- 没有动 `Scan.lua` 里对 `AchievementFrame` / `AchievementFrameComparison` 的静音/还原：1.60.1 上这两个全局恒为 nil，那两段目前是死代码（有守卫，不报错）。
