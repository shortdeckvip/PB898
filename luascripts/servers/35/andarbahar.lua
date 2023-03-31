local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local texas = require(CLIBS["c_texas"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local ANDAR_BAHAR_WINTYPE = {
    ANDAR_BAHAR_WINTYPE_ANDAR = 1, -- Andar
    ANDAR_BAHAR_WINTYPE_BAHAR = 2, -- Bahar
}

local ANDAR_BAHAR_WINTYPE_IB = {
    ANDAR_BAHAR_WINTYPE_ANDAR = 1, -- Andar
    ANDAR_BAHAR_WINTYPE_BAHAR = 2, -- Bahar

    ANDAR_BAHAR_WINTYPE_1_5   = 3,
    ANDAR_BAHAR_WINTYPE_6_10  = 4,
    ANDAR_BAHAR_WINTYPE_11_15 = 5,
    ANDAR_BAHAR_WINTYPE_16_25 = 6,
    ANDAR_BAHAR_WINTYPE_26_30 = 7,
    ANDAR_BAHAR_WINTYPE_31_35 = 8,
    ANDAR_BAHAR_WINTYPE_36_40 = 9,
    ANDAR_BAHAR_WINTYPE_41_52 = 10,
}


AndarBahar = AndarBahar or {}
setmetatable(AndarBahar, { __index = Poker })

function AndarBahar:new(o)
    o = o or {}
    setmetatable(o, { __index = self })

    o:init()
    return o
end

-- 根据牌数据获取赢得一方及第几张牌与第一张大小相同
-- 返回值: 第1个值是第几张牌与第一张相同，第2个值是指哪一方赢
function AndarBahar:getWinType(Cards)
    local winArea = {} -- 赢的区域
    local cardnum = #Cards; -- 牌张数
    local equalpos = 1 -- 第几张牌与第一张牌大小相同
    local first_value = self:cardValue(Cards[1]) % 0x0E; -- 第一张牌点数
    for i = 2, cardnum, 1 do
        if first_value == (self:cardValue(Cards[i]) % 0x0E) then
            if (i % 2) == 0 then
                --winArea[1] = ANDAR_BAHAR_WINTYPE.ANDAR_BAHAR_WINTYPE_ANDAR
                --return  i, ANDAR_BAHAR_WINTYPE.ANDAR_BAHAR_WINTYPE_ANDAR
                table.insert(winArea, ANDAR_BAHAR_WINTYPE.ANDAR_BAHAR_WINTYPE_ANDAR)
            else
                table.insert(winArea, ANDAR_BAHAR_WINTYPE.ANDAR_BAHAR_WINTYPE_BAHAR)
            end
            return i, winArea
        end
    end
end

-- 根据牌数据获取赢得一方及第几张牌与第一张大小相同
-- 返回值: 第1个值是第几张牌与第一张相同，第2个值是指哪一方赢
function AndarBahar:getWinType_IB(Cards)
    local winArea = {} -- 赢的区域
    local cardnum = #Cards; -- 牌张数
    local equalpos = 1 -- 第几张牌与第一张牌大小相同
    local first_value = self:cardValue(Cards[1]) % 0x0E; -- 第一张牌点数
    for i = 2, cardnum, 1 do
        if first_value == (self:cardValue(Cards[i]) % 0x0E) then
            if (i % 2) == 0 then
                --winArea[1] = ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_ANDAR
                --return  i, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_ANDAR
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_ANDAR)
            else
                --winArea[1] = ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_BAHAR
                --return  i, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_BAHAR
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_BAHAR)
            end

            
            local j = i - 1
            if j <= 5 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_1_5)
            elseif j <= 10 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_6_10)
            elseif j <= 15 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_11_15)
            elseif j <= 25 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_16_25)
            elseif j <= 30 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_26_30)
            elseif j <= 35 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_31_35)
            elseif j <= 40 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_36_40)
            elseif j <= 52 then
                table.insert(winArea, ANDAR_BAHAR_WINTYPE_IB.ANDAR_BAHAR_WINTYPE_41_52)
            end
            return i, winArea
        end
    end
end
