-- NinjaWatcher - 全需党规避器
-- Tooltip.lua: one local line on a player's mouseover tooltip.
--
-- The line is local. It never sends chat and never changes another addon's
-- tooltip content. When a scan finishes, the existing line is updated in
-- place if the same tooltip is still visible.

local ADDON, NW = ...

local Tooltip = {}
NW.Tooltip = Tooltip

local Stats, Scan, Rate, DB = NW.Stats, NW.Scan, NW.Rate, NW.DB
local shown = nil

-- Resolved on use so a missing or swapped locale never freezes the label.
local function labelText()
    return NW.L("TOOLTIP_LABEL")
end

local function secret(value)
    return NW.IsSecret(value)
end

local function lineText(index)
    return _G["GameTooltipTextLeft" .. index]
end

local function rightText(index)
    return _G["GameTooltipTextRight" .. index]
end

local function findLabelLine(tooltip)
    if not tooltip or type(tooltip.NumLines) ~= "function" then return nil end
    for i = 1, tooltip:NumLines() do
        local fs = lineText(i)
        if fs and fs.GetText and fs:GetText() == labelText() then
            return i
        end
    end
    return nil
end

local function setRight(tooltip, index, text, color)
    local right = rightText(index)
    if not right then return false end
    right:SetText(text)
    right:SetTextColor(color[1], color[2], color[3])
    right:Show()
    return true
end

local function addDouble(tooltip, text, color)
    local from = tooltip:NumLines() + 1
    tooltip:AddDoubleLine(labelText(), text, 1, 1, 1, color[1], color[2], color[3])
    return from
end

local function addDetail(tooltip, text)
    local from = tooltip:NumLines() + 1
    tooltip:AddLine(text, 0.65, 0.65, 0.65)
    return from
end

local function statusKey(status)
    if status == "PENDING" then return "TOOLTIP_PENDING" end
    if status == "FAR" then return "TOOLTIP_STATUS_FAR" end
    if status == "BUSY" then return "TOOLTIP_STATUS_BUSY" end
    if status == "COMBAT" then return "TOOLTIP_STATUS_COMBAT" end
    if status == "NOAPI" then return "TOOLTIP_STATUS_NOAPI" end
    if status == "TIMEOUT" then return "TOOLTIP_STATUS_TIMEOUT" end
    if status == "NODATA" then return "TOOLTIP_STATUS_NODATA" end
    return "TOOLTIP_UNKNOWN"
end

local function retryKey(status)
    if status == "FAR" or status == "BUSY" or status == "COMBAT"
        or status == "TIMEOUT" or status == "NODATA" then
        return "TOOLTIP_STATUS_RETRY"
    end
    return nil
end

local function compose(row)
    local result = Rate.Evaluate(row)
    if result.status == "unknown" then
        local field, quality = tostring(result.reason or ""):match("^([^:]+):(.+)$")
        return NW.L("TOOLTIP_UNKNOWN"),
            NW.L("TOOLTIP_UNKNOWN_FIELD", Rate.FieldLabel(field or "?"),
                Rate.QualityLabel(quality or "unknown")),
            NW.COLORS.gray
    end
    if result.status == "insufficient" then
        return NW.L("TOOLTIP_INSUFFICIENT"),
            NW.L("TOOLTIP_INSUFFICIENT_DETAIL", NW.RULE.grayBelowEntries),
            NW.COLORS.gray
    end
    if result.branch == "pass" then
        return NW.L("TOOLTIP_PASS"),
            NW.L("TOOLTIP_PASS_DETAIL", result.rolls, result.threshold, result.entries),
            NW.COLORS.darkgreen
    end
    local band = result.band or "gray"
    local label = NW.L(Rate.BandLabelKey(band))
    local detail = NW.L("TOOLTIP_SAMPLE", row.need, row.greed, row.entries, result.rolls)
    if result.redCapped then
        detail = detail .. " · " .. NW.L("TOOLTIP_RED_CAP")
    end
    return NW.L("TOOLTIP_RATE", (result.ratio or 0) * 100, label), detail, Rate.Color(band)
end

local function paint(tooltip, row, identity, status)
    if not tooltip then return end
    local text, detail, color
    if row then
        text, detail, color = compose(row)
    else
        text = NW.L(statusKey(status))
        color = NW.COLORS.gray
        local retry = retryKey(status)
        if retry then detail = NW.L(retry) end
    end

    local line = findLabelLine(tooltip)
    if line then
        setRight(tooltip, line, text, color)
    else
        line = addDouble(tooltip, text, color)
    end
    local detailLine = nil
    local sameUnit = shown and shown.tooltip == tooltip
        and shown.guid == (identity and identity.guid or nil)
    if detail then
        local nextIndex = line + 1
        local left = lineText(nextIndex)
        if left and sameUnit and shown.detail == nextIndex then
            left:SetText(detail)
            left:SetTextColor(0.65, 0.65, 0.65)
            left:Show()
            detailLine = nextIndex
        else
            detailLine = addDetail(tooltip, detail)
        end
    elseif sameUnit and shown.detail then
        local old = lineText(shown.detail)
        if old then
            old:SetText("")
            old:Hide()
        end
    end
    shown = {
        tooltip = tooltip,
        guid = identity and identity.guid or nil,
        identity = identity,
        line = line,
        detail = detailLine,
        status = row and "READY" or status,
    }
end

function Tooltip.Paint(tooltip, row, identity)
    paint(tooltip, row, identity, "READY")
end

function Tooltip.PaintStatus(tooltip, status, identity)
    paint(tooltip, nil, identity, status)
end

local function refresh(guid, row, status)
    if not shown or not guid or shown.guid ~= guid then return end
    local tooltip = shown.tooltip or GameTooltip
    if not tooltip or not tooltip.IsShown or not tooltip:IsShown() then return end
    local line = findLabelLine(tooltip)
    if not line then
        local mouse = UnitGUID("mouseover")
        if not secret(mouse) and mouse == guid and shown.identity then
            paint(tooltip, row, shown.identity, status)
        end
        return
    end
    if status == "READY" and row then
        local text, detail, color = compose(row)
        setRight(tooltip, line, text, color)
        if detail then
            local detailIndex = line + 1
            local left = lineText(detailIndex)
            if left and shown.detail == detailIndex then
                left:SetText(detail)
                left:SetTextColor(0.65, 0.65, 0.65)
                left:Show()
            else
                shown.detail = addDetail(tooltip, detail)
            end
        end
        shown.status = "READY"
    else
        local text = NW.L(statusKey(status))
        setRight(tooltip, line, text, NW.COLORS.gray)
        local retry = retryKey(status)
        if retry then
            local detailIndex = line + 1
            local left = lineText(detailIndex)
            if left and shown.detail == detailIndex then
                left:SetText(NW.L(retry))
                left:Show()
            else
                shown.detail = addDetail(tooltip, NW.L(retry))
            end
        elseif shown.detail then
            local old = lineText(shown.detail)
            if old then
                old:SetText("")
                old:Hide()
            end
            shown.detail = nil
        end
        shown.status = status
    end
end

local function liveUnit(value)
    if secret(value) or type(value) ~= "string" or value == "" then return nil end
    local ok, exists = Stats.SafeCall(UnitExists, value)
    if ok and exists then return value end
    return nil
end

-- A vanilla tooltip hands back the unit token; this client hands back the
-- unit's name first and the token second. Take whichever one names a unit
-- that exists, so neither shape is read as a token by mistake.
local function tooltipUnit(tooltip)
    local ok, first, second = pcall(tooltip.GetUnit, tooltip)
    if not ok then return nil end
    return liveUnit(second) or liveUnit(first)
end

function Tooltip.OnUnit(tooltip)
    if tooltip ~= GameTooltip then return end
    if not DB.Get("tooltip") then return end

    local unit = tooltipUnit(tooltip) or "mouseover"

    local identity, why = Stats.UnitIdentity(unit)
    if not identity then
        if why == "hidden" then
            Tooltip.PaintStatus(tooltip, "NODATA", { guid = nil })
        end
        return
    end
    if not identity.isPlayer then return end

    if identity.isSelf then
        if not DB.Get("selfTooltip") then return end
        local row = Stats.SelfRow()
        if row and Stats.RowUsable(row) then
            Tooltip.Paint(tooltip, row, identity)
        else
            Tooltip.PaintStatus(tooltip, "NODATA", identity)
        end
        return
    end

    local row, status = Scan.Request(unit, { front = true, priority = false })
    if row then
        Tooltip.Paint(tooltip, row, identity)
    elseif status then
        Tooltip.PaintStatus(tooltip, status, identity)
    end
end

local installed = false

function Tooltip.Init()
    if installed then return end
    installed = true

    Scan.OnReady(function(guid, row, status)
        refresh(guid, row, status)
    end)

    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function()
            shown = nil
        end)
    end

    if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        local ok = pcall(TooltipDataProcessor.AddTooltipPostCall,
            Enum.TooltipDataType.Unit, function(tooltip)
                Tooltip.OnUnit(tooltip)
            end)
        if ok then
            Tooltip.mode = "processor"
            return
        end
    end

    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            Tooltip.OnUnit(tooltip)
        end)
        if ok then
            Tooltip.mode = "script"
        end
    end

    if not Tooltip.mode then
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        watcher:SetScript("OnEvent", function()
            if GameTooltip and GameTooltip:IsShown() then
                Tooltip.OnUnit(GameTooltip)
            end
        end)
        Tooltip.mode = "event"
    end
end
