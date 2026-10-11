# GrimlightGoldScanner 功能全解 · 与汉化评估

> 依据：GGS v0.9.5 源码逐文件阅读（`Tooltip.lua` / `Score.lua` / `Stats.lua` / `Scan.lua` / `Core.lua` 完整读过，其余据 README 归纳）。
> 所有阈值来自 `Core.lua` 第 23–51 行的 `GGS.DEFAULTS`，全部可调。

---

## 零、结论先行

**功能上，它覆盖了你的预期。**悬停即可看到判定 + 金币峰值，报告里有完整的来源拆解和解释。

**但"只做汉化"这个计划有两处冲突：**

1. 「汉化」其实是**两个完全不同的问题**，其中一个不是汉化而是核心功能修复
2. GGS 的许可是 **All Rights Reserved**，**汉化后发布 = 明确违反许可**

详见第九、十节。**先跑待办清单的 B-4，再决定做什么。**

---

## 一、它是什么

一句话：**把其他玩家的「历史最大金币」与游戏自己记录的「金币收入计数器」对比，看这堆数字对不对得上。**

- 进得去的：成就统计系统里的公开计数器
- 进不去的：他人的**当前**金币（`GetMoney()` 只对自己，暴雪零容忍）
- 它**不判断**"这人是不是 RMT"，只判断"这些数字自不自洽"

---

## 二、核心数据模型：5 个必需 + 5 个辅助

从 `Core.lua` 第 53–55 行：

```lua
ID_KEYS      = { "peak", "total", "loot", "quest", "vendor", "ah", "posted", "bought", "quests", "kills" }
MONEY_KEYS   = { peak, total, loot, quest, vendor, ah }     -- 这六个按货币解析
REQUIRED_KEYS= { "peak", "loot", "quest", "vendor", "ah" }  -- 这五个缺一个就无法判定
```

| 键 | 含义 | 角色 |
|---|---|---|
| `peak` | **历史最大金币** | 基准 |
| `total` | 累计获得金币 | 参考 |
| `loot` | 拾取金币 | 收入项 |
| `quest` | 任务奖励金币 | 收入项 |
| `vendor` | 卖店收入 | 收入项 |
| `ah` | 拍卖行收入 | 收入项 |
| `posted` / `bought` | 拍卖行挂单数 / 购买数 | 仓库号判据 |
| `quests` / `kills` | 完成任务数 / 击杀数 | "真实游玩"的旁证 |

另可选读约 80 条其他计数器（死亡、副本、伤害、专业高水位、坐骑宠物……），只用于展示，不参与判定。

**核心等式**：

```
explained = loot + quest + vendor + ah          -- 能解释的收入
gap       = max(0, peak - explained)            -- 解释不了的部分
coverage  = explained / max(peak, 1)            -- 收入覆盖率
slack     = max(5000, peak × 10%)               -- 容差
```

---

## 三、悬停鼠标时到底显示什么

`Tooltip.lua` 第 31–38 行，注释写着 "Two facts only"：

```
GGS    <判定词>
Peak   <金币>
```

**就两行，没有第三行，按住 Shift 也不会展开**（代码注释：`Extra arguments (including the old Shift flag) intentionally add no detail`）。

八个判定词（`Score.lua` 第 22–31 行）：

| 判定词 | 中文 | 颜色 |
|---|---|---|
| `Scanning...` | 扫描中 | 灰 |
| `Too far` | 太远 | 灰 |
| `Identity hidden` | 身份被隐藏 | 灰 |
| `Too little data` | 数据太少 | 金 |
| `Empty history, large peak` | 历史空白但峰值巨大 | 红 |
| `Bank-shaped` | 仓库号形态 | 蓝 |
| `Unexplained peak` | 无法解释的峰值 | 橙 |
| `Explained` | 可解释 | 绿 |

扫描失败时的提示语也是硬编码的，例如 `No answer from the client. Hover again to retry.`、`Leave combat, then hover again to retry.`

> ⚠️ **注意**：`Score.DISCLAIMER = "Unexplained is not proof of RMT"`（第 33 行）**定义了但不出现在悬停提示框里**，只在完整报告里。所以两行的 tooltip 可能被误读成"这人是 RMT"。**这是一个可以改进的点。**

---

## 四、判定逻辑（完整规则 + 默认阈值）

`Score.lua` 第 65–108 行，**按顺序判断，命中即停**：

| 顺序 | 判定 | 条件（默认值） |
|---|---|---|
| 1 | **Too little data** | 五个必需项（peak/loot/quest/vendor/ah）**缺任意一个**；或 峰值 < 1 金 且 任务+击杀 < 20 |
| 2 | **Empty history, large peak** | 等级 ≤ 5 且（峰值 ≥ 20 金 **或** 交易中被给出的金币 ≥ 10 金） |
| 3 | **Bank-shaped** | posted+bought ≥ 200 **且** 击杀 < 50 **且** 任务 < 30 |
| 4 | **Unexplained peak** | gap ≥ 10 金 **且** 覆盖率 ≤ 60% |
| 5 | **Explained** | gap ≤ 容差（峰值 10% 或 50 银，取大）；**或** 峰值 ≤ 等级 × 50 银 |
| 6 | 否则 | **Unexplained peak** |

默认阈值全表（`Core.lua` 第 23–51 行）：

```lua
mouseover        = true      -- ⚠️ 悬停扫描【默认开】
retainAll        = true      -- ⚠️ 保留全部扫描过的角色【默认开】
autoInspect      = false     -- Inspect 自动出报告（默认关，比 IRS 保守的一处）
encounterLog     = false     -- 第一手交易/邮件日志（默认关）
slackPct         = 0.10      -- 容差 = 峰值的 10%
slackMin         = 5000      -- 容差下限 50 银
gapGold          = 100000    -- 差额门槛 10 金
gapCover         = 0.60      -- 覆盖率门槛 60%
freshLevel       = 5         -- "新号"等级上限
freshGold        = 200000    -- "新号可疑峰值" 20 金
freshOffer       = 100000    -- 交易中给出 10 金即触发
bankPosts        = 200       -- 仓库号：挂单+购买
bankKills        = 50        -- 仓库号：击杀少于此
bankQuests       = 30        -- 仓库号：任务少于此
trivialPerLevel  = 5000      -- 每级 50 银以下视为无意义峰值
originMin        = 10000     -- 观测财富小于 1 金不做来源对比
jumpGold         = 500000    -- 两次快照间 50 金以上的无法解释上升
jumpShare        = 0.5       -- 且占该次上升的一半以上
peerMin          = 3         -- 等级对比所需的最少样本
cacheMin         = 10        -- 缓存新鲜度（分钟）
cacheCap         = 400       -- 缓存上限（retainAll=true 时不生效）
```

**这些设定给你的三个判断**：

- 判定**相当宽松**——10 金的差额门槛、60% 的覆盖率门槛，意味着小额异常不会触发
- **`Too little data` 会非常常见**——只要拍卖行计数器在客户端上不返回（README 说低等级角色常常如此），就永远停在"数据太少"
- **`Bank-shaped` 是个聪明的设计**——它绕开了"金币多就是坏人"的陷阱，改为识别"拍卖行重度使用 + 几乎不战斗"这个仓库号特征

---

## 五、报告里有什么（六个标签页）

左键点小地图按钮，或 `/ggs player`／`/ggs me` 打开：

| 标签页 | 内容 |
|---|---|
| **Report** | 头条判定、评分、置信度、收入覆盖率条、首要理由 |
| **Origin** | 金币来源七分类（见下节） |
| **Activity** | 七个活动领域的正向活动与计数器覆盖度（与财富无关） |
| **Statistics** | 客户端返回的**全部公开统计量**，按游戏自己的分类，带搜索框 |
| **History** | 该角色的历史快照（每角色保留 20 份），两次快照间的变化 |
| **Players** | 可搜索的本地目录，可按峰值/收入/等级/判定排序 |

**可复制为纯文本**（`/ggs copy`），包含统计量、原始采集时间、最近历史；**复制自己时会带钱包**。复制内容包含对方身份信息，分享前需自行检查。**不包含**私有发票总额和第一手日志，也**不会自动发送任何东西**。

---

## 六、金币来源七分类

| 分类 | 置信度 | 怎么来的 |
|---|---|---|
| 任务 | 高 | 直接游戏计数器 |
| 拾取金币 | 高 | 直接游戏计数器 |
| 卖店 | 高 | 直接游戏计数器 |
| 拍卖行 | **低** | 公开计数器不完整；只有自己的报告在有 Grimlight Auctions 佐证时才升为中 |
| 邮件与交易 | —— | **只来自你自己的第一手日志**（默认关） |
| 专业 | —— | 没有独立计数器，产物最终计入卖店或拍卖行 |
| 其他 | —— | 总获得减去已分项，**只显示，永不计数** |

覆盖率条会给出例如 `About 82% of observed wealth is explained by recorded income`；数据不全时会说 `About 92% explained (partial: auction income not reported)` 并降置信度。

**观测财富**定义为 `max(peak, 已记录支出 + 你自己的钱包)`。

---

## 七、一致性评分（报告内的 0–100，与 tooltip 判定是两套）

| 因素 | 权重 | 规则 |
|---|---|---|
| 收入覆盖率 | 35 | ≤30% 得 0，≥90% 得 100 |
| 无法解释的上升 | 20 | 无 = 100；有则 ≤60，越大越低 |
| 同等级财富对比 | 15 | 与至少 3 名±5级内玩家的中位数比：≤2倍 = 100，≥10倍 = 0 |
| 活动度 | 20 | 七个活动领域命中 ≥4 = 100 |
| 第一手证据 | 10 | 仅来自你自己的日志 |

判定档位：**≥80 Adds up** / **60–79 Mostly adds up** / **40–59 Needs a closer look** / **<40 Doesn't add up** / **Not enough data**（覆盖率不可测，或加权因素不足一半有数据）。

缺数据的因素被剔除，改为**降低置信度**而不是当成 0。

---

## 八、汉化评估

### ⚠️ 先分清两个完全不同的问题

| | (a) UI 文本汉化 | (b) 统计量名称匹配 |
|---|---|---|
| 是什么 | 把界面上的英文改成中文 | 让插件能在中文客户端上**认得出**统计量 |
| 影响 | **纯外观**。不做也能用，只是界面是英文 | **功能存亡**。匹配不上则所有数值为空，插件完全空转 |
| 工作量 | 大而琐碎 | 小而关键 |
| 要动哪 | 全部 18 个文件的字符串 | 主要 `Stats.lua` 的 `MATCH` 表（第 22–43 行）+ 可选表（47–126 行） |

### (b) 才是关键，而它根本不是「汉化」

`Stats.MATCH` 表里全是**英文字符串**：

```lua
{ key = "peak", exact = { "most gold ever owned", "maximum gold held", ... },
  contains = { "most gold", "maximum gold", "highest gold" } },
{ key = "loot", exact = { "gold looted", ... }, contains = { "loot" } },
...
```

**若国服客户端返回中文统计量名，这些全部匹配不上**，插件会打印
`wealth statistics not found on this build`，所有数值为空。

作者在注释里明说了预期的处理方式：

> `Extend this table from /ggs names; never guess IDs.`
> （用 `/ggs names` 扩展这张表；不要猜 ID）

**但"扩展"意味着改 `Stats.lua` 的源码。** 这不是翻译，是补一层数据映射。

### (a) 的工作量

全插件 7214 个引号对（≈3600 个字符串字面量），但其中大量是纹理路径、颜色值、API 名、框架名，**不是用户可见文案**。真正的界面文案估计在 **300–600 条**，散在 18 个文件里（最多的是 `Details.lua` 941 个引号、`Catalog.lua` 431 个、`PanelTools.lua` 325 个）。

**而且它没有任何本地化基础设施**：无 `Locale.lua`，无 `gettext`，无 `L[]` 查表（已 grep 确认）。所有字符串硬编码。要做干净的话得**先加一层 i18n**，那本身就是一次改造。

### 顺序建议

**先跑 B-4（`/ggs ids` + `/ggs names`）**：

- 若 (b) 不存在问题（中文客户端居然返回英文名 / 或返回的名字能匹配上）→ **连汉化都不必做**，直接用
- 若 (b) 存在 → 你要做的是**核心功能修复**，(a) 才是可选的锦上添花

**别把主次搞反。**

---

## 九、许可：汉化后发布是明确违反

GGS 的许可原文（`LICENSE` 文件）：

> All Rights Reserved. Copyright (c) 2026 Veruca Grimlight.
> Original Grimlight Gold Scanner source and product text are All Rights Reserved.
> Downloads are free and source is readable. **No permission to redistribute, modify for redistribution, sublicense or sell** these contributions is granted.

| 你想做的事 | 是否允许 |
|---|---|
| 读源码 | ✅ |
| 改了自己用（含汉化） | ⚠️ 灰色。不改发布，实务上无事 |
| **汉化后发布** | ❌ **明确违反**（"modify for redistribution"） |
| 摘代码进自己的发布版 | ❌ |

**三条干净路径**：

1. **联系作者请求授权。**站点（grimlightdepot.com）有 Discord。插件作者通常欢迎本地化贡献——这是社区常态
2. **把汉化贡献回上游**，让作者合并进官方版本。**这是最优解**：你不发布衍生版，玩家用官方版就有中文
3. 若前两条都不通，且你坚持要发布自己的版本 → **只能从零写**。那样工作量远大于"汉化"，但许可干净、发布自由

---

## 十、一句话总结

GGS 在功能上**达到了你的预期**（悬停给判定、报告给来源拆解），而且判定逻辑比我预想的稳健（`Bank-shaped` 那条尤其聪明）。

但「只做汉化就行了」这个计划要修正为：

> **先确认统计量能不能匹配上（B-4）。能匹配 → 什么都不用做。不能匹配 → 你要做的是功能修复，不是汉化。不论哪种情况，想发布就得先拿到作者授权，或者自己从零写。**
