-- serverdev\luascripts\servers\36\domino.lua
local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local log = require(CLIBS["c_log"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

----0, 1, 2, 3, 4, 5, 6
--- 多米诺牌数据(共28张)
local DEFAULT_POKER_TABLE = {
    0x0000,
    0x0001,
    0x0002,
    0x0003,
    0x0004,
    0x0005,
    0x0006,
    0x0101,
    0x0102,
    0x0103,
    0x0104,
    0x0105,
    0x0106,
    0x0202,
    0x0203,
    0x0204,
    0x0205,
    0x0206,
    0x0303,
    0x0304,
    0x0305,
    0x0306,
    0x0404,
    0x0405,
    0x0406,
    0x0505,
    0x0506,
    0x0606
}

local COLOR_MASK = 0xFF00
local VALUE_MASK = 0x00FF

--每人手上7张牌
local MAX_HANDCARDS_NUM = 7
--一副牌
local MAX_POKER_NUM = 1

Domino = Domino or {}
setmetatable(Domino, {__index = Poker})

function Domino:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

--
local function unionIdxAndValue(self, card)
    self.uniqueid = self.uniqueid + 1
    return (self.uniqueid << 16) | card
end

function Domino:resetAll()
end

--
function Domino:start()
    --唯一索引递增器
    self.uniqueid = 0
    --初始化1副牌
    local poker = {}
    for i = 1, MAX_POKER_NUM do
        for _, v in ipairs(DEFAULT_POKER_TABLE) do
            table.insert(poker, unionIdxAndValue(self, v))
        end
    end

    self.discardCards = {} -- 弃牌(已出的牌)
    self.leftpoint = -1 -- 左边可连接的点数
    self.rightpoint = -1 -- 右边可连接的点数
    --余牌集合
    self:init(poker, COLOR_MASK, VALUE_MASK)
end

-- 随机获取num张牌
function Domino:getCards(num)
    local poker = {} -- 要获取的扑克
    -- self:init()
    self:reset() -- 洗牌
    for i = 1, num, 1 do
        poker[i] = self.cards[i]
    end
    return poker
end

--弃牌(已出的牌)，需要校验card是否位于手牌中
function Domino:discard(card)
    
    if card < 0 then
        table.insert(self.discardCards, 1, card) -- 将牌放到最前
        if self.leftpoint < 0 then
            -- 约定：第一张牌小的点数在左，大的点数在右
            if self:cardColor(math.abs(card)) < self:cardValue(math.abs(card)) then
                self.leftpoint = self:cardColor(math.abs(card))
                self.rightpoint = self:cardValue(math.abs(card))
            else
                self.leftpoint = self:cardValue(math.abs(card))
                self.rightpoint = self:cardColor(math.abs(card))
            end
        else
            if self.leftpoint == self:cardColor(math.abs(card)) then
                self.leftpoint = self:cardValue(math.abs(card))
            else
                self.leftpoint = self:cardColor(math.abs(card))
            end
        end
    else
        table.insert(self.discardCards, card) -- 将牌放到最后
        if self.rightpoint < 0 then
            if self:cardColor(math.abs(card)) < self:cardValue(math.abs(card)) then
                self.leftpoint = self:cardColor(math.abs(card))
                self.rightpoint = self:cardValue(math.abs(card))
            else
                self.leftpoint = self:cardValue(math.abs(card))
                self.rightpoint = self:cardColor(math.abs(card))
            end
        else
            if self.rightpoint == self:cardColor(math.abs(card)) then
                self.rightpoint = self:cardValue(math.abs(card))
            else
                self.rightpoint = self:cardColor(math.abs(card))
            end
        end
    end
    -- log.info("discard(.) card=%s, leftpoint=%s,rightpoint=%s", tostring(card), tostring(self.leftpoint), tostring(self.rightpoint))
end

-- 获取废弃的牌
function Domino:getDiscardCards()
    return self.discardCards
end

-- 判断牌card是否为特殊牌
function Domino:isMagic(card)
    return self:cardColor(math.abs(card)) == self:cardValue(math.abs(card))
end

-- 检测是否可以加入(接龙)card这张牌
-- 返回值: 0:不可加入  1：可加到左边  2:可加到右边  3:即可加到左边也可加到右边
function Domino:checkJoinable(card)
    if #self.discardCards == 0 then -- 如果尚未出过牌
        return 3
    end

    local abscard = math.abs(card)
    local join = 0

    if self:cardColor(abscard) == self.leftpoint or self:cardValue(abscard) == self.leftpoint then
        join = join | 1
    end
    if self:cardColor(abscard) == self.rightpoint or self:cardValue(abscard) == self.rightpoint then
        join = join | 2
    end

    return join
end

-- 获取点数
function Domino:getPointSum(card)
    return self:cardColor(math.abs(card)) + self:cardValue(math.abs(card))
end

-- 获取最小的牌点数
function Domino:getMinPointOneCard(cards)
    local minpoint = 13
    for i, v in ipairs(cards) do
        if v ~= 0 and self:getPointSum(v) < minpoint then
            minpoint = self:getPointSum(v)
        end
    end
    return minpoint
end

-- 获取最小点数牌中半边最小的点数
function Domino:getMinPointSelfCard(cards)
    local minpointOne = self:getMinPointOneCard(cards)
    local minpoint = 7
    for i, v in ipairs(cards) do
        if v ~= 0 and self:getPointSum(v) <= minpointOne then
            if self:cardColor(math.abs(v)) < minpoint then
                minpoint = self:cardColor(math.abs(v))                
            end
            if self:cardValue(math.abs(v)) < minpoint then
                minpoint = self:cardValue(math.abs(v))
            end
        end
    end
    return minpoint
end


-- 获取一手牌的总点数
function Domino:getTotalPoint(handcards)
    local totalPoint = 0
    for i, v in ipairs(handcards) do
        if v ~= 0 then
            totalPoint = totalPoint + self:getPointSum(v)
        end
    end
    return totalPoint
end

