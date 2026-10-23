-- NinjaWatcher - 全需党规避器
-- Stats.lua: read the three public counters and resolve unit identity.
--
-- Only 1044 (Need), 1043 (Greed) and 932 (5-player dungeon entries) are read.
-- No loot history, no roll frames, no combat log.
--
-- Value semantics:
--   number / digit string -> readable count
--   "", "-", "--", em dash -> zero / unreported (0)
--   nil, secret, API error, unsupported format -> unknown (never stored as 0)

local ADDON, NW = ...

local Stats = {}
NW.Stats = Stats

local DASH = "\226\128\148" -- em dash

-- A secret value must not be compared, concatenated, hashed or formatted.
local function isSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(issecretvalue, value)
    return not ok or (secret and true or false)
end
NW.IsSecret = isSecret

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Calls a game API. Returns ok, first, second, third. A secret return makes
-- the whole call unavailable; the addon treats that as unknown.
function Stats.SafeCall(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, ...)
    if not ok or isSecret(a) or isSecret(b) or isSecret(c) then
        return false
    end
    return true, a, b, c
end

-- Returns count, quality. Quality is one of:
--   readable, zero, unknown, restricted, format
function Stats.ParseCount(value)
    if isSecret(value) then return nil, "restricted" end
    if type(value) == "number" then
        if value ~= value or value < 0 or value == math.huge or value ~= math.floor(value) then
            return nil, "format"
        end
        return value, "readable"
    end
    if type(value) ~= "string" then
        return nil, "unknown"
    end
    local text = trim(value)
    if text == "" or text == "-" or text == "--" or text == DASH then
        return 0, "zero"
    end
    text = text:gsub(",", ""):gsub("%s", "")
    -- Some statistics come back as "18.00"; accept it only when it is a whole
    -- number, and still reject real fractions such as "18.5".
    if text:match("^%d+%.?%d*$") then
        local count = tonumber(text)
        if count and count >= 0 and count < math.huge and count == math.floor(count) then
            return count, "readable"
        end
    end
    return nil, "format"
end

-- Reads one statistic through a getter such as GetStatistic or
-- GetComparisonStatistic. The second return of those APIs is a skip flag.
function Stats.ReadOne(getter, id)
    if type(getter) ~= "function" then
        return nil, "api"
    end
    local ok, value, skip = pcall(getter, id)
    if not ok then return nil, "error" end
    if isSecret(value) or isSecret(skip) then return nil, "restricted" end
    if skip then return nil, "skipped" end
    return Stats.ParseCount(value)
end

local function readField(getter, id)
    local value, quality = Stats.ReadOne(getter, id)
    return value, quality
end

-- Reads the three counters into a fresh row. The getter is either the player's
-- own GetStatistic or the comparison-window GetComparisonStatistic.
function Stats.ReadRow(getter)
    local row = {
        at = time(),
        quality = {},
        source = "scan",
    }
    row.need, row.quality.need = readField(getter, NW.STAT.need)
    row.greed, row.quality.greed = readField(getter, NW.STAT.greed)
    row.entries, row.quality.entries = readField(getter, NW.STAT.dungeons)
    return row
end

local function usableQuality(quality, value)
    if quality == nil then
        return type(value) == "number"
    end
    return quality == "readable" or quality == "zero"
end

-- True only when all three counters are usable numbers. A row with any
-- unknown field is remembered but cannot be classified.
function Stats.RowUsable(row)
    if type(row) ~= "table" then return false end
    return usableQuality(row.quality and row.quality.need, row.need)
        and usableQuality(row.quality and row.quality.greed, row.greed)
        and usableQuality(row.quality and row.quality.entries, row.entries)
end

function Stats.UnknownField(row)
    if type(row) ~= "table" then return "row" end
    if not usableQuality(row.quality and row.quality.need, row.need) then return "need" end
    if not usableQuality(row.quality and row.quality.greed, row.greed) then return "greed" end
    if not usableQuality(row.quality and row.quality.entries, row.entries) then return "entries" end
    return nil
end

-- The player's own row uses GetStatistic. Other players use the comparison
-- getter only after SetAchievementComparisonUnit has fired its ready event.
function Stats.SelfRow()
    local identity = Stats.UnitIdentity("player")
    if not identity or not identity.isSelf then return nil end
    local row = Stats.ReadRow(GetStatistic)
    row.name = identity.name
    row.realm = identity.realm
    row.level = identity.level
    row.class = identity.class
    row.classKey = identity.classKey
    row.source = "self"
    row.self = true
    return row
end

function Stats.ComparisonRow()
    return Stats.ReadRow(GetComparisonStatistic)
end

-- Resolves a unit token without assuming that a missing value is zero.
-- Returns identity, nil or nil, reason ("none" or "hidden").
function Stats.UnitIdentity(unit)
    if isSecret(unit) or type(unit) ~= "string" then
        return nil, "none"
    end
    local ok, exists = Stats.SafeCall(UnitExists, unit)
    if not ok then return nil, "hidden" end
    if not exists then return nil, "none" end

    local guidOk, guid = Stats.SafeCall(UnitGUID, unit)
    if not guidOk or type(guid) ~= "string" or guid == "" then
        return nil, "hidden"
    end

    local playerOk, isPlayer = Stats.SafeCall(UnitIsPlayer, unit)
    if not playerOk or isPlayer == nil then return nil, "hidden" end
    if not isPlayer then
        return nil, "none"
    end

    local nameOk, name, realm = Stats.SafeCall(UnitName, unit)
    if not nameOk or type(name) ~= "string" or name == "" then
        return nil, "hidden"
    end
    if type(realm) ~= "string" or realm == "" then
        local realmOk, current = Stats.SafeCall(GetRealmName)
        realm = realmOk and type(current) == "string" and current or nil
    end

    local levelOk, level = Stats.SafeCall(UnitLevel, unit)
    if not levelOk or type(level) ~= "number" or level < 0 or level ~= math.floor(level) then
        level = nil
    end

    local selfOk, isSelf = Stats.SafeCall(UnitIsUnit, unit, "player")
    if not selfOk or isSelf == nil then return nil, "hidden" end

    local classOk, class, classKey = Stats.SafeCall(UnitClass, unit)
    if not classOk then class, classKey = nil, nil end

    return {
        guid = guid,
        name = name,
        realm = type(realm) == "string" and realm or nil,
        level = level,
        isPlayer = true,
        isSelf = isSelf and true or false,
        class = type(class) == "string" and class or nil,
        classKey = type(classKey) == "string" and classKey or nil,
    }
end
