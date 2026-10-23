-- 金账簿 - Scan.lua
-- 成就对比 API 的唯一接触点。
--
-- 状态机：IDLE → pending → INFLIGHT → READY / TIMEOUT / FAR
--
-- 三条必须遵守的规矩：
--   1. 同一时刻只允许一个请求在飞（对比槽是全局共享资源）
--   2. 绝不调用 NotifyInspect / InspectAchievements，绝不清掉原生的装备检查目标
--   3. 绝不替换 SetAchievementComparisonUnit 这些函数，只用 hooksecurefunc 观察
--
-- ⚠️ 最大的坑：Blizzard 的 AchievementFrameComparison 框体只要加载过成就界面
--    就一直在监听 INSPECT_ACHIEVEMENT_READY。它在"没有对比在显示"时收到该事件
--    会抛 Lua 错误。所以发请求前必须临时注销它的事件，请求结束后原样恢复。

local ADDON_NAME, GL = ...
local Scan = {}
GL.Scan = Scan
local S = GL.Secrets
local Stats = GL.Stats

--------------------------------------------------------------------
-- 参数
--------------------------------------------------------------------

Scan.DEBOUNCE       = 0.30
Scan.FLOOR          = 1.5      -- 两次请求之间的最小间隔
Scan.TIMEOUT        = 2.5      -- 悬停触发的等待上限
Scan.MANUAL_TIMEOUT = 15       -- /gl scan 的等待上限
Scan.FAR_TTL        = 3        -- "太远"状态在 tooltip 上停留多久

--------------------------------------------------------------------
-- 状态
--------------------------------------------------------------------

local state = "IDLE"
local pending, inflight
local lastSet
local farUntil = {}
local listeners = {}
local callingComparison = false   -- 区分"是不是我们自己调的"
local ownsComparison = false
local externalUntil = 0           -- 别人占用时的退避截止时间
local hookedNames = {}
local nativeGuard                 -- 被我们保护的原生对比框

local frame = CreateFrame("Frame")

local function now() return GetTime() end

function Scan.State() return state end

function Scan.HasAPI()
    return type(SetAchievementComparisonUnit) == "function"
        and type(ClearAchievementComparisonUnit) == "function"
        and type(GetComparisonStatistic) == "function"
end

function Scan.OnReady(fn)
    listeners[#listeners + 1] = fn
end

local function notify(guid, row, status)
    for _, fn in ipairs(listeners) do pcall(fn, guid, row, status) end
end

--------------------------------------------------------------------
-- 缓存
--
-- ⚠️ 默认【不留存】：retain 关着时，观测只进会话内的临时表，
--    不写 SavedVariables，重载即消失。这是有意为之。
--------------------------------------------------------------------

local sessionCache = {}

local function cache()
    local db = GL.Config.DB()
    if GL.Config.Get("retain") and db and type(db.cache) == "table" then
        return db.cache
    end
    return sessionCache
end

function Scan.Peek(guid)
    if not guid then return nil end
    return cache()[guid]
end

-- 新鲜度内的缓存行
function Scan.Get(guid)
    local row = Scan.Peek(guid)
    if not row then return nil end
    local minutes = tonumber(GL.Config.Get("cacheMin")) or 10
    if (time() - (tonumber(row.at) or 0)) < minutes * 60 then return row end
    return nil
end

function Scan.Items()
    local list = {}
    for guid, row in pairs(cache()) do
        if type(row) == "table" then list[#list + 1] = { guid = guid, row = row } end
    end
    return list
end

function Scan.Clear()
    Scan.Cancel()
    for k in pairs(cache()) do cache()[k] = nil end
    farUntil = {}
    notify(nil, nil, "CLEARED")
end

function Scan.Status(guid)
    if inflight and inflight.guid == guid then return "PENDING" end
    if pending and pending.guid == guid then return "PENDING" end
    if farUntil[guid] and farUntil[guid] > now() then return "FAR" end
    return nil
end

--------------------------------------------------------------------
-- 原生对比框的保护（★ 最容易踩的坑）
--------------------------------------------------------------------

-- 玩家自己的成就窗开着时，对比槽被它占着
function Scan.Busy()
    local af = AchievementFrame
    return (af and type(af.IsShown) == "function" and af:IsShown()) and true or false
end

-- 订阅要跟随可见性：Forever 的隐藏对比面板无法消费主动送达的回复
local function syncNative()
    local cmp = nativeGuard
    if not cmp then return end
    local ok, visible = pcall(cmp.IsVisible, cmp)
    if not ok or S.IsSecret(visible) then return end
    if visible then
        pcall(cmp.RegisterEvent, cmp, "INSPECT_ACHIEVEMENT_READY")
    else
        pcall(cmp.UnregisterEvent, cmp, "INSPECT_ACHIEVEMENT_READY")
    end
end

function Scan.GuardNative()
    local cmp = AchievementFrameComparison
    if not cmp or nativeGuard == cmp then return end
    if type(cmp.HookScript) ~= "function"
        or type(cmp.IsVisible) ~= "function"
        or type(cmp.RegisterEvent) ~= "function"
        or type(cmp.UnregisterEvent) ~= "function" then
        return
    end
    nativeGuard = cmp
    cmp:HookScript("OnShow", syncNative)
    cmp:HookScript("OnHide", syncNative)
    syncNative()
end

-- 发请求前：把原生对比框从这个事件上摘下来
local function quietNative(entry)
    local cmp = nativeGuard or AchievementFrameComparison
    if not cmp or type(cmp.IsEventRegistered) ~= "function" then return end
    local ok, registered = pcall(cmp.IsEventRegistered, cmp, "INSPECT_ACHIEVEMENT_READY")
    if ok and registered == true then
        if pcall(cmp.UnregisterEvent, cmp, "INSPECT_ACHIEVEMENT_READY") then
            entry.needRestore = true
        end
    end
end

-- 请求结束后原样恢复
local function restoreNative(entry)
    if not entry or not entry.needRestore then return end
    entry.needRestore = nil
    local cmp = nativeGuard or AchievementFrameComparison
    if not cmp then return end
    if cmp == nativeGuard then
        syncNative()
    elseif type(cmp.RegisterEvent) == "function" then
        pcall(cmp.RegisterEvent, cmp, "INSPECT_ACHIEVEMENT_READY")
    end
end

--------------------------------------------------------------------
-- 礼让：别人动了对比槽就让位
--------------------------------------------------------------------

function Scan.WatchComparison()
    if type(hooksecurefunc) ~= "function" then return false end
    local function changed()
        if callingComparison then return end   -- 自己调的，不管
        ownsComparison = false
        externalUntil = now() + 5              -- 5 秒退避
        Scan.Cancel("BUSY")
    end
    for _, name in ipairs({ "SetAchievementComparisonUnit", "ClearAchievementComparisonUnit" }) do
        if not hookedNames[name] and type(_G[name]) == "function" then
            hookedNames[name] = pcall(hooksecurefunc, name, changed)
        end
        if not hookedNames[name] then return false end
    end
    return true
end

local function comparisonCall(fn, ...)
    callingComparison = true
    local ok, result = pcall(fn, ...)
    callingComparison = false
    return ok, result
end

local function releaseComparison()
    if ownsComparison then
        ownsComparison = false
        comparisonCall(ClearAchievementComparisonUnit)
    end
end

--------------------------------------------------------------------
-- 请求
--------------------------------------------------------------------

local function settle()
    if pending or state == "INFLIGHT" then
        frame:SetScript("OnUpdate", Scan.Tick)
    else
        frame:SetScript("OnUpdate", nil)
    end
end

function Scan.Cancel(status)
    local entry, queued = inflight, pending
    frame:UnregisterEvent("INSPECT_ACHIEVEMENT_READY")
    releaseComparison()
    if entry then restoreNative(entry) end
    inflight, pending, state = nil, nil, "IDLE"
    settle()
    if entry then notify(entry.guid, nil, status or "CANCELLED") end
    if queued then notify(queued.guid, nil, status or "CANCELLED") end
end

-- 返回 row, "READY"（命中缓存）
-- 或 nil, 状态："PENDING" / "FAR" / "HIDDEN" / "SELF" / "NPC" / "NONE" / "NOAPI" / "COMBAT" / "BUSY"
function Scan.Request(unit, force, priority)
    local id, why = GL.Core.Identity(unit)
    if not id then return nil, (why == "hidden") and "HIDDEN" or "NONE" end
    if not id.isPlayer then return nil, "NPC" end
    if id.isSelf then return nil, "SELF" end

    local row = Scan.Get(id.guid)
    if row and not force then return row, "READY" end

    if not Scan.HasAPI() or not Scan.WatchComparison() then return nil, "NOAPI" end

    local okCombat, lockdown = pcall(InCombatLockdown)
    if okCombat and lockdown == true then return nil, "COMBAT" end

    if Scan.Busy() or now() < externalUntil then return nil, "BUSY" end

    local status = Scan.Status(id.guid)
    if force and status == "FAR" then status = nil end
    if status then
        if pending and pending.guid == id.guid then
            pending.unit = unit
            pending.priority = pending.priority or priority
        end
        return nil, status
    end

    if pending then notify(pending.guid, nil, "CANCELLED") end
    pending = {
        guid = id.guid, unit = unit, name = id.name, level = id.level,
        class = id.class, guild = id.guild, at = now(), priority = priority,
    }
    settle()
    return nil, "PENDING"
end

--------------------------------------------------------------------
-- 执行
--------------------------------------------------------------------

local function finish(row, status)
    if row and status == "READY" then
        -- 一个可读值都没有，等于没数据
        local readable = false
        for _, key in ipairs(Stats.ALL_KEYS) do
            if row[Stats.FIELD[key]] ~= nil then readable = true break end
        end
        if not readable then row, status = nil, "NODATA" end
    end

    local entry = inflight
    frame:UnregisterEvent("INSPECT_ACHIEVEMENT_READY")
    releaseComparison()
    restoreNative(entry)
    state, inflight = "IDLE", nil

    -- 对比界面自己弹出来了：关掉它
    if entry and not entry.frameWasShown and AchievementFrame
        and type(AchievementFrame.IsShown) == "function" and AchievementFrame:IsShown() then
        pcall(HideUIPanel, AchievementFrame)
    end

    if entry and status == "READY" and row then
        row.name, row.level, row.at = entry.name, entry.level, time()
        row.unitToken = entry.unit
        GL.Judge.Evaluate(row)
        if GL.Config.Get("retain") then
            cache()[entry.guid] = row
        end
        sessionCache[entry.guid] = row      -- 会话内始终缓存，方便 tooltip 复用
        notify(entry.guid, row, "READY")
    elseif entry then
        notify(entry.guid, nil, status)
    end
    settle()
end

local function fire(entry)
    if #Stats.Missing() > 0 then Stats.Resolve(true) end

    lastSet = now()
    entry.frameWasShown = Scan.Busy()
    quietNative(entry)

    state, inflight, ownsComparison = "INFLIGHT", entry, true
    entry.started = now()
    frame:RegisterEvent("INSPECT_ACHIEVEMENT_READY")

    -- 返回值 false 就是【太远】——距离判定不需要自己算
    local ok, result = comparisonCall(SetAchievementComparisonUnit, entry.unit)
    if not ok or S.IsSecret(result) or result == false then
        farUntil[entry.guid] = now() + Scan.FAR_TTL
        if inflight == entry then finish(nil, "FAR") end
        return
    end
    settle()
end

function Scan.Tick()
    local t = now()

    if (pending or inflight) then
        local okCombat, lockdown = pcall(InCombatLockdown)
        if okCombat and lockdown == true then Scan.Cancel("COMBAT") return end
    end

    if state == "INFLIGHT" then
        if inflight and (t - inflight.started) >
            (inflight.priority and Scan.MANUAL_TIMEOUT or Scan.TIMEOUT) then
            finish(nil, "TIMEOUT")
        else
            return
        end
    end

    if not pending then settle() return end
    if (t - pending.at) < Scan.DEBOUNCE then return end
    if lastSet and (t - lastSet) < Scan.FLOOR then return end

    local entry = pending
    pending = nil

    -- 鼠标可能已经移开了：单位必须仍然解析成同一个人
    local id = GL.Core.Identity(entry.unit)
    if not id or id.guid ~= entry.guid or not id.isPlayer or id.isSelf
        or Scan.Busy() or t < externalUntil then
        notify(entry.guid, nil, Scan.Busy() and "BUSY" or "CANCELLED")
        settle()
        return
    end
    entry.name = id.name or entry.name
    entry.level = id.level or entry.level
    fire(entry)
end

--------------------------------------------------------------------
-- 事件
--------------------------------------------------------------------

frame:SetScript("OnEvent", function(_, event, guid)
    if event ~= "INSPECT_ACHIEVEMENT_READY" or state ~= "INFLIGHT" or not inflight then
        return
    end
    -- 载荷是 GUID，必须与本次请求一致，也必须是我们在持有
    if S.IsSecret(guid) or type(guid) ~= "string" or guid ~= inflight.guid then return end
    if not ownsComparison then return end

    if (now() - inflight.started) >
        (inflight.priority and Scan.MANUAL_TIMEOUT or Scan.TIMEOUT) then
        finish(nil, "TIMEOUT")
        return
    end

    local okCombat, lockdown = pcall(InCombatLockdown)
    if okCombat and lockdown == true then Scan.Cancel("COMBAT") return end

    local id = GL.Core.Identity(inflight.unit)
    if not id or id.guid ~= guid then Scan.Cancel() return end

    local row = Stats.ReadRow(GetComparisonStatistic)
    finish(row, "READY")
end)

--------------------------------------------------------------------
-- 登录后
--------------------------------------------------------------------

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:RegisterEvent("ADDON_LOADED")
loginFrame:SetScript("OnEvent", function()
    Scan.GuardNative()
    Scan.WatchComparison()
end)

GL.Scan = Scan
