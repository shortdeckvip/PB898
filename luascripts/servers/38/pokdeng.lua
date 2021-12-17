-- serverdev\luascripts\servers\38\pokdeng.lua
local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local log = require(CLIBS["c_log"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

--- 博定牌数据(共52张)
local DEFAULT_POKER_TABLE = {
    ---- 2, 3, 4, 5, 6, 7, 8, 9 , 10, J, Q, K, A,
    0x102, -- 2
    0x103, -- 3
    0x104, -- 4
    0x105, -- 5
    0x106, -- 6
    0x107, -- 7
    0x108, -- 8
    0x109, -- 9
    0x10A, -- 10
    0x10B, -- J
    0x10C, -- Q
    0x10D, -- K
    0x10E, -- A
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
local VALUE_MASK = 0x00FF

--每人手上至少2张牌，最多3张牌
local MAX_HANDCARDS_NUM = 3
--一副牌
local MAX_POKER_NUM = 1

local PokDengCardType = {
    PokDengCardType_Normal = 1, -- 普通牌
    PokDengCardType_TwoSameColorValue = 2, -- 同花两张或对子
    PokDengCardType_SameColor = 3, -- 同花三张
    PokDengCardType_Serial = 4, -- 顺子(三张牌)
    PokDengCardType_SameColorSerial = 5, -- 同花顺
    PokDengCardType_ThreeYellow = 6, -- 三黄(3张牌，有且只有KQJ组成的牌,如：KKJ)
    PokDengCardType_ThreeSamePoint = 7, -- 三条(3张牌组成，数值一样的牌,如：AAA)
    PokDengCardType_8_NotSameColorValue = 8, -- 博定8-非同花或者对子
    PokDengCardType_8_SameColorValue = 9, -- 博定8-同花或者对子
    PokDengCardType_9_NotSameColor = 10, -- 博定9-非同花
    PokDengCardType_9_SameColor = 11 -- 博定9-同花(博定9且为同花)
}

local PokDengCardTypeMuti = {
    [PokDengCardType.PokDengCardType_Normal] = 1, -- 普通牌
    [PokDengCardType.PokDengCardType_TwoSameColorValue] = 2, -- 同花两张或对子
    [PokDengCardType.PokDengCardType_SameColor] = 3, -- 同花三张
    [PokDengCardType.PokDengCardType_Serial] = 3, -- 顺子(三张牌)
    [PokDengCardType.PokDengCardType_SameColorSerial] = 5, -- 同花顺
    [PokDengCardType.PokDengCardType_ThreeYellow] = 3, -- 三黄(3张牌，有且只有KQJ组成的牌,如：KKJ)
    [PokDengCardType.PokDengCardType_ThreeSamePoint] = 5, -- 三条(3张牌组成，数值一样的牌,如：AAA)
    [PokDengCardType.PokDengCardType_8_NotSameColorValue] = 1, -- 博定8-非同花或者对子
    [PokDengCardType.PokDengCardType_8_SameColorValue] = 2, -- 博定8-同花或者对子
    [PokDengCardType.PokDengCardType_9_NotSameColor] = 1, -- 博定9-非同花
    [PokDengCardType.PokDengCardType_9_SameColor] = 2 -- 博定9-同花(博定9且为同花)
}

PokDeng = PokDeng or {}
setmetatable(PokDeng, {__index = Poker})

--
function PokDeng:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    return o
end

-- 设置唯一牌值
local function unionIdxAndValue(self, card)
    self.uniqueid = self.uniqueid + 1
    return (self.uniqueid << 16) | card
end

-- 重置
function PokDeng:resetAll()
    self:reset()
end

--
function PokDeng:start()
    --唯一索引递增器
    self.uniqueid = 0
    --初始化1副牌
    -- local poker = {}
    -- for i = 1, MAX_POKER_NUM do
    --     for _, v in ipairs(DEFAULT_POKER_TABLE) do
    --         table.insert(poker, unionIdxAndValue(self, v))
    --     end
    -- end

    --余牌集合
    -- self:init(poker, COLOR_MASK, VALUE_MASK)
    self:init(DEFAULT_POKER_TABLE, COLOR_MASK, VALUE_MASK)
end

-- -- 随机获取num张牌
-- function PokDeng:getCards(num)
--     local poker = {} -- 要获取的扑克
--     -- self:init()
--     self:reset() -- 洗牌
--     for i = 1, num, 1 do
--         poker[i] = self.cards[i]
--     end
--     return poker
-- end

--function Poker:getNCard(n)

-- 获取点数
function PokDeng:getPointSum(card)
    return self:cardColor(math.abs(card)) + self:cardValue(math.abs(card))
end

------------------------------------------------------

-- 根据一组牌获取牌型
function PokDeng:getCardType(handcard)
    local cardtype = PokDengCardType.PokDengCardType_Normal
    --判断是否为表类型
    if type(handcard) ~= "table" then
        return cardtype
    end

    local cardnum = #handcard -- 牌张数

    if cardnum == 2 then
        local totalPoint = self:getCardPoint(handcard)
        if totalPoint == 9 then
            if self:cardColor(handcard[1]) == self:cardColor(handcard[2]) then
                return PokDengCardType.PokDengCardType_9_SameColor
            else
                return PokDengCardType.PokDengCardType_9_NotSameColor
            end
        elseif totalPoint == 8 then
            if
                self:cardColor(handcard[1]) == self:cardColor(handcard[2]) or
                    (self:cardValue(handcard[1]) == self:cardValue(handcard[2]))
             then
                return PokDengCardType.PokDengCardType_8_SameColorValue
            else
                return PokDengCardType.PokDengCardType_8_NotSameColorValue
            end
        end
    elseif cardnum == 3 then
        if
            (self:cardValue(handcard[1]) == self:cardValue(handcard[2])) and
                self:cardValue(handcard[1]) == self:cardValue(handcard[3])
         then
            return PokDengCardType.PokDengCardType_ThreeSamePoint -- 三条
        end

        -- 三黄判断
        if
            (0xB <= self:cardValue(handcard[1]) and (self:cardValue(handcard[1]) <= 0xD)) and
                (0xB <= self:cardValue(handcard[2]) and (self:cardValue(handcard[2]) <= 0xD)) and
                (0xB <= self:cardValue(handcard[3]) and (self:cardValue(handcard[3]) <= 0xD))
         then
            return PokDengCardType.PokDengCardType_ThreeYellow -- 三黄色
        end

        local isSerial = false
        -- 判断是否是顺子

        if self:cardValue(handcard[1]) > self:cardValue(handcard[2]) then
            if
                self:cardValue(handcard[3]) == (self:cardValue(handcard[1]) + 1) and
                    self:cardValue(handcard[1]) == (self:cardValue(handcard[2] + 1))
             then
                isSerial = true
            elseif
                self:cardValue(handcard[1]) == (self:cardValue(handcard[3]) + 1) and
                    self:cardValue(handcard[3]) == (self:cardValue(handcard[2] + 1))
             then
                isSerial = true
            elseif
                self:cardValue(handcard[1]) == (self:cardValue(handcard[2]) + 1) and
                    self:cardValue(handcard[2]) == (self:cardValue(handcard[3] + 1))
             then
                isSerial = true
            end
        else
            if
                self:cardValue(handcard[3]) == (self:cardValue(handcard[2]) + 1) and
                    self:cardValue(handcard[2]) == (self:cardValue(handcard[1] + 1))
             then
                isSerial = true
            elseif
                self:cardValue(handcard[2]) == (self:cardValue(handcard[3]) + 1) and
                    self:cardValue(handcard[3]) == (self:cardValue(handcard[1] + 1))
             then
                isSerial = true
            elseif
                self:cardValue(handcard[2]) == (self:cardValue(handcard[1]) + 1) and
                    self:cardValue(handcard[1]) == (self:cardValue(handcard[3] + 1))
             then
                isSerial = true
            end
        end

        if isSerial then -- 如果是顺子
            if
                (self:cardColor(handcard[1]) == self:cardColor(handcard[2])) and
                    self:cardColor(handcard[1]) == self:cardColor(handcard[3])
             then -- 如果是同花色
                return PokDengCardType.PokDengCardType_SameColorSerial
            else
                return PokDengCardType.PokDengCardType_Serial
            end
        end
    end

    return cardtype
end

-- 根据一组牌获取牌型
function PokDeng:getNormalCardType(handcard)
    local cardtype = PokDengCardType.PokDengCardType_Normal
    --判断是否为表类型
    if type(handcard) ~= "table" then
        return cardtype
    end

    local cardnum = #handcard -- 牌张数

    if cardnum == 2 then
        -- 同花2张或对子
        if self:cardValue(handcard[1]) == self:cardValue(handcard[2]) or self:cardColor(handcard[1]) == self:cardColor(handcard[2])  then
            return PokDengCardType.PokDengCardType_TwoSameColorValue
        end
    elseif cardnum == 3 then
        if
            (self:cardColor(handcard[1]) == self:cardColor(handcard[2])) and
                self:cardColor(handcard[1]) == self:cardColor(handcard[3])
         then -- 如果是同花色
            return PokDengCardType.PokDengCardType_SameColor -- 同花三张
        end
    end
    return cardtype
end

--比较两手牌大小
-- 返回值: 第一手牌大则返回正数1，相等则返回0，第二手牌大就返回-1
function PokDeng:compare(handcard1, handcard2)
    local handtype1 = self:getCardType(handcard1)
    local handtype2 = self:getCardType(handcard2)
    if handtype1 > handtype2 then
        return 1
    elseif handtype1 < handtype2 then
        return -1
    end
    -- 下面是牌型相同的情况
    if handtype1 >= PokDengCardType.PokDengCardType_8_NotSameColorValue then
        return 0
    end
    if handtype1 == PokDengCardType.PokDengCardType_ThreeSamePoint then
        if handcard1[1] > handcard2[1] then
            return 1
        else
            return -1
        end
    end

    -- 三黄 比较
    if handtype1 == PokDengCardType.PokDengCardType_ThreeYellow then
        local sortedcard1 = self:sort(handcard1)
        local sortedcard2 = self:sort(handcard1)

        if self:cardValue(sortedcard1[1]) > self:cardValue(sortedcard2[1]) then
            return 1
        elseif self:cardValue(sortedcard1[1]) < self:cardValue(sortedcard2[1]) then
            return -1
        else
            if self:cardValue(sortedcard1[2]) > self:cardValue(sortedcard2[2]) then
                return 1
            elseif self:cardValue(sortedcard1[2]) < self:cardValue(sortedcard2[2]) then
                return -1
            else
                if self:cardValue(sortedcard1[3]) > self:cardValue(sortedcard2[3]) then
                    return 1
                elseif self:cardValue(sortedcard1[3]) < self:cardValue(sortedcard2[3]) then
                    return -1
                else
                    return 0
                end
            end
        end
    end

    -- 同花顺
    if handtype1 == PokDengCardType.PokDengCardType_SameColorSerial then
        local sortedcard1 = self:sort(handcard1)
        local sortedcard2 = self:sort(handcard1)
        if self:cardValue(sortedcard1[1]) > self:cardValue(sortedcard2[1]) then
            return 1
        elseif self:cardValue(sortedcard1[1]) < self:cardValue(sortedcard2[1]) then
            return -1
        else
            if self:cardColor(handcard1[1]) > self:cardColor(handcard2[1]) then
                return 1
            else
                return -1
            end
        end
    end

    -- 顺子
    if handtype1 == PokDengCardType.PokDengCardType_Serial then
        local sortedcard1 = self:sort(handcard1)
        local sortedcard2 = self:sort(handcard1)
        if self:cardValue(sortedcard1[1]) > self:cardValue(sortedcard2[1]) then
            return 1
        elseif self:cardValue(sortedcard1[1]) < self:cardValue(sortedcard2[1]) then
            return -1
        else
            return 0
        end
    end

    -- 普通牌型(首先根据点数判断，若点数相同，则根据普通牌型判断)
    local point1 = self:getCardPoint(handcard1)
    local point2 = self:getCardPoint(handcard2)
    if point1 > point2 then
        return 1
    elseif point1 < point2 then
        return -1
    else -- 点数相同时
        local normalType1 = self:getNormalCardType(handcard1)
        local normalType2 = self:getNormalCardType(handcard2)
        if normalType1 > normalType2 then
            return 1
        elseif normalType1 < normalType2 then
            return -1
        end
        return 0
    end
end

-- 根据两手牌的牌型获取输赢倍数
function PokDeng:getWinTimes(bigCardType, smallCardType)
    if bigCardType == PokDengCardType.PokDengCardType_9_SameColor then
        if smallCardType == PokDengCardType.PokDengCardType_9_NotSameColor then
            return 1
        else
            return 2
        end
    elseif bigCardType == PokDengCardType.PokDengCardType_9_NotSameColor then
        return 1
    elseif bigCardType == PokDengCardType.PokDengCardType_8_SameColorValue then
        if smallCardType < PokDengCardType.PokDengCardType_8_NotSameColorValue then
            return 2
        end
        return 1
    elseif bigCardType == PokDengCardType.PokDengCardType_8_NotSameColorValue then
        return 1
    elseif bigCardType == PokDengCardType.PokDengCardType_ThreeSamePoint then
        return 5
    elseif bigCardType == PokDengCardType.PokDengCardType_ThreeYellow then
        return 3
    elseif bigCardType == PokDengCardType.PokDengCardType_SameColorSerial then
        return 5
    elseif bigCardType == PokDengCardType.PokDengCardType_Serial then
        return 3
    elseif bigCardType == PokDengCardType.PokDengCardType_SameColor then
        if smallCardType == PokDengCardType.PokDengCardType_Normal then
            return 2
        end
        return 1
    end
    return 1
end

-- 根据牌型获取倍数
function PokDeng:getTimesByType(cardType)
    return PokDengCardTypeMuti[cardType]
end

-- 根据牌数据获取倍数 
function PokDeng:getTimesByCard(handcard)
    local cardType = self:getCardType(handcard)
    if cardType == PokDengCardType.PokDengCardType_Normal then
        cardType = self:getNormalCardType(handcard)
    end
    return PokDengCardTypeMuti[cardType]
end



-- 从大到小排序
function PokDeng:sort(handcard)
    local sortedCard = g.copy(handcard)
    local buf = sortedCard[1]

    if self:cardValue(sortedCard[1]) < self:cardValue(sortedCard[2]) then
        buf = sortedCard[1]
        sortedCard[1] = sortedCard[2]
        sortedCard[2] = buf
    end
    if self:cardValue(sortedCard[2]) < self:cardValue(sortedCard[3]) then
        buf = sortedCard[2]
        sortedCard[2] = sortedCard[3]
        sortedCard[3] = buf
    end
    if self:cardValue(sortedCard[1]) < self:cardValue(sortedCard[2]) then
        buf = sortedCard[1]
        sortedCard[1] = sortedCard[2]
        sortedCard[2] = buf
    end

    return sortedCard
end

--- 获取一手牌的点数
function PokDeng:getCardPoint(handcard)
    local totalPoint = 0
    local cardNum = #handcard
    local point = 0

    if cardNum <= 0 or cardNum > 3 then
        return totalPoint
    end

    for i = 1, cardNum, 1 do
        point = self:cardValue(handcard[i])
        if point == 0xE then
            point = 1 -- A为1点
        elseif point > 10 then
            point = 0 -- 10、J、Q、K为0点
        end
        totalPoint = totalPoint + point
    end
    totalPoint = totalPoint % 10

    return totalPoint
end
