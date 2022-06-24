local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local EnumTeemPattiCardWinType = {
    EnumTeemPattiCardWinType_HIGHCARD = 1, --高牌
    EnumTeemPattiCardWinType_ONEPAIR = 2, --對子(pair)
    EnumTeemPattiCardWinType_FLUSH = 3, --同花(color)
    EnumTeemPattiCardWinType_STRAIGHT = 4, --順子(sequence)
    EnumTeemPattiCardWinType_STRAIGHTFLUSH = 5, --同花順(pure sequence)
    EnumTeemPattiCardWinType_THRREKAND = 6, --三條(set)
    EnumTeemPattiCardWinType_THRREKANDACE = 7 --三條Ace
}

local EnumTPBetType = {
    --胜平负
    EnumTPBetType_Red = 1, --红
    EnumTPBetType_Black = 2, --黑
    EnumTPBetType_Draw = 3, --和(赢牌独有类型)
    EnumTPBetType_OnePair = 4, -- 对子
    EnumTPBetType_Flush = 5, -- 同花
    EnumTPBetType_Straight = 6, -- 顺子
    EnumTPBetType_StraightFlush  = 7,-- 同花顺
    EnumTPBetType_ThrreKand  = 8, -- 三条
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
    return v >> 4
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

-- 获取牌型
function TeemPatti:getPokerTypebyCards(cards)
    if not cards then
        return 0
    end
    table.sort(cards, compByCardsValue)
    local ct = 0
    if isLeopard(cards) then    -- 三条
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKAND 

        if cardValue(cards[1]) == 0xE then -- 三条A
            ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKANDACE
        end
    elseif isStraightFlush(cards) then -- 同花顺
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHTFLUSH
    elseif isStraight(cards) then -- 顺子
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHT
    elseif isFlush(cards) then -- 同花
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_FLUSH
    elseif isPair(cards) then -- 对子
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_ONEPAIR
    else                      -- 高牌
        ct = EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_HIGHCARD 
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
function TeemPatti:isBankerWin(bankCards, otherCards)
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
    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHTFLUSH then
        local bt_a23 = isA32(bankCards)
        local ot_a23 = isA32(otherCards)
        if bt_a23 and ot_a23 then
            return 0
        end
        
        if bt_a23 then
            if  cardValue(otherCards[1]) == 0xE or cardValue(otherCards[3]) == 0xE  or cardValue(otherCards[2]) == 0xE then
                return -1
            else
                return 1;
            end
        end
        if ot_a23 then
            if  cardValue(bankCards[1]) == 0xE or cardValue(bankCards[3]) == 0xE or cardValue(bankCards[2]) == 0xE then
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
    if bt == EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHT then
        local bt_a23 = isA32(bankCards)
        local ot_a23 = isA32(otherCards)
        if bt_a23 and ot_a23 then
            return 0
        end
        
        if bt_a23 then
            if  cardValue(otherCards[1]) == 0xE or cardValue(otherCards[3]) == 0xE  or cardValue(otherCards[2]) == 0xE then
                return -1
            else
                return 1;
            end
        end
        if ot_a23 then
            if  cardValue(bankCards[1]) == 0xE or cardValue(bankCards[3]) == 0xE or cardValue(bankCards[2]) == 0xE then
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

-- 获取获胜类型
-- @param cardsA: 红牌
-- @param cardsB: 黑牌
-- @return wintypes,winpokertype
function TeemPatti:getWinTypes(cardsA,cardsB)
    assert(cardsA and type(cardsA) == "table" and #cardsA == 3)
    assert(cardsB and type(cardsB) == "table" and #cardsB == 3)

    local wintypes = {}
    local winpokertype = -1 
    --红和黑
	local result = self:isBankerWin(cardsA, cardsB)
	if result == -1 then -- 黑(cardsB赢)
		table.insert(wintypes,EnumTPBetType.EnumTPBetType_Black)
		winpokertype = self:getPokerTypebyCards(cardsB)
	elseif result == 0 then --和
		table.insert(wintypes, EnumTPBetType.EnumTPBetType_Draw)
		winpokertype = self:getPokerTypebyCards(cardsA)
	else
		table.insert(wintypes, EnumTPBetType.EnumTPBetType_Red)
		winpokertype = self:getPokerTypebyCards(cardsA)
	end

    

	--print(winpokertype, cjson.encode({EnumCowboyPokerType.EnumCowboyPokerType_ThreeKind, EnumCowboyPokerType.EnumCowboyPokerType_Straight, EnumCowboyPokerType.EnumCowboyPokerType_Flush}))
	
    --获胜牌型(可能一个下注区域包含几种牌型)
	if g.isInTable({EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHTFLUSH}, winpokertype) then  -- 同花顺
		table.insert(wintypes,EnumTPBetType.EnumTPBetType_StraightFlush)
    elseif g.isInTable({EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_ONEPAIR},winpokertype) then -- 对子
        table.insert(wintypes,EnumTPBetType.EnumTPBetType_OnePair)
    elseif g.isInTable({EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_FLUSH},winpokertype) then -- 同花
        table.insert(wintypes,EnumTPBetType.EnumTPBetType_Flush)
    elseif g.isInTable({EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_STRAIGHT},winpokertype) then -- 顺子
        table.insert(wintypes,EnumTPBetType.EnumTPBetType_Straight)
    elseif g.isInTable({EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKAND,EnumTeemPattiCardWinType.EnumTeemPattiCardWinType_THRREKANDACE},winpokertype) then -- 三条或者三条A
        table.insert(wintypes,EnumTPBetType.EnumTPBetType_ThrreKand)
    end

	return wintypes, winpokertype
end

--print(getPokerNameByType(getPokerTypebyCards({0x22,0x23,0x49})), isBankerWin({0x102,0x103,0x104}, {0x205,0x206,0x207}))
-------------------------牌型判定以及比较-----------------------

--[[
local poker = TeemPatti:new()
local statistic_pokertype = {0, 0, 0, 0, 0, 0, 0}
local tie_num = 0
local totalnum = 1000000
for i = 1, totalnum do
    poker:reset()
    local handcard1 = poker:getNCard(3)
    local handcard2 = poker:getNCard(3)
    local handtype1 = poker:getPokerTypebyCards(handcard1)
    local handtype2 = poker:getPokerTypebyCards(handcard2)
    --statistic_pokertype[handtype1] = statistic_pokertype[handtype1] + 1
    --statistic_pokertype[handtype2] = statistic_pokertype[handtype2] + 1
    local result = poker:isBankerWin(handcard1, handcard2)
    if result == 0 then
        tie_num = tie_num + 1
    elseif result == 1 then
        statistic_pokertype[handtype1] = statistic_pokertype[handtype1] + 1
    else
        statistic_pokertype[handtype2] = statistic_pokertype[handtype2] + 1
    end
end
print(
    "pokertype:",
    statistic_pokertype[1] / totalnum,
    " ",
    statistic_pokertype[2] / totalnum,
    " ",
    statistic_pokertype[3] / totalnum,
    " ",
    statistic_pokertype[4] / totalnum,
    " ",
    statistic_pokertype[5] / totalnum,
    " ",
    statistic_pokertype[6] / totalnum,
    " ",
    statistic_pokertype[7] / totalnum,
    " ",
    "tienum:",
    tie_num / totalnum
)

--]] --
