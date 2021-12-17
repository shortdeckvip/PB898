local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local SamGongCardWinType = {
    SamGongCardWinType_PointCard = 1,
    SamGongCardWinType_Flush = 2,
    SamGongCardWinType_Straight = 3,
    SamGongCardWinType_JQKCard = 4,
    SamGongCardWinType_FlushStraight = 5,
    SamGongCardWinType_SamGong = 6
}

SamGong = SamGong or {}
setmetatable(SamGong, {__index = Poker})

function SamGong:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

function SamGong:resetAll()
end

function SamGong:start()
    self:init()
end

function SamGong:checkStraight(cards)
    local value = self:cardValue(cards[1])
    return (self:cardValue(cards[2]) == value + 1 and self:cardValue(cards[3]) == value + 2) or
        (value == 0x2 and self:cardValue(cards[2]) == 0x3 and self:cardValue(cards[3]) == 0xE)
end

function SamGong:getPoint(cards)
    local sumpoint = 0
    for _, v in ipairs(cards) do
        local p = self:cardValue(v)
        if p >= 0xA then
            p = 0
        end
        sumpoint = sumpoint + p
    end
    return sumpoint % 10
end

function SamGong:getHandType(handcard)
    local handtype = SamGongCardWinType.SamGongCardWinType_PointCard

    local cards = g.copy(handcard)
    self:sort(cards)
    local color, value = self:cardColor(cards[1]), self:cardValue(cards[1])

    if value == self:cardValue(cards[2]) and value == self:cardValue(cards[3]) then
        handtype = SamGongCardWinType.SamGongCardWinType_SamGong
    elseif color == self:cardColor(cards[3]) and color == self:cardColor(cards[2]) and self:checkStraight(cards) then
        handtype = SamGongCardWinType.SamGongCardWinType_FlushStraight
    elseif value > 0xA and self:cardValue(cards[3]) < 0xE then
        handtype = SamGongCardWinType.SamGongCardWinType_JQKCard
    elseif self:checkStraight(cards) then
        handtype = SamGongCardWinType.SamGongCardWinType_Straight
    elseif color == self:cardColor(cards[3]) and color == self:cardColor(cards[2]) then
        handtype = SamGongCardWinType.SamGongCardWinType_Flush
    end

    return handtype, cards
end

function SamGong:compare(handcard1, handcard2)
    local handtype1, cards1 = self:getHandType(handcard1)
    local handtype2, cards2 = self:getHandType(handcard2)

    if handtype1 < handtype2 then
        return -1
    elseif handtype1 > handtype2 then
        return 1
    else
        if handtype1 == SamGongCardWinType.SamGongCardWinType_SamGong then
            if self:cardValue(cards1[1]) == 3 then
                return 1
            elseif self:cardValue(cards2[1]) == 0x3 then
                return -1
            elseif self:cardValue(cards1[1]) == 0xE then
                return 1
            elseif self:cardValue(cards2[1]) == 0xE then
                return -1
            else
                return self:cardValue(cards1[1]) > self:cardValue(cards2[1]) and 1 or -1
            end
        elseif handtype1 == SamGongCardWinType.SamGongCardWinType_FlushStraight then
            if self:cardColor(cards1[1]) > self:cardColor(cards2[1]) then
                return 1
            elseif self:cardColor(cards1[1]) < self:cardColor(cards2[1]) then
                return -1
            else
                if self:cardValue(cards1[1]) > self:cardValue(cards2[1]) then
                    return 1
                elseif self:cardValue(cards1[1]) < self:cardValue(cards2[1]) then
                    return -1
                else
                    return self:cardValue(cards1[3]) > self:cardValue(cards2[3]) and 1 or -1
                end
            end
        elseif handtype1 == SamGongCardWinType.SamGongCardWinType_JQKCard then
            local card1 = self:getMaxCard(cards1)
            local card2 = self:getMaxCard(cards2)
            if self:cardValue(card1) > self:cardValue(card2) then
                return 1
            elseif self:cardValue(card1) < self:cardValue(card2) then
                return -1
            else
                return self:cardColor(card1) > self:cardColor(card2) and 1 or -1
            end   
        elseif handtype1 == SamGongCardWinType.SamGongCardWinType_Straight then
            if self:cardValue(cards1[1]) > self:cardValue(cards2[1]) then
                return 1
            elseif self:cardValue(cards1[1]) < self:cardValue(cards2[1]) then
                return -1
            else
                return self:cardColor(cards1[3]) > self:cardColor(cards2[3]) and 1 or -1
            end
        elseif handtype1 == SamGongCardWinType.SamGongCardWinType_Flush then
            if self:cardColor(cards1[3]) > self:cardColor(cards2[3]) then
                return 1
            elseif self:cardColor(cards1[3]) < self:cardColor(cards2[3]) then
                return -1
            else
                return self:cardValue(cards1[3]) > self:cardValue(cards2[3]) and 1 or -1
            end
        elseif handtype1 == SamGongCardWinType.SamGongCardWinType_PointCard then
            local card1Point = self:getCardsPoint(cards1)
            local card2Point = self:getCardsPoint(cards2)
            if card1Point > card2Point then
                return 1
            elseif card1Point < card2Point then
                return -1
            end
            local card1 = self:getMaxCard(cards1)
            local card2 = self:getMaxCard(cards2)
            card1Point = self:cardValue(card1)
            card2Point = self:cardValue(card2)
            if card1Point > card2Point then
                return 1
            elseif card1Point < card2Point then
                return -1
            end
            if self:cardColor(card1) > self:cardColor(card2) then
                return 1
            else
                return -1
            end
        end
    end
end

-- 获取一手牌的点数
function SamGong:getCardsPoint(cards)
    local sumpoint = 0
    for _, v in ipairs(cards) do
        local p = self:cardValue(v)
        if p == 0xE then
            sumpoint = sumpoint + 1
        elseif p < 0xA then
            sumpoint = sumpoint + p
        end
    end
    sumpoint = sumpoint % 10
    return sumpoint
end

-- 获取最大的牌(K>Q>J>10>9>8>7>6>5>4>3>2>A)
function SamGong:getMaxCard(cards)
    local card = 0
    local point = 0
    for _, v in ipairs(cards) do
        if self:cardValue(v) == 0xE then
            if point < 1 then
                point = 1
                card = v
            end
        elseif self:cardValue(v) > point then
            point = self:cardValue(v)
            card = v
        elseif self:cardValue(v) == point then
            if self:cardColor(v) > self:cardColor(card) then
                card = v
            end
        end
    end
    return card
end


-- 获取最大的牌(A>K>Q>J>10>9>8>7>6>5>4>3>2)
function SamGong:getMaxCardA(cards)
    local card = 0
    for _, v in ipairs(cards) do
        if self:cardValue(v) > self:cardValue(card) then
            card = v
        elseif self:cardValue(v) == self:cardValue(card) then
            if self:cardColor(v) > self:cardColor(card) then
                card = v
            end
        end
    end
    return card
end




local function test()
    local poker = SamGong:new()
    local maxnum = 10
    for i = 1, maxnum do
        poker:start()
        local handcards1 = {poker:pop(), poker:pop(), poker:pop()}
        local handcards2 = {poker:pop(), poker:pop(), poker:pop()}
        local handtype1 = poker:getHandType(handcards1)
        local handtype2 = poker:getHandType(handcards2)
        local result = poker:compare(handcards1, handcards2)
        local fstr =
            string.format(
            "handcards1 %s:%s handcards2 %s:%s result %s",
            cjson.encode(handcards1),
            handtype1,
            cjson.encode(handcards2),
            handtype2,
            result
        )
        print(fstr)
    end
end

--test()
