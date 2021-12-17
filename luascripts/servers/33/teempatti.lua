local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local EnumTeemPattiCardWinType = {
    EnumTeemPattiCardWinType_HIGHCARD = 1, --高牌
    EnumTeemPattiCardWinType_ONEPAIR = 2, --對子
    EnumTeemPattiCardWinType_FLUSH = 3, --同花
    EnumTeemPattiCardWinType_STRAIGHT = 4, --順子
    EnumTeemPattiCardWinType_STRAIGHTFLUSH = 5, --同花順
    EnumTeemPattiCardWinType_THRREKAND = 6, --三條
    EnumTeemPattiCardWinType_THRREKANDACE = 7 --三條Ace
}

TeemPatti = TeemPatti or {}
setmetatable(TeemPatti, {__index = Poker})

function TeemPatti:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    o:init()
    return o
end

-------------------------牌型判定以及比较-----------------------
local function cardColor(v)
    return v >> 8
end

local function cardValue(v)
    return v & 0xf
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

function TeemPatti:getPokerTypebyCards(cards)
    if not cards then
        return 0
    end
    table.sort(cards, compByCardsValue)
    local ct = 0
    if isLeopard(cards) then
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKAND
        if cardValue(cards[1]) == 0xE then
            ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKANDACE
        end
    elseif isStraightFlush(cards) then
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHTFLUSH
    elseif isStraight(cards) then
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHT
    elseif isFlush(cards) then
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_FLUSH
    elseif isPair(cards) then
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_ONEPAIR
    else
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_HIGHCARD
    end
    return ct
end

--牌型规则：
--三条>同花顺>同花>顺子>对子>高牌。
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
function TeemPatti:isBankerWin(bankCards, otherCards)
    if not bankCards or not otherCards then
        return -1
    end
    local bt = self:getPokerTypebyCards(bankCards) -- 获取庄家牌型
    local ot = self:getPokerTypebyCards(otherCards) -- 获取牌型

    if bt ~= ot then
        if bt > ot then
            return 1
        elseif bt < ot then
            return -1
        end
    end

    -- 下面是牌型相同的情况
    if
        bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKAND or
            bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKANDACE
     then
        if cardValue(bankCards[1]) > cardValue(otherCards[1]) then
            return 1
        elseif cardValue(bankCards[1]) < cardValue(otherCards[1]) then
            return -1
        else
            return 0
        end
    end

    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHTFLUSH then -- 如果为同花顺
        local bt_a23 = isA32(bankCards)
        local ot_a23 = isA32(otherCards)
        if bt_a23 and ot_a23 then
            return 0
        end
        if bt_a23 then
            if cardValue(otherCards[1]) == 0xE or cardValue(otherCards[3]) == 0xE or cardValue(otherCards[2]) == 0xE then
                return -1
            else
                return 1
            end
        end
        if ot_a23 then
            if cardValue(bankCards[1]) == 0xE or cardValue(bankCards[3]) == 0xE or cardValue(bankCards[2]) == 0xE then
                return 1
            else
                return -1
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
    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHT then -- 顺子
        local bt_a23 = isA32(bankCards)
        local ot_a23 = isA32(otherCards)
        if bt_a23 and ot_a23 then
            return 0
        end

        if bt_a23 then
            if cardValue(otherCards[1]) == 0xE or cardValue(otherCards[3]) == 0xE or cardValue(otherCards[2]) == 0xE then
                return -1
            else
                return 1
            end
        end
        if ot_a23 then
            if cardValue(bankCards[1]) == 0xE or cardValue(bankCards[3]) == 0xE or cardValue(bankCards[2]) == 0xE then
                return 1
            else
                return -1
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
    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_FLUSH then
        for i = 3, 1, -1 do
            if cardValue(bankCards[i]) > cardValue(otherCards[i]) then
                return 1
            elseif cardValue(bankCards[i]) < cardValue(otherCards[i]) then
                return -1
            end
        end
        return 0
    end
    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_ONEPAIR then
        if cardValue(bankCards[2]) > cardValue(otherCards[2]) then
            return 1
        elseif cardValue(bankCards[2]) < cardValue(otherCards[2]) then
            return -1
        else
            if cardValue(bankCards[1]) + cardValue(bankCards[3]) > cardValue(otherCards[1]) + cardValue(otherCards[3]) then
                return 1
            elseif
                cardValue(bankCards[1]) + cardValue(bankCards[3]) < cardValue(otherCards[1]) + cardValue(otherCards[3])
             then
                return -1
            else
                return 0
            end
        end
    end
    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_HIGHCARD then
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

function TeemPatti:getPokerNameByType(pt)
    if pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKANDACE then
        return "三条Ace"
    elseif pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKAND then
        return "三条"
    elseif pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHTFLUSH then
        return "同花顺"
    elseif pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHT then
        return "顺子"
    elseif pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_FLUSH then
        return "同花"
    elseif pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_ONEPAIR then
        return "对子"
    elseif pt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_HIGHCARD then
        return "高牌"
    else
        return "无效牌型"
    end
end

-- 判断某张牌是否已经发出去了
-- 参数 sendcards: 已经发出的所有牌
function TeemPatti:hasSend(sendcards, card)
    if type(sendcards) ~= "table" then
        return false
    end
    for i, v in pairs(sendcards) do
        if v and v == card then
            return true
        end
    end
    return false
end

-- 根据2张已知牌获取Joker牌数据(合成最大的一手牌)
-- 参数 handcards: 手牌(共2张)
function TeemPatti:getJokerCard(handcards)
    local jokerCard = 0
    if cardValue(handcards[1]) == cardValue(handcards[2]) then
        local color = rand.rand_between(1, 4) -- 随机花色
        local value = rand.rand_between(2, 0xE) -- 随机牌值
        if value == cardValue(handcards[1]) then -- 避免出现3张情况
            if value == 0xE then
                value = value - 1
            else
                value = value + 1
            end
        end
        jokerCard = value + (color << 8) -- 第3张牌随机
    else
        if cardColor(handcards[1]) == cardColor(handcards[2]) then -- 如果手牌花色相同
            -- 判断是否可以合成顺子
            if cardValue(handcards[1]) < cardValue(handcards[2]) then
                if cardValue(handcards[2]) - cardValue(handcards[1]) == 2 then -- 中间一张是joker
                    jokerCard = handcards[1] + 1
                elseif cardValue(handcards[2]) - cardValue(handcards[1]) == 1 then --边上一张是joker
                    if cardValue(handcards[2]) == 0xE then -- 如果大牌为A
                        jokerCard = handcards[1] - 1
                    elseif cardValue(handcards[1]) == 0x2 then -- 2 3   A
                        jokerCard = handcards[1] + 0xE - 0x2
                    else
                        jokerCard = handcards[2] + 1
                    end
                elseif cardValue(handcards[2]) == 0xE then -- 如果有一张牌为A，判断是否可以合成32A这个顺子
                    if cardValue(handcards[1]) == 0x2 then
                        jokerCard = handcards[1] + 1
                    elseif cardValue(handcards[1]) == 0x3 then
                        jokerCard = handcards[1] - 1
                    end
                end
            else
                if cardValue(handcards[1]) - cardValue(handcards[2]) == 2 then -- 中间一张是joker
                    jokerCard = handcards[2] + 1
                elseif cardValue(handcards[1]) - cardValue(handcards[2]) == 1 then --边上一张是joker
                    if cardValue(handcards[1]) == 0xE then -- 如果大牌为A
                        jokerCard = handcards[2] - 1
                    elseif cardValue(handcards[2]) == 0x2 then -- 2 3   A
                        jokerCard = handcards[2] + 0xE - 0x2
                    else
                        jokerCard = handcards[1] + 1
                    end
                elseif cardValue(handcards[1]) == 0xE then -- 如果有一张牌为A，判断是否可以合成32A这个顺子
                    if cardValue(handcards[2]) == 0x2 then
                        jokerCard = handcards[2] + 1
                    elseif cardValue(handcards[2]) == 0x3 then
                        jokerCard = handcards[2] - 1
                    end
                end
            end
            if jokerCard == 0 then -- 如果未能合成同花顺
                local randnum = rand.rand_between(2, 0xE)
                jokerCard = (handcards[1] & 0xFF00) + randnum
                if handcards[1] == jokerCard or handcards[2] == jokerCard then -- 如果出现重复的牌
                    if randnum < 0xE then
                        randnum = randnum + 1
                    else
                        randnum = 0x2
                    end
                    jokerCard = (handcards[1] & 0xFF00) + randnum
                    if handcards[1] == jokerCard or handcards[2] == jokerCard then
                        if randnum < 0xE then
                            randnum = randnum + 1
                        else
                            randnum = 0x2
                        end
                        jokerCard = (handcards[1] & 0xFF00) + randnum
                    end
                end
            else -- 可合成同花顺
                -- 修改joker牌的花色，使其变成顺子 
                if jokerCard >= 0x400 then
                    jokerCard = jokerCard - 0x100
                else
                    jokerCard = jokerCard + 0x100
                end
            end
            return jokerCard
        end

        --判断是否可以合成顺子
        if cardValue(handcards[1]) < cardValue(handcards[2]) then
            if cardValue(handcards[2]) - cardValue(handcards[1]) == 2 then -- 中间一张是joker
                jokerCard = handcards[1] + 1
            elseif cardValue(handcards[2]) - cardValue(handcards[1]) == 1 then --边上一张是joker
                if cardValue(handcards[2]) == 0xE then -- 如果大牌为A
                    jokerCard = handcards[1] - 1
                elseif cardValue(handcards[1]) == 0x2 then
                    jokerCard = handcards[1] + 0xE - 0x2
                else
                    jokerCard = handcards[2] + 1
                end
            elseif cardValue(handcards[2]) == 0xE then -- 如果有一张牌为A，判断是否可以合成32A这个顺子
                if cardValue(handcards[1]) == 0x2 then
                    jokerCard = handcards[1] + 1
                elseif cardValue(handcards[1]) == 0x3 then
                    jokerCard = handcards[1] - 1
                end
            end
        else
            if cardValue(handcards[1]) - cardValue(handcards[2]) == 2 then -- 中间一张是joker
                jokerCard = handcards[2] + 1
            elseif cardValue(handcards[1]) - cardValue(handcards[2]) == 1 then --边上一张是joker
                if cardValue(handcards[1]) == 0xE then -- 如果大牌为A
                    jokerCard = handcards[2] - 1
                elseif cardValue(handcards[2]) == 0x2 then
                    jokerCard = handcards[2] + 0xE - 0x2
                else
                    jokerCard = handcards[1] + 1
                end
            elseif cardValue(handcards[1]) == 0xE then -- 如果有一张牌为A，判断是否可以合成32A这个顺子
                if cardValue(handcards[2]) == 0x2 then
                    jokerCard = handcards[2] + 1
                elseif cardValue(handcards[2]) == 0x3 then
                    jokerCard = handcards[2] - 1
                end
            end
        end
        if jokerCard ~= 0 then -- 如果可以合成顺子
            return jokerCard
        end

        -- 合成对子
        if rand.rand_between(1, 100) > 50 then
            if cardColor(handcards[2]) == 4 then
                jokerCard = handcards[2] - 0x100
            else
                jokerCard = handcards[2] + 0x100
            end
        else
            if cardColor(handcards[1]) == 4 then
                jokerCard = handcards[1] - 0x100
            else
                jokerCard = handcards[1] + 0x100
            end
        end
    end
    return jokerCard
end

--print(getPokerNameByType(getPokerTypebyCards({0x22,0x23,0x49})), isBankerWin({0x102,0x103,0x104}, {0x205,0x206,0x207}))
-------------------------牌型判定以及比较-----------------------

--[[
local poker = TeemPatti:new()
local statistic_pokertype = {0, 0, 0, 0, 0, 0, 0}
local tie_num = 0
for i = 1, 1000 do
    poker:reset()
    local handcard1 = poker:getNCard(3)
    local handcard2 = poker:getNCard(3)
    local handtype1 = poker:getPokerNameByType(poker:getPokerTypebyCards(handcard1))
    local handtype2 = poker:getPokerNameByType(poker:getPokerTypebyCards(handcard2))
    statistic_pokertype[handtype1] = statistic_pokertype[handtype1] + 1
    statistic_pokertype[handtype2] = statistic_pokertype[handtype2] + 1
    if poker:isBankerWin(handcard1, handcard2) == 0 then
        tie_num = tie_num + 1
    end
end
print(
    "pokertype:",
    statistic_pokertype[1],
    " ",
    statistic_pokertype[2],
    " ",
    statistic_pokertype[3],
    " ",
    statistic_pokertype[4],
    " ",
    statistic_pokertype[5],
    " ",
    statistic_pokertype[6],
    " ",
    statistic_pokertype[7],
    " ",
    "tienum:",
    tie_num
)

--]] --
