-- NinjaWatcher - 全需党规避器
-- DB.lua: the local-only player catalog.
--
-- SavedVariables: NinjaWatcherDB
--   version  = schema version
--   options  = user settings
--   players  = { [guid] = row }
--   reports  = { [guid] = sample }   BETA(0.2.0), see below
--
-- A row is the latest observation of one player:
--   name, realm, level, class, classKey
--   need, greed, entries, quality = { need=, greed=, entries= }
--   at, firstAt, scanCount, source
--
-- Nothing here talks to the network. The only way data leaves the machine is
-- the optional red party message in Party.lua, and that is off by default.

local ADDON, NW = ...

local DB = {}
NW.DB = DB

local SCHEMA = 1

local function is_number(value)
    return type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end

local function is_count(value)
    return is_number(value) and value == math.floor(value)
end

local function copy_option_defaults(options)
    for key, value in pairs(NW.DEFAULTS) do
        if options[key] == nil then
            options[key] = value
        end
    end
end

local function normalise()
    if type(NinjaWatcherDB) ~= "table" then
        NinjaWatcherDB = {}
    end
    local db = NinjaWatcherDB
    if type(db.version) ~= "number" or db.version < 0 or db.version > SCHEMA then
        db.version = SCHEMA
    end
    if type(db.options) ~= "table" then
        db.options = {}
    end
    copy_option_defaults(db.options)
    if type(db.players) ~= "table" then
        db.players = {}
    end
    -- BETA(0.2.0): the tester's own "this one is a ninja" marks.
    if type(db.reports) ~= "table" then
        db.reports = {}
    end
    return db
end

function DB.Init()
    return normalise()
end

function DB.Get(key)
    local db = normalise()
    local value = db.options[key]
    if value == nil then
        value = NW.DEFAULTS[key]
    end
    return value
end

function DB.Set(key, value)
    local db = normalise()
    db.options[key] = value
end

function DB.Players()
    return normalise().players
end

function DB.GetPlayer(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local row = normalise().players[guid]
    if type(row) ~= "table" then return nil end
    return row
end

local function safe_text(value, limit)
    if NW.IsSecret(value) or type(value) ~= "string" then return nil end
    local text = value:gsub("[%c]", " ")
    if text == "" then return nil end
    return text:sub(1, limit or 80)
end

local function safe_quality(value)
    if type(value) ~= "string" then return "unknown" end
    return value:sub(1, 24)
end

-- Store one observation. The caller supplies parsed counts and quality flags.
-- Unknown values are never written as zero; if a field is unknown the row is
-- still remembered but Rate.Evaluate will refuse to classify it.
function DB.Upsert(guid, row)
    if type(guid) ~= "string" or guid == "" or type(row) ~= "table" then
        return nil
    end
    local db = normalise()
    local previous = db.players[guid]
    if type(previous) ~= "table" then previous = nil end

    local at = is_number(row.at) and row.at or time()
    local out = {
        name = safe_text(row.name, 80),
        realm = safe_text(row.realm, 80),
        level = is_count(row.level) and row.level or nil,
        class = safe_text(row.class, 40),
        classKey = safe_text(row.classKey, 40),
        need = is_count(row.need) and row.need or nil,
        greed = is_count(row.greed) and row.greed or nil,
        entries = is_count(row.entries) and row.entries or nil,
        quality = {
            need = safe_quality(row.quality and row.quality.need),
            greed = safe_quality(row.quality and row.quality.greed),
            entries = safe_quality(row.quality and row.quality.entries),
        },
        at = at,
        firstAt = previous and previous.firstAt or at,
        scanCount = previous and (tonumber(previous.scanCount) or 1) + 1 or 1,
        source = safe_text(row.source, 20) or "scan",
    }
    db.players[guid] = out
    return out
end

function DB.Remove(guid)
    local db = normalise()
    if type(guid) == "string" and db.players[guid] ~= nil then
        db.players[guid] = nil
        return true
    end
    return false
end

function DB.Clear()
    local db = normalise()
    local count = 0
    for _ in pairs(db.players) do count = count + 1 end
    db.players = {}
    -- BETA(0.2.0): "clear all records" clears the reported samples too.
    db.reports = {}
    return count
end

function DB.Count()
    local count = 0
    for _ in pairs(normalise().players) do count = count + 1 end
    return count
end

-- Rows for the settings catalog, newest first. Invalid rows are skipped.
function DB.List()
    local list = {}
    for guid, row in pairs(normalise().players) do
        if type(guid) == "string" and type(row) == "table"
            and is_number(row.at) and is_count(row.need)
            and is_count(row.greed) and is_count(row.entries) then
            list[#list + 1] = { guid = guid, row = row }
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.row.at) or 0) > (tonumber(b.row.at) or 0)
    end)
    return list
end

function DB.ResetOptions()
    local db = normalise()
    db.options = {}
    copy_option_defaults(db.options)
end

-- ---------------------------------------------------------------- BETA(0.2.0)
-- The tester marks a player from the portrait menu. A mark is a judgement, not
-- a scan result, so it carries a frozen snapshot: the counters and the rule's
-- verdict as they stood at that moment. A later rule change must not rewrite
-- what an old sample was judged against. No name is stored here.
local REPORT_NUMBERS = { "need", "greed", "entries", "rolls", "ratio", "threshold" }

function DB.Reported(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local report = normalise().reports[guid]
    if type(report) ~= "table" then return nil end
    return report
end

function DB.SetReport(guid, snapshot)
    if type(guid) ~= "string" or guid == "" then return nil end
    snapshot = type(snapshot) == "table" and snapshot or {}
    local report = {
        at = is_number(snapshot.at) and snapshot.at or time(),
        status = safe_text(snapshot.status, 20),
        branch = safe_text(snapshot.branch, 20),
        band = safe_text(snapshot.band, 20),
    }
    for _, key in ipairs(REPORT_NUMBERS) do
        if is_number(snapshot[key]) then report[key] = snapshot[key] end
    end
    normalise().reports[guid] = report
    return report
end

-- A mark made before the player was ever scanned has no counters yet; fill
-- them in when a scan lands, keeping the original mark time.
function DB.FillReport(guid, snapshot)
    local report = DB.Reported(guid)
    if not report or is_number(report.rolls) then return report end
    if type(snapshot) ~= "table" then return report end
    for _, key in ipairs(REPORT_NUMBERS) do
        if is_number(snapshot[key]) then report[key] = snapshot[key] end
    end
    local status = safe_text(snapshot.status, 20)
    if status then report.status = status end
    local branch = safe_text(snapshot.branch, 20)
    if branch then report.branch = branch end
    local band = safe_text(snapshot.band, 20)
    if band then report.band = band end
    return report
end

function DB.ClearReport(guid)
    local db = normalise()
    if type(guid) == "string" and db.reports[guid] ~= nil then
        db.reports[guid] = nil
        return true
    end
    return false
end

-- Reported samples, newest mark first.
function DB.ReportList()
    local list = {}
    for guid, report in pairs(normalise().reports) do
        if type(guid) == "string" and type(report) == "table" then
            list[#list + 1] = { guid = guid, report = report }
        end
    end
    table.sort(list, function(a, b)
        return (tonumber(a.report.at) or 0) > (tonumber(b.report.at) or 0)
    end)
    return list
end
