# 开发进度

**快照日期**：2026-10-23
**当前阶段**：v0.1.0 脚本完成；静态检查通过；**尚未游戏内实测**（客户端离线）。
**代码状态**：`src/` 下 10 个 Lua + `.toc` 已可加载；规则、校准脚本、文档已对齐。

## 总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 0 | 命名、范围、数据接口、样本分布、UI/报警设计 | 已完成 |
| Phase 1 | 放弃派筛查与 N/R 档位定案（q_lo=5.4+gap、E<4、R≥30） | 已完成 |
| Phase 2 | 插件脚本：TOC/Config/Locale/DB/Stats/Rate/Scan/Tooltip/Party/Settings/Core | 已完成 |
| Phase 3 | 静态检查、pytest 式自测（14 例）、文档对齐 | 已完成 |
| Phase 4 | 数据驱动标定脚本 + 首份报告 | 已完成 |
| Phase 5 | 游戏内实测（load/try/snap、提示、报警、设置页） | **未开始（游戏离线）** |
| Phase 6 | 满级样本校准、发布材料 | 未开始 |

## 已完成

### 1. 规则定案

- 数据源只有 `N=1044`、`G=1043`、`E=932`；`R=N+G`。
- 放弃派筛查：`q_lo=5.4`，`L(E)=5.4E`，`gap=max(3,0.15L(E))`，`T(E)=L(E)−gap`。
  - `E<4` → 样本不足（灰）。
  - `R<T(E)` → 放弃派，放行。
  - `R≥T(E)` → 贪婪派，进入 N/R。
- N/R：`<10` 深绿、`10–50` 绿、`50–70` 黄（仅本地）、`≥70` 红（且 `R≥30`）；`R<20` 灰；`R<30` 的 ≥70% 封顶为黄。
- 5.4 是保守先验，不是 p10；p10≈3.12（E≥4）被否决，原因是会误判 `G=0`、`N/E=3.60` 的放弃派。

### 2. 插件脚本（`src/`）

| 文件 | 状态 |
|---|---|
| `NinjaWatcher.toc` | 完成：`Interface 16001`、`AllowLoadGameType: camelot`、`SavedVariables: NinjaWatcherDB` |
| `Config.lua` | 完成：统计 ID、`NW.RULE`、扫描参数、颜色、默认选项 |
| `Locale_zhCN.lua` | 完成：全部中文文案 |
| `DB.lua` | 完成：按 GUID 存储、未知字段保持 nil、清除/排序 |
| `Stats.lua` | 完成：1044/1043/932；自己/对比；secret/nil/小数解析 |
| `Rate.lua` | 完成：`Threshold`、`Evaluate`、档位、14 个边界用例 |
| `Scan.lua` | 完成：单请求队列、1.5s 间隔、超时、缓存、原生对比窗静音、战斗保护 |
| `Tooltip.lua` | 完成：`TooltipDataProcessor` + 回退；双行提示 |
| `Party.lua` | 完成：5 人队监测、4→5 补扫、黄档本地、红档可选 `/p`、冷却 |
| `Settings.lua` | 完成：设置 → 插件注册；玩家目录 + 选项两页 |
| `Core.lua` | 完成：初始化、`/nw` 命令、状态/自测/清除 |

### 3. 本轮修复的关键缺陷

| 缺陷 | 后果 | 修复 |
|---|---|---|
| `Scan.lua` 战斗检查只取 `SafeCall` 第一个返回值 | `true ~= false` 恒真，所有扫描被判战斗 | 新增 `inCombat()`，失败即按战斗处理 |
| `Settings.lua` 在加载时捕获全局 `Settings` | 全局未就绪时设置页永久不注册 | 改为 `Open`/`Init` 内实时取 `_G.Settings` |
| `Settings.lua` 档位颜色传参错误 | `SetTextColor(table,nil,nil)` 报错 | 改为返回 `label, colorTable` 并拆三分量 |
| `Party.lua` 4 人→5 人不补扫 | 第 5 人加入后老成员不报警 | 增加 `wasFiveMan`/`firstFive`，补排队 |
| `Tooltip.lua` 详情行重复/残留 | 提示框越堆越长 | 复用同一行，状态消失时清空隐藏 |
| `Stats.ParseCount` 拒绝 `"18.00"` | 整数值被当成不可读 | 接受整值小数，仍拒绝 `18.5` |

### 4. 静态检查

- 无限工坊 `check`：10 个文件，`errors: []`、`warnings: []`、`ok: true`。
- 仅 3 个已用 `pcall`/存在性守卫的暴雪全局未解析：`AchievementFrame`、`AchievementFrameComparison`、`TooltipDataProcessor`。
- `/nw test` 的 14 个用例由 `Rate.SelfTest()` 覆盖，尚未游戏内跑。

### 5. 数据驱动标定

- 脚本：`analysis/calibrate_pass_ratio.py`。
- 自测 16/16 通过；首份报告已写 `analysis/calibration/{pass_ratio_history.csv,latest.md,latest.json,latest.lua}`。
- 快照：GGS 2,046,898 字节；170 缓存行 → 107 可用 → 68 主样本（E≥4）。
- 当前 5.4 在 E≥4 主样本约 p23.5；p10=3.117、p15=3.841。
- 5.4+gap：放弃派 12、贪婪派 56、被 gap 改判 4；档位灰 1/深绿 13/绿 41/黄 1/红 0。
- 低 G（`G/R≤10/20/30%`）在主样本为 0 行 → 无法估计上界，维持 5.4。
- 隐私 grep：输出无名字/GUID/账号路径。

### 6. 文档

- `README.md`、`src/README.md`、`docs/SPEC.md`（v0.2）已按现行规则重写。
- `docs/DECISIONS.md`、`PROGRESS.md`、`TODO.md`、`GLOSSARY.md`、`DATA-NOTES.md`、`OPEN-QUESTIONS.md`、`analysis/README.md`、`analysis/O-model-math.md` 本轮对齐。

## 当前阻塞

1. **游戏离线**：无法 `load`/`try`/`snap`，无法验证扫描、提示、报警、设置页。
2. **样本偏窄**：Beta 11–30 级；满级分布未知，`q_lo` 与档位仍是先验。
3. **低 G 样本为 0**：无法从数据估计放弃派上界。
4. **`932` 口径未在正式服复验**：当前按“5 人本进入次数”使用。

## 明确未做

- 没有在游戏内加载或实测。
- 没有做 `Locale_enUS.lua`。
- 没有做头像/常驻 HUD。
- 没有自动应用标定结果。
- 没有修改 WTF、没有发任何游戏内聊天、没有打开暴雪面板。
- 没有提交/推送任何仓库。
