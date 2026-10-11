-- 金账簿 - Core.lua
-- 骨架：命名空间、事件、存档、输出、身份解析。

local ADDON_NAME, GL = ...
local Core = {}
GL.Core = Core

GL.NAME = ADDON_NAME

--------------------------------------------------------------------
-- 输出（只走本地聊天框，绝不发送任何消息）
--------------------------------------------------------------------

local frame = CreateFrame("Frame")

function GL.Print(msg)
    local text = GL.L.TAG .. " " .. tostring(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

function GL.Printf(fmt, ...)
    -- 所有参数必须已经过 Secrets 校验；机密值进不了 string.format
    GL.Print(string.format(fmt, ...))
end

--------------------------------------------------------------------
-- 工具
--------------------------------------------------------------------

-- 去首尾空白（含不间断空格）。绝不用在任何可能是机密值的输入上。
function Core.trim(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("^[%s\194\160]+", ""):gsub("[%s\194\160]+$", ""))
end

GL.Core.trim = Core.trim

--------------------------------------------------------------------
-- 客户端版本
--------------------------------------------------------------------

function Core.Build()
    local ok, version, build = GL.Secrets.Read(GetBuildInfo)
    if not ok or not version or not build then return nil end
    if type(version) ~= "string" or type(build) ~= "string" then return nil end
    if not build:match("^%d+$") then return nil end
    return version .. "." .. build
end

--------------------------------------------------------------------
-- 身份解析（全部经过机密值校验）
--------------------------------------------------------------------

-- 返回 { guid, name, realm, level, class, guild, isPlayer, isSelf } 或 nil, 原因
function Core.Identity(unit)
    unit = GL.Secrets.Text(unit)
    if not unit or unit == "" then return nil, "hidden" end

    local ok, exists = pcall(UnitExists, unit)
    if not ok or not GL.Secrets.Value(exists) then return nil, "none" end

    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    isPlayer = GL.Secrets.Value(isPlayer)

    local guid = GL.Secrets.Text(select(1, UnitGUID(unit)))
    if not guid then return nil, "hidden" end

    local name, realm = UnitName(unit)
    name = GL.Secrets.Text(name)
    realm = GL.Secrets.Text(realm)
    if not name then return nil, "hidden" end
    if realm and (#realm == 0 or #realm > 128) then realm = nil end

    local level = GL.Secrets.Int(UnitLevel(unit))
    local class = GL.Secrets.Text(select(2, UnitClass(unit)))
    local guild = GL.Secrets.Text(GetGuildInfo(unit))

    local isSelf = false
    local okSelf, selfGUID = pcall(UnitGUID, "player")
    if okSelf then
        local sg = GL.Secrets.Text(selfGUID)
        isSelf = (sg ~= nil and sg == guid)
    end

    return {
        guid = guid, name = name, realm = realm, level = level,
        class = class, guild = guild,
        isPlayer = isPlayer == true, isSelf = isSelf,
    }
end

--------------------------------------------------------------------
-- 事件
--------------------------------------------------------------------

local function onLogin()
    GL.Config.Init(GoldLedgerDB)

    local build = Core.Build()
    GL.Print("已加载。客户端 " .. (build or "未知"))

    local total = GL.Stats.Resolve()
    if total and total > 0 then
        local missing = GL.Stats.Missing()
        if #missing == 0 then
            GL.Printf(GL.L.CMD.RESOLVED, total, total)
        else
            GL.Printf("已识别 %d 个统计量，缺 %d 个：%s",
                total, #missing, table.concat(missing, ", "))
            GL.Print("缺的直接用 /gl set <key> <id> 手动绑。")
        end
    else
        GL.Print(GL.L.CMD.NO_IDS)
    end

    if GL.Config.Get("loginLine") then
        GL.Stats.PrintSelfLine()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        GL.Config.Init(GoldLedgerDB)
    elseif event == "PLAYER_LOGIN" then
        local ok, err = pcall(onLogin)
        if not ok then GL.Print("登录初始化出错：" .. tostring(err)) end
    end
end)

GL.Core.frame = frame
