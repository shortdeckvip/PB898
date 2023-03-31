local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local EnumTeenPattiCardWinType = {
    EnumTeenPattiCardWinType_HIGHCARD = 1, --高牌
    EnumTeenPattiCardWinType_ONEPAIR = 2, --對子(pair)
    EnumTeenPattiCardWinType_FLUSH = 3, --同花(color)
    EnumTeenPattiCardWinType_STRAIGHT = 4, --順子(sequence)
    EnumTeenPattiCardWinType_STRAIGHTFLUSH = 5, --同花順(pure sequence)
    EnumTeenPattiCardWinType_THRREKAND = 6, --三條(set)
    EnumTeenPattiCardWinType_THRREKANDACE = 7 --三條Ace
}

local EnumTP2CardsType = {
    --胜平负
    EnumTP2CardsType_Red = 1, --红
    EnumTP2CardsType_Black = 2, --黑
    EnumTP2CardsType_Draw = 3, --和(赢牌独有类型)
}

TeenPatti = TeenPatti or {}
setmetatable(TeenPatti, { __index = Poker })

function TeenPatti:new(o)
    o = o or {}
    setmetatable(o, { __index = self })

    o:init()
    return o
end

-------------------------牌型判定以及比较-----------------------
local function cardColor(v)
    return v >> 8
end

local function cardValue(v)
    return v & 0xff
end

local function compByCardsValue(a, b)
    if cardValue(a) < cardValue(b) then
        return true
    elseif cardValue(a) > cardValue(b) then
        return false
    else
        return cardColor(a) < cardColor(b)
    end
end

--豹子：三张牌值相同的牌型，由于是有序的，故只需判断第一张与第三张牌值是否相等即可
local function isLeopard(cards)
    if cardValue(cards[1]) == cardValue(cards[3]) then
        return true
    else
        return false
    end
end

--同花：三张牌花色相同
local function isFlush(cards)
    if cardColor(cards[1]) == cardColor(cards[2]) and cardColor(cards[1]) == cardColor(cards[3]) then
        return true
    else
        return false
    end
end

--最小的顺子
local function isA32(cards)
    if cardValue(cards[1]) == 2 and cardValue(cards[2]) == 3 and cardValue(cards[3]) == 14 then
        return true
    else
        return false
    end
end

--顺子：三张牌牌值依次递增1，同时还包括A23特殊牌型
local function isStraight(cards)
    if isA32(cards) then
        return true
    end

    if cardValue(cards[3]) - cardValue(cards[2]) == 1 and cardValue(cards[2]) - cardValue(cards[1]) == 1 then
        return true
    else
        return false
    end
end

--同花顺：即满足同花又满足顺子的牌型
local function isStraightFlush(cards)
    local b1 = isFlush(cards)
    local b2 = isStraight(cards)
    if b1 and b2 then
        return true
    else
        return false
    end
end

--对子：两张牌牌值相等，但第一张与第三张不能相等，否则就是豹子了
local function isPair(cards)
    if cardValue(cards[1]) ~= cardValue(cards[3]) then
        if cardValue(cards[1]) == cardValue(cards[2]) then
            return true
        end
        if cardValue(cards[2]) == cardValue(cards[3]) then
            return true
        end
        return false
    else
        return false
    end
end

-- 获取牌型
function TeenPatti:getPokerTypebyCards(cards)
    if not cards then
        return 0
    end
    table.sort(cards, compByCardsValue)
    local ct = 0
    if isLeopard(cards) then -- 三条
        ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_THRREKAND

        if cardValue(cards[1]) == 0xE then -- 三条A
            ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_THRREKANDACE
        end
    elseif isStraightFlush(cards) then -- 同花顺
        ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_STRAIGHTFLUSH
    elseif isStraight(cards) then -- 顺子
        ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_STRAIGHT
    elseif isFlush(cards) then -- 同花
        ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_FLUSH
    elseif isPair(cards) then -- 对子
        ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_ONEPAIR
    else -- 高牌
        ct = EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_HIGHCARD
    end
    return ct
end

--牌型规则：
--三条>同花顺>顺子>同花>对子>高牌。
--顺子：AKQ>KQJ>…>32A。
--散牌：A>K>…>3>2。
--牌形比较，bankCards与otherCards比较，>0则bankCards比otherCards大，<0则bankCards比otherCards小, =0则相等
--牌形不同直接比较牌形大小，如果牌形相同则：
--豹子：比较单张牌牌值
--同花顺：比较第三张牌，同时考虑A23特殊顺子情况
--同花：从第三张牌开始依次比较
--顺子：比较第三张牌，同时考虑A23特殊顺子情况
--对子：首先比较第二张，因为第二张一定是构成对子的那张牌。若相同则再比对（第一张+第三张）
--另外：teempatti规定，三张牌值完全相同的情况下，比牌者输
function TeenPatti:isBankerWin(bankCards, otherCards)
    if not bankCards or not otherCards then
        return -1
    end
    local bt = self:getPokerTypebyCards(bankCards)
    local ot = self:getPokerTypebyCards(otherCards)

    if bt ~= ot then
        if bt > ot then
            return 1
        elseif bt < ot then
            return -1
        end
    end

    if bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_THRREKAND or
        bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_THRREKANDACE
    then
        if cardValue(bankCards[1]) > cardValue(otherCards[1]) then
            return 1
        elseif cardValue(bankCards[1]) < cardValue(otherCards[1]) then
            return -1
        else
            return 0
        end
    end
    if bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_STRAIGHTFLUSH then
        local bt_a23 = isA32(bankCards)
        local ot_a23 = isA32(otherCards)
        if bt_a23 and ot_a23 then
            return 0
        end

        if bt_a23 then
            if cardValue(otherCards[1]) == 0xE or cardValue(otherCards[3]) == 0xE or cardValue(otherCards[2]) == 0xE then
                return -1
            else
                return 1;
            end
        end
        if ot_a23 then
            if cardValue(bankCards[1]) == 0xE or cardValue(bankCards[3]) == 0xE or cardValue(bankCards[2]) == 0xE then
                return 1
            else
                return -1;
            end
        end

        if not bt_a23 and not ot_a23 then
            if cardValue(bankCards[3]) > cardValue(otherCards[3]) then
                return 1
            elseif cardValue(bankCards[3]) < cardValue(otherCards[3]) then
                return -1
            else
                return 0
            end
        end
    end
    if bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_STRAIGHT then
        local bt_a23 = isA32(bankCards)
        local ot_a23 = isA32(otherCards)
        if bt_a23 and ot_a23 then
            return 0
        end

        if bt_a23 then
            if cardValue(otherCards[1]) == 0xE or cardValue(otherCards[3]) == 0xE or cardValue(otherCards[2]) == 0xE then
                return -1
            else
                return 1;
            end
        end
        if ot_a23 then
            if cardValue(bankCards[1]) == 0xE or cardValue(bankCards[3]) == 0xE or cardValue(bankCards[2]) == 0xE then
                return 1
            else
                return -1;
            end
        end

        if not bt_a23 and not ot_a23 then
            if cardValue(bankCards[3]) > cardValue(otherCards[3]) then
                return 1
            elseif cardValue(bankCards[3]) < cardValue(otherCards[3]) then
                return -1
            else
                return 0
            end
        end
    end
    if bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_FLUSH then
        for i = 3, 1, -1 do
            if cardValue(bankCards[i]) > cardValue(otherCards[i]) then
                return 1
            elseif cardValue(bankCards[i]) < cardValue(otherCards[i]) then
                return -1
            end
        end
        return 0
    end
    if bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_ONEPAIR then
        if cardValue(bankCards[2]) > cardValue(otherCards[2]) then
            return 1
        elseif cardValue(bankCards[2]) < cardValue(otherCards[2]) then
            return -1
        else
            if cardValue(bankCards[1]) + cardValue(bankCards[3]) > cardValue(otherCards[1]) + cardValue(otherCards[3]) then
                return 1
            elseif cardValue(bankCards[1]) + cardValue(bankCards[3]) <
                cardValue(otherCards[1]) + cardValue(otherCards[3])
            then
                return -1
            else
                return 0
            end
        end
    end
    if bt == EnumTeenPattiCardWinType.EnumTeenPattiCardWinType_HIGHCARD then
        for i = 3, 1, -1 do
            if cardValue(bankCards[i]) > cardValue(otherCards[i]) then
                return 1
            elseif cardValue(bankCards[i]) < cardValue(otherCards[i]) then
                return -1
            end
        end
        return 0
    end
    assert(false)
end

-- 获取获胜类型
-- @param cardsA: 红牌
-- @param cardsB: 黑牌
-- @return wintypes,winpokertype
function TeenPatti:getWinType(cardsA, cardsB)
    assert(cardsA and type(cardsA) == "table" and #cardsA >= 2)
    assert(cardsB and type(cardsB) == "table" and #cardsB >= 2)

    local wintypes = {}
    local winpokertype = -1
    local newCardsA = self:getMaxCards(cardsA)
    local newCardsB = self:getMaxCards(cardsB)

    --红和黑
    local result = self:isBankerWin(newCardsA, newCardsB)
    if result == -1 then -- 黑(cardsB赢)
        table.insert(wintypes, EnumTP2CardsType.EnumTP2CardsType_Black)
        winpokertype = self:getPokerTypebyCards(newCardsB)
    elseif result == 0 then --和
        table.insert(wintypes, EnumTP2CardsType.EnumTP2CardsType_Draw)
        winpokertype = self:getPokerTypebyCards(newCardsA)
    else
        table.insert(wintypes, EnumTP2CardsType.EnumTP2CardsType_Red)
        winpokertype = self:getPokerTypebyCards(newCardsA)
    end

    return wintypes, winpokertype
end

-- 获取最大的三张牌
function TeenPatti:getMaxCards(cards)
    assert(cards and type(cards) == "table" and #cards >= 2)
    local v1 = cardValue(cards[1])
    local v2 = cardValue(cards[2])
    local color1 = cardColor(cards[1])
    local color2 = cardColor(cards[2])
    local newCards = {}
    table.insert(newCards, cards[1])
    table.insert(newCards, cards[2])

    -- 尝试组合成3张
    if v1 == v2 then
        local color = 1
        if color == color1 then
            color = color + 1
        end
        if color == color2 then
            color = color + 1
        end
        table.insert(newCards, (color << 8) | v1) -- 合成3张
        return newCards
    end

    -- 尝试组合成同花顺子或顺子
    if v1 > v2 then
        if v1 - v2 == 2 then
            table.insert(newCards, cards[1] - 1)
            return newCards
        elseif v1 - v2 == 1 then
            if v1 == 3 then -- 32
                table.insert(newCards, (color1 << 8) | 14)
                return newCards
            elseif v1 == 14 then -- AK
                table.insert(newCards, (color1 << 8) | v2 - 1)
                return newCards
            else
                table.insert(newCards, (color1 << 8) | v1 + 1)
                return newCards
            end
        elseif v1 == 14 then -- A
            if v2 == 3 then
                table.insert(newCards, (color1 << 8) | 2)
                return newCards
            elseif v2 == 2 then
                table.insert(newCards, (color1 << 8) | 3)
                return newCards
            end
        end
    elseif v2 > v1 then
        if v2 - v1 == 2 then
            table.insert(newCards, cards[2] - 1)
            return newCards
        elseif v2 - v1 == 1 then
            if v2 == 3 then -- 32
                table.insert(newCards, (color1 << 8) | 14)
                return newCards
            elseif v2 == 14 then -- AK
                table.insert(newCards, (color1 << 8) | v1 - 1)
                return newCards
            else
                table.insert(newCards, (color1 << 8) | v2 + 1)
                return newCards
            end
        elseif v2 == 14 then -- A
            if v1 == 3 then
                table.insert(newCards, (color1 << 8) | 2)
                return newCards
            elseif v1 == 2 then
                table.insert(newCards, (color1 << 8) | 3)
                return newCards
            end
        end
    end

    -- 尝试组合成同花
    if color1 == color2 then
        if v1 > v2 then
            if v1 == 14 then
                table.insert(newCards, cards[1] - 1)
            else
                table.insert(newCards, (color1 << 8) | 14)
            end
            return newCards -- 组合成最大的同花
        else
            if v2 == 14 then
                table.insert(newCards, cards[2] - 1)
            else
                table.insert(newCards, (color1 << 8) | 14)
            end
            return newCards
        end
    end

    -- 最后组合成最大的对子
    if v1 > v2 then
        table.insert(newCards, (color2 << 8) | v1)
        return newCards
    else
        table.insert(newCards, (color1 << 8) | v2)
        return newCards
    end
end

-- 获取2张牌可组合的最大牌型
function TeenPatti:GetCardsType(cards)
    local newCards = self:getMaxCards(cards)
    return self:getPokerTypebyCards(newCards)
end