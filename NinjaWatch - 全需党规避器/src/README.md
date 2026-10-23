# 源码目录

这里已经是可安装的插件源码（v0.1.0）。静态检查通过；**尚未在游戏内实测**（游戏离线），装进客户端前先看最后一节。

## 文件

| 文件 | 职责 |
|---|---|
| `NinjaWatcher.toc` | 清单：`Interface: 16001`、`AllowLoadGameType: camelot`、`SavedVariables: NinjaWatcherDB`、文件顺序 |
| `Config.lua` | 统计 ID、`NW.RULE`（q_lo/gap/灰线/档位）、扫描参数、颜色、默认选项、`NW.L` 兜底 |
| `Locale_zhCN.lua` | 中文文案；键名稳定，可另加 `Locale_enUS.lua` |
| `DB.lua` | `NinjaWatcherDB.players[guid]` 的 upsert/查询/清除/迁移；只本地 |
| `Stats.lua` | 读 `1044`/`1043`/`932`；`GetStatistic` 与 `GetComparisonStatistic`；secret/nil 过滤；单位身份 |
| `Rate.lua` | 纯函数分类器：放弃型门槛、需求率档位、`/nw test` 的 14 个边界用例 |
| `Scan.lua` | 成就对比单请求队列、1.5s 间隔、悬停 2.5s / 手动 15s 超时、缓存、原生对比窗静音 |
| `Tooltip.lua` | `TooltipDataProcessor` 后置回调（回退 `OnTooltipSetUnit` / `UPDATE_MOUSEOVER_UNIT`）；一行本地提示 |
| `Party.lua` | 5 人队监测、新成员扫描、黄档本地提示、红档可选 `/p`、冷却去重 |
| `Settings.lua` | `设置 → 插件` 注册；两页：玩家目录 + 显示与提示 |
| `Core.lua` | 初始化、`/nw` 命令、状态/自测/清除 |

文件顺序：`Config` → `Locale_zhCN` → `DB` → `Stats` → `Rate` → `Scan` → `Tooltip` → `Party` → `Settings` → `Core`。

没有 `Threshold.lua`：等级段中位数/MAD 的旧方案已被下面的规则取代。

## 运行时规则

所有量都来自三个公开成就统计（游戏内显示中文名）：

- `需求掷骰次数 = 1044`
- `贪婪掷骰次数 = 1043`
- `进入地下城次数 = 932`（5 人本）
- `合计掷骰次数 = 需求 + 贪婪`

**第一步，放弃型（「低」档）筛查**

```
L(E) = q_lo × E                     q_lo = 5.4
gap  = max(3, 0.15 × L(E))          = max(3, 0.81 × E)
T(E) = L(E) − gap
E < 4                  → 数据不足（灰），不分类
R < T(E)               → 低档（放弃型），不评估需求率、不报警
R ≥ T(E)               → 进入第二步
```

`q_lo` 是“正常玩家每进一次 5 人本至少有多少次掷骰”的保守下界，单位是**掷骰次数/次进入**，不是掉落件数。5.4 是公测样本的先验，不是 p10；当前主样本（E≥4）p10≈3.12、p15≈3.84，5.4 约在 p23。gap 是政策缓冲，不是置信区间。

**第二步，需求率档位**

| 需求率 | 档位 | 颜色 | 行为 |
|---|---|---|---|
| 放弃型（合计 < 门槛） | 低 | 深绿 | 不评估需求率、不报警 |
| < 50% | 正常 | 绿 | 仅提示 |
| 50–70% | 偏高 | 黄 | 本地聊天框提示；**不发队伍** |
| ≥ 70% 且 合计≥30 | 极高 | 红 | 本地提示；开关开启时 5 人队 `/p` 一次 |
| ≥ 70% 但 合计<30 | 偏高（封顶） | 黄 | 仅本地 |
| 合计<20 | 样本少 | 灰 | 不判档 |

需求率是比例，不是概率。例：`需求率 34.6%` 表示该玩家记录到的掷骰里 34.6% 选了需求。`进入地下城次数<4` 整行显示“数据不足”。（0.1.1 起原 `<10% 低` 并入「正常」，原「放弃派」改称「低」。）

## 扫描与缓存

- 他人：`SetAchievementComparisonUnit(unit)` → `INSPECT_ACHIEVEMENT_READY` → `GetComparisonStatistic(id)` → `ClearAchievementComparisonUnit()`。
- 自己：`GetStatistic(id)`，不经过对比接口。
- 单请求在飞；1.5s 最小间隔；悬停 2.5s 超时、手动 15s；缓存默认 10 分钟。
- 不调用 `NotifyInspect` / `InspectAchievements`；不发聊天（红档 `/p` 除外，默认关闭）；不注册受限事件；不打开暴雪面板。
- 原生 `AchievementFrameComparison` 也监听同一事件：请求期间临时注销它的订阅，结束后恢复；若原生窗口被我们的请求弹出，隐藏它。

## 数据与隐私

- `NinjaWatcherDB` 只写本机 SavedVariables；不上传、不发邮件、不交易。
- 设置页“清除全部记录”两次点击确认；`/nw clear confirm` 同样。
- 发布截图打码；不泄露角色名/GUID/服务器。
- GGS 为 All Rights Reserved：本项目只使用公开统计 ID 与 API 事实，未复制其代码。

## 开发期安装与测试

1. 把整个 `src/` 复制为 `Interface/AddOns/NinjaWatcher/`（文件夹名与 `.toc` 同名）。
2. 新文件/`.toc` 变更需要**完整重启游戏**；只改 Lua 可用无限工坊 `load`。
3. `check` 清错 → `load` → `try` 只读场景 → `snap` 看界面。
4. 游戏内：
   - `/nw test`：14 个边界用例，应全部通过。
   - `/nw status`：看自己的 N/G/E/R 与判定。
   - `/nw`：打开设置页。
   - 鼠标指向队友/自己：看提示行。
   - 5 人队：看黄档本地提示；红档需在选项里手动开启 `/p`。
5. 已知未实测项：原生对比窗静音/恢复、队伍从 4 人到 5 人的补扫、热加载时的命名框冲突（已计划完整重启）。

## 数据驱动的标定

`../analysis/calibrate_pass_ratio.py` 只读 GGS/NinjaWatcher 的 SavedVariables，输出到 `../analysis/calibration/`：

```
py -I analysis/calibrate_pass_ratio.py            # 有新快照才写
py -I analysis/calibrate_pass_ratio.py --dry-run  # 只打印
py -I analysis/calibrate_pass_ratio.py --force    # 强制写
py -I analysis/calibrate_pass_ratio.py --self-test
```

产物：`pass_ratio_history.csv`、`latest.md`、`latest.json`、`latest.lua`（只供复核，插件不读取）。脚本**不会**改 `Config.lua`；确认后手动改 `NW.RULE`，再 `/nw test`。

当前样本：GGS 170 缓存行 → 107 可用（E>0, R>0）→ 68 主样本（E≥4）；G/R≤10% 的低 G 行为 0，因此本轮无法从数据估计放弃派上界，报告建议维持 5.4。
