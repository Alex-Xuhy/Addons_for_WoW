-- Grimlight Gold Scanner v0.11.4 - optional zhCN additions (19 entries)
-- Translation by Arclight_Huguang, 2026-10-20; reviewed and final.
-- For review and manual integration into Locale_zhCN.lua, or as an optional
-- file loaded after Locales.lua / Locale_zhCN.lua (it merges these keys only).
-- This is NOT a replacement for Locale_zhCN.lua and keeps the other 621 entries.
-- Placeholders keep the same order as the English keys.
local GGS = GGS
if GGS.locale ~= "zhCN" then return end
local strings = {
    ["%.1f%% of %s rolls"] = "%.1f%%（共 %s 次掷骰）",
    ["%s recorded Need/Greed rolls; share is shown from %d rolls."] = "已记录 %s 次需求/贪婪掷骰；合计达到 %d 次后显示占比。",
    ["A gap cannot be determined while income counters are missing."] = "收入计数器缺失时，无法确定缺口。",
    ["Activity scoring is unavailable: missing counters could change the number of recorded areas."] = "活动评分不可用：缺失的计数器可能改变已记录区域的数量。",
    ["Both Need and Greed counters must be readable; missing counts are not zero."] = "需求与贪婪计数器都必须可读；缺失的计数不是零。",
    ["Dealings remain in your private log; incomplete income prevents a scoring comparison."] = "往来仍保留在你的第一手日志中；收入不完整，无法进行评分对比。",
    ["Income coverage is excluded from scoring: income counters are missing or cannot be compared reliably."] = "收入覆盖率不计入评分：收入计数器缺失，或无法可靠比较。",
    ["Income coverage must also be comparable before a consistency verdict is shown."] = "收入覆盖率也必须可比较，才会显示一致性判定。",
    ["Incomplete data"] = "数据不完整",
    ["Loot rolls"] = "战利品掷骰",
    ["Need share"] = "需求次数占比",
    ["Need share is Need / (Need + Greed), shown after at least %d recorded rolls. It does not show whether an item was an upgrade or which loot rules the group agreed to. No score uses this share."] = "需求次数占比 = 需求掷骰 /（需求掷骰 + 贪婪掷骰），至少记录到 %d 次掷骰后显示。它不能说明某件物品是否为升级，也不能说明队伍约定的拾取规则。任何评分都不使用此占比。",
    ["Need share: %s"] = "需求次数占比：%s",
    ["Not comparable"] = "不可比较",
    ["Not established"] = "未确定",
    ["Partial: %s. The percentage describes readable amounts only; missing income cannot establish a gap."] = "部分：%s。该百分比只描述可读金额；缺失的收入无法确定缺口。",
    ["Recording period"] = "记录时段",
    ["Spending coverage is incomplete. Only reported amounts are included; missing spending is unknown."] = "支出覆盖率不完整。仅计入已上报的金额；缺失的支出视为未知。",
    ["The combined roll count is too large to compare reliably."] = "合计掷骰次数过大，无法可靠比较。",
}
GGS.RegisterLocale("zhCN", strings, "Arclight_Huguang")
