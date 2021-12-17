local pb = require("protobuf")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local DUMMY_RES_TYPE = {
    DUMMY_RES_TYPE_RUN = 1,
    DUMMY_RES_TYPE_SET = 2,
    DUMMY_RES_TYPE_INVALID = 3
}

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
local COLOR_MASK = 0xFF00
local VALUE_MASK = 0xFF

Dummy = Dummy or {}
setmetatable(Dummy, {__index = Poker})

function Dummy:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

local function cardIndex(card)
    return (card >> 24) & 0xFF
end

local function cardSid(card)
    return (card >> 20) & 0xF
end

local function unionIdxAndValue(id, card)
    return (id << 24) | card
end

function Dummy:setOwnerSid(sid, card)
    card = card & 0xFF0FFFFF
    card = card | (sid << 20)
    return card
end

function Dummy:setToSid(sid, card)
    card = card & 0xFFF0FFFF
    card = card | (sid << 16)
    return card
end

function Dummy:resetAll()
    self.foldCards = {}
end

function Dummy:start()
    --余牌集合
    self:init(nil, COLOR_MASK, VALUE_MASK)
    for k, v in ipairs(self.cards) do
        self.cards[k] = unionIdxAndValue(k, v)
    end
    --弃牌集合
    self.foldCards = self:getNCard(1)
end

function Dummy:trimByOwnerSid(cards, sid)
    cards = cards or {}
    local res = {}
    for _, v in ipairs(cards) do
        if cardSid(v) == sid then
            table.insert(res, v)
        end
    end
    return res
end

function Dummy:isInFoldCard(card)
    for _, vv in ipairs(self.foldCards) do
        if card == vv then
            return true
        end
    end
    return false
end

function Dummy:getFoldCard()
    return self.foldCards or {}
end

function Dummy:dealCard(n, sid)
    local cards
    if self:isLeft() then
        cards = self:getNCard(n)
        for k, v in ipairs(cards) do
            cards[k] = self:setOwnerSid(sid, v)
        end
    end
    return cards
end

--check create
function Dummy:isAllFold(discards)
    discards = discards or {}
    if #discards > 0 then
        local len = 0
        --包含整个子序列
        for _, v in ipairs(self.foldCards) do
            if v == discards[1] then
                len = len + 1
            elseif len > 0 then
                len = len + 1
            end
            if v == discards[#discards] then
                break
            end
        end
        return discards[#discards] == self.foldCards[#self.foldCards] and len == #discards
    end
    return false
end

--生牌(从弃牌集合中抽出首张至末尾)
function Dummy:create(discards)
    local cards = {}
    discards = discards or {}
    if #discards > 0 then
        local discard = discards[1]
        local idx = #self.foldCards
        for k, v in ipairs(self.foldCards) do
            if discard == v then
                idx = k
                break
            end
        end
        for i = #self.foldCards, idx, -1 do
            if not g.isInTable(discards, self.foldCards[i]) then
                table.insert(cards, 1, self.foldCards[i])
            end
            table.remove(self.foldCards, i)
        end
    end
    return cards
end

--在生牌的时候触发 foldcard：弃牌堆上的牌列表 zone
function Dummy:onCreatePoint(sid, foldcard, handcard, zone)
    local tosid, additional = 0, {}

    for k, v in ipairs(zone) do
        zone[k] = self:setOwnerSid(sid, v)
    end

    if cardIndex(foldcard[1]) == 1 then
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FirstCard")] = 50
    end
    if #foldcard >= 2 and handcard and #handcard > 0 then
        --放炮首牌
        if cardIndex(foldcard[1]) == 1 and cardSid(foldcard[#foldcard]) ~= sid then
            tosid = cardSid(foldcard[#foldcard])
            additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FirstBlast")] = -50
        end
        --放炮特殊牌(♣2或者♠Q)
        for _, v in ipairs(foldcard) do
            if self:isSpecialCard(v) and cardSid(foldcard[#foldcard]) ~= sid then
                tosid = cardSid(foldcard[#foldcard])
                additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SpecialBlast")] = -50
                break
            end
        end
    end
    return {tosid, additional}
end

--在丢牌的时候触发
function Dummy:onDropPoint(card, zones)
    local additional = {}
    local tmp = g.copy(self.foldCards)
    self:sort(tmp)
    --丢分
    for i = 1, #tmp - 2 do
        local isin = card == tmp[i] or card == tmp[i + 1] or card == tmp[i + 2]
        if isin and self:getRunOrSet({tmp[i], tmp[i + 1], tmp[i + 2]}) ~= DUMMY_RES_TYPE.DUMMY_RES_TYPE_INVALID then
            additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DropScore")] = -50
            break
        end
    end

    --丢大米
    for _, v in ipairs(zones) do
        local ctype = self:getRunOrSet(v)
        if ctype == DUMMY_RES_TYPE.DUMMY_RES_TYPE_RUN then
            if
                self:cardColor(card) == self:cardColor(v[1]) and
                    (self:cardValue(card) + 1 == self:cardValue(v[1]) or
                        self:cardValue(v[#v]) + 1 == self:cardValue(card))
             then
                additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DropDummy")] = -50
                break
            end
        elseif ctype == DUMMY_RES_TYPE.DUMMY_RES_TYPE_SET then
            if self:cardValue(card) == self:cardValue(v[1]) then
                additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DropDummy")] = -50
                break
            end
        end
    end
    return additional
end

function Dummy:isSpecialCard(card)
    return (self:cardColor(card) == 0x2 and self:cardValue(card) == 0x2) or
        (self:cardColor(card) == 0x4 and self:cardValue(card) == 0xC)
end

--在存牌的时候触发
function Dummy:onSavePoint(card, zone)
    local tosid, additional = 0, {}
    if
        self:isSpecialCard(card) and
            (self:cardValue(card) == self:cardValue(zone[1]) or self:cardValue(card) == self:cardValue(zone[#zone]))
     then
        tosid = cardSid(card)
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SpetTo")] = -50
    end
    return {tosid, additional}
end

--在Knock的时候触发
function Dummy:onKnockPoint(card, zone, zones, lastfoldcard, oneshotflag)
    local tosid, knocktype = 0, pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_KNOCK")
    local additional = {}
    local savesid, savezoneid = 0, 0

    --knock
    additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_KNOCK")] = 50
    --手上最后一张牌拿去存牌
    for _, v in ipairs(zones) do
        --zone,sid,zoneid
        local vv = v[1]
        local ctype = self:getRunOrSet(vv)
        if ctype == DUMMY_RES_TYPE.DUMMY_RES_TYPE_RUN then
            if self:cardValue(card) + 1 == self:cardValue(vv[1]) or self:cardValue(vv[#vv]) + 1 == self:cardValue(card) then
                additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SaveLast")] = 50
                savesid = v[2]
                savezoneid = v[3]
                break
            end
        elseif ctype == DUMMY_RES_TYPE.DUMMY_RES_TYPE_SET then
            if self:cardValue(card) == self:cardValue(vv[1]) then
                additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SaveLast")] = 50
                savesid = v[2]
                savezoneid = v[3]
                break
            end
        end
    end

    --特殊牌（梅花2或者黑桃Q）Knock
    if self:isSpecialCard(card) then
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SpecialKnock")] = 50
        knocktype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SpecialKnock")
    end

    --同花knock
    local csum, color = 0, 0
    for _, v in ipairs(zone) do
        local ctype = self:getRunOrSet(v)
        if ctype ~= DUMMY_RES_TYPE.DUMMY_RES_TYPE_RUN then
            break
        end
        color = self:cardColor(v[1])
        csum = csum + color
    end
    if csum > 0 and csum == color * #zone then
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FlushKnock")] = 2
        knocktype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FlushKnock")
    end

    --蠢
    if lastfoldcard > 0 then
        tosid = cardSid(lastfoldcard)
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_Stupid")] = -50
    end

    --一次knock
    if oneshotflag > 0 then
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_OnceKnock")] = 2
        knocktype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_OnceKnock")
    end

    --超级knock
    if
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_OnceKnock")] and
            additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FlushKnock")]
     then
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FlushKnock")] = nil
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_OnceKnock")] = nil
        additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SuperKnock")] = 4
        knocktype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SuperKnock")
    end

    return {tosid, additional, knocktype, savesid, savezoneid}
end

--弃牌，需要校验card是否位于手牌中
function Dummy:discard(card)
    table.insert(self.foldCards, card)
end

--判定一组牌是Run还是Set(同花顺或3条)
function Dummy:getRunOrSet(grouCards)
    if type(grouCards) ~= "table" or #grouCards < 3 then
        return DUMMY_RES_TYPE.DUMMY_RES_TYPE_INVALID
    end
    local tmp = g.copy(grouCards)
    self:sort(tmp)

    if self:cardValue(tmp[1]) == self:cardValue(tmp[#tmp]) then
        return DUMMY_RES_TYPE.DUMMY_RES_TYPE_SET
    end
    local c = self:cardColor(tmp[1])
    for i = 2, #tmp do
        if self:cardValue(tmp[i - 1]) + 1 ~= self:cardValue(tmp[i]) or c ~= self:cardColor(tmp[i]) then
            return DUMMY_RES_TYPE.DUMMY_RES_TYPE_INVALID
        end
    end

    return DUMMY_RES_TYPE.DUMMY_RES_TYPE_RUN
end

function Dummy:calZoneScore(cards, sid)
    --local ctype = self:getRunOrSet(cards)
    local sum = 0
    for _, v in ipairs(cards) do
        local cv = self:cardValue(v)
        local cc = self:cardColor(v)
        if sid == cardSid(v) then
            if cv >= 0x2 and cv <= 0x9 then
                if cc == 0x2 and cv == 0x2 then
                    sum = sum + 50
                else
                    sum = sum + 5
                end
            elseif cv >= 0xA and cv <= 0xD then
                if cc == 0x4 and cv == 0xC then
                    sum = sum + 50
                else
                    sum = sum + 10
                end
            elseif cv == 0xE then
                sum = sum + 15
            --if ctype == DUMMY_RES_TYPE.DUMMY_RES_TYPE_RUN then
            --    sum = sum + 10
            --elseif ctype == DUMMY_RES_TYPE.DUMMY_RES_TYPE_SET then
            --    sum = sum + 15
            --end
            end
        end
    end
    return sum
end

function Dummy:calHandScore(cards)
    local sum = 0
    for _, v in ipairs(cards) do
        local cv = self:cardValue(v)
        if cv >= 0x2 and cv <= 0x9 then
            sum = sum + 5
        elseif cv >= 0xA and cv < 0xE then
            sum = sum + 10
        elseif cv == 0xE then
            sum = sum + 15
        end
    end
    return sum
end

local function test()
    local poker = Dummy:new()
    poker:start()

    local card = 171966732
    local tmp = {0x302, 0x308, 0x404, 0x303}
    poker:sort(tmp)
    --丢分
    for i = 1, #tmp - 2 do
        local isin = card == tmp[i] or card == tmp[i + 1] or card == tmp[i + 2]
        print("ssssssssss", i, poker:getRunOrSet({tmp[i], tmp[i + 1], tmp[i + 2]}))
        if isin and poker:getRunOrSet({tmp[i], tmp[i + 1], tmp[i + 2]}) ~= DUMMY_RES_TYPE.DUMMY_RES_TYPE_INVALID then
            break
        end
    end
end
--test()
--assert(false)
