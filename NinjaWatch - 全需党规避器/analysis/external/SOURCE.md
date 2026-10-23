# 外部数据源说明

## 文件

- 文件名：`achievement.csv`
- 大小：252,634 字节
- 行数：1,770 行（含 1 行表头，1,769 条数据）
- SHA-256：`a29d188b2090f10a2f4c420e36c66d064114a04a0d7bed8c0b77fa1996d530c1`
- 获取日期：2026-10-21
- 来源：**wago.tools** 的 Achievement DB2 表 CSV 导出（`https://wago.tools/db2/Achievement`）
- 性质：公开游戏数据（成就/统计定义），不含玩家数据。

## 为什么需要它

- 把统计 ID 映射到可读名称，确认：
  - `1103` = Lich King 5-player dungeons completed（5 人副本完成）
  - `1467` = Lich King 5-player bosses defeated（5 人首领击杀）
  - `1045` = Total cheers（不是 Pass）
  - `4456`/`4556` = 随机普通/英雄 5 人副本完成
  - `1760`/`1770` = 25/10 人首领击杀
- 用于 `map_ids.py` 的映射输出；插件运行时不依赖此 CSV。

## 字段（本档案用到的）

| 字段 | 用途 |
|---|---|
| `ID` | 统计/成就 ID |
| `Title_lang` | 标题 |
| `Description_lang` | 描述 |
| `Category` | 分类；5 人副本相关多在 `14807` |
| `Flags` | 标志位，仅记录，不解释 |
| `Supercedes` | 被替代关系；与“GGS 可能漏 hidden/superceded”有关 |

## 已知限制

1. **不是运行时统计表**：这是成就 DB2 导出，不是客户端 `GetStatistic` 的完整名单；`1043`/`1044` 不在 CSV 中（可能是统计 ID 而非成就条目，或该导出不含）。
2. **构建相关**：DB2 随客户端版本变化；本文件是 2026-10-21 的快照，未记录具体 build 号。换版本后 ID 可能增删，需重新导出。
3. **名称是英文**：中文名以客户端为准；本档案只用英文名做识别。
4. **不能证明可读性**：表里有 ID ≠ 客户端对他人可读；仍须游戏内探针（T-001）。

## 刷新方法

1. 打开 `https://wago.tools/db2/Achievement`，选择与目标客户端一致的 build。
2. 导出 CSV，覆盖本目录的 `achievement.csv`（保持文件名）。
3. 重新运行：
   ```bash
   cd "D:/Users/MLTZ/Desktop/Addons of WoW/NinjaWatch - 全需党规避器/analysis"
   py -3 -I map_ids.py > outputs/id_map.txt
   ```
4. 更新本文件的日期、大小、行数、SHA-256。

## 使用边界

- 只读参考；不把 CSV 内容硬编码进插件作为判定依据。
- 不把 CSV 与玩家数据合并输出。
- 公开数据，但仍注明来源与快照日期，避免把旧 build 的名称当永久事实。
