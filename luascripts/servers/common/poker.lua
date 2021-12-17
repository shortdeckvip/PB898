local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")

local COLOR_MASK = 0xFF00 -- 花色掩码
local VALUE_MASK = 0x00FF -- 牌值掩码

---- 默认牌
local DEFAULT_POKER_TABLE = {
    ---- 2, 3, 4, 5, 6, 7, 8, 9 , 10, J, Q, K, A,
    0x102,
    0x103,
    0x104,
    0x105,
    0x106,
    0x107,
    0x108,
    0x109,
    0x10A,
    0x10B,
    0x10C,
    0x10D,
    0x10E,
    --方块

    0x202,
    0x203,
    0x204,
    0x205,
    0x206,
    0x207,
    0x208,
    0x209,
    0x20A,
    0x20B,
    0x20C,
    0x20D,
    0x20E,
    --梅花

    0x302,
    0x303,
    0x304,
    0x305,
    0x306,
    0x307,
    0x308,
    0x309,
    0x30A,
    0x30B,
    0x30C,
    0x30D,
    0x30E,
    --红桃

    0x402,
    0x403,
    0x404,
    0x405,
    0x406,
    0x407,
    0x408,
    0x409,
    0x40A,
    0x40B,
    0x40C,
    0x40D,
    0x40E
    --黑桃
}

--local DEFAULT_POKER_COUNT = #DEFAULT_POKER_TABLE

local COLOR_STRFORMAT_TABLE = {
    [1] = "D",
    --Diamond
    [2] = "C",
    --Club
    [3] = "H",
    --Heart
    [4] = "S"
    --Spade
}

-- 洗牌算法
local function shuffle(cards)
    assert(cards and type(cards) == "table")
    for i = 1, #cards - 1 do
        local s = rand.rand_between(i, #cards)
        cards[i], cards[s] = cards[s], cards[i] -- 交换两张牌
    end
end

local function defaultCompare(c1, c2)
    return (VALUE_MASK & c1) < (VALUE_MASK & c2)
end

Poker = Poker or {}

function Poker:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

-- 初始化扑克
function Poker:init(pokerTable, colorMask, valueMask, compareFun)
    self.DEFAULT_POKER_TABLE = pokerTable or DEFAULT_POKER_TABLE -- 默认的一幅扑克牌
    self.DEFAULT_POKER_COUNT = #self.DEFAULT_POKER_TABLE -- 一副牌的张数
    self.COLOR_MASK = colorMask or COLOR_MASK
    self.VALUE_MASK = valueMask or VALUE_MASK
    self.compareCard = compareFun or defaultCompare
    self.currentIdx = 0
    self.cards = {}
    for k, v in ipairs(self.DEFAULT_POKER_TABLE) do
        table.insert(self.cards, v)
    end
    self:reset() -- 洗牌
end

-- 重置扑克牌
function Poker:reset()
    self.currentIdx = 0
    shuffle(self.cards) -- 洗牌
end

-- 参数 r： 要出的这一手牌
-- 返回值： 返回打出去的牌
function Poker:removes(r)
    local ret = {}
    for _, v in ipairs(r) do
        for kk, vv in ipairs(self.cards) do
            if vv & 0xFFFF == v & 0xFFFF then
                table.insert(ret, vv)
                table.remove(self.cards, kk)
                break
            end
        end
    end
    return ret
end

-- 获取剩余的牌张数
function Poker:getLeftCardsCnt()
    if not self.cards then
        return 0
    end
    assert(self.currentIdx <= #self.cards)
    return #self.cards - self.currentIdx
end

function Poker:pop()
    assert(self.currentIdx < #self.cards)
    self.currentIdx = self.currentIdx + 1
    return self.cards[self.currentIdx]
    --return table.remove(self.cards)
end

function Poker:bottomCard()
    if not self.cards then
        return 0
    end
    return self.cards[#self.cards]
end

-- 检查还有剩余扑克牌
function Poker:isLeft()
    if not self.cards then
        return false
    end
    return self.currentIdx < #self.cards
end

-- 获取 N 张牌
-- @return {} ...
function Poker:getNCard(n)
    local tmp = {}
    for i = 1, n do
        table.insert(tmp, self:pop())
    end
    return tmp
end

-- 获取 M 组牌, 每组 N 张牌
-- @return {}, {} ...
function Poker:getMNCard(m, n)
    assert(m * n <= self:getLeftCardsCnt())
    local mcards = {}
    for i = 1, m do
        local ncards = {}
        for j = 1, n do
            table.insert(ncards, self:pop())
        end
        table.insert(mcards, ncards)
    end
    return table.unpack(mcards)
end

function Poker:cardColor(v)
    assert(v and type(v) == "number")
    return (v & self.COLOR_MASK) >> 8
end

function Poker:cardValue(v)
    assert(v and type(v) == "number")
    return v & self.VALUE_MASK
end

-- 排序
function Poker:sort(cards)
    table.sort(cards, self.compareCard)
end

-- print cards
function Poker:printCards(cards, level)
    level = level or 1

    io.write("[")
    for k, v in pairs(cards) do
        if type(v) == "table" then
            io.write(k .. ":")
            self:printCards(v, level + 1)
        else
            io.write(string.format("0x%X, ", v))
        end
    end
    io.write("], ")
    if level == 1 then
        io.write("\n")
    end
end

function Poker:formatCards(cards)
    assert(cards and type(cards) == "table")
    local str = ""
    for _, v in ipairs(cards) do
        local cc = self:cardColor(v)
        str = str .. COLOR_STRFORMAT_TABLE[cc]
        local cv = self:cardValue(v)
        if cv <= 0x9 then
            str = str .. tostring(cv)
        elseif cv == 0xA then
            str = str .. "T"
        elseif cv == 0xB then
            str = str .. "J"
        elseif cv == 0xC then
            str = str .. "Q"
        elseif cv == 0xD then
            str = str .. "K"
        elseif cv == 0xE then
            str = str .. "A"
        end
        str = str .. "|"
    end
    str = string.sub(str, 1, -2)
    return str
end
