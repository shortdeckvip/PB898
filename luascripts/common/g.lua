local rand = require(CLIBS["c_rand"])
local log = require(CLIBS["c_log"])
local global = require(CLIBS["c_global"])
local http = require(CLIBS["c_http"])

local MyGlobal = {}

-- 参数 t：表结构
-- 参数 f: 排序函数
function MyGlobal.pairsByKeys(t, f)
    local a = {} -- 存放所有的key
    for n in pairs(t) do
        table.insert(a, n) -- 插入各元素的key值
    end
    table.sort(a, f) -- 排序表中元素(key值)  使大的key在前
    local i = 0 -- iterator variable
    local iter = function()
        -- iterator function
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]] -- 返回t的元素key,t的元素值
        end
    end
    return iter
end

function MyGlobal.getProbabilityIdx(prob, t)
    local r = rand.rand_between(1, 10000, t)
    for k, v in ipairs(prob) do
        if r <= v then
            return k
        end
        r = r - v
    end
    return #prob
end

function MyGlobal.randYByX(x, y)
    if x < y then
        return nil
    end
    local a = {}
    for i = 1, x do
        a[i] = i
    end
    local b = {}
    local i = 1
    while i <= y do
        local pos = rand.rand_between(1, x)
        if a[pos] ~= 0 then
            b[i] = pos
            a[pos] = 0
            i = i + 1
        end
    end
    return b
end

-- 判断t是否为空的表
function MyGlobal.isEmptyTable(t)
    if type(t) ~= "table" then
        return true
    end
    return next(t) == nil and true or false
end

-- 检查 item 是否为表 t 的项
function MyGlobal.isInTable(t, item)
    if MyGlobal.isEmptyTable(t) then
        return false
    end

    for k, v in pairs(t) do
        if type(v) == type(item) and v == item then
            return true
        end
    end
    return false
end

-- 对序列 t 求和
function MyGlobal.sum(t)
    if not t or type(t) ~= "table" then
        return 0
    end

    local sum = 0
    for _, v in ipairs(t) do
        sum = sum + v
    end
    return sum
end

-- table.move
-- t2[t ..] = t1[f .. e]
function MyGlobal.move(t1, f, e, t, t2)
    if not t2 then
        t2 = t1
    end

    for i = f, e do
        table.insert(t2, t + (i - f), t1[i])
    end
    --[[
	for k,v in ipairs(t1) do
		if k < f or k > e then
			break
		end
		if k >= f and k <= e then
			table.insert(t2, t + (k - f), v)
		end
	end
	--]]
end

-- 深拷贝
-- 与 MyGlobal.move 的区别：
--		1、能处理非连续 table
--		2、深拷贝
function MyGlobal.copy(t)
    if not t or type(t) ~= "table" then
        return nil
    end

    local copyt = {}
    if MyGlobal.isEmptyTable(t) then
        return copyt
    end

    for k, v in pairs(t) do
        if k ~= "__index" then
            if type(v) == "table" then -- 如果遇到表类型，必须深拷贝
                copyt[k] = MyGlobal.copy(v)
            else
                copyt[k] = v -- 非表类型可以直接拷贝
            end
        end
    end
    return copyt
end

-- 返回找到的第一个数据
-- @param t : table
-- @param e : 要查找的元素
-- @param f : compare function
-- @return : 索引
function MyGlobal.find(t, e, f)
    if not t or type(t) ~= "table" then
        return -1
    end

    for k, v in ipairs(t) do
        if f and f(v) then
            return k
        end
        if e and v == e then
            return k
        end
    end
    return -1
end

-- 合并 table
-- @param t1: 表 1
-- @param t2: 表 2
function MyGlobal.merge(t1, t2)
    local t = {}
    if not t1 or not t2 or type(t1) ~= "table" or type(t2) ~= "table" then
        return t
    end

    for k, v in ipairs(t1) do
        table.insert(t, v)
    end
    for k, v in ipairs(t2) do
        table.insert(t, v)
    end
    return t
end

function MyGlobal.count(t)
    if not t or type(t) ~= "table" then
        return 0
    end

    local count = 0
    for k, v in pairs(t) do
        --print('MyGlobal.count', k, v)
        count = count + 1
    end
    return count
end

-- 保留 n 位浮点精度
function MyGlobal.convert2PrecisionN(f, n)
    if not f or type(f) ~= "number" then
        return 0
    end
    return tonumber(string.format("%." .. n .. "f", f))
end

-- print table
function MyGlobal.print(t, indent)
    if not indent then
        indent = 0
    end
    local formatting = string.rep("  ", indent)
    for k, v in pairs(t) do
        io.write(formatting .. k .. ":")
        if type(v) == "table" then
            io.write(formatting .. "{\n")
            MyGlobal.print(v, indent + 1)
            io.write(formatting .. "}\n")
        elseif type(v) == "boolean" then
            io.write(formatting .. tostring(v) .. "\n")
        elseif type(v) == "string" then
            io.write(formatting .. '"' .. v .. '"' .. "\n")
        else
            io.write(formatting .. v .. "\n")
        end
    end
end

-- split string to string table
function MyGlobal.split(pString, pPattern)
    local Table = {} -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pPattern
    local last_end = 1
    local s, e, cap = pString:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(Table, cap)
        end
        last_end = e + 1
        s, e, cap = pString:find(fpat, last_end)
    end
    if last_end <= #pString then
        cap = pString:sub(last_end)
        table.insert(Table, cap)
    end
    return Table
end

-- convert string table to number table
function MyGlobal.at2it(t)
    if not t or type(t) ~= "table" then
        return t
    end
    local tmp = {}
    for k, v in ipairs(t) do
        if type(v) == "string" then
            table.insert(tmp, tonumber(v))
        end
    end
    return tmp
end

local function char_to_hex(c)
    return string.format("%%%02X", string.byte(c))
end

function MyGlobal.urlencode(url)
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w ])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

local function hex_to_char(x)
    return string.char(tonumber(x, 16))
end

function MyGlobal.urldecode(url)
    if url == nil then
        return
    end
    url = url:gsub("+", " ")
    url = url:gsub("%%(%x%x)", hex_to_char)
    return url
end

local function onResp(code, resp, context)
    log.info("%s %s", code, resp)
end
local function onErrHandler(err)
    log.error("err traceback %s", tostring(err))
    err =
        string.format(
        "[%s %s-%s] %s",
        tostring(SERVERLIST_CONF[9003]),
        tostring(global.stype()),
        tostring(global.lowsid()),
        tostring(err)
    )
    if SERVERLIST_CONF[9002] then
        local alarmurl = string.format(SERVERLIST_CONF[9002], MyGlobal.urlencode(tostring(err)))
        http.get(alarmurl, onResp)
    end
end

function MyGlobal.call(f, ...)
    return xpcall(f, onErrHandler, ...)
end

function MyGlobal.uuid(sid)
    if sid then
        return string.format("%x-%x-%x", global.sid(), global.ctmicros(), sid)
    else
        return string.format("%x-%x", global.sid(), global.ctmicros())
    end
end

return MyGlobal
