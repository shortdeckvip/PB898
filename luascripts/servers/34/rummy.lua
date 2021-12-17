local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local RUMMY_RES_TYPE = {
    RUMMY_RES_TYPE_PURERUN = 1,
    RUMMY_RES_TYPE_NONPURE_RUN = 2,
    RUMMY_RES_TYPE_SET = 3,
    RUMMY_RES_TYPE_INVALID = 4
}

local RUMMY_RES_COUNT = {
    --count,result
    [RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN] = 0,
    [RUMMY_RES_TYPE.RUMMY_RES_TYPE_NONPURE_RUN] = 0,
    [RUMMY_RES_TYPE.RUMMY_RES_TYPE_SET] = 0,
    [RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID] = 0
}

local LITTLE_JOKER = 0x50F
local BIG_JOKER = 0x510
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
    0x40E,
    --黑桃
    LITTLE_JOKER,
    BIG_JOKER
}
local COLOR_MASK = 0xFF00
local VALUE_MASK = 0xFF

--每人手上13张牌
local MAX_HANDCARDS_NUM = 13
--两副牌
local MAX_POKER_NUM = 2
--最高分值
local MAX_SCORE_VALUE = 80
--run(pure or non pure)mininum cards
local MIN_RUNCARDS_NUM = 3

local function cardColor(v)
    return (v & COLOR_MASK) >> 8
end

local function cardValue(v)
    return v & VALUE_MASK
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

local function isJoker(card)
    return cardColor(card) == cardColor(BIG_JOKER)
end

Rummy = Rummy or {}
setmetatable(Rummy, {__index = Poker})

function Rummy:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

local function unionIdxAndValue(self, card)
    self.uniqueid = self.uniqueid + 1
    return (self.uniqueid << 16) | card
end

function Rummy:resetAll()
    self.foldCards = {}
    self.magicCard = 0
    self.magicCards = {}
end

function Rummy:checkCardValid(card)
    card = card or 0
    local color = cardColor(card)
    local value = cardValue(card)
    return color >= 0x1 and color <= 0x5 and value >= 0x2 and value <= 0x10
end

function Rummy:start()
    --唯一索引递增器
    self.uniqueid = 0
    --初始化两副牌
    local poker = {}
    for i = 1, MAX_POKER_NUM do
        for _, v in ipairs(DEFAULT_POKER_TABLE) do
            table.insert(poker, unionIdxAndValue(self, v))
        end
    end

    --余牌集合
    self:init(poker, COLOR_MASK, VALUE_MASK)
    --弃牌集合
    self.foldCards = self:getNCard(1)
    --赖子
    self.magicCard = self:bottomCard()
    --RUMMYCONF.CONFCARDS.magiccard or self:bottomCard()
    local mc = self.magicCard
    --如果magic card是大小王，则Ace也是magic cards
    if cardColor(mc) == 5 then
        mc = 270
    end

    --赖子集合
    self.magicCards = {}
    for j = 1, 4 do
        table.insert(self.magicCards, (j << 8) | cardValue(mc))
    end
    table.insert(self.magicCards, LITTLE_JOKER)
    table.insert(self.magicCards, BIG_JOKER)
end

--获取弃牌最顶上牌
function Rummy:getTopFoldCard()
    return self.foldCards and (self.foldCards[#self.foldCards] or 0) or 0
end

--获取初始赖子
function Rummy:getMagicCard()
    return self.magicCard or 0
end

--获取赖子列表
function Rummy:getMagicCardList()
    return self.magicCards
end

function Rummy:getLeftFoldCardCnt()
    return self.foldCards and #self.foldCards or 0
end

--默认分组：按照花色进行分组
function Rummy:group(cards)
    cards = g.copy(cards)
    local groups = {{cards = {}}, {cards = {}}, {cards = {}}, {cards = {}}, {cards = {}}}
    for _, v in ipairs(cards) do
        table.insert(groups[cardColor(v)].cards, v)
    end
    for _, v in ipairs(groups) do
        table.sort(v.cards, compByCardsValue)
    end
    return groups
end

--摸牌，is_left：true 从余牌集合中抽出一张 否则从弃牌集合中抽出一张
function Rummy:draw(is_left)
    local card, reshuffle = 0, false

    if is_left then
        card = self:getNCard(1)[1], reshuffle
    else
        card = table.remove(self.foldCards), reshuffle
    end
    if not self:isLeft() then
        self:init(self.foldCards, COLOR_MASK, VALUE_MASK)
        self.foldCards = self:getNCard(1)
        self.magicCard = 0
        reshuffle = true
    end
    return card, reshuffle
end

--弃牌，需要校验card是否位于手牌中
function Rummy:discard(card)
    table.insert(self.foldCards, card)
end

--判定一组牌是Run还是Set
--√ Rule1:Mininum two runs(sequences) are required.
--√ Rule2:One of these runs(sequences) must be pure(called First Life).
--√ Rule3:The second run can be pure or non pure(called Second Life).
--√ Rule4:Either First or Second Life must have 4 or more cards.
--Rummy Rules
--√ A sequence/run can also use a joker(wild card) as substitute for any missing card. Such a sequence is non pure sequence. You can use only one joker in a mon-pure sequence.
--√ A set consists of 3 or 4 cards of same rank but of different suits or two such cards and a joker.
--√ Three cards of same rank and same suit(except printed jokers) are treated as pure sequence/run.
--× If the open card under the stock pile is a printed joker, then only the printed jokers are wild cards.
--√ While declaring. if you have unused jokers, select these jokers and put on a sequence plank.
--× When all the 13 cards are unmatched, you lose 80 points.
--√ If you drop from the game without picking even a single card from the discard pile or stock pile, you lose 20 points. If you drop in between a hand, before any othe player has done a valid declare, you lose 40 points.
function Rummy:getRunOrSet(grouCards)
    if type(grouCards) ~= "table" or #grouCards < 3 then
        return RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID
    end
    local tmp = {}
    for _, v in ipairs(grouCards) do
        table.insert(tmp, v & 0xFFFF)
    end
    --sort cards by card rank and card suit
    table.sort(tmp, compByCardsValue)
    local srctmp = g.copy(tmp)
    local jokerNum, jockerIdx = 0, {}
    --replace magicCards to big joker
    for k, v in ipairs(tmp) do
        if g.isInTable(self.magicCards, v) then
            table.insert(jockerIdx, k)
            tmp[k] = BIG_JOKER
            jokerNum = jokerNum + 1
        end
    end
    --remove joker cards
    for i = #jockerIdx, 1, -1 do
        table.remove(tmp, jockerIdx[i])
    end
    --You can use only one joker in a non-pure sequence
    if jokerNum > 1 then
    --return RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID
    end

    --A23需要特殊处理Ace的牌值
    --取两头最短距离，如果右侧距离大于等于左侧就把Ace换成1
    for i = #tmp, 1, -1 do
        if tmp[i] and cardValue(tmp[i]) ~= 0xE then
            if 0xE - cardValue(tmp[i]) >= cardValue(tmp[1]) then
                for j = 1, #tmp do
                    if cardValue(tmp[j]) == 0xE then
                        tmp[j] = (tmp[j] & COLOR_MASK) | 0x1
                    end
                end
                table.sort(tmp, compByCardsValue)
            end
            break
        end
    end

    --condition: preDiff < 0(SET) else RUN. RUN by default.
    --1.loop for non joker cards
    --2.diff
    local prevCard, leftJokerNum, preDiff = nil, jokerNum, nil
    for _, v in ipairs(tmp) do
        if v ~= BIG_JOKER then
            if prevCard then
                local diff = cardValue(v) - cardValue(prevCard) - 1
                preDiff = preDiff or diff
                --不允许既是RUN又是SET && 如果是SET，那么牌的花色不能一样 && 如果是RUN，那么牌的花色必须相同，即是同花顺
                if
                    ((preDiff < 0 and diff >= 0) or (preDiff >= 0 and diff < 0)) or
                        (preDiff < 0 and cardColor(v) == cardColor(prevCard)) or
                        (preDiff >= 0 and cardColor(v) ~= cardColor(prevCard))
                 then
                    leftJokerNum = -1
                    break
                end
                if diff > leftJokerNum then
                    leftJokerNum = -1
                    break
                else
                    leftJokerNum = leftJokerNum - (diff < 0 and 0 or diff)
                end
            end
            prevCard = v
        end
    end

    local res = RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID
    if leftJokerNum >= 0 then
        res =
            (preDiff or 0) < 0 and RUMMY_RES_TYPE.RUMMY_RES_TYPE_SET or
            (jokerNum == 0 and RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN or RUMMY_RES_TYPE.RUMMY_RES_TYPE_NONPURE_RUN)
    end

    if res == RUMMY_RES_TYPE.RUMMY_RES_TYPE_NONPURE_RUN then
        --检查赖子是否可以组成RUMMY_RES_TYPE_PURERUN
        if cardValue(srctmp[1]) == 0x2 and cardValue(srctmp[#srctmp]) == 0xE then
            srctmp[#srctmp] = (srctmp[#srctmp] & COLOR_MASK) | 0x1
            table.sort(srctmp, compByCardsValue)
        end
        for i = 2, #srctmp do
            if cardColor(srctmp[i]) ~= cardColor(srctmp[i - 1]) or cardValue(srctmp[i]) - cardValue(srctmp[i - 1]) ~= 1 then
                return res
            end
        end
        res = RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN
    elseif res == RUMMY_RES_TYPE.RUMMY_RES_TYPE_SET then
        --检查RUMMY_RES_TYPE_SET是否有赖子嵌入
        if #srctmp > 4 then
            res = RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID
        end
    end

    return res
end

local function cardScore(self, card)
    card = card & 0xFFFF
    if g.isInTable(self.magicCards, card) then
        return 0
    elseif cardValue(card) >= 10 then
        return 10
    end
    return cardValue(card)
end

--计算总分值:cards[group1,group2,group3...]
function Rummy:calScore(cards)
    --需要记录每一分组牌型索引
    local need_score_group = {}
    --每个分组牌型结果数量统计
    local count = g.copy(RUMMY_RES_COUNT)
    for _, v in ipairs(cards) do
        local res = self:getRunOrSet(v)
        count[res] = count[res] + 1
        table.insert(need_score_group, res)
    end

    --Rule4:Either First or Second Life must have 4 or more cards.
    local is_match_runcards = false
    for k, v in ipairs(need_score_group) do
        if v == RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN or v == RUMMY_RES_TYPE.RUMMY_RES_TYPE_NONPURE_RUN then
            is_match_runcards = #cards[k] >= MIN_RUNCARDS_NUM
        end
        if is_match_runcards then
            break
        end
    end
    if not is_match_runcards then
    --return MAX_SCORE_VALUE
    end

    local scoreSum = 0
    --√ Rule1:Mininum two runs(sequences) are required.
    --√ Rule2:One of these runs(sequences) must be pure(called First Life).
    --√ Rule3:The second run can be pure or non pure(called Second Life).
    --√ Rule4:Either First or Second Life must have 4 or more cards.
    if
        is_match_runcards and count[RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN] > 0 and
            count[RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN] + count[RUMMY_RES_TYPE.RUMMY_RES_TYPE_NONPURE_RUN] > 1
     then
        for k, v in ipairs(need_score_group) do
            if v == RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID then
                local score_cards = cards[k]
                for _, vv in ipairs(score_cards) do
                    scoreSum = scoreSum + cardScore(self, vv)
                end
            end
        end
    else
        for k, v in ipairs(need_score_group) do
            if v ~= RUMMY_RES_TYPE.RUMMY_RES_TYPE_PURERUN then
                local score_cards = cards[k]
                for _, vv in ipairs(score_cards) do
                    scoreSum = scoreSum + cardScore(self, vv)
                end
            end
        end
    end

    return scoreSum > MAX_SCORE_VALUE and MAX_SCORE_VALUE or scoreSum, count[RUMMY_RES_TYPE.RUMMY_RES_TYPE_INVALID] > 0
end

----test case begin
local function printCards(mark, cards)
    local str = mark
    for _, v in ipairs(cards) do
        str = str .. string.format(" 0x%x ", v)
    end
    print(str)
end
local function unit_test()
    local poker = Rummy:new()

    poker.magicCards = {0x102, 0x202, 0x302, 0x402, LITTLE_JOKER, BIG_JOKER}
    print("===========", poker:getRunOrSet({0x30E, 0x303, 0x304, LITTLE_JOKER, BIG_JOKER}))
    print("===========", poker:getRunOrSet({0x30E, 0x303, 0x304}))
    print("===========", poker:getRunOrSet({0x30E, 0x303, 0x302}))
    print(">>>>>>>>>>>>>>>>>>>>")
    poker.magicCards = {0x10E, 0x20E, 0x30E, 0x40E, LITTLE_JOKER, BIG_JOKER}
    print("===========", poker:getRunOrSet({0x30E, 0x302, 0x303, LITTLE_JOKER, BIG_JOKER}))
    print("===========", poker:getRunOrSet({0x30E, 0x302, 0x303}))
    print("===========", poker:getRunOrSet({0x30E, 0x302, 0x303, 0x30D}))
    print("===========", poker:getRunOrSet({0x30E, 0x302, 0x303, 0x30D, LITTLE_JOKER, BIG_JOKER}))
    --[[
    local score =
        poker:calScore(
        {
            {
                2622466,
                2688003,
                3408910
            },
            {
                5833482,
                2360075,
                3540240
            },
            {
                1245703,
                6489095,
                4784647
            },
            {
                1901316,
                5505797,
                3474703,
                2032390
            },
            {}
        }
    )

    print("============= ", score)
    --]]
    --[[
    for i = 1, 1 do
        poker:start()
        local topFoldCard = poker:getTopFoldCard()
        local magicCard = poker:getMagicCard()

        printCards("magiccards", poker.magicCards)

        --deal cards for five positions
        local seats = {
            {handcards = poker:getNCard(MAX_HANDCARDS_NUM)},
            {handcards = poker:getNCard(MAX_HANDCARDS_NUM)},
            {handcards = poker:getNCard(MAX_HANDCARDS_NUM)},
            {handcards = poker:getNCard(MAX_HANDCARDS_NUM)},
            {handcards = poker:getNCard(MAX_HANDCARDS_NUM)}
        }
        for j = 1, #poker.cards + 3 do
            local d, r = poker:draw(true)
            poker:discard(d)
            poker:getLeftCardsCnt()
            --v.handcards, v.groupcards = poker:group(v.handcards)
            --printCards("handcards", v.handcards)
            --for _, vv in ipairs(v.groupcards) do
            --    printCards("groupcards", vv)
            --    print(poker:getRunOrSet(vv))
            --end
            --print("=========score:", poker:calScore(v.groupcards))
        end
    end
    --]]
end
--unit_test()
--assert(false)
----test case end
