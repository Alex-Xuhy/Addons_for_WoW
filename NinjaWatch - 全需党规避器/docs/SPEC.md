# NinjaWatcher 设计规格

**版本**：v0.2（2026-10-23）
**状态**：与 `src/` 现行代码一致；静态检查通过；尚未游戏内实测。

## 1. 目标

在 5 人小队中，用三个公开成就统计识别“需求占比异常”的队友；先排除“很少贪婪、以放弃为主”的正常玩家（放弃派），再对剩余玩家看 Need 占比。

两类信号：

1. **放弃派筛查**：`R=N+G` 与 `T(E)` 比较；低于门槛的玩家直接放行，不进入 N/R 评价，也不报警。
2. **N/R 档位**：对贪婪派计算 `N/R`，按 10/50/70% 分档；红档才可能触发可选 `/p`。

## 2. 非目标

v1 不做，除非用户明确解禁：

- 逐件/逐场掉落记录、某次需求时其他人是否也需求。
- 跨甲、跨天赋、A/N 适配判断。
- 两次扫描的增量。
- 读取 Need/Greed 之外的掷骰数据（`C_LootHistory`、`GetLootRoll`、`START_LOOT_ROLL`）。
- 终身 Pass 统计（不存在）。
- 右键头像菜单、小地图按钮、独立主窗口、GGS 风格皮肤。
- 除红档 `/p` 外的任何自动聊天。
- 复制/改写 GGS 代码（All Rights Reserved）。
- 同等级段绝对 Need 阈值/中位数+MAD（v0.1 旧方案，已删除）。
- 从 GGS 缓存冷启动 `NinjaWatcherDB`（未实现）。

## 3. 数据接口

| 字段 | ID | 含义 | 来源 |
|---|---:|---|---|
| Need | 1044 | Need rolls made on loot / 需求掷骰 | 他人 `GetComparisonStatistic`；自己 `GetStatistic` |
| Greed | 1043 | Greed rolls made on loot / 贪婪掷骰 | 同上 |
| Entries | 932 | Total 5-player dungeons entered / 5 人本进入次数 | 同上 |

- 三者都是**终身计数**，不是本场。
- `R = N + G`。
- 没有可用的终身 `Pass` 统计；`1045` 是“Total cheers”，不是 Pass。
- 缺失/secret/API 报错 → 未知，**绝不按 0**。
- `1103`/`1467`（巫妖王 5 人本完成/首领击杀）在 GGS 缓存中 0 行，v1 不用作通用 `B`；`932` 是当前 `E` 的口径。
- `C_LootHistory` 的 `NoRoll` 不等于主动放弃，v1 不读。

## 4. 运行时模型

### 4.1 放弃派筛查

```
q_lo = 5.4
L(E) = q_lo × E
gap  = max(3, 0.15 × L(E)) = max(3, 0.81 × E)
T(E) = L(E) − gap
```

- `E < 4` → `insufficient`（灰），不分类。
- `R < T(E)` → `pass`（放弃派）：不评估 N/R、不报警。
- `R ≥ T(E)` → `greed`（贪婪派）：进入 4.2。

量纲与含义：

- `q_lo` 的单位是**掷骰次数/次进入**，不是掉落件数。
- `L(E)` 是“正常玩家 E 次进入至少应有多少次 Need+Greed”的保守下界；`q_total`（每趟总可 roll 机会）约 9–25，正常玩家会放弃很大一部分，所以 `R` 低于 `q_total×E` 是正常的。
- `gap` 是政策缓冲，不是置信区间；15% 是相对容忍，3 次是小数样本保护。`E≥4` 时等价于“比下界再低 15% 才判放弃派”。
- `q_lo=5.4` 是公测样本的保守先验，**不是 p10**。当前主样本（E≥4）p10≈3.12、p15≈3.84，5.4 约在 p23；全样本（E>0）p10≈3.82、p15≈5.10，5.4 约在 p18。不要把 5.4 标成 p10。
- 为什么不用 p10=3.12：一个 `G=0`、`N/E=3.60` 的放弃派在 3.12 线下会被判贪婪派，E≥10 时还可能进红档；5.4+gap 能把他清掉。
- `N/E` 不是门槛：`R/E = N/E + G/E ≥ N/E`；高 `N/E` 足以排除放弃派，低 `N/E` 不能单独证明放弃派。

### 4.2 N/R 档位

只对 `greed` 分支：

| 档位 | N/R | 颜色 | 行为 |
|---|---:|---|---|
| 低 | `<10%` | 深绿 | 仅提示 |
| 正常 | `10%–<50%` | 绿 | 仅提示 |
| 偏高 | `50%–<70%` | 黄 | 本地聊天框；**不发队伍** |
| 极高 | `≥70%` 且 `R≥30` | 红 | 本地提示；开关开启时 5 人队 `/p` 一次 |
| 封顶 | `≥70%` 且 `20≤R<30` | 黄 | 仅本地，提示“R<30，最高只显示黄档” |
| 样本少 | `R<20` | 灰 | 不判档（优先于封顶） |

- `N/R` 是比例，不是概率；`N/R=34.6%` 表示记录到的 Need+Greed 中 34.6% 是 Need。
- 50% 是结构性线（Need 过半），不是统计显著性线；70% 是“Need 压倒性”政策线 + 小样本保护，不是数据里的自然断点。
- 70% 在 `R=30` 的精确单侧 95% 下界约 53.5%；50% 在 `R=30` 的下界约 33.9%，所以 50% 不能用来“证明 >50%”，只用于分档。
- 黄档只在本地聊天框；红档 `/p` 默认关闭，按 GUID 冷却 300 秒。

## 5. UI

入口：**设置 → 插件 → NinjaWatcher**。不做右键菜单、小地图按钮、独立主窗口。

两页：

1. **玩家**：本地目录；列 Name/Level/N/G/E/R/N-R/档位/最后扫描；支持按最近或 N/R 排序；扫描队伍、两次确认清除全部。
2. **选项**：鼠标提示、自己提示、黄档本地提示、红档 `/p`；规则说明；隐私说明；恢复默认。

鼠标提示：`GameTooltip:AddDoubleLine("NinjaWatcher", "需求率 xx% · 档位")`，下一行灰色样本 `N/G/E/R`。放弃派显示“放弃派 · 不评估”与 `R < T(E)`；样本不足/不可读显示原因。只追加，不遮挡其他插件。

入队报警：

- 只在 5 人小队（非团队）触发；新成员或队伍从 4 人变 5 人时补扫。
- 黄档：本地聊天框，文案“队伍中「姓名」的需求率偏高…仅本地提示。”
- 红档：若 `partyAlert` 开启，发一次 `/p`：“玩家xxx疑似全需党，ta在R次战利品掷骰中选择需求了N次。请留意。（数据来自公开成就统计，仅供参考，不构成决策建议）”；未开启则本地红字。
- 同一 GUID 冷却 300 秒；离开队伍后 `seen` 重置。

## 6. 扫描与缓存

- 他人：`SetAchievementComparisonUnit(unit)` → `INSPECT_ACHIEVEMENT_READY` → `GetComparisonStatistic(1044/1043/932)` → `ClearAchievementComparisonUnit()`。
- 自己：`GetStatistic(id)`。
- 同一时间一个请求在飞；最小间隔 1.5s；悬停超时 2.5s；手动 15s；悬停去抖 0.3s；远距离失败 TTL 3s。
- 按 GUID 缓存；默认 10 分钟新鲜。
- 绝不调用 `NotifyInspect`/`InspectAchievements`；不注册受限事件；不打开暴雪面板。
- 原生 `AchievementFrameComparison` 也监听 `INSPECT_ACHIEVEMENT_READY`：请求期间临时注销它的订阅，结束后恢复；若原生窗口被我们的请求弹出，隐藏它。
- `SetAchievementComparisonUnit`/`ClearAchievementComparisonUnit` 用 `hooksecurefunc` 监视；外部改动会取消我们的请求（BUSY 5s），避免读错人。
- 战斗中不扫描；`InCombatLockdown` 检查失败也按战斗处理（fail safe）。

## 7. 数据库

`NinjaWatcherDB`（SavedVariables，仅本地）：

```
version = 1
options = { tooltip, selfTooltip, localAlert, partyAlert,
            cacheMinutes, redCooldown }
players[guid] = {
  name, realm, level, class, classKey,
  need, greed, entries,
  quality = { need, greed, entries },  -- readable/zero/unknown/...
  at, firstAt, scanCount, source
}
```

- 按 GUID 去重；每次扫描更新最新值；未知字段保持 nil，不写 0。
- `quality` 用于区分“可读的 0”与“不可读”；`Rate.Evaluate` 拒绝不可读行。
- 目录页可清除全部；`/nw clear confirm` 同样。
- 不上传、不分享；不写 WTF 以外的位置。

## 8. 数据驱动标定

`analysis/calibrate_pass_ratio.py`：

- 只读 GGS `GGSDB.cache` 与 NinjaWatcher `NinjaWatcherDB.players`；按 GUID 去重（新时间戳优先，NinjaWatcher 优先），排除本人行，要求 N/G/E 可读、E>0、R>0。
- 主样本 `E≥4`；输出 R/E 的 p05/p10/p15/p18/p20/p50/p90、5.4 的严格百分位、候选 q_lo 的放弃派/贪婪派计数与档位分布、低 G（G/R≤10/20/30%）N/E、高 N/R（≥50/60/70%）N/E。
- 产物：`analysis/calibration/pass_ratio_history.csv`、`latest.md`、`latest.json`、`latest.lua`（复核用，插件不读取）。
- 快照未变则跳过；`--force` 强制；`--dry-run` 只打印；`--self-test` 16 项边界测试。
- **不修改 `Config.lua`**；确认后手动改 `NW.RULE`，再 `/nw test`。
- 当前样本：GGS 170 缓存行 → 107 可用 → 68 主样本；`G/R≤10%` 低 G 行为 0，无法估计放弃派上界，维持 5.4。

## 9. 错误处理

- Need/Greed/Entries 任一不可读：`unknown`，提示具体字段；不写 0。
- `E<4`：`insufficient`，灰。
- `R<20`：N/R 灰。
- `20≤R<30` 且 N/R≥70%：黄档 + “R<30，最高只显示黄档”；`R<20` 时先判灰。
- 统计 API 缺失/secret/报错：不报错；提示“数据不可读/客户端不支持对比”。
- 扫描超时/远距离/战斗/原生窗口占用：提示状态，可再次悬停重试。
- 目录页数据过期/等级变化：显示最后扫描时间；不推断未扫描期间的变化。

## 10. 待定/未实测

1. `E<4` 灰线是否最终确认（等价于旧 `L(E)<20` 在 q_lo=5.4 下的写法；已解耦，避免 q_lo 改动带动灰线）。
2. 红档 `/p` 文案是否再收紧；当前默认关闭。
3. 是否需要头像/常驻 HUD；当前只有鼠标提示 + 本地聊天提示。
4. 原生对比窗静音/恢复、4 人→5 人补扫、热加载命名框冲突：代码已处理，需游戏内实测。
5. 低 G 样本达到 20 后，是否用数据分界区间替换 5.4；当前脚本只报告，不自动改。
6. 上线后 `932` 的口径是否稳定（5 人本进入次数 vs 完成/首领击杀）。
