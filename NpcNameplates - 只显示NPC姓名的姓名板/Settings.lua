-- NpcNameplates - 设置页
-- 注册在 设置 → 插件 → NpcNameplates；六项：名字字号、名字垂直偏移、<头衔> 行开关、
-- 姓名板堆叠开关、靠近放大开关、三个阵营各自的颜色。
-- 布局：所有控件按上一块的实际高度依次往下排（文本高度用 GetStringHeight 量），避免文本串行。

local ADDON_NAME, ns = ...

local Settings = {}
ns.Settings = Settings

local TITLE = "NpcNameplates"
local WIDTH = 600
local LEFT = 8
local INDENT = 16

local frame, category
local scroll, content
local slider, sizeText, offsetSlider, offsetText, titleCheck, resetButton
local stackingCheck, stackingStatus
local scaleCheck, scaleStatus
local swatchRows = {}

local function db()
    return ns.EnsureDB()
end

-- ---------------------------------------------------------------- 小工具

local function NewText(parent, template, text, x, y, width)
    local t = parent:CreateFontString(nil, "OVERLAY", template)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetWidth(width or WIDTH)
    t:SetJustifyH("LEFT")
    t:SetText(text)
    return t
end

-- FontString 的实际排版高度；量不出来时给个保守值，宁可多留白。
local function TextHeight(t, fallback)
    local ok, h = pcall(t.GetStringHeight, t)
    if ok and type(h) == "number" and h > 0 then return h end
    return fallback or 15
end

local function RGBText(c)
    return ("R %.0f%%  G %.0f%%  B %.0f%%   #%02X%02X%02X"):format(
        c.r * 100, c.g * 100, c.b * 100,
        math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function Apply()
    if ns.ApplyAll then
        ns.ApplyAll()
    end
end

-- ---------------------------------------------------------------- 控件更新

local function UpdateSwatch(row)
    local c = db()[row.key]
    if row.tex then
        row.tex:SetColorTexture(c.r, c.g, c.b, 1)
    end
    if row.valueText then
        row.valueText:SetText(RGBText(c))
    end
end

-- 勾选框显示「当前生效值」；来源标注是插件接管还是跟随游戏原生。
local function RefreshStacking()
    if not stackingCheck then return end
    local enemy = ns.GetStacking and ns.GetStacking(true) or false
    local friendly = ns.GetStacking and ns.GetStacking(false) or false
    stackingCheck:SetChecked(enemy and friendly)
    if stackingStatus then
        stackingStatus:SetFormattedText("当前：敌方单位 %s · 友方单位 %s（%s）",
            enemy and "开" or "关", friendly and "开" or "关",
            db().stacking == nil and "跟随游戏原生设置" or "插件设定")
    end
end

-- 靠近放大：读当前生效值（含插件临时值）与来源。
local function RefreshScale()
    if not scaleCheck then return end
    local on, min, max
    if ns.GetScaleEnabled then
        on, min, max = ns.GetScaleEnabled()
    else
        on, min, max = true, 1, 1
    end
    scaleCheck:SetChecked(on and true or false)
    if scaleStatus then
        scaleStatus:SetFormattedText("当前：%s（近 %.2f 倍 / 远 %.2f 倍，%s）",
            on and "开启" or "关闭", max, min,
            db().scaleEnabled == nil and "跟随游戏原生设置" or "插件设定")
    end
end

local function UpdateControls()
    if not frame then return end
    if slider then slider:SetValue(db().fontSize) end
    if sizeText then sizeText:SetFormattedText("%.1f", db().fontSize) end
    if offsetSlider then offsetSlider:SetValue(db().offsetY) end
    if offsetText then offsetText:SetFormattedText("%d", db().offsetY) end
    if titleCheck then titleCheck:SetChecked(db().showTitle and true or false) end
    RefreshStacking()
    RefreshScale()
    for i = 1, #swatchRows do
        UpdateSwatch(swatchRows[i])
    end
end

local function ResetToDefaults()
    local d = ns.DEFAULTS
    local ddb = db()
    ddb.fontSize = d.fontSize
    ddb.offsetY = d.offsetY
    ddb.showTitle = d.showTitle
    for _, key in ipairs({ "color", "colorEnemy", "colorNeutral" }) do
        local c = ddb[key]
        c.r, c.g, c.b = d[key].r, d[key].g, d[key].b
    end
    -- 两个客户端开关恢复为「跟随游戏原生设置」：摘掉临时值，什么都不写进客户端。
    ddb.stacking = nil
    ddb.scaleEnabled = nil
    ddb.scaleMin = nil
    ddb.scaleMax = nil
    if ns.ApplyCVarPrefs then
        ns.ApplyCVarPrefs()
    end
    UpdateControls()
    Apply()
end

-- ---------------------------------------------------------------- 各区块

local function BuildFontSize(parent, y)
    NewText(parent, "GameFontNormal", "名字字号", INDENT, y, 200)
    y = y - 22

    slider = _G.NpcNameplatesFontSizeSlider
    if slider then
        slider:ClearAllPoints()
        slider:SetParent(parent)
        slider:Show()
    else
        slider = CreateFrame("Slider", "NpcNameplatesFontSizeSlider", parent, "OptionsSliderTemplate")
    end
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT, y)
    slider:SetWidth(300)
    slider:SetHeight(18)
    slider:SetMinMaxValues(10, 30)
    slider:SetValueStep(0.5)
    pcall(slider.SetObeyStepOnDrag, slider, true)
    slider:SetScript("OnValueChanged", function(self, value)
        local v = math.floor(value * 2 + 0.5) / 2
        db().fontSize = v
        if sizeText then sizeText:SetFormattedText("%.1f", v) end
        Apply()
    end)

    local low = _G["NpcNameplatesFontSizeSliderLow"]
    local high = _G["NpcNameplatesFontSizeSliderHigh"]
    if low then low:SetText("10") end
    if high then high:SetText("30") end

    sizeText = NewText(parent, "GameFontHighlight", "", INDENT + 320, y - 1, 60)
    sizeText:SetJustifyH("LEFT")

    y = y - 36
    local hint = NewText(parent, "GameFontHighlightSmall",
        "客户端原生字号为 17.5。友方、敌方、中立 NPC 都用这一字号；玩家姓名板与玩家控制的单位（宠物/图腾等）不受影响。",
        INDENT, y, WIDTH - INDENT)
    return y - TextHeight(hint) - 14
end

local function BuildOffset(parent, y)
    NewText(parent, "GameFontNormal", "名字垂直偏移", INDENT, y, 200)
    y = y - 22

    offsetSlider = _G.NpcNameplatesOffsetSlider
    if offsetSlider then
        offsetSlider:ClearAllPoints()
        offsetSlider:SetParent(parent)
        offsetSlider:Show()
    else
        offsetSlider = CreateFrame("Slider", "NpcNameplatesOffsetSlider", parent, "OptionsSliderTemplate")
    end
    offsetSlider:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT, y)
    offsetSlider:SetWidth(300)
    offsetSlider:SetHeight(18)
    offsetSlider:SetMinMaxValues(-40, 40)
    offsetSlider:SetValueStep(1)
    pcall(offsetSlider.SetObeyStepOnDrag, offsetSlider, true)
    offsetSlider:SetScript("OnValueChanged", function(self, value)
        local v = math.floor(value + 0.5)
        db().offsetY = v
        if offsetText then offsetText:SetFormattedText("%d", v) end
        Apply()
    end)

    local low = _G["NpcNameplatesOffsetSliderLow"]
    local high = _G["NpcNameplatesOffsetSliderHigh"]
    if low then low:SetText("-40") end
    if high then high:SetText("40") end

    offsetText = NewText(parent, "GameFontHighlight", "", INDENT + 320, y - 1, 60)

    y = y - 36
    local hint = NewText(parent, "GameFontHighlightSmall",
        "以「姓名板」为参照上下挪动名字：0 = 姓名板正中，负值往下（更贴近人物），正值往上。"
        .. "头衔行跟着名字一起走。",
        INDENT, y, WIDTH - INDENT)
    return y - TextHeight(hint) - 14
end

local function BuildTitleToggle(parent, y)
    titleCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    titleCheck:SetSize(26, 26)
    titleCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y + 4)
    titleCheck:SetScript("OnClick", function(self)
        db().showTitle = self:GetChecked() and true or false
        Apply()
    end)

    -- 勾选框自带的名牌文本在匿名帧上取不到，这里自己放一个标签。
    NewText(parent, "GameFontNormal", "在名字下方显示 <头衔> 行", 42, y, WIDTH - 50)

    y = y - 26
    local hint = NewText(parent, "GameFontHighlightSmall",
        "例如 <锻造供应商>、<馅饼商人>。字号为名字字号的 0.8 倍，颜色与名字相同；"
        .. "没有头衔的 NPC 不显示这一行。",
        42, y, WIDTH - 50)
    return y - TextHeight(hint) - 14
end

local function BuildStacking(parent, y)
    if not (ns.CVarSwitchAvailable and ns.CVarSwitchAvailable()) then
        return y
    end

    NewText(parent, "GameFontNormal", "姓名板堆叠", INDENT, y, 200)
    y = y - 24

    stackingCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    stackingCheck:SetSize(26, 26)
    stackingCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y + 4)
    stackingCheck:SetScript("OnClick", function(self)
        db().stacking = self:GetChecked() and true or false
        if ns.ApplyCVarPrefs then ns.ApplyCVarPrefs() end
        RefreshStacking()
    end)

    NewText(parent, "GameFontNormal", "堆叠姓名板", 42, y, WIDTH - 50)

    y = y - 26
    stackingStatus = NewText(parent, "GameFontHighlightSmall", "", 42, y, WIDTH - 50)

    y = y - 18
    local hint = NewText(parent, "GameFontHighlightSmall",
        "开启后姓名板垂直堆叠以避免互相重叠（敌方单位、友方单位一起开或一起关）。"
        .. "与 设置 → 姓名板 里的「堆叠姓名板」控制同一个客户端数值。插件只在本进程内用临时值覆盖，"
        .. "不写入游戏配置文件；卸载插件后立刻回到游戏原生设置。「恢复默认」= 交还给游戏原生设置。",
        42, y, WIDTH - 50)
    return y - TextHeight(hint) - 14
end

local function BuildScale(parent, y)
    if not (ns.CVarSwitchAvailable and ns.CVarSwitchAvailable()) then
        return y
    end

    NewText(parent, "GameFontNormal", "靠近放大", INDENT, y, 200)
    y = y - 24

    scaleCheck = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    scaleCheck:SetSize(26, 26)
    scaleCheck:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y + 4)
    scaleCheck:SetScript("OnClick", function(self)
        db().scaleEnabled = self:GetChecked() and true or false
        if ns.ApplyCVarPrefs then ns.ApplyCVarPrefs() end
        RefreshScale()
    end)

    NewText(parent, "GameFontNormal", "靠近 NPC 时放大姓名板", 42, y, WIDTH - 50)

    y = y - 26
    scaleStatus = NewText(parent, "GameFontHighlightSmall", "", 42, y, WIDTH - 50)

    y = y - 18
    local hint = NewText(parent, "GameFontHighlightSmall",
        "客户端按距离缩放姓名板：近距离用最大缩放（默认 1.00 倍），远距离缩到最小缩放（默认 0.80 倍），"
        .. "所以走近时会放大。关闭后把最小缩放临时抬到与最大缩放相同，远近保持同一倍率。"
        .. "插件只在本进程内用临时值覆盖 nameplateMinScale，不写入游戏配置文件；"
        .. "卸载插件后立刻回到游戏原生设置。",
        42, y, WIDTH - 50)
    return y - TextHeight(hint) - 14
end

local function BuildColorRow(parent, y, key, labelText, defaultTip)
    NewText(parent, "GameFontNormal", labelText, INDENT, y, 120)

    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(48, 18)
    swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", INDENT + 130, y - 1)
    local tex = swatch:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(swatch)
    local border = swatch:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", swatch, "TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.8)
    border:SetDrawLayer("BORDER", -1)

    local valueText = NewText(parent, "GameFontHighlightSmall", "", INDENT + 190, y, WIDTH - INDENT - 190)

    local row = { key = key, label = labelText, swatch = swatch, tex = tex, valueText = valueText }
    swatchRows[#swatchRows + 1] = row
    UpdateSwatch(row)

    swatch:SetScript("OnClick", function()
        local c = db()[key]
        local previous = { r = c.r, g = c.g, b = c.b }
        local info = {
            r = c.r,
            g = c.g,
            b = c.b,
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                c.r, c.g, c.b = r, g, b
                UpdateSwatch(row)
                Apply()
            end,
            cancelFunc = function()
                c.r, c.g, c.b = previous.r, previous.g, previous.b
                UpdateSwatch(row)
                Apply()
            end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    local tip = NewText(parent, "GameFontHighlightSmall", "默认 " .. defaultTip, INDENT + 190, y - 16,
        WIDTH - INDENT - 190)
    return y - 20 - TextHeight(tip) - 10
end

local function BuildColors(parent, y)
    y = BuildColorRow(parent, y, "color", "友方 NPC 颜色", "#00FF00（亮绿）")
    y = BuildColorRow(parent, y, "colorEnemy", "敌方 NPC 颜色", "#8C0000（深红）")
    y = BuildColorRow(parent, y, "colorNeutral", "中立 NPC 颜色", "#FFD100（黄）")
    local hint = NewText(parent, "GameFontHighlightSmall",
        "点色块打开取色器。名字与 <头衔> 行使用同一颜色。",
        INDENT, y, WIDTH - INDENT)
    return y - TextHeight(hint) - 10
end

-- ---------------------------------------------------------------- 面板

local Build  -- 先声明：滚动区的 OnSizeChanged 要用到

-- 客户端的设置画布会把本帧拉伸到它的可视区大小（宽度/高度都不是我们说了算），
-- 内容比可视区高时不会裁剪，会直接画到面板外面。所以内容全部放进滚动区：
-- 可视尺寸由设置窗口决定，内容高度由排版决定，超出部分滚动查看。
-- 上一版（没有滚动区时）把控件直接挂在 frame 上；热重载后这些旧控件要清走，
-- 否则会和滚动区里的新控件叠在一起。
local function ClearFrameDirectChildren()
    local trash = _G.NpcNameplatesTrash
    if not trash then
        trash = CreateFrame("Frame", "NpcNameplatesTrash", UIParent)
        _G.NpcNameplatesTrash = trash
    end
    trash:Hide()
    local kids = { frame:GetChildren() }
    for i = 1, #kids do
        local k = kids[i]
        if k ~= scroll then
            k:ClearAllPoints()
            k:SetParent(trash)
        end
    end
    local regs = { frame:GetRegions() }
    for i = 1, #regs do
        regs[i]:ClearAllPoints()
        regs[i]:SetParent(trash)
    end
end

local function OnScrollSized(self)
    content:SetWidth(math.max(200, self:GetWidth()))
    -- 画布第一次给我们尺寸时按真实宽度重新排版（文字换行会变）。
    if frame and frame:IsShown() then Build() end
end

local function EnsureScroll()
    scroll = _G.NpcNameplatesScrollFrame
    content = _G.NpcNameplatesContentFrame
    if scroll and content then
        pcall(scroll.SetScrollChild, scroll, content)
        -- 脚本要换成这一版的闭包，否则热重载后仍在调上一版的 Build。
        scroll:SetScript("OnSizeChanged", OnScrollSized)
        ClearFrameDirectChildren()
        return
    end

    scroll = CreateFrame("ScrollFrame", "NpcNameplatesScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -26, 1)

    content = CreateFrame("Frame", "NpcNameplatesContentFrame", scroll)
    content:SetSize(540, 400)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", OnScrollSized)

    ClearFrameDirectChildren()
end

local function ClearFrame(f)
    local trash = _G.NpcNameplatesTrash
    if not trash then
        trash = CreateFrame("Frame", "NpcNameplatesTrash", UIParent)
        _G.NpcNameplatesTrash = trash
    end
    trash:Hide()
    local kids = { f:GetChildren() }
    for i = 1, #kids do
        kids[i]:ClearAllPoints()
        kids[i]:SetParent(trash)
    end
    local regs = { f:GetRegions() }
    for i = 1, #regs do
        regs[i]:ClearAllPoints()
        regs[i]:SetParent(trash)
    end
end

function Build()
    local parent = content or frame
    ClearFrame(parent)
    swatchRows = {}
    stackingCheck = nil
    stackingStatus = nil
    scaleCheck = nil
    scaleStatus = nil

    -- 内容宽度跟随滚动区实际宽度：设置窗口大小和 UI 缩放不同，可用宽度也不同。
    -- 文本从 x=8 起排，宽度取「可用宽度 - 12」，右边留一点余量，避免最后一行贴到裁剪边。
    local okW, cw = pcall(parent.GetWidth, parent)
    if okW and type(cw) == "number" and cw >= 200 then
        WIDTH = cw - 12
    end

    local title = NewText(parent, "GameFontNormalLarge", TITLE, LEFT, -8, WIDTH)
    local y = -8 - TextHeight(title) - 10

    local desc = NewText(parent, "GameFontHighlightSmall",
        "把暴雪只给「友方玩家」的「仅显示名字」同步给 NPC：友方、敌方、中立 NPC 的姓名板都只显示名字，"
        .. "不显示血条、血量数字与等级；施法条保留。\n"
        .. "玩家姓名板与玩家控制的单位（宠物/图腾等）完全不碰。所有设置都只存在插件自己的存档里；"
        .. "两个客户端开关只用临时值覆盖、不写入游戏配置文件，卸载插件后游戏立刻恢复原生。\n"
        .. "使用前提：设置 → 姓名板 里开启对应阵营的姓名板（友方 NPC 需勾选「友方NPC姓名板」）。",
        LEFT, y, WIDTH)
    desc:SetSpacing(3)
    y = y - TextHeight(desc, 48) - 18

    y = BuildFontSize(parent, y)
    y = BuildOffset(parent, y)
    y = BuildTitleToggle(parent, y)
    y = BuildStacking(parent, y)
    y = BuildScale(parent, y)
    y = BuildColors(parent, y)

    resetButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetButton:SetSize(140, 24)
    resetButton:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y - 6)
    resetButton:SetText("恢复默认")
    resetButton:SetScript("OnClick", ResetToDefaults)

    -- 画布给的框高度由设置窗口决定；内容多高由排版决定，超出部分靠滚动区查看。
    -- 恢复默认按钮在 y-6 处、高 24，内容高度要把按钮底部（y-30）也包进来，再留 16 的底部空白。
    if content then
        content:SetHeight(-y + 46)
    end
    if scroll and scroll.UpdateScrollChildRect then
        pcall(scroll.UpdateScrollChildRect, scroll)
    end
    UpdateControls()
end

local function OnPanelShow()
    if scroll then
        pcall(scroll.SetVerticalScroll, scroll, 0)
    end
    UpdateControls()
end

function Settings.Open()
    if not frame then return end
    local api = _G.Settings
    if api and api.OpenToCategory and category and category.GetID then
        pcall(api.OpenToCategory, category:GetID())
    end
end

function Settings.Init()
    local api = _G.Settings
    if type(api) ~= "table" or type(api.RegisterCanvasLayoutCategory) ~= "function"
        or type(api.RegisterAddOnCategory) ~= "function" then
        return
    end

    -- 热重载（工坊 load）时面板和分类都还在：清空内容重建，沿用原分类，不再重复注册。
    if _G.NpcNameplatesSettingsFrame then
        frame = _G.NpcNameplatesSettingsFrame
        category = frame.nnpCategory
        Settings.category = category
        -- 分类名在登录时已按 TITLE 注册；热重载换了 TITLE 就要就地改名（侧栏随之刷新）。
        if category and category.SetName then
            pcall(category.SetName, category, TITLE)
        end
        frame:SetScript("OnShow", nil)
        frame.OnRefresh = nil
        frame.OnDefault = nil
        EnsureScroll()
        Build()
        frame.OnRefresh = UpdateControls
        frame.OnDefault = ResetToDefaults
        frame:SetScript("OnShow", OnPanelShow)
        return
    end

    frame = CreateFrame("Frame", "NpcNameplatesSettingsFrame", UIParent)
    frame:SetSize(640, 420)
    frame:Hide()
    EnsureScroll()
    Build()

    frame.OnRefresh = UpdateControls
    frame.OnDefault = ResetToDefaults
    frame:SetScript("OnShow", OnPanelShow)

    category = api.RegisterCanvasLayoutCategory(frame, TITLE)
    api.RegisterAddOnCategory(category)
    frame.nnpCategory = category
    Settings.category = category
end

-- 正常登录走 ADDON_LOADED；工坊热更不会触发那个事件，这里补一次。
pcall(Settings.Init)
