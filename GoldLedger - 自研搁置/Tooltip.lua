-- 金账簿 - Tooltip.lua
-- 悬停提示框集成。
--
-- 我们只往 GameTooltip 上【追加】行，绝不清空它，也绝不替换原生锚点。
--
-- 与 GGS 的一处有意不同：免责声明【就在 tooltip 里】，不只在报告里。
-- 两三个字的判定词单独出现时最容易被当成结论，所以这句必须跟着它一起出现。

local ADDON_NAME, GL = ...
local Tooltip = {}
GL.Tooltip = Tooltip
local S = GL.Secrets
local Stats, Scan, Judge = GL.Stats, GL.Scan, GL.Judge

local shown   -- { guid, unit, from, status }

local GRAY = "|cff9aa0a6"
local GRAY_END = "|r"

--------------------------------------------------------------------
-- 内容
--------------------------------------------------------------------

function Tooltip.Compose(row)
    local lines = {
        { GL.L.TAG, Judge.Colored(row.verdict) },
        { "峰值", Stats.FormatMoney(row.peak) },
    }
    if GL.Config.Get("tipDisclaimer") then
        lines[#lines + 1] = { GRAY .. GL.L.DISCLAIMER .. GRAY_END }
    end
    return lines
end

local function addLines(tooltip, lines)
    for _, line in ipairs(lines) do
        if line[2] then
            tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
        else
            tooltip:AddLine(line[1], 1, 1, 1)
        end
    end
end

local function paint(tooltip, row, id)
    local from = tooltip:NumLines() + 1
    addLines(tooltip, Tooltip.Compose(row))
    tooltip:Show()
    shown = { guid = id and id.guid or nil, unit = id and id.unit or nil, from = from }
end

local function paintStatus(tooltip, status, id)
    local word = GL.L.VERDICT[status]
    if not word then return end
    local from = tooltip:NumLines() + 1
    tooltip:AddDoubleLine(GL.L.TAG, Judge.Colored(status, word), 1, 1, 1, 1, 1, 1)
    tooltip:Show()
    shown = { guid = id and id.guid or nil, unit = id and id.unit or nil, from = from, status = status }
end

-- 扫描落地后【原地替换】那一行，而不是再加一行，避免提示框跳动
local function replaceInPlace(tooltip, lines)
    if not shown or not shown.from then return false end
    local left = _G["GameTooltipTextLeft" .. shown.from]
    local right = _G["GameTooltipTextRight" .. shown.from]
    if not left or not right or type(left.GetText) ~= "function" then return false end
    local ok, text = pcall(left.GetText, left)
    if not ok or text ~= GL.L.TAG then return false end
    if tooltip:NumLines() ~= shown.from then return false end

    if lines[1] and lines[1][2] then
        right:SetText(lines[1][2])
        if right.Show then right:Show() end
    end
    for i = 2, #lines do addLines(tooltip, { lines[i] }) end
    tooltip:Show()
    return true
end

function Tooltip.RefreshIfShowing(guid, row, status)
    if not shown or not guid or shown.guid ~= guid then return end
    local tooltip = GameTooltip
    if not tooltip or not tooltip:IsShown() then return end

    if status == "READY" and row then
        local lines = Tooltip.Compose(row)
        if not replaceInPlace(tooltip, lines) then
            addLines(tooltip, lines)
            tooltip:Show()
        end
        shown.status = nil
    elseif status == "FAR" then
        replaceInPlace(tooltip, { { GL.L.TAG, Judge.Colored("FAR") } })
        shown.status = "FAR"
    elseif status == "TIMEOUT" or status == "CANCELLED" or status == "BUSY"
        or status == "NODATA" or status == "COMBAT" then
        local reason
        if status == "TIMEOUT" then reason = "客户端没有回应。再悬停一次重试。"
        elseif status == "COMBAT" then reason = "离开战斗后再悬停一次。"
        else reason = "扫描不可用。再悬停一次重试。" end
        replaceInPlace(tooltip, { { GL.L.TAG, Judge.Colored("THIN") }, { GRAY .. reason .. GRAY_END } })
        shown.status = "THIN"
    end
end

--------------------------------------------------------------------
-- 挂钩
--------------------------------------------------------------------

local function tooltipUnit(tooltip)
    if not tooltip or type(tooltip.GetUnit) ~= "function" then return "mouseover" end
    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if ok and S.Text(unit) and unit ~= "" then return unit end
    return "mouseover"
end

function Tooltip.OnUnit(tooltip)
    if tooltip ~= GameTooltip then return end
    if not GL.Config.Get("hover") then return end

    local unit = tooltipUnit(tooltip)
    local id, why = GL.Core.Identity(unit)
    if not id then
        if why == "hidden" then paintStatus(tooltip, "HIDDEN") end
        return
    end
    id.unit = unit
    if not id.isPlayer then return end

    if id.isSelf then
        -- 悬停自己也显示（可选），但绝不走扫描——自己的数据直接读
        if GL.Config.Get("hoverSelf") then
            local row = Stats.SelfRow()
            if row then paint(tooltip, row, id) end
        end
        return
    end

    local row, status = Scan.Request(unit)
    if row then
        paint(tooltip, row, id)
    elseif status == "PENDING" or status == "FAR" or status == "HIDDEN" then
        paintStatus(tooltip, status, id)
    end
end

Scan.OnReady(function(guid, row, status)
    if status == "CLEARED" then
        if shown and GameTooltip then GameTooltip:Hide() end
        shown = nil
        return
    end
    Tooltip.RefreshIfShowing(guid, row, status)
end)

-- 优先用现代的数据处理器，其次老的脚本钩子，最后退回鼠标悬停事件
local function install()
    if type(TooltipDataProcessor) == "table"
        and type(TooltipDataProcessor.AddTooltipPostCall) == "function"
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            Tooltip.OnUnit(tooltip)
        end)
        Tooltip.mode = "processor"
        return
    end
    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tooltip)
            Tooltip.OnUnit(tooltip)
        end)
        if ok then Tooltip.mode = "script" return end
    end
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    watcher:SetScript("OnEvent", function()
        if GameTooltip and GameTooltip:IsShown() then Tooltip.OnUnit(GameTooltip) end
    end)
    Tooltip.mode = "event"
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    local ok, err = pcall(install)
    if not ok then GL.Print("tooltip 挂钩失败：" .. tostring(err)) end
end)

if GameTooltip and type(GameTooltip.HookScript) == "function" then
    pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function() shown = nil end)
end
