-- NinjaWatcher - 全需党规避器
-- Rate.lua: the runtime classifier. Pure Lua, no game API, easy to test.
--
-- Inputs are the three counters:
--   N = need rolls (1044)
--   G = greed rolls (1043)
--   E = 5-player dungeon entries (932)
--
-- Step 1, pass-type screen:
--   L(E) = 5.4 * E
--   gap  = max(3, 0.15 * L(E)) = max(3, 0.81 * E)
--   T(E) = L(E) - gap
--   E < 4 -> insufficient sample (gray), do not classify.
--   R < T(E) -> pass-type: not a ninja candidate, no rate and no alert.
--
-- Step 2, greed-type Need share:
--   N/R with bands <50 / 50-70 / >=70. The old <10 dark-green band was
--   merged into 正常 in 0.1.1 and the pass-type screen now reads as 低.
--   N/R is gray when R < 20.
--   For 20 <= R < 30, the >=70 band is capped to yellow; red requires R >= 30.
--
-- N/R is a share, not a probability. "N/R = 34.6%" means 34.6% of this
-- player's recorded Need+Greed rolls were Need rolls.

local ADDON, NW = ...

local Rate = {}
NW.Rate = Rate

local function isCount(value)
    return type(value) == "number" and value == value
        and value >= 0 and value < math.huge and value == math.floor(value)
end

local function qualityOk(quality, value)
    if not isCount(value) then return false end
    if quality == nil then return true end
    return quality == "readable" or quality == "zero"
end

function Rate.Threshold(entries)
    local rule = NW.RULE
    local e = isCount(entries) and entries or 0
    local lower = rule.qLo * e
    local gap = math.max(rule.gapMin, rule.gapPct * lower)
    return lower, gap, lower - gap
end

-- Returns a plain table:
--   status = "ok" | "insufficient" | "unknown"
--   branch = "pass" | "greed" (only when status == "ok")
--   band   = "darkgreen" | "green" | "yellow" | "red" | "gray"
--   ratio  = N/R as a fraction (nil for pass/insufficient/unknown)
--   L, gap, threshold = the pass-type screen values
--   redCapped = true when N/R >= 70% but R < 30
--   reason = the unreadable field or quality, when status == "unknown"
function Rate.Evaluate(need, greed, entries, quality)
    if type(need) == "table" then
        local row = need
        need, greed, entries = row.need, row.greed, row.entries
        quality = row.quality
    end
    quality = type(quality) == "table" and quality or {}
    local rule = NW.RULE

    local result = {
        need = need,
        greed = greed,
        entries = entries,
        status = "ok",
    }

    if not qualityOk(quality.need, need) then
        result.status = "unknown"
        result.reason = "need:" .. tostring(quality.need or "missing")
        return result
    end
    if not qualityOk(quality.greed, greed) then
        result.status = "unknown"
        result.reason = "greed:" .. tostring(quality.greed or "missing")
        return result
    end
    if not qualityOk(quality.entries, entries) then
        result.status = "unknown"
        result.reason = "entries:" .. tostring(quality.entries or "missing")
        return result
    end

    local rolls = need + greed
    local lower, gap, threshold = Rate.Threshold(entries)
    result.rolls = rolls
    result.L = lower
    result.gap = gap
    result.threshold = threshold

    if entries < rule.grayBelowEntries then
        result.status = "insufficient"
        return result
    end

    if rolls < threshold then
        result.branch = "pass"
        return result
    end

    result.branch = "greed"
    result.ratio = rolls > 0 and need / rolls or nil

    if rolls < rule.ratioGrayBelowRolls then
        result.band = "gray"
    elseif result.ratio >= rule.yellowBelow then
        if rolls >= rule.redMinRolls then
            result.band = "red"
        else
            result.band = "yellow"
            result.redCapped = true
        end
    elseif result.ratio >= rule.greenBelow then
        result.band = "yellow"
    elseif result.ratio >= rule.darkGreenBelow then
        result.band = "green"
    else
        result.band = "darkgreen"
    end
    return result
end

-- The dark-green band was dropped in 0.1.1: everything below 50% reads as
-- 正常. The internal name stays so old rows and the self-test are unchanged.
function Rate.BandLabelKey(band)
    if band == "darkgreen" or band == "green" then return "BAND_GREEN" end
    if band == "yellow" then return "BAND_YELLOW" end
    if band == "red" then return "BAND_RED" end
    if band == "gray" then return "BAND_GRAY" end
    return "BAND_UNKNOWN"
end

function Rate.Color(band)
    if band == "darkgreen" then return NW.COLORS.green end
    return NW.COLORS[band] or NW.COLORS.gray
end

local FIELD_KEYS = {
    need = "FIELD_NEED",
    greed = "FIELD_GREED",
    entries = "FIELD_ENTRIES",
    rolls = "FIELD_ROLLS",
}

local QUALITY_KEYS = {
    readable = "STATUS_READABLE",
    zero = "STATUS_ZERO",
    unknown = "STATUS_UNKNOWN",
    restricted = "STATUS_RESTRICTED",
    format = "STATUS_FORMAT",
    skipped = "STATUS_SKIPPED",
    api = "STATUS_API",
    error = "STATUS_ERROR",
    missing = "STATUS_UNREPORTED",
}

-- Chinese names for the counters and for the parse qualities, so nothing in
-- the game shows a bare N/G/E/R or an English token.
function Rate.FieldLabel(field)
    local key = FIELD_KEYS[field]
    return key and NW.L(key) or tostring(field)
end

function Rate.QualityLabel(quality)
    local key = QUALITY_KEYS[quality]
    return key and NW.L(key) or tostring(quality)
end

-- Boundary tests for /nw test. They do not touch the game or the DB.
function Rate.SelfTest()
    local cases = {
        { n = 45, g = 5, e = 10, status = "ok", branch = "greed", band = "red", label = "90%, R=50" },
        { n = 20, g = 0, e = 10, status = "ok", branch = "pass", label = "R below threshold" },
        { n = 100, g = 0, e = 3, status = "insufficient", label = "E<4" },
        { n = 20, g = 60, e = 10, status = "ok", branch = "greed", band = "green", label = "25%" },
        { n = 9, g = 91, e = 10, status = "ok", branch = "greed", band = "darkgreen", label = "9%" },
        { n = 50, g = 50, e = 10, status = "ok", branch = "greed", band = "yellow", label = "50%" },
        { n = 27, g = 15, e = 14, status = "ok", branch = "pass", label = "64.3% but R below threshold" },
        { n = 100, g = 0, e = 10, status = "ok", branch = "greed", band = "red", label = "100%" },
        { n = 29, g = 0, e = 5, status = "ok", branch = "greed", band = "yellow", label = "100%, R<30 capped" },
        { n = 10, g = 19, e = 5, status = "ok", branch = "greed", band = "green", label = "34.5%" },
        { n = 20, g = 0, e = 4, status = "ok", branch = "greed", band = "yellow", label = "100%, R=20 capped" },
        { n = 1, g = 18, e = 4, status = "ok", branch = "greed", band = "gray", label = "5.3%, R<20" },
        { n = 18, g = 0, e = 4, status = "ok", branch = "pass", label = "R=18 below 18.36" },
        { n = 0, g = 0, e = 0, status = "insufficient", label = "empty row" },
    }
    local results = {}
    for i, case in ipairs(cases) do
        local got = Rate.Evaluate(case.n, case.g, case.e, {
            need = "readable", greed = "readable", entries = "readable",
        })
        local ok = got.status == case.status
            and (case.branch == nil or got.branch == case.branch)
            and (case.band == nil or got.band == case.band)
        results[#results + 1] = {
            index = i,
            ok = ok,
            label = case.label,
            expected = { status = case.status, branch = case.branch, band = case.band },
            got = got,
        }
    end
    return results
end
