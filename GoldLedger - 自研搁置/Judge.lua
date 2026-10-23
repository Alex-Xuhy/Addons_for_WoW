-- 金账簿 - Judge.lua
-- 判定引擎。
--
-- ⚠️ 这里的阈值全部来自 Config.DEFAULTS，是【起点，不是定论】。
--    请用自己的角色标定：跑 /gl me 扫你自己所有的号，看覆盖率分布，
--    再把阈值调到「能区分出你自己仓库号」的位置。
--
-- 判定词只描述【数字】，不描述【人】。改这里的时候别破坏这条约束。

local ADDON_NAME, GL = ...
local Judge = {}
GL.Judge = Judge
local S = GL.Secrets
local Stats = GL.Stats

local floor, max = math.floor, math.max

-- 判定优先级：命中即停
function Judge.Evaluate(row, offer)
    if type(row) ~= "table" then return nil end
    local C = GL.Config.Get

    local peak = S.Number(row.peak)
    local loot = S.Number(row.loot)
    local questGold = S.Number(row.questGold)
    local vendor = S.Number(row.vendor)
    local ahGold = S.Number(row.ahGold)

    -- 五个必需项齐了才算"完整"，缺一个就只能说"数据太少"
    local complete = peak and loot and questGold and vendor and ahGold

    local explained, gap, coverage
    if complete then
        explained = loot + questGold + vendor + ahGold
        if explained > Stats.MAX_INTEGER then
            complete, explained = false, nil
        else
            gap = max(0, peak - explained)
            coverage = explained / max(peak, 1)
        end
    end

    local slack = peak and max(tonumber(C("slackMin")) or 0,
                               floor(peak * (tonumber(C("slackPct")) or 0))) or 0
    local quests = row.quests or 0
    local kills = row.kills or 0
    local posts = (row.posted or 0) + (row.bought or 0)
    local level = tonumber(row.level)
    offer = tonumber(offer) or 0

    local verdict
    if not complete or (peak and peak < 10000 and quests + kills < 20) then
        verdict = "THIN"
    elseif (level and level <= (C("freshLevel") or 5)
            and (peak or 0) >= (C("freshGold") or 200000))
        or offer >= (C("freshOffer") or 100000) then
        verdict = "FRESH"
    elseif S.Number(row.kills) and S.Number(row.quests)
        and S.Number(row.posted) and S.Number(row.bought)
        and posts >= (C("bankPosts") or 200)
        and kills < (C("bankKills") or 50)
        and quests < (C("bankQuests") or 30) then
        verdict = "BANK"
    elseif complete and gap >= (C("gapGold") or 100000)
        and coverage <= (C("gapCover") or 0.60) then
        verdict = "GAP"
    elseif complete and (gap <= slack
        or (level and peak <= level * (C("trivialPerLevel") or 5000))) then
        verdict = "CLEAN"
    elseif complete then
        verdict = "GAP"
    else
        verdict = "THIN"
    end

    row.explained = explained
    row.gap = gap
    row.coverage = coverage
    row.slack = slack
    row.complete = complete
    row.verdict = verdict
    return row
end

-- 判定词（带颜色）。颜色含义见 Locale 里的注释。
local COLORS = {
    PENDING = "9AA0A6", FAR = "9AA0A6", HIDDEN = "9AA0A6",
    THIN = "C9A227", FRESH = "C0392B", BANK = "2E86AB",
    GAP = "D35400", CLEAN = "1F6B3A",
}

function Judge.Word(verdict)
    return GL.L.VERDICT[verdict] or GL.L.VERDICT.THIN
end

function Judge.Color(verdict)
    return COLORS[verdict] or "9AA0A6"
end

function Judge.Colored(verdict, text)
    return "|cff" .. Judge.Color(verdict) .. (text or Judge.Word(verdict)) .. "|r"
end

-- 给出判定的理由，用于报告和 tooltip
function Judge.Reason(row)
    if not row or not row.verdict then return nil end
    local v = row.verdict
    if v == "GAP" and row.gap and row.peak then
        local pct = row.coverage and floor(row.coverage * 100 + 0.5) or nil
        if pct then
            return string.format("记录到的收入只能解释峰值的 %d%%。", pct)
        end
    elseif v == "BANK" then
        local posts = (row.posted or 0) + (row.bought or 0)
        return string.format("拍卖行 %d 次，击杀 %d，任务 %d。",
            posts, row.kills or 0, row.quests or 0)
    elseif v == "FRESH" and row.peak then
        return string.format("等级 %d，峰值 %s。",
            row.level or 0, GL.Stats.FormatMoney(row.peak))
    elseif v == "THIN" then
        local missing = {}
        for _, key in ipairs(Stats.REQUIRED) do
            if not row[Stats.FIELD[key]] then
                missing[#missing + 1] = Stats.LABEL[key]
            end
        end
        if #missing > 0 then
            return "缺：" .. table.concat(missing, "、")
        end
    end
    return GL.L.VERDICT_DESC[v]
end
