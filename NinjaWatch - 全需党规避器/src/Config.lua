-- NinjaWatcher - 全需党规避器
-- Config.lua: constants, defaults and the plain-language glossary.
--
-- The addon reads exactly three public statistics:
--   1044 = Need rolls made on loot
--   1043 = Greed rolls made on loot
--    932 = Total 5-player dungeons entered
--
-- Runtime rule (no rates, no probability model):
--   N = Need rolls, G = Greed rolls, E = 5-player dungeon entries, R = N + G.
--   q_lo is a conservative lower bound of a normal player's R per entry.
--   L(E) = q_lo * E is the lower bound of a normal player's total rolls.
--   gap  = max(3, 0.15 * L(E)) is a policy buffer, not a confidence interval.
--   T(E) = L(E) - gap.  R < T(E) => pass-type, clear the player.
--   R >= T(E) => greed-type, then read the Need share N/R.
--
-- q_lo = 5.4 is a conservative prior from the beta sample. It is not the
-- current p10: on the current readable sample p10 is about 3.82 (all E>0)
-- or 3.12 (E>=4), and p15 is about 5.10 (all) or 3.84 (E>=4). 5.4 sits near
-- p18 all / p23 at E>=4. Do not relabel it as p10. The calibration script
-- reports where 5.4 sits and proposes a reviewed replacement; it never edits
-- this file.
--
-- N/R bands (greed-type only):
--   < 50% green; 50-70% yellow (local HUD only);
--   >= 70% red, but red also requires R >= 30.
--   Since 0.1.1 the old < 10% dark-green band reads as 正常 and the
--   pass-type screen reads as 低, so the visible order is 低/正常/偏高/极高.
--   N/R is gray below R = 20 (small sample).
--   The pass-type screen is gray below E = 4 (the old L(E) < 20 line at
--   q_lo = 5.4 is equivalent to E < 4; it is kept as E < 4 so a future q_lo
--   change does not silently move the gray line).

local ADDON, NW = ...

NW.NAME = ADDON
NW.VERSION = "0.1.1"

NW.STAT = {
    need = 1044,
    greed = 1043,
    dungeons = 932,
}

NW.RULE = {
    -- Conservative normal-player lower bound, rolls per dungeon entry.
    qLo = 5.4,
    -- Policy buffer: max(gapMin, gapPct * L(E)).
    gapPct = 0.15,
    gapMin = 3,
    -- The pass-type screen is not evaluated below this many entries.
    grayBelowEntries = 4,
    -- N/R band edges.
    darkGreenBelow = 0.10,
    greenBelow = 0.50,
    yellowBelow = 0.70,
    -- Small-sample guards.
    ratioGrayBelowRolls = 20,
    redMinRolls = 30,
}

NW.SCAN = {
    debounce = 0.30,
    floor = 1.5,
    hoverTimeout = 2.5,
    manualTimeout = 15,
    farTTL = 3,
}

NW.COLORS = {
    darkgreen = { 0.10, 0.72, 0.24 },
    green = { 0.25, 0.95, 0.35 },
    yellow = { 1.00, 0.82, 0.00 },
    red = { 1.00, 0.25, 0.25 },
    gray = { 0.62, 0.62, 0.62 },
    white = { 1.00, 1.00, 1.00 },
}

NW.DEFAULTS = {
    -- Local tooltip line on other players.
    tooltip = true,
    -- Local tooltip line on the player's own character.
    selfTooltip = true,
    -- Yellow band: local chat frame only, never sent to the party.
    localAlert = true,
    -- Red band: send one /p message to the party. Off by default because it
    -- is visible to other players.
    partyAlert = false,
    -- How long a stored observation stays fresh, in minutes.
    cacheMinutes = 10,
    -- Minimum seconds between two red alerts for the same GUID.
    redCooldown = 300,
}

-- NW.L is replaced by Locale_zhCN.lua. This fallback keeps the addon usable
-- if a locale file is missing.
function NW.L(key, ...)
    local text = (NW.strings and NW.strings[key]) or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, text, ...)
        if ok then return formatted end
    end
    return text
end
