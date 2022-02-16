local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local texas = require(CLIBS["c_texas"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local COLOR_MASK = 0xf00
local VALUE_MASK = 0x00f

-- 默认牌
local DEFAULT_POKER_TABLE = {
    -- 2, 3, 4, 5, 6, 7, 8, 9 , 10, J, Q, K, A,
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

local EnumCowboyPokerType = {
    EnumCowboyPokerType_PieCard = 1,
    EnumCowboyPokerType_HighCard = 2, --高牌 Pie Card + HighCard
    EnumCowboyPokerType_Pair = 3, --对子
    EnumCowboyPokerType_TwoPair = 4, --两对
    EnumCowboyPokerType_ThreeKind = 5, --三条
    EnumCowboyPokerType_Straight = 6, --顺子
    EnumCowboyPokerType_Flush = 7, --同花
    EnumCowboyPokerType_FullHouse = 8, --葫芦
    EnumCowboyPokerType_FourKind = 9, --四条、金刚
    EnumCowboyPokerType_StraightFlush = 10,
    --同花顺
    EnumCowboyPokerType_RoyalFlush = 11
    --皇家同花顺
}

local EnumCowboyType = {
    --胜平负
    EnumCowboyType_Cowboy = 1, --牛仔
    EnumCowboyType_Bull = 2, --公牛
    EnumCowboyType_Draw = 3, --平局
    --任一手牌
    EnumCowboyType_FlushInRow = 4, --同花/连牌/同花连牌
    EnumCowboyType_Pair = 5, --对子(包含对A)
    EnumCowboyType_PairA = 6, --对子A
    --获胜牌型
    EnumCowboyType_HighCardPair = 7, --高牌/一对
    EnumCowboyType_TwoPair = 8, --两对
    EnumCowboyType_ThrKndStrghtFlsh = 9, --三条/顺子/同花
    EnumCowboyType_FullHouse = 10, --葫芦
    EnumCowboyType_BeyondFourKind = 11 --金刚/同花顺/皇家同花顺
}

Cowboy = Cowboy or {}
setmetatable(Cowboy, {__index = Poker})

function Cowboy:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    o:init(DEFAULT_POKER_TABLE, COLOR_MASK, VALUE_MASK)
    o.pokerhands = texas.create()
    return o
end

-- 两张牌同花
function Cowboy:isFlush(c1, c2)
    return (self:cardColor(c1) == self:cardColor(c2))
end

-- 连牌
function Cowboy:isInrow(c1, c2)
    local v1 = self:cardValue(c1)
    local v2 = self:cardValue(c2)
    if (v1 == 0xE and v2 == 0x2) or (v1 == 0x2 and v2 == 0xE) then
        return true
    end
    return (v1 == v2 + 1 or v2 == v1 + 1)
end

-- 对子
function Cowboy:isPair(c1, c2)
    local v1 = self:cardValue(c1)
    local v2 = self:cardValue(c2)
    return (v1 == v2)
end

-- 对 A
function Cowboy:isPairA(c1, c2)
    local v1 = self:cardValue(c1)
    local v2 = self:cardValue(c2)
    return (v1 == v2 and v1 == 0xE)
end

-- 牌型
function Cowboy:getPokersType(cards, cardsPub)
    assert(cards and type(cards) == "table" and #cards == 2)
    assert(cardsPub and type(cardsPub) == "table" and #cardsPub == 5)
    texas.initialize(self.pokerhands)
    texas.sethands(self.pokerhands, cards[1], cards[2], cardsPub)
    --最佳的五张牌
    local besthand = texas.checkhandstype(self.pokerhands)
    --最佳的五张牌组成的牌型
    local pokertype = texas.gethandstype(self.pokerhands)
    if pokertype == EnumCowboyPokerType.EnumCowboyPokerType_PieCard then
        pokertype = EnumCowboyPokerType.EnumCowboyPokerType_HighCard
    end
    return pokertype, besthand
end

-- 比较两组牌
-- @return -1, ct1, ct2 : (cardsA) < (cardsB), type(cardsA), type(cardsB)
-- @return 0, ct1, ct2 : (cardsA) == (cardsB), type(cardsA), type(cardsB)
-- @return 1, ct1, ct2 : (cardsA) > (cardsB), type(cardsA), type(cardsB)
function Cowboy:compareCards(cardsA, cardsB, cardsPub)
    assert(cardsA and type(cardsA) == "table" and #cardsA == 2)
    assert(cardsB and type(cardsB) == "table" and #cardsB == 2)
    assert(cardsPub and type(cardsPub) == "table" and #cardsPub == 5)
    local pokertypeA, besthandA = self:getPokersType(cardsA, cardsPub)
    local pokertypeB, besthandB = self:getPokersType(cardsB, cardsPub)
    return texas.comphandstype(self.pokerhands, pokertypeA, besthandA, pokertypeB, besthandB), pokertypeA, pokertypeB, besthandA, besthandB
end

-- 获取获胜类型
-- @param cardsA: 牛仔牌
-- @param cardsB: 公牛牌
-- @param cardsPub: 公共牌
-- @return wintypes, winpokertype, besthand
function Cowboy:getWinTypes(cardsA, cardsB, cardsPub)
    assert(cardsA and type(cardsA) == "table" and #cardsA == 2)
    assert(cardsB and type(cardsB) == "table" and #cardsB == 2)
    assert(cardsPub and type(cardsPub) == "table" and #cardsPub == 5)
    local wintypes = {} -- 存放所有赢的区域
    local winpokertype = -1
    local besthand = {}
    --胜平负
    local result, pokertypeA, pokertypeB, besthandA, besthandB = self:compareCards(cardsA, cardsB, cardsPub)
    if result == -1 then
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_Bull)
        winpokertype = pokertypeB
        besthand = besthandB
    elseif result == 0 then
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_Draw)
        winpokertype = pokertypeA
        besthand = besthandA
    else
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_Cowboy)
        winpokertype = pokertypeA
        besthand = besthandA
    end
    --任一手牌
    if
        self:isFlush(cardsA[1], cardsA[2]) or self:isFlush(cardsB[1], cardsB[2]) or self:isInrow(cardsA[1], cardsA[2]) or
            self:isInrow(cardsB[1], cardsB[2])
     then --同花/连牌/同花连牌
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_FlushInRow)
    end
    if self:isPair(cardsA[1], cardsA[2]) or self:isPair(cardsB[1], cardsB[2]) then --对子(包含对A)
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_Pair)
    end
    if self:isPairA(cardsA[1], cardsA[2]) or self:isPairA(cardsB[1], cardsB[2]) then --对子A
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_PairA)
    end
    --print(winpokertype, cjson.encode({EnumCowboyPokerType.EnumCowboyPokerType_ThreeKind, EnumCowboyPokerType.EnumCowboyPokerType_Straight, EnumCowboyPokerType.EnumCowboyPokerType_Flush}))
    --获胜牌型
    if
        g.isInTable(
            {EnumCowboyPokerType.EnumCowboyPokerType_HighCard, EnumCowboyPokerType.EnumCowboyPokerType_Pair},
            winpokertype
        )
     then --高牌/一对
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_HighCardPair)
    elseif winpokertype == EnumCowboyPokerType.EnumCowboyPokerType_TwoPair then --两对
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_TwoPair)
    elseif
        g.isInTable(
            {
                EnumCowboyPokerType.EnumCowboyPokerType_ThreeKind,
                EnumCowboyPokerType.EnumCowboyPokerType_Straight,
                EnumCowboyPokerType.EnumCowboyPokerType_Flush
            },
            winpokertype
        )
     then --三条/顺子/同花
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_ThrKndStrghtFlsh)
    elseif winpokertype == EnumCowboyPokerType.EnumCowboyPokerType_FullHouse then --葫芦
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_FullHouse)
    elseif
        g.isInTable(
            {
                EnumCowboyPokerType.EnumCowboyPokerType_FourKind,
                EnumCowboyPokerType.EnumCowboyPokerType_StraightFlush,
                EnumCowboyPokerType.EnumCowboyPokerType_RoyalFlush
            },
            winpokertype
        )
     then --金刚/同花顺/皇家同花顺
        table.insert(wintypes, EnumCowboyType.EnumCowboyType_BeyondFourKind)
    end
    return wintypes, winpokertype, besthand
end

local function test()
    local poker = Cowboy:new()

    local statistic_pokertype, handcard_statistic_pokertype = {}, {}
    for _, v in pairs(EnumCowboyPokerType) do
        statistic_pokertype[v] = 0
        handcard_statistic_pokertype[v] = 0
    end
    local tie_num = 0
    local totalnum = 1000000
    for i = 1, totalnum do
        poker:reset()
        local cardsA, cardsB = poker:getMNCard(2, 2) -- 牛仔牌，公牛牌
        local cardsPub = poker:getNCard(5) -- 公共牌
        local pokertypeA = poker:getPokersType(cardsA, cardsPub)
        local pokertypeB = poker:getPokersType(cardsB, cardsPub)
        local winTypes, winPokerType, besthands = poker:getWinTypes(cardsA, cardsB, cardsPub)

        if g.isInTable(winTypes, EnumCowboyType.EnumCowboyType_Draw) then
            tie_num = tie_num + 1
        else
            statistic_pokertype[winPokerType] = statistic_pokertype[winPokerType] + 1
            if
                (g.find(besthands, cardsA[1]) ~= -1 and g.find(besthands, cardsA[2]) ~= -1) or
                    (g.find(besthands, cardsB[1]) ~= -1 and g.find(besthands, cardsB[2]) ~= -1)
             then
                handcard_statistic_pokertype[winPokerType] = handcard_statistic_pokertype[winPokerType] + 1
            end
        end
    end
    for _, v in pairs(EnumCowboyPokerType) do
        print("pokertype:", v, statistic_pokertype[v] / totalnum)
    end
    print("tienum", tie_num / totalnum)
    for _, v in pairs(EnumCowboyPokerType) do
        print("pokertype:", v, handcard_statistic_pokertype[v] / totalnum)
    end
end

--test()
