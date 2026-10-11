-- 金账簿 - Secrets.lua
-- 机密值防护的唯一入口。所有对游戏 API 的读取都必须经过这里。
--
-- 规则（12.0 起，无限完整保留）：
--   机密值可以做：原样传给接受它的 API、拼接（结果仍是机密）、存进表
--   机密值不可以做：运算、与同类型值比较、取长度、当表键、当布尔判断、
--                   交给 math.* / string.upper 这类会转成数字或字符串的函数
--   做这些会立刻抛 Lua 错误，所以每一个值在使用前都必须先过这一层。

local ADDON_NAME, GL = ...
local Secrets = {}
GL.Secrets = Secrets

--------------------------------------------------------------------
-- 判断
--------------------------------------------------------------------

function Secrets.IsSecret(value)
    if issecretvalue == nil then return false end
    local ok, result = pcall(issecretvalue, value)
    return ok and result == true
end

function Secrets.IsSecretTable(value)
    if issecrettable ~= nil then
        local ok, result = pcall(issecrettable, value)
        if ok and result == true then return true end
    end
    return false
end

-- 安全调用：任何 API 调用都走这里，保证不把错误抛到调用方
function Secrets.Call(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

--------------------------------------------------------------------
-- 取值：机密一律当"未知"（nil），绝不当代零，也绝不沿用旧值
--------------------------------------------------------------------

function Secrets.Value(value)
    if value == nil then return nil end
    if Secrets.IsSecret(value) then return nil end
    return value
end

function Secrets.Text(value)
    value = Secrets.Value(value)
    if type(value) ~= "string" then return nil end
    return value
end

-- 有限数字。NaN 和无穷都算无效。
function Secrets.Number(value)
    value = Secrets.Value(value)
    if type(value) ~= "number" then return nil end
    if value ~= value then return nil end            -- NaN
    if value == math.huge or value == -math.huge then return nil end
    return value
end

-- 非负整数。计数器只可能是这个形态。
function Secrets.Int(value)
    local n = Secrets.Number(value)
    if n == nil then return nil end
    if n < 0 or n ~= math.floor(n) then return nil end
    return n
end

-- 表：拒绝受保护的表和带元表的表
function Secrets.Table(value)
    value = Secrets.Value(value)
    if type(value) ~= "table" then return nil end
    if Secrets.IsSecretTable(value) then return nil end
    if getmetatable(value) ~= nil then return nil end
    return value
end

--------------------------------------------------------------------
-- 多返回值：API 常常一次返回好几个，逐个过筛
--------------------------------------------------------------------

-- 返回经过校验的第 n 个返回值，其余丢弃
function Secrets.Nth(ok, n, ...)
    if not ok then return nil end
    local values = { ... }
    return Secrets.Value(values[n])
end

-- 包装一次 API 调用：返回 是否成功, 校验后的返回值列表
function Secrets.Read(fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return false end
    return true, Secrets.Value(a), Secrets.Value(b), Secrets.Value(c), Secrets.Value(d)
end
