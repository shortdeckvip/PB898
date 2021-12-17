local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

----0, 1, 2, 3, 4, 5, 6
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
local VALUE_MASK = 0xFF

local QiuQiuCardWinType = {
    QiuQiuCardWinType_HIGHCARD = 1,
    QiuQiuCardWinType_QIUQIU = 2,
    QiuQiuCardWinType_BIGSERIES = 3,
    QiuQiuCardWinType_SMALLSERIES = 4,
    QiuQiuCardWinType_TWINSERIES = 5,
    QiuQiuCardWinType_SIXGOD = 6
}

--一副牌
local MAX_POKER_NUM = 1

QiuQiu = QiuQiu or {}
setmetatable(QiuQiu, {__index = Poker})

function QiuQiu:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

local function unionIdxAndValue(self, card)
    self.uniqueid = self.uniqueid + 1
    return (self.uniqueid << 16) | card
end

function QiuQiu:resetAll()
end

function QiuQiu:start()
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
end

function QiuQiu:getPointSum(card)
    return self:cardColor(math.abs(card)) + self:cardValue(math.abs(card))
end

function QiuQiu:getHandType(handcard)
    local handtype = QiuQiuCardWinType.QiuQiuCardWinType_HIGHCARD
    if #handcard < 4 then
        return handtype
    end
    local check = true
    for _, v in ipairs(handcard) do
        if 6 ~= self:getPointSum(v) then
            check = false
            break
        end
    end
    if check then
        handtype = QiuQiuCardWinType.QiuQiuCardWinType_SIXGOD
        return handtype
    end

    check = true
    for _, v in ipairs(handcard) do
        if self:cardColor(math.abs(v)) ~= self:cardValue(math.abs(v)) then
            check = false
            break
        end
    end
    if check then
        handtype = QiuQiuCardWinType.QiuQiuCardWinType_TWINSERIES
        return handtype
    end

    local sumPoint = 0 
    for _, v in ipairs(handcard) do
        sumPoint = sumPoint + self:getPointSum(v)
    end
    if sumPoint <= 9 then
        handtype = QiuQiuCardWinType.QiuQiuCardWinType_SMALLSERIES
        return handtype
    end
    if sumPoint >= 39 then
        return QiuQiuCardWinType.QiuQiuCardWinType_BIGSERIES
    end

    if handtype == QiuQiuCardWinType.QiuQiuCardWinType_HIGHCARD then
        if
            (self:getPointSum(handcard[1]) + self:getPointSum(handcard[2])) % 10 == 9 and
                (self:getPointSum(handcard[3]) + self:getPointSum(handcard[4])) % 10 == 9
         then
            handtype = QiuQiuCardWinType.QiuQiuCardWinType_QIUQIU
        end
    end

    return handtype
end

function QiuQiu:compare(handcard1, handcard2)
    local handtype1 = self:getHandType(handcard1)
    local handtype2 = self:getHandType(handcard2)

    if handtype1 < handtype2 then
        return -1
    elseif handtype1 > handtype2 then
        return 1
    else
        local hc1_pair1 = (self:getPointSum(handcard1[1]) + self:getPointSum(handcard1[2])) % 10
        local hc1_pair2 = (self:getPointSum(handcard1[3]) + self:getPointSum(handcard1[4])) % 10

        local hc2_pair1 = (self:getPointSum(handcard2[1]) + self:getPointSum(handcard2[2])) % 10
        local hc2_pair2 = (self:getPointSum(handcard2[3]) + self:getPointSum(handcard2[4])) % 10

        if hc1_pair1 >= hc2_pair1 and hc1_pair2 > hc2_pair2 then
            return 1
        elseif hc1_pair1 <= hc2_pair1 and hc1_pair2 < hc2_pair2 then
            return -1
        elseif hc1_pair2 == hc2_pair2 then
            if hc1_pair1 > hc2_pair1 then
                return 1
            elseif hc1_pair1 < hc2_pair1 then
                return -1
            else
                return 0
            end
        else
            return 0
        end
    end
    assert(false)
end

function QiuQiu:checkValid(srccards, dstcards)
    if type(srccards) ~= "table" or type(dstcards) ~= "table" then
        return false
    end
    local srclen, dstlen = 0, 0
    for k, v in ipairs(srccards) do
        if v > 0 then
            srclen = srclen + 1
        end
        if (dstcards[k] or 0) > 0 then
            dstlen = dstlen + 1
        end
    end
    if srclen ~= dstlen or srclen < 3 then
        return false
    end
    srccards = g.copy(srccards)
    table.sort(
        srccards,
        function(a, b)
            return a > b
        end
    )
    local cmpdstcards = g.copy(dstcards)
    table.sort(
        cmpdstcards,
        function(a, b)
            return a > b
        end
    )
    for k, v in ipairs(cmpdstcards) do
        if v ~= srccards[k] then
            return false
        end
    end
    if srclen == 4 then
        local hc1_pair1 = (self:getPointSum(dstcards[1]) + self:getPointSum(dstcards[2])) % 10
        local hc1_pair2 = (self:getPointSum(dstcards[3]) + self:getPointSum(dstcards[4])) % 10
        if hc1_pair1 < hc1_pair2 then
            return false
        end
    end
    return true
end
