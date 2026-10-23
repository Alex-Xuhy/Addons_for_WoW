-- NinjaWatcher - 全需党规避器
-- Core.lua: namespace helpers, login wiring and the /nw command.

local ADDON, NW = ...

local initialized = false
local eventFrame = CreateFrame("Frame")

function NW.Print(message, color)
    if not DEFAULT_CHAT_FRAME or type(DEFAULT_CHAT_FRAME.AddMessage) ~= "function" then
        return
    end
    local c = color or NW.COLORS.white
    local text = tostring(message or "")
    DEFAULT_CHAT_FRAME:AddMessage(NW.L("CHAT_PREFIX") .. " " .. text, c[1], c[2], c[3])
end

local function safeInit(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        NW.Print("初始化失败（" .. name .. "）：" .. tostring(err), NW.COLORS.red)
    end
    return ok
end

local function login()
    if initialized then return end
    initialized = true
    safeInit("DB", function() NW.DB.Init() end)
    safeInit("Scan", function() NW.Scan.Init() end)
    safeInit("Tooltip", function() NW.Tooltip.Init() end)
    safeInit("Party", function() NW.Party.Init() end)
    safeInit("Settings", function() NW.Settings.Init() end)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON then
        safeInit("DB", function() NW.DB.Init() end)
    elseif event == "PLAYER_LOGIN" then
        login()
    end
end)

local function help()
    NW.Print(NW.L("CHAT_HELP_TITLE"))
    NW.Print(NW.L("CHAT_HELP_OPEN"))
    NW.Print(NW.L("CHAT_HELP_SCAN"))
    NW.Print(NW.L("CHAT_HELP_STATUS"))
    NW.Print(NW.L("CHAT_HELP_TEST"))
    NW.Print(NW.L("CHAT_HELP_CLEAR"))
end

local function status()
    local row = NW.Stats.SelfRow()
    if not row then
        NW.Print(NW.L("CHAT_STATUS_UNKNOWN", "self"))
        return
    end
    if not NW.Stats.RowUsable(row) then
        NW.Print(NW.L("CHAT_STATUS_UNKNOWN",
            NW.Rate.FieldLabel(NW.Stats.UnknownField(row) or "unknown")))
        return
    end
    local result = NW.Rate.Evaluate(row)
    local label
    if result.status == "insufficient" then
        label = NW.L("TABLE_INSUFFICIENT")
    elseif result.status ~= "ok" then
        label = NW.L("TABLE_UNKNOWN")
    elseif result.branch == "pass" then
        label = NW.L("TABLE_PASS")
    else
        label = NW.L(NW.Rate.BandLabelKey(result.band))
        if result.ratio then
            label = NW.L("CHAT_STATUS_RATE", label, result.ratio * 100)
        end
    end
    NW.Print(NW.L("CHAT_STATUS", row.need, row.greed, row.entries,
        row.need + row.greed, label))
end

local function test()
    local results = NW.Rate.SelfTest()
    local passed = 0
    NW.Print(NW.L("CHAT_TEST_TITLE"))
    for _, item in ipairs(results) do
        if item.ok then
            passed = passed + 1
        else
            local got = item.got or {}
            NW.Print(string.format("#%d %s：期望 %s/%s/%s，实际 %s/%s/%s",
                item.index, item.label,
                tostring(item.expected.status), tostring(item.expected.branch),
                tostring(item.expected.band),
                tostring(got.status), tostring(got.branch), tostring(got.band)),
                NW.COLORS.red)
        end
    end
    NW.Print(NW.L("CHAT_TEST_OK", passed, #results),
        passed == #results and NW.COLORS.green or NW.COLORS.yellow)
end

local function clear(arg)
    if arg == "confirm" then
        local count = NW.DB.Clear()
        NW.Print(NW.L("CHAT_CLEAR_DONE", count))
        if NW.Settings and NW.Settings.RefreshPlayers then
            NW.Settings.RefreshPlayers()
        end
    else
        NW.Print(NW.L("CHAT_CLEAR_ASK"), NW.COLORS.yellow)
    end
end

local function debug()
    local info = NW.Scan.Debug()
    NW.Print(NW.L("CHAT_DEBUG", tostring(info.state), info.queue, NW.DB.Count(),
        info.api and "可用" or "不可用"))
end

SLASH_NINJAWATCHER1 = "/nw"
SLASH_NINJAWATCHER2 = "/ninjawatcher"
SlashCmdList["NINJAWATCHER"] = function(message)
    local command = tostring(message or ""):lower():match("^%s*(.-)%s*$")
    if command == "" then
        NW.Settings.Open()
    elseif command == "help" then
        help()
    elseif command == "scan" then
        NW.Party.ScanAll(true)
    elseif command == "status" then
        status()
    elseif command == "test" then
        test()
    elseif command:match("^clear") then
        clear(command:match("^clear%s+(.+)$") or "")
    elseif command == "debug" then
        debug()
    else
        help()
    end
end
