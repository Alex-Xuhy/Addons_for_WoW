-- NinjaWatcher - 全需党规避器
-- Party.lua: watch a 5-player party, scan new members and raise the two
-- approved alerts.
--
-- Yellow band: local chat frame only; never sent to the party.
-- Red band: optional one-shot /p message, off by default. It is sent only in
-- a 5-player party, with a per-player cooldown and a per-group-join guard.
--
-- Raids and battlegrounds are ignored. No invite, trade or mail is ever sent.

local ADDON, NW = ...

local Party = {}
NW.Party = Party

local Stats, Scan, Rate, DB = NW.Stats, NW.Scan, NW.Rate, NW.DB

local seen = {}
local alertPending = {}
local alerted = {}
local wasFiveMan = false
local frame = CreateFrame("Frame")

local function now()
    return time()
end

local function isRaid()
    return type(IsInRaid) == "function" and IsInRaid() and true or false
end

local function groupSize()
    if type(GetNumGroupMembers) ~= "function" then return 0 end
    return tonumber(GetNumGroupMembers()) or 0
end

function Party.IsParty()
    return not isRaid() and groupSize() >= 2 and groupSize() <= 5
end

function Party.IsFiveMan()
    return not isRaid() and groupSize() == 5
end

local function cooldown(key, seconds)
    local record = alerted[key]
    local last = record and tonumber(record.localAt) or 0
    return now() - last < seconds
end

local function localAlert(guid, row, result, red)
    if not DB.Get("localAlert") then return end
    local seconds = tonumber(DB.Get("redCooldown")) or 300
    if cooldown(guid, seconds) then return end
    local name = row.name or "?"
    local message
    if red then
        message = NW.L("ALERT_RED_LOCAL", name, (result.ratio or 0) * 100,
            row.need, row.greed, row.entries, result.rolls)
    else
        message = NW.L("ALERT_YELLOW", name, (result.ratio or 0) * 100,
            row.need, row.greed, row.entries, result.rolls)
    end
    NW.Print(message, red and NW.COLORS.red or NW.COLORS.yellow)
    alerted[guid] = alerted[guid] or {}
    alerted[guid].localAt = now()
end

local function partyAlert(guid, row)
    if not DB.Get("partyAlert") then return false end
    if not Party.IsFiveMan() then return false end
    local seconds = tonumber(DB.Get("redCooldown")) or 300
    local record = alerted[guid]
    local last = record and tonumber(record.partyAt) or 0
    if now() - last < seconds then return false end
    local name = row.name or "?"
    local message = NW.L("ALERT_RED", name, row.need + row.greed, row.need)
    if type(SendChatMessage) ~= "function" then return false end
    local ok = pcall(SendChatMessage, message, "PARTY")
    if not ok then return false end
    alerted[guid] = alerted[guid] or {}
    alerted[guid].partyAt = now()
    return true
end

local function evaluate(guid, row)
    if not Party.IsFiveMan() then return end
    local result = Rate.Evaluate(row)
    if result.status ~= "ok" or result.branch ~= "greed" then return end
    if result.band == "yellow" then
        localAlert(guid, row, result, false)
    elseif result.band == "red" then
        if not partyAlert(guid, row) then
            localAlert(guid, row, result, true)
        end
    end
end

local function onReady(guid, row, status)
    if status ~= "READY" or not row then return end
    if not alertPending[guid] then return end
    alertPending[guid] = nil
    if not Party.IsFiveMan() then return end
    if not Stats.RowUsable(row) then return end
    evaluate(guid, row)
end

local function currentMembers()
    local members = {}
    if not Party.IsParty() then return members end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local identity = Stats.UnitIdentity(unit)
            if identity and identity.isPlayer and not identity.isSelf then
                members[identity.guid] = unit
            end
        end
    end
    return members
end

function Party.Update()
    if not Party.IsParty() then
        seen = {}
        alertPending = {}
        wasFiveMan = false
        return
    end
    local five = Party.IsFiveMan()
    local firstFive = five and not wasFiveMan
    local members = currentMembers()
    local present = {}
    for guid, unit in pairs(members) do
        present[guid] = true
        local newMember = not seen[guid]
        if newMember then
            seen[guid] = true
        end
        if five and (newMember or firstFive) then
            alertPending[guid] = true
        end
        -- A group that just reached five players may contain members scanned
        -- during the 4-player stage; request them again so they get a verdict.
        if newMember or (firstFive and alertPending[guid]) then
            local row, status = Scan.Request(unit, { force = false, priority = false, queue = true })
            if row and status == "READY" then
                onReady(guid, row, "READY")
            end
        end
    end
    wasFiveMan = five
    for guid in pairs(seen) do
        if not present[guid] then
            seen[guid] = nil
            alertPending[guid] = nil
        end
    end
end

function Party.ScanAll(force)
    local requested, ready = Scan.ScanParty(force and true or false)
    if requested + ready == 0 then
        NW.Print(NW.L("SETTINGS_SCAN_NONE"))
    else
        NW.Print(NW.L("SETTINGS_SCAN_STARTED", requested + ready))
    end
    return requested, ready
end

-- Retry scans that were blocked by combat, once combat ends.
local function retryPending()
    if not Party.IsFiveMan() then return end
    for guid in pairs(alertPending) do
        local found
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local identity = Stats.UnitIdentity(unit)
                if identity and identity.guid == guid then
                    found = unit
                    break
                end
            end
        end
        if found then
            local row, status = Scan.Request(found, { force = true, priority = true, queue = true })
            if row and status == "READY" then
                onReady(guid, row, "READY")
            end
        else
            alertPending[guid] = nil
        end
    end
end

function Party.Init()
    Scan.OnReady(onReady)
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            retryPending()
        else
            Party.Update()
        end
    end)
end
