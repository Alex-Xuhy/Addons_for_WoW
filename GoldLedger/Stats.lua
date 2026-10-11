-- 金账簿 - Stats.lua
-- 统计量发现、名称解析、货币/计数解析。
--
-- 两条铁律：
--   1. 靠【名称】发现 ID，绝不硬编码、绝不猜测。下面的 KNOWN 只是快路径，
--      用之前必须先拿 GetAchievementInfo 核对名字对不对。
--   2. 每一次读取都过 pcall + 机密值校验。解析不出来返回 nil，【绝不返回 0】。
--      0 会污染后面所有的差额与覆盖率计算。

local ADDON_NAME, GL = ...
local Stats = {}
GL.Stats = Stats
local S = GL.Secrets

--------------------------------------------------------------------
-- 十个 key
--------------------------------------------------------------------

Stats.ALL_KEYS    = { "peak", "total", "loot", "quest", "vendor", "ah",
                      "posted", "bought", "quests", "kills" }
Stats.MONEY_KEYS  = { peak = true, total = true, loot = true,
                      quest = true, vendor = true, ah = true }
Stats.REQUIRED    = { "peak", "loot", "quest", "vendor", "ah" }

Stats.FIELD = {
    peak = "peak", total = "total", loot = "loot", quest = "questGold",
    vendor = "vendor", ah = "ahGold", posted = "posted", bought = "bought",
    quests = "quests", kills = "kills",
}

Stats.LABEL = {
    peak = "历史最大金币", total = "累计获得金币", loot = "拾取金币",
    quest = "任务奖励金币", vendor = "卖店收入", ah = "拍卖行收入",
    posted = "拍卖行挂单数", bought = "拍卖行购买数",
    quests = "完成任务数", kills = "击杀数",
}

--------------------------------------------------------------------
-- 名称表
--
-- 中文名来自「无限图鉴」(wuxianwow.com)，取自国服 Beta 客户端 1.60.1.70338
-- 的成就统计数据。英文名是同一批统计量的英文版，用于兼容英文客户端。
--
-- ⚠️ 实机请用 /gl names 复核一遍：名字对不上就用 /gl set 手动绑。
--------------------------------------------------------------------

Stats.RESOLVE = {
    { key = "peak", names = {
        "最大金币数量", "most gold ever owned", "maximum gold held", "highest gold ever owned" } },
    { key = "total", names = {
        "获得的金币总量", "total gold acquired", "total gold received", "total gold earned" } },
    { key = "loot", names = {
        "拾取金币", "gold looted", "gold looted from corpses", "total gold looted" } },
    { key = "quest", names = {
        "通过任务奖励所得金币", "gold from quest rewards", "gold from quests" } },
    { key = "vendor", names = {
        "向商人出售物品所得金币", "gold from vendors" } },
    { key = "ah", names = {
        "通过拍卖行所得金币", "gold earned from auctions", "gold from auction house" } },
    { key = "posted", names = {
        "在拍卖行出售物品", "auctions posted", "auctions listed" } },
    { key = "bought", names = {
        "在拍卖行购买物品", "auction purchases", "auctions purchased" } },
    { key = "quests", names = {
        "完成任务", "quests completed" } },
    { key = "kills", names = {
        "世界消灭总数", "creatures killed", "total creatures killed", "total kills" } },
}

-- 子串匹配用的关键词（精确名匹配失败时才用）
Stats.CONTAINS = {
    peak   = { "最大金币", "most gold", "maximum gold", "highest gold" },
    total  = { "金币总量", "total gold" },
    loot   = { "拾取金币", "gold looted" },
    quest  = { "任务奖励", "quest reward" },
    vendor = { "商人出售", "向商人", "vendor" },
    ah     = { "拍卖行所得", "auction house", "earned from auctions" },
    posted = { "出售物品", "auctions posted", "listed" },
    bought = { "购买物品", "auction purchases", "purchased" },
    quests = { "完成任务" },
    kills  = { "消灭总数", "creatures killed" },
}

-- 子串匹配绝不能接受的词（防止把"花费/最高价/平均值/死亡"当成收入）
Stats.EXCLUDE = {
    "花费", "最高价格", "最高价", "平均", "每日", "死亡",
    "spent", "most expensive", "highest auction", "average", "daily", "death",
}

-- 快路径：来自无限图鉴的已知 ID。用之前必须核对名字。
Stats.KNOWN = {
    peak = 334, total = 328, loot = 333, quest = 326, vendor = 921, ah = 919,
    posted = 329, bought = 330, quests = 98, kills = 1488,
}

Stats.MAX_INTEGER = 9007199254740991

--------------------------------------------------------------------
-- 发现：走一遍客户端的所有统计量
--------------------------------------------------------------------

function Stats.HasDiscoveryAPI()
    return type(GetStatisticsCategoryList) == "function"
        and type(GetCategoryNumAchievements) == "function"
        and type(GetAchievementInfo) == "function"
end

-- 返回 entries, 错误原因。entries = { { id=, name=, cat= }, ... }
function Stats.Discover()
    local entries, seen = {}, {}
    if not Stats.HasDiscoveryAPI() then return entries, "noapi" end

    local okCats, cats = pcall(GetStatisticsCategoryList)
    if not okCats then return entries, "nocats" end
    cats = S.Table(cats)
    if not cats then return entries, "nocats" end

    -- 分类表可能有空洞，用 pairs 遍历，ID 全靠发现
    local list = {}
    for idx, cat in pairs(cats) do
        local i = S.Int(idx)
        local c = S.Int(cat)
        if i and c then list[#list + 1] = { i = i, c = c } end
    end
    table.sort(list, function(a, b) return a.i < b.i end)

    for _, item in ipairs(list) do
        local okN, count = pcall(GetCategoryNumAchievements, item.c)
        if not okN then
            -- 无限的用法字符串里这个函数带第二个参数
            okN, count = pcall(GetCategoryNumAchievements, item.c, true)
        end
        count = S.Int(count)
        if okN and count and count > 0 and count <= 10000 then
            for n = 1, count do
                local id, name
                -- 新式：GetStatistic(cat, index) 的第 3 个返回值是统计量 ID
                if type(GetStatistic) == "function" then
                    local okS, _, _, sid = pcall(GetStatistic, item.c, n)
                    local sidVal = S.Int(sid)
                    if okS and sidVal and sidVal > 0 then
                        local okI, rid, label = pcall(GetAchievementInfo, sidVal)
                        if okI and S.Int(rid) == sidVal then
                            id, name = sidVal, S.Text(label)
                        end
                    end
                end
                -- 旧式：GetAchievementInfo(cat, index)
                if not id then
                    local okI, rid, label = pcall(GetAchievementInfo, item.c, n)
                    if okI then
                        id, name = S.Int(rid), S.Text(label)
                    end
                end
                if id and id > 0 and name and #name <= 300 and not seen[id] then
                    seen[id] = true
                    entries[#entries + 1] = { id = id, name = name, cat = item.c }
                end
            end
        end
    end

    Stats.entries = entries
    return entries
end

--------------------------------------------------------------------
-- 解析：名称 -> key
--------------------------------------------------------------------

local function lower(s) return (s:gsub("[A-Z]", string.lower)) end

local function acceptable(key, lowerName)
    for _, bad in ipairs(Stats.EXCLUDE) do
        if lowerName:find(bad, 1, true) then return false end
    end
    for _, part in ipairs(Stats.CONTAINS[key] or {}) do
        if lowerName:find(lower(part), 1, true) then return true end
    end
    return false
end

-- 建索引：key -> 名称列表
Stats.RESOLVE_INDEX = {}
for _, rule in ipairs(Stats.RESOLVE) do
    Stats.RESOLVE_INDEX[rule.key] = rule.names
end

-- 返回识别出的数量。已手动绑定的 key 永不被覆盖。
function Stats.Resolve(quiet)
    local db = GL.Config.DB()
    if not db then return 0 end
    local ids = db.ids
    local entries = Stats.Discover()
    local used, count = {}, 0

    -- 先把已经手动绑好的记下来，标记为已占用
    for key, id in pairs(ids) do
        if type(id) == "number" then used[id] = true; count = count + 1 end
    end

    -- 第 1 遍：快路径 + 精确名匹配
    for _, rule in ipairs(Stats.RESOLVE) do
        local key = rule.key
        if not ids[key] then
            -- 1a. 已知 ID 快路径（先核对名字）
            local known = Stats.KNOWN[key]
            if known and not used[known] then
                local okI, rid, label = pcall(GetAchievementInfo, known)
                local nm = okI and S.Text(label)
                if nm then
                    for _, want in ipairs(rule.names) do
                        if lower(nm) == lower(want) then
                            ids[key], db.idNames[key], used[known] = known, nm, true
                            count = count + 1
                            break
                        end
                    end
                end
            end
            -- 1b. 精确名匹配
            if not ids[key] then
                local found, ambiguous
                for _, entry in ipairs(entries) do
                    if not used[entry.id] then
                        for _, want in ipairs(rule.names) do
                            if lower(entry.name) == lower(want) then
                                if found then ambiguous = true end
                                found = entry
                                break
                            end
                        end
                    end
                end
                if found and not ambiguous then
                    ids[key], db.idNames[key], used[found.id] = found.id, found.name, true
                    count = count + 1
                end
            end
        end
    end

    -- 第 2 遍：子串匹配
    for _, rule in ipairs(Stats.RESOLVE) do
        local key = rule.key
        if not ids[key] then
            local found, ambiguous
            for _, entry in ipairs(entries) do
                if not used[entry.id] and acceptable(key, lower(entry.name)) then
                    if found then ambiguous = true end
                    found = entry
                end
            end
            if found and not ambiguous then
                ids[key], db.idNames[key], used[found.id] = found.id, found.name, true
                count = count + 1
            end
        end
    end

    if not quiet and count == 0 then GL.Print(GL.L.CMD.NO_IDS) end
    return count
end

function Stats.Missing()
    local db = GL.Config.DB()
    local missing = {}
    if not db then return missing end
    for _, key in ipairs(Stats.REQUIRED) do
        if not db.ids[key] then missing[#missing + 1] = key end
    end
    return missing
end

--------------------------------------------------------------------
-- 解析：值 -> 数字
-- 【铁律】解析不出来返回 nil，绝不返回 0
--------------------------------------------------------------------

-- 货币单位分两张表：中文是多字节，不能用 %a 匹配，直接做前缀比较
local COIN_UNITS_CN = { ["金"] = 10000, ["银"] = 100, ["铜"] = 1 }
local COIN_UNITS_EN = { gold = 10000, g = 10000, silver = 100, s = 100, copper = 1, c = 1 }

-- 客户端千位分隔符探测（不假定是逗号）
local probedFn, probedSep = nil, nil
local function groupingSeparator()
    local fn = BreakUpLargeNumbers
    if probedFn ~= fn then
        probedFn, probedSep = fn, nil
        if type(fn) == "function" then
            local ok, sample = pcall(fn, 1234567)
            if ok and type(sample) == "string" then
                for _, sep in ipairs({ ".", " ", "\194\160", "\226\128\175" }) do
                    if sample == "1" .. sep .. "234" .. sep .. "567" then
                        probedSep = sep
                        break
                    end
                end
            end
        end
    end
    return probedSep
end

local function stripMarkup(text)
    if type(text) ~= "string" or #text > 512 then return nil end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    -- 金币图标纹理 -> 单位字
    text = text:gsub("|T([^|]+)|t", function(path)
        local coin = path:match("^[Ii]nterface\\[Mm]oney[Ff]rame\\[Uu][Ii]%-(%a+)[Ii]con:")
            or path:match("^[Ii]nterface/[Mm]oney[Ff]rame/[Uu][Ii]%-(%a+)[Ii]con:")
        if not coin then return "|" end
        local c = coin:lower()
        if c == "gold" then return "金" end
        if c == "silver" then return "银" end
        if c == "copper" then return "铜" end
        return "|"
    end)
    text = text:gsub("|A([^|]+)|a", function(atlas)
        local coin = atlas:match("^:?coin%-(%a+):")
        if not coin then return "|" end
        local c = coin:lower()
        if c == "gold" then return "金" end
        if c == "silver" then return "银" end
        if c == "copper" then return "铜" end
        return "|"
    end)
    if text:find("|", 1, true) then return nil end   -- 还有不认识的标记
    return GL.Core.trim(text)
end

-- 纯数字串 -> 整数（处理千位分隔符）
local function toInteger(text)
    if type(text) ~= "string" then return nil end
    local sep = groupingSeparator()
    if sep and sep ~= "" and sep ~= "," then
        if text:find(",", 1, true) then return nil end
        local esc = sep:gsub("(%W)", "%%%1")
        text = text:gsub(esc, ",")
    end
    if not text:match("^[%d,]+$") then return nil end
    if text:find(",", 1, true) then
        local head, tail = text:match("^(%d+)(,.*)$")
        if not head or #head > 3 then return nil end
        while #tail > 0 do
            local group, rest = tail:match("^,(%d%d%d)(.*)$")
            if not group then return nil end
            tail = rest
        end
    end
    local n = tonumber((text:gsub(",", "")))
    if not n or n < 0 or n ~= math.floor(n) or n > Stats.MAX_INTEGER then return nil end
    return n
end

-- 金额：支持 "1,234金 56银 78铜" / "1234g56s78c" / 图标标记 / 纯数字（按铜算）
--
-- ⚠️ Lua 5.1 的 string.match / string.find 没有起始位置参数（那是 5.2 才加的），
--    所以这里用「不断截短剩余子串」的方式推进游标，不要写成 text:match(pat, pos)。
function Stats.ParseMoney(value)
    if S.IsSecret(value) then return nil end
    if type(value) == "number" then return S.Int(value) end
    local text = stripMarkup(value)
    if not text or text == "" then return nil end

    -- 整串都是数字：没有单位词，一律按铜处理
    if text:match("^[%d,%.%s]+$") then
        return toInteger((text:gsub("[%.,%s\194\160]", "")))
    end

    local total, last, found = 0, nil, false
    local rest = text
    while #rest > 0 do
        rest = rest:gsub("^[%s,\194\160，]+", "")   -- 跳过前导空白与分隔符
        if rest == "" then break end

        local numStr = rest:match("^[%d,]+")
        if not numStr then break end
        rest = rest:sub(#numStr + 1)

        local amount = toInteger(numStr)
        if not amount then return nil end

        -- 单位：先试中文（多字节前缀比较），再试英文
        local weight, consumed
        for unit, w in pairs(COIN_UNITS_CN) do
            if rest:sub(1, #unit) == unit then
                weight, consumed = w, #unit
                break
            end
        end
        if not weight then
            local word = rest:match("^[%a]+")
            if word then weight, consumed = COIN_UNITS_EN[word:lower()], #word end
        end
        if not weight then return nil end
        if last and weight >= last then return nil end   -- 单位必须递减：金→银→铜

        total = total + amount * weight
        if total > Stats.MAX_INTEGER then return nil end
        found, last = true, weight
        rest = rest:sub(consumed + 1)
    end
    if not found then return nil end
    return total
end

-- 计数：纯数字
function Stats.ParseCount(value)
    if S.IsSecret(value) then return nil end
    if type(value) == "number" then return S.Int(value) end
    local text = stripMarkup(value)
    if not text then return nil end
    return toInteger((text:gsub("[%s]", "")))
end

--------------------------------------------------------------------
-- 读取
--------------------------------------------------------------------

-- getter: GetStatistic（自己）或 GetComparisonStatistic（他人）
-- 返回 row，每个 key 都有值或 nil，quality 记录取不到的原因
function Stats.ReadRow(getter)
    local db = GL.Config.DB()
    local row = { quality = {}, raw = {}, build = GL.Core.Build(), src = 1 }

    if not db then return row end

    for _, key in ipairs(Stats.ALL_KEYS) do
        local id = db.ids[key]
        if not id then
            row.quality[key] = "unresolved"
        elseif type(getter) ~= "function" then
            row.quality[key] = "noapi"
        else
            local ok, text, skip = pcall(getter, id)
            if not ok then
                row.quality[key] = "error"
            elseif S.IsSecret(text) or S.IsSecret(skip) then
                row.quality[key] = "restricted"
            elseif skip then
                row.quality[key] = "skipped"
            else
                local value
                if Stats.MONEY_KEYS[key] then value = Stats.ParseMoney(text)
                else value = Stats.ParseCount(text) end

                local empty = (text == nil)
                    or (type(text) == "string" and (GL.Core.trim(text) == ""
                        or text == "-" or text == "--" or text == "—"))
                if value ~= nil then
                    row[Stats.FIELD[key]] = value
                    row.raw[key] = type(text) == "string" and text:sub(1, 64) or text
                    row.quality[key] = "readable"
                elseif empty then
                    row.quality[key] = "unreported"
                else
                    row.quality[key] = "format"
                    row.raw[key] = type(text) == "string" and text:sub(1, 64) or tostring(text)
                end
            end
        end
    end
    return row
end

--------------------------------------------------------------------
-- 自己
--------------------------------------------------------------------

function Stats.SelfRow()
    local id = GL.Core.Identity("player")
    if not id or not id.isSelf then return nil end
    local row = Stats.ReadRow(GetStatistic)
    row.name, row.level, row.self = id.name, id.level, true
    row.at = time()
    local ok, money = pcall(GetMoney)
    if ok then row.wallet = S.Int(money) end   -- 钱包只有自己有，绝不用于他人
    GL.Judge.Evaluate(row)
    return row
end

function Stats.PrintSelfLine()
    if not GL.Judge then return end
    local row = Stats.SelfRow()
    if not row then return end
    if not row.peak then
        GL.Print("自己：还没读到峰值，先打开角色面板→统计，再运行 /gl me")
        return
    end
    GL.Printf("自己：峰值 %s｜可解释 %s｜差额 %s（%s）",
        Stats.FormatMoney(row.peak), Stats.FormatMoney(row.explained),
        Stats.FormatMoney(row.gap), GL.L.VERDICT[row.verdict] or "?")
end

--------------------------------------------------------------------
-- 格式化
--------------------------------------------------------------------

local COIN = {
    gold   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
    silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
    copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}

function Stats.FormatMoney(copper)
    local n = S.Number(copper)
    if not n then return "—" end
    n = math.floor(n)
    local g = math.floor(n / 10000)
    local s = math.floor(n / 100) % 100
    local c = n % 100
    if g > 0 then return g .. COIN.gold .. " " .. s .. COIN.silver .. " " .. c .. COIN.copper end
    if s > 0 then return s .. COIN.silver .. " " .. c .. COIN.copper end
    return c .. COIN.copper
end

function Stats.FormatCount(n)
    local v = S.Number(n)
    if not v then return "—" end
    return tostring(math.floor(v))
end
