-- NinjaWatcher - 全需党规避器
-- Settings.lua: the only entry point, registered under Settings -> AddOns.
-- Two pages: the local player catalog and the four display/alert options.

local ADDON, NW = ...

local Settings = {}
NW.Settings = Settings

local DB, Stats, Rate, Scan = NW.DB, NW.Stats, NW.Rate, NW.Scan

local ROW_HEIGHT = 22
local COLUMNS = {
    { key = "name", x = 4, width = 136, title = "COL_NAME", align = "LEFT" },
    { key = "level", x = 144, width = 32, title = "COL_LEVEL", align = "LEFT" },
    { key = "need", x = 180, width = 36, title = "COL_NEED", align = "RIGHT" },
    { key = "greed", x = 220, width = 36, title = "COL_GREED", align = "RIGHT" },
    { key = "entries", x = 260, width = 36, title = "COL_ENTRIES", align = "RIGHT" },
    { key = "rolls", x = 300, width = 36, title = "COL_ROLLS", align = "RIGHT" },
    { key = "rate", x = 340, width = 58, title = "COL_RATE", align = "RIGHT" },
    { key = "band", x = 402, width = 58, title = "COL_BAND", align = "LEFT" },
    -- The timestamp needs a full "MM-DD HH:MM" on one line; a narrow column
    -- wrapped it into two lines that ran over the next row.
    { key = "time", x = 464, width = 104, title = "COL_TIME", align = "LEFT" },
}

local frame
local playersPage
local optionsPage
local scroll
local scrollChild
local emptyText
local countText
local sortButton
local clearButton
local clearArmed = false
local rows = {}
local checkboxes = {}
local sortMode = "recent"
local activePage = "players"

local function safeName(row)
    local name = row.name
    if NW.IsSecret(name) or type(name) ~= "string" or name == "" then return "?" end
    return name:sub(1, 40)
end

local function safeTime(at)
    if type(at) ~= "number" or at <= 0 then return "–" end
    if type(date) ~= "function" then return tostring(at) end
    local ok, text = pcall(date, "%m-%d %H:%M", at)
    return ok and text or "–"
end

local function rateText(result)
    if result and result.status == "ok" and result.branch == "greed" and result.ratio then
        return string.format("%.1f%%", result.ratio * 100)
    end
    return "–"
end

local function bandText(result)
    if not result then return NW.L("TABLE_UNKNOWN"), NW.COLORS.gray end
    if result.status == "insufficient" then return NW.L("TABLE_INSUFFICIENT"), NW.COLORS.gray end
    if result.status ~= "ok" then return NW.L("TABLE_UNKNOWN"), NW.COLORS.gray end
    if result.branch == "pass" then return NW.L("TABLE_PASS"), NW.COLORS.darkgreen end
    return NW.L(Rate.BandLabelKey(result.band)), Rate.Color(result.band)
end

local function addColumn(parent, column, header)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", parent, "LEFT", column.x, 0)
    text:SetWidth(column.width)
    text:SetJustifyH(column.align or "LEFT")
    if header then
        text:SetText(NW.L(column.title))
        text:SetTextColor(1, 0.82, 0)
    end
    return text
end

local function makeRow(index)
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(row)
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    row.texts = {}
    for _, column in ipairs(COLUMNS) do
        local text = addColumn(row, column, false)
        -- A fixed height keeps a long value from wrapping into the row below.
        text:SetHeight(ROW_HEIGHT)
        row.texts[column.key] = text
    end
    row:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then return end
        local result = entry.result
        local bandLabel = bandText(result)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(safeName(entry.row), 1, 1, 1)
        GameTooltip:AddLine(NW.L("TABLE_ROW_DETAIL",
            entry.row.need, entry.row.greed, entry.row.entries or 0,
            result and result.rolls or (entry.row.need + entry.row.greed),
            rateText(result), bandLabel, safeTime(entry.row.at)), 0.8, 0.8, 0.8, true)
        if result and result.threshold then
            GameTooltip:AddLine(NW.L("TOOLTIP_THRESHOLD", result.threshold, entry.row.entries or 0),
                0.65, 0.65, 0.65)
        end
        GameTooltip:AddLine(NW.L("RATE_HINT"), 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return row
end

local function getRow(index)
    if not rows[index] then
        rows[index] = makeRow(index)
    end
    return rows[index]
end

local function setRow(index, entry)
    local row = getRow(index)
    local result = entry.result
    local bandLabel, bandColor = bandText(result)
    row.entry = entry
    row.texts.name:SetText(safeName(entry.row))
    row.texts.level:SetText(entry.row.level and tostring(entry.row.level) or "–")
    row.texts.need:SetText(tostring(entry.row.need))
    row.texts.greed:SetText(tostring(entry.row.greed))
    row.texts.entries:SetText(entry.row.entries and tostring(entry.row.entries) or "–")
    row.texts.rolls:SetText(tostring(result and result.rolls or (entry.row.need + entry.row.greed)))
    row.texts.rate:SetText(rateText(result))
    row.texts.band:SetText(bandLabel)
    row.texts.band:SetTextColor(bandColor[1], bandColor[2], bandColor[3])
    row.texts.time:SetText(safeTime(entry.row.at))
    row:Show()
end

local function sortItems(items)
    if sortMode == "rate" then
        table.sort(items, function(a, b)
            local ar = a.result and a.result.ratio
            local br = b.result and b.result.ratio
            if ar == nil and br == nil then
                return (a.row.at or 0) > (b.row.at or 0)
            elseif ar == nil then
                return false
            elseif br == nil then
                return true
            elseif ar == br then
                return (a.row.at or 0) > (b.row.at or 0)
            end
            return ar > br
        end)
    end
end

function Settings.RefreshPlayers()
    if not scrollChild then return end
    local list = DB.List()
    local items = {}
    for _, entry in ipairs(list) do
        items[#items + 1] = {
            guid = entry.guid,
            row = entry.row,
            result = Rate.Evaluate(entry.row),
        }
    end
    sortItems(items)
    for i, entry in ipairs(items) do
        setRow(i, entry)
    end
    for i = #items + 1, #rows do
        rows[i]:Hide()
        rows[i].entry = nil
    end
    scrollChild:SetHeight(math.max(1, #items * ROW_HEIGHT))
    countText:SetText(NW.L("SETTINGS_COUNT", #items))
    emptyText:SetShown(#items == 0)
    if clearArmed then
        clearArmed = false
        clearButton:SetText(NW.L("SETTINGS_CLEAR_ALL"))
    end
end

local function setPage(page)
    activePage = page
    playersPage:SetShown(page == "players")
    optionsPage:SetShown(page == "options")
    if page == "players" then
        Settings.RefreshPlayers()
    end
end

local function makeTab(parent, labelKey, page, x)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(100, 24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -52)
    button:SetText(NW.L(labelKey))
    button:SetScript("OnClick", function() setPage(page) end)
    return button
end

local function checkbox(parent, key, label, y)
    local cb = CreateFrame("CheckButton", "NinjaWatcherOption_" .. key, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y)
    local text = cb.Text
    if not text then
        local name = cb:GetName()
        text = name and _G[name .. "Text"] or nil
    end
    if text then
        text:SetText(label)
        text:SetWidth(520)
        text:SetJustifyH("LEFT")
    end
    cb:SetChecked(DB.Get(key) and true or false)
    cb:SetScript("OnClick", function(self)
        DB.Set(key, self:GetChecked() and true or false)
    end)
    checkboxes[key] = cb
    return cb
end

function Settings.RefreshOptions()
    for key, cb in pairs(checkboxes) do
        cb:SetChecked(DB.Get(key) and true or false)
    end
end

function Settings.Refresh()
    if not frame then return end
    Settings.RefreshOptions()
    if activePage == "players" then
        Settings.RefreshPlayers()
    end
end

function Settings.Open()
    local api = _G.Settings
    if not Settings.category then
        NW.Print(NW.L("CHAT_NO_SETTINGS"))
        return
    end
    if type(api) ~= "table" or type(api.OpenToCategory) ~= "function" then
        NW.Print(NW.L("CHAT_NO_SETTINGS"))
        return
    end
    local ok = pcall(function()
        api.OpenToCategory(Settings.category:GetID())
    end)
    if not ok then
        pcall(api.OpenToCategory, Settings.category.ID)
    end
end

local function buildPlayersPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local hint = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
    hint:SetWidth(570)
    hint:SetJustifyH("LEFT")
    hint:SetText(NW.L("SETTINGS_PLAYERS_HINT"))

    local legend = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -20)
    legend:SetWidth(568)
    legend:SetJustifyH("LEFT")
    legend:SetText(NW.L("TABLE_LEGEND"))
    legend:SetTextColor(0.62, 0.62, 0.62)

    local scanButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    scanButton:SetSize(110, 24)
    scanButton:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -50)
    scanButton:SetText(NW.L("SETTINGS_SCAN_PARTY"))
    scanButton:SetScript("OnClick", function()
        NW.Party.ScanAll(true)
    end)

    clearButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    clearButton:SetSize(150, 24)
    clearButton:SetPoint("LEFT", scanButton, "RIGHT", 8, 0)
    clearButton:SetText(NW.L("SETTINGS_CLEAR_ALL"))
    clearButton:SetScript("OnClick", function(self)
        if not clearArmed then
            clearArmed = true
            self:SetText(NW.L("SETTINGS_CLEAR_CONFIRM"))
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(5, function()
                    if clearArmed and clearButton then
                        clearArmed = false
                        clearButton:SetText(NW.L("SETTINGS_CLEAR_ALL"))
                    end
                end)
            end
            return
        end
        clearArmed = false
        self:SetText(NW.L("SETTINGS_CLEAR_ALL"))
        local count = DB.Clear()
        Settings.RefreshPlayers()
        NW.Print(NW.L("SETTINGS_CLEAR_DONE", count))
    end)

    sortButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    sortButton:SetSize(130, 24)
    sortButton:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -50)
    sortButton:SetText(NW.L("SETTINGS_SORT_RECENT"))
    sortButton:SetScript("OnClick", function(self)
        sortMode = sortMode == "recent" and "rate" or "recent"
        self:SetText(NW.L(sortMode == "recent" and "SETTINGS_SORT_RECENT" or "SETTINGS_SORT_RATE"))
        Settings.RefreshPlayers()
    end)

    -- The header needs its own row so it clips above the scroll frame.
    local header = CreateFrame("Frame", nil, page)
    header:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -80)
    header:SetSize(570, 18)
    for _, column in ipairs(COLUMNS) do
        addColumn(header, column, true)
    end

    scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -102)
    scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -30, 28)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(570, 1)
    scroll:SetScrollChild(scrollChild)

    emptyText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyText:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, -8)
    emptyText:SetWidth(540)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetText(NW.L("SETTINGS_EMPTY"))

    countText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 4, 6)
    countText:SetText(NW.L("SETTINGS_COUNT", 0))

    return page
end

local function buildOptionsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent)

    local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -4)
    title:SetText(NW.L("OPTIONS_TITLE"))

    checkbox(page, "tooltip", NW.L("OPTIONS_TOOLTIP"), -40)
    checkbox(page, "selfTooltip", NW.L("OPTIONS_SELF"), -72)
    checkbox(page, "localAlert", NW.L("OPTIONS_LOCAL"), -104)
    checkbox(page, "partyAlert", NW.L("OPTIONS_PARTY"), -136)

    local warning = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    warning:SetPoint("TOPLEFT", page, "TOPLEFT", 42, -166)
    warning:SetWidth(520)
    warning:SetJustifyH("LEFT")
    warning:SetText(NW.L("OPTIONS_PARTY_WARN"))
    warning:SetTextColor(1, 0.55, 0.55)

    local ruleTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ruleTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -200)
    ruleTitle:SetText(NW.L("OPTIONS_RULE_TITLE"))

    local ruleText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ruleText:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -224)
    ruleText:SetWidth(560)
    ruleText:SetJustifyH("LEFT")
    ruleText:SetSpacing(3)
    ruleText:SetText(NW.L("OPTIONS_RULE_TEXT"))

    local privacyTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    privacyTitle:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -330)
    privacyTitle:SetText(NW.L("OPTIONS_PRIVACY_TITLE"))

    local privacyText = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    privacyText:SetPoint("TOPLEFT", page, "TOPLEFT", 8, -354)
    privacyText:SetWidth(560)
    privacyText:SetJustifyH("LEFT")
    privacyText:SetSpacing(3)
    privacyText:SetText(NW.L("OPTIONS_PRIVACY_TEXT"))

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(150, 24)
    reset:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 8, 8)
    reset:SetText(NW.L("OPTIONS_RESET"))
    reset:SetScript("OnClick", function()
        DB.ResetOptions()
        Settings.RefreshOptions()
        NW.Print(NW.L("OPTIONS_RESET_DONE"))
    end)

    return page
end

function Settings.Init()
    if frame then return end
    local api = _G.Settings
    if type(api) ~= "table" or type(api.RegisterCanvasLayoutCategory) ~= "function"
        or type(api.RegisterAddOnCategory) ~= "function" then
        return
    end

    frame = CreateFrame("Frame", "NinjaWatcherSettingsFrame", UIParent)
    frame:SetSize(640, 520)
    frame:Hide()
    frame.OnCommit = function() end
    frame.OnDefault = function()
        DB.ResetOptions()
        Settings.Refresh()
    end
    frame.OnRefresh = function()
        Settings.Refresh()
    end
    frame:SetScript("OnShow", function()
        Settings.Refresh()
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    title:SetText(NW.L("TITLE"))

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -10)
    version:SetText(NW.L("VERSION", NW.VERSION))

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    subtitle:SetWidth(600)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(NW.L("SUBTITLE"))

    local tabPlayers = makeTab(frame, "TAB_PLAYERS", "players", 8)
    local tabOptions = makeTab(frame, "TAB_OPTIONS", "options", 112)
    tabPlayers:SetScript("OnClick", function()
        setPage("players")
        tabPlayers:SetAlpha(1)
        tabOptions:SetAlpha(0.6)
    end)
    tabOptions:SetScript("OnClick", function()
        setPage("options")
        tabPlayers:SetAlpha(0.6)
        tabOptions:SetAlpha(1)
    end)
    tabPlayers:SetAlpha(1)
    tabOptions:SetAlpha(0.6)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -84)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

    playersPage = buildPlayersPage(content)
    optionsPage = buildOptionsPage(content)
    setPage("players")

    local category = api.RegisterCanvasLayoutCategory(frame, NW.L("TITLE"))
    api.RegisterAddOnCategory(category)
    Settings.category = category
end
