-- 金账簿 - Commands.lua
-- 全部斜杠命令。诊断能力是这里的重点：出了问题时靠命令定位，不要靠肉眼。

local ADDON_NAME, GL = ...
local Cmd = {}
GL.Cmd = Cmd
local S = GL.Secrets
local Stats = GL.Stats

local MAX_LINES = 25   -- 单次命令最多打这么多行，避免刷屏

local function say(line) GL.Print(line) end

local function header(text)
    say("|cff8ab4f8" .. text .. "|r")
end

--------------------------------------------------------------------
-- 子命令
--------------------------------------------------------------------

local function cmdPing()
    local ok, version, build = GL.Secrets.Read(GetBuildInfo)
    local iface = select(4, GetBuildInfo())
    header("诊断")
    say("  插件版本 0.1.0")
    say("  客户端   " .. tostring(version) .. "  构建 " .. tostring(build))
    say("  Interface " .. tostring(S.Value(iface)))

    local has = type(SetAchievementComparisonUnit) == "function"
        and type(ClearAchievementComparisonUnit) == "function"
        and type(GetComparisonStatistic) == "function"
    say("  对比接口 " .. (has and "|cff1f6b3a可用|r" or "|cffc0392b缺失|r"))
    say("  统计发现 " .. (Stats.HasDiscoveryAPI() and "|cff1f6b3a可用|r" or "|cffc0392b缺失|r"))
    say("  issecretvalue " .. (issecretvalue and "有" or "无（旧客户端）"))
    say("  命令：/gl help")
end

local function cmdIds()
    local db = GL.Config.DB()
    header("统计量绑定")
    local n = 0
    for _, key in ipairs(Stats.ALL_KEYS) do
        local id = db.ids[key]
        local name = db.idNames[key] or "—"
        local mark = id and "|cff1f6b3a✔|r" or "|cffc0392b✘|r"
        say(string.format("  %s %-8s %-12s %s",
            mark, key, id and tostring(id) or "—", name))
        if id then n = n + 1 end
    end
    say(string.format("共 %d/%d。缺的用 /gl set <key> <id> 手动绑。", n, #Stats.ALL_KEYS))
end

local function listEntries(filter, withId)
    local entries = Stats.entries
    if type(entries) ~= "table" or #entries == 0 then
        entries = Stats.Discover()
    end
    if #entries == 0 then
        say(GL.L.CMD.NO_API)
        return 0
    end
    local needle = filter and GL.Core.trim(filter):lower() or nil
    if needle == "" then needle = nil end

    local shown, total = 0, 0
    for _, e in ipairs(entries) do
        local hit = true
        if needle then hit = e.name:lower():find(needle, 1, true) ~= nil end
        if hit then
            total = total + 1
            if shown < MAX_LINES then
                if withId then
                    say(string.format("  %-8d %s", e.id, e.name))
                else
                    say("  " .. e.name)
                end
                shown = shown + 1
            end
        end
    end
    if total > shown then
        say(string.format("  …还有 %d 条，加关键词过滤", total - shown))
    end
    return total
end

local function cmdProbe(filter)
    header("客户端返回的统计量（共 " .. tostring(#(Stats.entries or {})) .. " 条已发现）")
    local n = listEntries(filter, true)
    if n == 0 then say("  没有匹配项。") end
    say("用 /gl set <key> <id> 把 ID 绑到 key 上。")
end

local function cmdNames(filter)
    header("统计量名称（用于核对本地化）")
    local n = listEntries(filter, false)
    if n == 0 then say("  没有匹配项。") end
    say("如果名字是中文但 /gl ids 全空，说明名称表要补——把这里看到的贴出来。")
end

local function cmdSet(key, idText)
    key = GL.Core.trim(tostring(key or ""))
    local id = tonumber(GL.Core.trim(tostring(idText or "")))
    if key == "" or not id then
        say("用法：/gl set <key> <id>")
        say("key 取值：" .. table.concat(Stats.ALL_KEYS, " "))
        return
    end
    local valid = false
    for _, k in ipairs(Stats.ALL_KEYS) do
        if k == key then valid = true break end
    end
    if not valid then
        say("未知的 key：" .. key)
        return
    end
    id = math.floor(id)
    local ok, rid, label = pcall(GetAchievementInfo, id)
    local name = ok and S.Text(label) or nil
    if not name then
        say("ID " .. id .. " 读不到名字。确认它是个统计量条目吗？")
        return
    end
    local db = GL.Config.DB()
    db.ids[key], db.idNames[key] = id, name
    say(string.format("已绑定 %s → %d（%s）", key, id, name))
end

local function cmdReset()
    local db = GL.Config.DB()
    db.ids, db.idNames = {}, {}
    say("已清除全部绑定，重新自动识别中…")
    local n = Stats.Resolve()
    say(string.format("识别到 %d 个。", n))
end

local function cmdMe()
    local row = Stats.SelfRow()
    if not row then
        say("拿不到自己的身份。")
        return
    end
    header("自己角色的账")
    say("  等级 " .. tostring(row.level or "—") .. "   " .. tostring(row.name or ""))
    for _, key in ipairs(Stats.ALL_KEYS) do
        local field = Stats.FIELD[key]
        local value = row[field]
        local shown
        if value == nil then
            shown = "—（" .. (GL.L.MISSING[row.quality[key]] or "?") .. "）"
        elseif Stats.MONEY_KEYS[key] then
            shown = Stats.FormatMoney(value)
        else
            shown = Stats.FormatCount(value)
        end
        say(string.format("  %-8s %s", Stats.LABEL[key], shown))
    end
    if row.verdict then
        say("  判定     " .. GL.Judge.Colored(row.verdict))
        local reason = GL.Judge.Reason(row)
        if reason then say("  理由     " .. reason) end
        say("  |cff9aa0a6" .. GL.L.DISCLAIMER .. "|r")
    end
end

local function cmdScan()
    say(GL.L.CMD.SCAN_LATER)
    say("M4 才实现。现在先用 /gl me 确认自己角色读得准。")
end

local function cmdExport()
    local db = GL.Config.DB()
    header("手动绑定导出")
    say("  GL.Stats.KNOWN = {")
    for _, key in ipairs(Stats.ALL_KEYS) do
        if db.ids[key] then
            say(string.format("      %s = %d,", key, db.ids[key]))
        end
    end
    say("  }")
end

local function cmdHelp()
    header("金账簿 命令")
    say("  /gl ping          诊断：客户端版本与接口可用性")
    say("  /gl probe [词]    列出客户端返回的全部统计量（ID + 名称）")
    say("  /gl names [词]    只列名称，用于核对本地化")
    say("  /gl ids           显示十个 key 的绑定情况")
    say("  /gl set <k> <id>  手动绑定统计量")
    say("  /gl reset         清除手动绑定并重新识别")
    say("  /gl export        导出手动绑定")
    say("  /gl me            查看自己角色的账")
    say("  /gl scan          扫描目标（M4）")
    say("  /gl hover on|off  悬停扫描开关（默认开）")
    say("  /gl retain on|off 留存档案开关（默认关）")
    say("  /gl help          这条")
    say("")
    say("|cff9aa0a6只用公开统计量；不发送任何消息；" .. GL.L.DISCLAIMER .. "|r")
end

--------------------------------------------------------------------
-- 分发
--------------------------------------------------------------------

local function handler(input)
    local args = {}
    for word in tostring(input or ""):gmatch("%S+") do args[#args + 1] = word end
    local cmd = (args[1] or "help"):lower()

    local ok, err = pcall(function()
        if cmd == "help" or cmd == "" then cmdHelp()
        elseif cmd == "ping" then cmdPing()
        elseif cmd == "probe" then cmdProbe(args[2])
        elseif cmd == "names" then cmdNames(args[2])
        elseif cmd == "ids" then cmdIds()
        elseif cmd == "set" then cmdSet(args[2], args[3])
        elseif cmd == "reset" then cmdReset()
        elseif cmd == "export" then cmdExport()
        elseif cmd == "me" then cmdMe()
        elseif cmd == "scan" or cmd == "player" then cmdScan()
        elseif cmd == "hover" then
            local v = args[2] == "on" and true or args[2] == "off" and false
            if v == nil then say("用法：/gl hover on|off") else
                GL.Config.Set("hover", v); say("悬停扫描：" .. (v and "开" or "关")) end
        elseif cmd == "retain" then
            local v = args[2] == "on" and true or args[2] == "off" and false
            if v == nil then say("用法：/gl retain on|off") else
                GL.Config.Set("retain", v)
                say("留存档案：" .. (v and "开" or "关"))
                if v then say("|cffc0392b注意：开启后会把扫过的玩家存进本地档案。|r") end
            end
        else
            say("未知命令 " .. cmd .. "。用 /gl help 看全部。")
        end
    end)
    if not ok then say("|cffc0392b命令出错：" .. tostring(err) .. "|r") end
end

SLASH_GOLDLEDGER1 = "/gl"
SLASH_GOLDLEDGER2 = "/goldledger"
SlashCmdList["GOLDLEDGER"] = handler
