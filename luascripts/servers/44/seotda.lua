local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")


-- 花札(花牌)
Seotda = Seotda or {}


-- 牌型
local EnumSeotdaCardsType = {
    EnumSeotdaCardsType_End_0      = 1, -- 망통(两张牌月份之和个的位数数值大小为0)
    EnumSeotdaCardsType_End_1_8    = 2, -- 끗(两张牌月份之和个的位数数值大小为1~8)
    EnumSeotdaCardsType_End_9      = 3, -- 갑오(月份加在一起时最后一位数字为 9 的任何牌组合)（例如 1+8、2+7、3+6、4+5、9+10）
    EnumSeotdaCardsType_4_6        = 4, -- 세륙(4月和6月的组合)  出现的概率 = 2/95
    EnumSeotdaCardsType_4_10       = 5, -- 장사(4月和10月的组合) 出现的概率 = 2/95
    EnumSeotdaCardsType_1_10       = 6, -- 장삥(1月和10月的组合) 出现的概率 = 2/95
    EnumSeotdaCardsType_1_9        = 7, -- 구삥(1月和9月的组合)  出现的概率 = 2/95
    EnumSeotdaCardsType_1_4        = 8, -- 독사(1月和4月的组合)  出现的概率 = 2/95
    EnumSeotdaCardsType_1_2        = 9, -- 알리(1月和2月的组合)  出现的概率 = 2/95
    EnumSeotdaCardsType_DuiZi      = 10, -- 땡 对子(相同月份的两张牌组合，按月份大小排序)    出现的概率 = 1/19
    EnumSeotdaCardsType_GuangDui   = 11, -- 광땡 光对(0x11+0x31 或 0x11+0x81)  13光对或18光对  出现的概率 = 1/95
    EnumSeotdaCardsType_38GuangDui = 12, -- 38광땡 38光对(0x31+0x81)   出现的概率 = 2/(20*19) = 1/190
}


-- 特殊牌型
local EnumSeotdaSpecialCardsType = {
    EnumSeotdaSpecialCardsType_Other = 1,
    EnumSeotdaSpecialCardsType_0x41_0x91     = 2, -- 멍텅구리구사(4月和9月不包括丝带的卡牌组合)
    EnumSeotdaSpecialCardsType_0x4X_0x9X     = 3, -- 구사(除去멍텅구리구사以外的4月和9月卡牌组合)
    EnumSeotdaSpecialCardsType_0x41_0x71     = 4, -- 암행어사(0x41+0x71)
    EnumSeotdaSpecialCardsType_0x31_0x71     = 5, -- 땡잡이(0x31+0x71)
}



-- 获取牌数据
function Seotda:GetCards()
    local cards = {
        0x11, 0x12, -- 1月  松树
        0x21, 0x22, -- 2月  梅花
        0x31, 0x32, -- 3月  樱花
        0x41, 0x42, -- 4月  紫藤
        0x51, 0x52, -- 5月  鸢尾（菖蒲）
        0x61, 0x62, -- 6月  牡丹
        0x71, 0x72, -- 7月  胡枝子（萩）
        0x81, 0x82, -- 8月  芒草
        0x91, 0x92, -- 9月  菊花
        0xA1, 0xA2, -- 10月 枫叶（红叶）
    }
    return cards
end

-- 根据2张牌数据获取牌型
function Seotda:GetCardsType(cards)
    if type(cards) ~= "table" or #cards < 2 then
        return 0
    end
    -- 确保第一张牌<第二张牌
    if cards[1] > cards[2] then
        cards[1], cards[2] = cards[2], cards[1]
    end

    if 0x31 == cards[1] and 0x81 == cards[2] then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_38GuangDui -- 38光对(0x31+0x81)
    end

    if 0x11 == cards[1] and (0x81 == cards[2] or 0x31 == cards[2]) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_GuangDui -- 光对(13光对或18光对)
    end

    if (cards[1] & 0xF0) == (cards[2] & 0xF0) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_DuiZi -- 对子
    end
    if (cards[1] & 0xF0 == 0x10) and (cards[2] & 0xF0 == 0x20) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_1_2 --
    end

    if (cards[1] & 0xF0 == 0x10) and (cards[2] & 0xF0 == 0x40) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_1_4 --
    end

    if (cards[1] & 0xF0 == 0x10) and (cards[2] & 0xF0 == 0x90) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_1_9 --
    end

    if (cards[1] & 0xF0 == 0x10) and (cards[2] & 0xF0 == 0xA0) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_1_10 --
    end

    if (cards[1] & 0xF0 == 0x40) and (cards[2] & 0xF0 == 0xA0) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_4_10 --
    end

    if (cards[1] & 0xF0 == 0x40) and (cards[2] & 0xF0 == 0x60) then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_4_6 --
    end

    local point1 = (cards[1] & 0xF0) >> 4;
    local point2 = (cards[2] & 0xF0) >> 4;
    local totalPoint = (point1 + point2) % 10
    if totalPoint == 9 then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_End_9 --
    end

    if 1 <= totalPoint and totalPoint <= 8 then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_End_1_8 --
    end

    if totalPoint == 9 then
        return EnumSeotdaCardsType.EnumSeotdaCardsType_End_0 --
    end

    return EnumSeotdaCardsType.EnumSeotdaCardsType_End_0 -- 最小牌型
end

-- 获取特殊牌牌型
function Seotda:GetSpecialCardsType(cards)
    if type(cards) ~= "table" or #cards < 2 then
        return 0
    end

    -- 确保第一张牌<第二张牌
    if cards[1] > cards[2] then
        cards[1], cards[2] = cards[2], cards[1]
    end

    if cards[1] == 0x31 and cards[2] == 0x71 then
        return EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x31_0x71
    end

    if cards[1] == 0x41 and cards[2] == 0x71 then
        return EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x41_0x71
    end
    if (cards[1] == 0x41 and cards[2] == 0x92) or (cards[1] == 0x42 and cards[2] == 0x91) or (cards[1] == 0x42 and cards[2] == 0x92) then
        return EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x4X_0x9X
    end
    if cards[1] == 0x41 and cards[2] == 0x91 then
        return EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x41_0x91 --멍텅구리구사(0x91+0x41)
    end
    return EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_Other -- 非特殊牌
end

-- 返回值: 第1手牌大则返回1，第1手牌小则返回-1，相等则返回0
function Seotda:Compare(cards1, cards2)
    local cardsType1 = self:GetCardsType(cards1)
    local cardsType2 = self:GetCardsType(cards2)
    if cardsType1 > cardsType2 then
        return 1
    elseif cardsType1 < cardsType2 then
        return -1
    end

    -- 对子
    if EnumSeotdaCardsType.EnumSeotdaCardsType_DuiZi == cardsType1 then
        if cards1[1] > cards2[2] then
            return 1
        else
            return -1
        end
    end

    -- 끗 (1~8끗)
    if EnumSeotdaCardsType.EnumSeotdaCardsType_End_1_8 == cardsType1 then
        local totalPoint1 = (((cards1[1] & 0xF0) >> 4) + ((cards1[2] & 0xF0) >> 4)) % 10
        local totalPoint2 = (((cards2[1] & 0xF0) >> 4) + ((cards2[2] & 0xF0) >> 4)) % 10
        if totalPoint1 > totalPoint2 then
            return 1
        elseif totalPoint1 < totalPoint2 then
            return -1
        else
            return 0
        end
    end

    return 0
end

-- 获取最大牌玩家牌型
function Seotda:GetMaxCardsType(cards1, cards2, cards3, cards4, cards5)
    local maxCards = cards1
    local ret = self:Compare(cards1, cards2)
    if ret == -1 then
        maxCards = cards2
    end
    if cards3 then
        ret = self:Compare(maxCards, cards3)
        if ret == -1 then
            maxCards = cards3
        end
    end

    if cards4 then
        ret = self:Compare(maxCards, cards4)
        if ret == -1 then
            maxCards = cards4
        end
    end

    if cards5 then
        ret = self:Compare(maxCards, cards5)
        if ret == -1 then
            maxCards = cards5
        end
    end
    return self:GetCardsType(maxCards)
end

-- 判断是否比最大牌要大
-- 参数 cards: 当前要比较的牌
-- 参数 maxCards: 最大牌
-- 返回值: 如果是特殊牌且比最大牌还大则返回1，否则返回0
function Seotda:CompareSpecial(cards, maxCards)
    local specialCards = self:GetSpecialCardsType(cards)
    local maxCardsType = self:GetCardsType(maxCards)

    if maxCardsType == EnumSeotdaCardsType.EnumSeotdaCardsType_GuangDui then  -- 光对
        if EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x41_0x71 == specialCards then
            return 1
        end
        return 0
    end
    if maxCardsType == EnumSeotdaCardsType.EnumSeotdaCardsType_DuiZi then
        if EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x31_0x71 == specialCards then
            if maxCards[1] < 0xA0 then   -- 比牌时其他玩家最大牌是1-9对，땡잡이获胜
                return 1
            end
        end
    end

    return 0
end

