-- 金账簿 - Config.lua
-- 默认阈值与设置读写。
--
-- ⚠️ 这些阈值是【起点，不是定论】。GGS 的那套是在它自己的样本上定的。
--    你应该用自己的角色标定：拿 /gl me 扫你自己所有的号（主号、小号、
--    仓库号、AFK 的号），看覆盖率分布长什么样，再把阈值调到「能区分出
--    你自己仓库号」的位置。仓库号那条判据尤其该拿自己的仓库号验一遍。

local ADDON_NAME, GL = ...
local Config = {}
GL.Config = Config

Config.DEFAULTS = {
    -- 交互
    hover       = true,      -- 悬停扫描（核心交互，默认开）
    retain      = false,     -- ⚠️ 留存档案默认【关】——扫描 ≠ 留存
    minimap     = true,
    loginLine   = true,      -- 每次登录打一行自己的账

    -- 判定：容差
    slackPct    = 0.10,      -- 容差 = 峰值的 10%
    slackMin    = 5000,      -- 容差下限，50 银

    -- 判定：无法解释
    gapGold     = 100000,    -- 差额门槛，10 金
    gapCover    = 0.60,      -- 覆盖率门槛，60%

    -- 判定：历史空白 + 大峰值
    freshLevel  = 5,
    freshGold   = 200000,    -- 20 金
    freshOffer  = 100000,    -- 交易中被给出 10 金

    -- 判定：仓库号形态
    bankPosts   = 200,       -- 拍卖行挂单 + 购买
    bankKills   = 50,
    bankQuests  = 30,

    -- 判定：小额的正常峰值
    trivialPerLevel = 5000,  -- 每级 50 银

    -- 扫描协议
    cacheMin    = 10,        -- 缓存新鲜度（分钟）
    cacheCap    = 400,       -- 缓存条目上限

    -- 历史
    historyCap  = 20,        -- 每个角色保留多少份快照
}

local db

function Config.Init(savedVars)
    db = savedVars
    if type(db.settings) ~= "table" then db.settings = {} end
    if type(db.ids) ~= "table" then db.ids = {} end       -- key -> 统计量 ID（含手动绑定）
    if type(db.idNames) ~= "table" then db.idNames = {} end
    if type(db.cache) ~= "table" then db.cache = {} end   -- guid -> 观测
    return db
end

function Config.DB()
    return db
end

function Config.Get(key)
    if db and type(db.settings) == "table" and db.settings[key] ~= nil then
        return db.settings[key]
    end
    return Config.DEFAULTS[key]
end

function Config.Set(key, value)
    if db and type(db.settings) == "table" then
        db.settings[key] = value
    end
end

function Config.Toggle(key)
    local v = not Config.Get(key)
    Config.Set(key, v)
    return v
end
