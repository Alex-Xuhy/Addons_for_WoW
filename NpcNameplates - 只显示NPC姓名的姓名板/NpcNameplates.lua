-- NpcNameplates - 只显示NPC姓名的姓名板
--
-- 暴雪原生只给"友方玩家"提供了「仅显示名字」(nameplateShowOnlyNameForFriendlyPlayerUnits)，
-- 友方 NPC 的姓名板没有对应选项，总是连血条一起画。
--
-- 客户端内部虽有 NamePlateSimplifiedType.FriendlyNpc 与
-- C_NamePlateManager.SetNamePlateSimplified()，但实测（1.60.1.70450）该接口
-- 不改变姓名板外观（UnitFrame.isSimplified 仍为 false），所以本插件改用
-- "逐个隐藏血条/等级/施法条等部件、只留名字 FontString" 的方式实现。
--
-- 玩家可在 设置 → 插件 → NpcNameplates 调整：
--   * 名字字号（默认 17.5，与客户端原生一致）
--   * 名字垂直偏移（默认 0 = 姓名板正中；正值往上）
--   * 是否在名字下方显示 <头衔> 行（默认显示；字号 = 名字字号 × 0.8）
--   * 友方/敌方/中立三个阵营各自的字体颜色（默认 #00FF00 / 深红 / 黄）
--   * 姓名板堆叠、靠近放大这两个客户端开关
--   * 以上所有选择都只保存在插件自己的存档 NpcNameplatesDB 里
--
-- 处理范围：友方/敌方/中立 NPC 都按同一套规则处理（只留名字 + 头衔行 + 字号），
-- 颜色按阵营区分。施法条不隐藏。玩家姓名板、以及玩家控制的单位
-- （友方玩家的宠物/图腾等）一律不碰。
--
-- 头衔来自客户端自己的提示框数据 C_TooltipInfo.GetUnit()：单位提示框第二行
-- 就是 NPC 的副标题（如「钥匙大师」「馅饼商人」）；没有副标题的单位第二行是
-- 「等级 N」，按 TOOLTIP_UNIT_LEVEL 的格式识别后跳过。
--
-- 配置全部插件化：本插件从不把设置写进客户端配置文件。两个客户端开关用
-- C_CVar.SetTempCVar 的临时值实现 —— 临时值只在本进程内生效、不写入 Config.wtf，
-- 退出游戏即消失；因此删掉插件文件夹后，游戏立刻回到原生状态，不需要任何清理。
--
-- 每 0.25 秒巡回一次：客户端在选中/刷新时会把部件重新显示，也会覆盖字号与颜色。

local ADDON_NAME, ns = ...

local DEFAULTS = {
    fontSize = 17.5,
    showTitle = true,
    offsetY = 0,                                        -- 名字在姓名板内的垂直偏移（正=上；0=正中）
    color = { r = 0.00, g = 1.00, b = 0.00 },           -- 友方：#00FF00
    colorEnemy = { r = 0.55, g = 0.00, b = 0.00 },      -- 敌方：深红 #8C0000
    colorNeutral = { r = 1.00, g = 0.82, b = 0.00 },    -- 中立：黄 #FFD100
}

ns.DEFAULTS = DEFAULTS

-- 只留名字：血条容器（含血条/数值/吸收条）、等级、等级差徽章、额外控件、光环、精英标记。
-- 施法条（CastBarsContainer）按用户要求保留，不在此列。
-- 名字 uf.name 是 uf 的直接子元素，不在这些容器里，不会被连带隐藏。
local HIDE = {
    "HealthBarsContainer",
    "PlayerLevelDiffFrame",
    "LevelFrame",
    "WidgetContainer",
    "AurasFrame",
    "ClassificationFrame",
}

local SUBTITLE_SCALE = 0.8
local PUMP_INTERVAL = 0.25

-- 每块姓名板的状态：{ stripped, reaction, guid, sub, subText, subRendered }
local state = setmetatable({}, { __mode = "k" })

-- 工坊热重载（load）只换代码、不销毁上一版建的 FontString：旧的名字/头衔会留在原位置，
-- 和新版叠成两份。这里登记本版创建的字串；文件载入时先把上一版登记的藏掉、清空文本。
local previousStrings = _G.NpcNameplatesOwnStrings
if type(previousStrings) == "table" then
    for i = 1, #previousStrings do
        local fs = previousStrings[i]
        if fs then
            pcall(fs.Hide, fs)
            pcall(fs.SetText, fs, "")
        end
    end
end
local ownStrings = {}
_G.NpcNameplatesOwnStrings = ownStrings

local db

local function EnsureDB()
    -- 若存档变量晚于本文件出现，就改用真正的存档表。
    if type(NpcNameplatesDB) ~= "table" then
        NpcNameplatesDB = {}
    end
    db = NpcNameplatesDB
    if type(db.fontSize) ~= "number" or db.fontSize < 6 or db.fontSize > 60 then
        db.fontSize = DEFAULTS.fontSize
    end
    if type(db.showTitle) ~= "boolean" then
        db.showTitle = DEFAULTS.showTitle
    end
    if type(db.offsetY) ~= "number" or db.offsetY < -40 or db.offsetY > 40 then
        db.offsetY = DEFAULTS.offsetY
    end
    -- 两个客户端开关的插件内偏好：nil = 跟随游戏原生设置，true/false = 由插件接管。
    if db.stacking ~= nil and type(db.stacking) ~= "boolean" then db.stacking = nil end
    if db.scaleEnabled ~= nil and type(db.scaleEnabled) ~= "boolean" then db.scaleEnabled = nil end
    -- 0.6.0 及更早版本的遗留字段（旧版直接写客户端缩放），迁移时用一次。
    if type(db.scaleMin) ~= "number" then db.scaleMin = nil end
    if type(db.scaleMax) ~= "number" then db.scaleMax = nil end
    for _, key in ipairs({ "color", "colorEnemy", "colorNeutral" }) do
        if type(db[key]) ~= "table" then
            db[key] = {}
        end
        local c, d = db[key], DEFAULTS[key]
        if type(c.r) ~= "number" or type(c.g) ~= "number" or type(c.b) ~= "number" then
            c.r, c.g, c.b = d.r, d.g, d.b
        end
    end
    ns.db = db
    return db
end

ns.EnsureDB = EnsureDB

-- ---------------------------------------------------------------- 客户端开关（临时值，不落盘）
-- 设置页里的两个客户端开关（姓名板堆叠 / 靠近放大）都只用「临时 CVar」：
-- C_CVar.SetTempCVar 的值只在本进程内生效、不写入 Config.wtf，退出游戏即消失。
-- 因此删掉插件之后，客户端读到的永远是它自己的原生设置；插件自己的选择
-- 记在 NpcNameplatesDB 里，登录时再用临时值应用（见 ns.ApplyCVarPrefs）。
--
-- 姓名板堆叠是位域 CVar nameplateStackingTypes（Enum.NamePlateStackType：
-- Enemy=1、Friendly=2）。1.60.1 把原始字节串按大端存成整数，索引 1 = 最低位、
-- 索引 2 = 次低位；其余高位是客户端/账号侧自己的状态，改写时原样保留。
local STACKING_CVAR = "nameplateStackingTypes"
local MIN_SCALE_CVAR = "nameplateMinScale"
local MAX_SCALE_CVAR = "nameplateMaxScale"
local SCHEMA = 2

local function CVarAPI()
    if type(C_CVar) == "table"
        and type(C_CVar.GetCVar) == "function"
        and type(C_CVar.SetTempCVar) == "function"
        and type(C_CVar.RemoveTempCVar) == "function" then
        return C_CVar
    end
    return nil
end

local function CVarsReady()
    local api = CVarAPI()
    if not api or type(api.AreCVarsLoaded) ~= "function" then return false end
    local ok, ready = pcall(api.AreCVarsLoaded)
    return ok and ready == true
end

function ns.CVarSwitchAvailable()
    local api = CVarAPI()
    return api ~= nil and type(api.GetCVarBitfield) == "function"
end

-- 大端字节串 ↔ 整数（最多用到 2^53 以内，double 足够）
local function RawToInt(raw)
    local n = 0
    for i = 1, #raw do
        n = n * 256 + string.byte(raw, i)
    end
    return n
end

local function IntToRaw(n)
    if n <= 0 then return "" end
    local bytes = {}
    while n > 0 do
        table.insert(bytes, 1, string.char(n % 256))
        n = math.floor(n / 256)
    end
    return table.concat(bytes)
end

-- enemy=true 读敌方单位，false 读友方单位；读的是「当前生效值」（含临时值）。
function ns.GetStacking(enemy)
    local api = CVarAPI()
    if not api or type(api.GetCVarBitfield) ~= "function" then return false end
    local ok, value = pcall(api.GetCVarBitfield, STACKING_CVAR, enemy and 1 or 2)
    return ok and value and true or false
end

-- 读出当前原始值，只改最低两位（1=敌方、2=友方），高位原样保留。
local function StackingRawFor(enemy, friendly)
    local api = CVarAPI()
    local ok, raw = pcall(api.GetCVar, STACKING_CVAR)
    local n = (ok and type(raw) == "string") and RawToInt(raw) or 0
    local want = (enemy and 1 or 0) + (friendly and 2 or 0)
    n = n - (n % 4) + want
    return IntToRaw(n)
end

local function ApplyStackingTemp(enemy, friendly)
    local api = CVarAPI()
    if not api then return false end
    pcall(api.SetTempCVar, STACKING_CVAR, StackingRawFor(enemy, friendly))
    if ns.GetStacking(true) ~= enemy or ns.GetStacking(false) ~= friendly then
        -- 退路：最简编码（1=敌方、2=友方、3=两者、空=都关）
        local bits = (enemy and 1 or 0) + (friendly and 2 or 0)
        pcall(api.SetTempCVar, STACKING_CVAR, bits == 0 and "" or string.char(bits))
    end
    return ns.GetStacking(true) == enemy and ns.GetStacking(false) == friendly
end

-- 靠近放大：客户端按距离在 nameplateMaxScale（近）与 nameplateMinScale（远）之间插值。
-- 关闭 = 把最小缩放临时抬到与最大缩放相同，远近恒定。
local function ScaleValues()
    local api = CVarAPI()
    if not api then return 1, 1 end
    local okMin, min = pcall(api.GetCVar, MIN_SCALE_CVAR)
    local okMax, max = pcall(api.GetCVar, MAX_SCALE_CVAR)
    min = okMin and tonumber(min) or 1
    max = okMax and tonumber(max) or 1
    return min, max
end

function ns.GetScaleEnabled()
    local min, max = ScaleValues()
    return (min < max - 1e-4), min, max
end

function ns.ClearCVarTemps()
    local api = CVarAPI()
    if not api then return end
    pcall(api.RemoveTempCVar, STACKING_CVAR)
    pcall(api.RemoveTempCVar, MIN_SCALE_CVAR)
end

-- 0.6.0 及更早把「靠近放大」直接写进了客户端配置：db.scaleMin 就是当初关掉之前的最小缩放。
-- 升级时把它写回客户端一次，之后这个开关只走临时值。
-- 「姓名板堆叠」是账号级存储（会同步到服务器），旧版没留下写前快照，分不清哪些位是插件
-- 写的，所以不擅自改写，插件这边按「跟随原生」处理。
local function MigrateLegacyDB()
    if db.schema == SCHEMA then return end
    local legacy = db.schema == nil
        and (type(db.fontSize) == "number" or type(db.offsetY) == "number"
            or type(db.showTitle) == "boolean" or type(db.color) == "table"
            or type(db.scaleMin) == "number" or type(db.scaleMax) == "number")
    db.schema = SCHEMA
    if not legacy then return end
    local api = CVarAPI()
    if api and type(api.SetCVar) == "function" and type(db.scaleMin) == "number" then
        local min, max = ScaleValues()
        if max > 0 then db.scaleEnabled = (min < max - 1e-4) end
        pcall(api.SetCVar, MIN_SCALE_CVAR, ("%.4f"):format(db.scaleMin))
    end
    db.scaleMin = nil
    db.scaleMax = nil
end

-- 把插件里的偏好应用到客户端（临时值）。nil = 不接管，交还给游戏原生设置。
function ns.ApplyCVarPrefs()
    if not CVarsReady() then return false end
    EnsureDB()
    MigrateLegacyDB()
    local api = CVarAPI()
    if not api then return false end

    if db.stacking == nil then
        pcall(api.RemoveTempCVar, STACKING_CVAR)
    else
        local want = db.stacking and true or false
        if ns.GetStacking(true) ~= want or ns.GetStacking(false) ~= want then
            ApplyStackingTemp(want, want)
        end
    end

    if db.scaleEnabled == nil then
        pcall(api.RemoveTempCVar, MIN_SCALE_CVAR)
    else
        local want = db.scaleEnabled and true or false
        local on, _, max = ns.GetScaleEnabled()
        if on ~= want then
            if want then
                local okD, d = pcall(api.GetCVarDefault, MIN_SCALE_CVAR)
                local restore = okD and tonumber(d) or nil
                if not restore or restore <= 0 or restore >= max - 1e-4 then
                    restore = max * 0.8
                end
                pcall(api.SetTempCVar, MIN_SCALE_CVAR, ("%.4f"):format(restore))
            else
                pcall(api.SetTempCVar, MIN_SCALE_CVAR, ("%.4f"):format(max))
            end
        end
    end
    return true
end

-- 阵营判定：返回 "friendly" / "enemy" / "neutral"；不属于处理范围时返回 nil。
-- 不处理的：玩家、玩家控制的单位（友方玩家的宠物/图腾/载具等，归玩家姓名板范畴）。
local function ReactionOf(unit)
    if type(unit) ~= "string" then return nil end
    if not UnitExists(unit) then return nil end
    if UnitIsPlayer(unit) then return nil end
    if type(UnitPlayerControlled) == "function" and UnitPlayerControlled(unit) then
        return nil
    end
    if UnitIsEnemy("player", unit) == true then return "enemy" end
    if UnitIsFriend("player", unit) == true then return "friendly" end
    return "neutral"
end

local function ReactionColor(reaction)
    local d = EnsureDB()
    if reaction == "enemy" then return d.colorEnemy end
    if reaction == "neutral" then return d.colorNeutral end
    return d.color
end

-- 从单位提示框取 NPC 副标题；没有副标题时返回 nil。
local function GetSubname(unit)
    if type(C_TooltipInfo) ~= "table" or type(C_TooltipInfo.GetUnit) ~= "function" then
        return nil
    end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    if not ok or type(data) ~= "table" then return nil end
    local lines = data.lines
    if type(lines) ~= "table" or #lines < 2 then return nil end
    local line = lines[2]
    if type(line) ~= "table" then return nil end
    local text = line.leftText
    if type(text) ~= "string" or text == "" then return nil end
    if issecretvalue and issecretvalue(text) then return nil end

    -- 第二行若就是等级行（TOOLTIP_UNIT_LEVEL = "等级 %s"），说明这个单位没有副标题。
    local format = _G.TOOLTIP_UNIT_LEVEL
    if type(format) == "string" then
        local level = UnitLevel(unit)
        local prefix = format:gsub("%%s$", "")
        if type(level) == "number" and level > 0
            and text == string.format(format, level) then
            return nil
        end
        if prefix ~= "" and text:sub(1, #prefix) == prefix then
            return nil
        end
    end
    return text
end

local function SameColor(r, g, b, c)
    if type(r) ~= "number" then return false end
    return math.abs(r - c.r) < 0.01
        and math.abs(g - c.g) < 0.01
        and math.abs(b - c.b) < 0.01
end

-- 名字：原生 uf.name 的位置由客户端每帧重排，从插件代码改它的锚点不生效（实测 SetPoint 后
-- 立刻被覆盖）；悬停时它还会被刷成白色。所以这里自己建一个 FontString 当名字，
-- 锚在姓名板的 CENTER 上，竖直偏移由设置项 offsetY 控制（正=上）；原生名字只用来读字体，然后隐藏。
local function ApplyName(plate, uf, st, c)
    local native = uf.name
    local label = st.label

    if not label then
        local baseFont, baseFlags = "Fonts\\ARKai_T.ttf", "OUTLINE, SLUG"
        if native then
            local okFont, f, _, fl = pcall(native.GetFont, native)
            if okFont and type(f) == "string" then
                baseFont, baseFlags = f, fl
            end
        end
        local ok, fs = pcall(function() return uf:CreateFontString(nil, "OVERLAY") end)
        if not ok or not fs then return nil, nil, nil end
        label = fs
        st.label = fs
        ownStrings[#ownStrings + 1] = fs
        st.baseFont, st.baseFlags = baseFont, baseFlags
        pcall(fs.SetFont, fs, baseFont, EnsureDB().fontSize, baseFlags)
    end

    -- 原生名字保持隐藏：留着会在悬停时闪白、也会跟自建名字重影。
    -- 透明度也压到 0：客户端悬停时会重新 Show 它，即使晚一帧才被藏，这一帧也看不见。
    if native then
        if native:IsShown() then pcall(native.Hide, native) end
        pcall(native.SetAlpha, native, 0)
    end

    local want = EnsureDB().fontSize
    local okFont, curFont, curSize, curFlags = pcall(label.GetFont, label)
    if not okFont or curFont ~= st.baseFont or type(curSize) ~= "number"
        or math.abs(curSize - want) > 0.01 or curFlags ~= st.baseFlags then
        pcall(label.SetFont, label, st.baseFont, want, st.baseFlags)
    end

    if type(st.nameText) == "string" and st.labelText ~= st.nameText then
        local okText = pcall(label.SetText, label, st.nameText)
        if okText then st.labelText = st.nameText end
    end

    pcall(label.ClearAllPoints, label)
    pcall(label.SetPoint, label, "CENTER", uf, "CENTER", 0, EnsureDB().offsetY)

    c = c or EnsureDB().color
    local okColor, r, g, b = pcall(label.GetTextColor, label)
    if not okColor or not SameColor(r, g, b, c) then
        pcall(label.SetTextColor, label, c.r, c.g, c.b)
    end
    return st.baseFont, want, st.baseFlags
end

-- 名字下方的 <头衔> 行。FontString 只建一次，挂在自建名字的下面。
local function ApplySubtitle(plate, uf, st, font, size, flags, c)
    local label = st.label
    local sub = st.sub
    if label == nil then return end

    if not EnsureDB().showTitle then
        if sub and sub:IsShown() then sub:Hide() end
        return
    end

    -- 姓名板会被回收给别的单位，单位代号（nameplate3）会重复使用，所以按 GUID 判断换人。
    local unit = plate.unitToken
    local guid = UnitGUID(unit)
    if st.guid ~= guid then
        st.guid = guid
        st.subText = GetSubname(unit)
    end
    local text = st.subText
    if not text then
        if sub and sub:IsShown() then sub:Hide() end
        return
    end

    if not sub then
        local ok, fs = pcall(function() return uf:CreateFontString(nil, "OVERLAY") end)
        if not ok or not fs then return end
        sub = fs
        st.sub = fs
        ownStrings[#ownStrings + 1] = fs
        pcall(sub.SetPoint, sub, "TOP", label, "BOTTOM", 0, -1)
    end

    -- 先设字体再设文本：新 FontString 没字体会让 SetText 直接失败（Font not set）。
    if type(font) == "string" and type(size) == "number" then
        local okFont, curFont, curSize, curFlags = pcall(sub.GetFont, sub)
        local wantSize = size * SUBTITLE_SCALE
        if not okFont or curFont ~= font or type(curSize) ~= "number"
            or math.abs(curSize - wantSize) > 0.01 or curFlags ~= flags then
            pcall(sub.SetFont, sub, font, wantSize, flags)
        end
    end
    local rendered = "<" .. text .. ">"
    if st.subRendered ~= rendered then
        local okText = pcall(sub.SetText, sub, rendered)
        if okText then st.subRendered = rendered end
    end
    c = c or EnsureDB().color
    local okColor, r, g, b = pcall(sub.GetTextColor, sub)
    if not okColor or not SameColor(r, g, b, c) then
        pcall(sub.SetTextColor, sub, c.r, c.g, c.b)
    end
    if not sub:IsShown() then sub:Show() end
end

-- 姓名板换人（同一块板被回收给别的单位）时，把当时藏起来的部件还给客户端。
local function Restore(uf, st)
    for i = 1, #HIDE do
        local f = uf[HIDE[i]]
        if f and not f:IsShown() then
            pcall(f.Show, f)
        end
    end
    local native = uf.name
    if native then
        pcall(native.SetAlpha, native, 1)
        if not native:IsShown() then
            pcall(native.Show, native)
        end
    end
    if st then
        if st.label and st.label:IsShown() then st.label:Hide() end
        if st.sub and st.sub:IsShown() then st.sub:Hide() end
        st.labelText = nil
    end
end

-- 对一块姓名板应用规则；返回阵营（"friendly"/"enemy"/"neutral"）或 nil（不在处理范围）。
local function ApplyPlate(plate)
    local uf = plate and plate.UnitFrame
    if not uf then return nil end
    local st = state[plate]
    local reaction = ReactionOf(plate.unitToken)

    if not reaction then
        if st and st.stripped then
            Restore(uf, st)
            st.stripped = nil
            st.guid = nil
            st.subText = nil
            st.nameText = nil
        end
        return nil
    end

    st = st or {}
    state[plate] = st
    st.reaction = reaction

    -- 姓名板会被回收给别的单位，单位代号（nameplate3）会重复使用，所以按 GUID 判断换人。
    local unit = plate.unitToken
    local guid = UnitGUID(unit)
    if st.guid ~= guid then
        st.guid = guid
        st.subText = GetSubname(unit)
        local okName, nameText = pcall(UnitName, unit)
        if okName and type(nameText) == "string" and not (issecretvalue and issecretvalue(nameText)) then
            st.nameText = nameText
        else
            st.nameText = nil
        end
    end

    for i = 1, #HIDE do
        local f = uf[HIDE[i]]
        if f and f:IsShown() then
            f:Hide()
        end
    end
    st.stripped = true

    local c = ReactionColor(reaction)
    local font, size, flags = ApplyName(plate, uf, st, c)
    ApplySubtitle(plate, uf, st, font, size, flags, c)
    return reaction
end

-- 每帧的轻量维护：客户端会在悬停/选中时把原生名字重新显示出来（并刷白），
-- 0.25 秒的巡回太慢会闪一下，所以这里每帧把原生名字按回去、顺手纠正颜色。
local function GuardTick()
    local plates = C_NamePlate.GetNamePlates()
    for i = 1, #plates do
        local plate = plates[i]
        local st = state[plate]
        if st and st.stripped then
            local uf = plate.UnitFrame
            if uf then
                -- 客户端在悬停/选中时会临时把原生名字和被藏起来的部件重新 Show 出来，
                -- 每帧按回去：否则会闪一下原生（白色）姓名板。
                for i = 1, #HIDE do
                    local f = uf[HIDE[i]]
                    if f and f:IsShown() then
                        pcall(f.Hide, f)
                    end
                end
                local native = uf.name
                if native then
                    if native:IsShown() then pcall(native.Hide, native) end
                    pcall(native.SetAlpha, native, 0)
                end
                local c = ReactionColor(st.reaction)
                local label = st.label
                if label then
                    local ok, r, g, b = pcall(label.GetTextColor, label)
                    if not ok or not SameColor(r, g, b, c) then
                        pcall(label.SetTextColor, label, c.r, c.g, c.b)
                    end
                end
                local sub = st.sub
                if sub then
                    local ok, r, g, b = pcall(sub.GetTextColor, sub)
                    if not ok or not SameColor(r, g, b, c) then
                        pcall(sub.SetTextColor, sub, c.r, c.g, c.b)
                    end
                end
            end
        end
    end
end

-- 返回 友方/敌方/中立 计数与总数。
local function ApplyAll()
    local plates = C_NamePlate.GetNamePlates()
    local friendly, enemy, neutral, total = 0, 0, 0, #plates
    for i = 1, total do
        local reaction = ApplyPlate(plates[i])
        if reaction == "friendly" then
            friendly = friendly + 1
        elseif reaction == "enemy" then
            enemy = enemy + 1
        elseif reaction == "neutral" then
            neutral = neutral + 1
        end
    end
    return friendly, enemy, neutral, total
end

ns.ApplyAll = ApplyAll

-- 具名帧：热重载（/reload 或工坊热更）时复用同一个帧，不会叠出第二个巡回。
local loader = _G.NpcNameplatesLoader or CreateFrame("Frame", "NpcNameplatesLoader")
_G.NpcNameplatesLoader = loader
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("NAME_PLATE_UNIT_ADDED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_LOGOUT")

loader:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        EnsureDB()
        if ns.Settings and ns.Settings.Init then
            pcall(ns.Settings.Init)
        end
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        local plate = C_NamePlate.GetNamePlateForUnit(arg1)
        if plate then ApplyPlate(plate) end
        return
    end
    if event == "PLAYER_LOGOUT" then
        -- 双保险：退出时把两个临时值摘掉，客户端存盘只会存它自己的原生值。
        ns.ClearCVarTemps()
        return
    end
    if db then
        ns.ApplyCVarPrefs()
        ApplyAll()
    end
end)

-- 巡回：客户端在选中/刷新时可能重新 Show 部件、重设字号与颜色，0.25 秒一次足够快。
local pump = _G.NpcNameplatesPump or CreateFrame("Frame", "NpcNameplatesPump")
_G.NpcNameplatesPump = pump
pump.elapsed = 0
pump:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed >= PUMP_INTERVAL then
        self.elapsed = 0
        if db then ApplyAll() end
    elseif db then
        GuardTick()
    end
end)

SLASH_NPCNAMEPLATES1 = "/nnp"
SLASH_NPCNAMEPLATES2 = "/nn"
SlashCmdList["NPCNAMEPLATES"] = function(msg)
    local cmd = type(msg) == "string" and msg:lower():match("^%s*(%S*)") or ""
    if cmd == "status" or cmd == "count" then
        local friendly, enemy, neutral, total = ApplyAll()
        print(("|cff69ccf0NpcNameplates|r 当前姓名板 %d 个：友方 NPC %d、敌方 %d、中立 %d 已只留姓名。")
            :format(total, friendly, enemy, neutral))
        return
    end
    if ns.Settings and ns.Settings.Open then
        ns.Settings.Open()
    else
        print("|cff69ccf0NpcNameplates|r 设置面板尚未就绪，请稍后再试。")
    end
end

-- 热重载（工坊 load）不会触发 ADDON_LOADED，这里先初始化一次。
-- 正常登录时 SavedVariables 在插件文件执行前就已载入，这里同样安全。
EnsureDB()
-- CVars 已就绪时立刻应用偏好（热重载、或登录阶段已加载完 CVar）；否则等 PLAYER_LOGIN。
if CVarsReady() then
    ns.ApplyCVarPrefs()
end
