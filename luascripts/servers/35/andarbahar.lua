local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local texas = require(CLIBS["c_texas"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local ANDAR_BAHAR_WINTYPE = {
	ANDAR_BAHAR_WINTYPE_ANDAR	= 1,      -- Andar 
	ANDAR_BAHAR_WINTYPE_BAHAR	= 2,      -- Bahar 
}

AndarBahar = AndarBahar or {}
setmetatable(AndarBahar, {__index = Poker})

function AndarBahar:new(o)
	o = o or {}
	setmetatable(o, {__index = self})

	o:init()
	return o
end



-- 根据牌数据获取赢得一方及第几张牌与第一张大小相同 
-- 返回值: 第1个值是第几张牌与第一张相同，第2个值是指哪一方赢 
function AndarBahar:getWinType(Cards)
	local cardnum = #Cards;   -- 牌张数 
	local equalpos = 1        -- 第几张牌与第一张牌大小相同 
	local first_value = self:cardValue(Cards[1]) %0x0E;   -- 第一张牌点数 
	for  i=2, cardnum, 1 do
		if first_value == (self:cardValue(Cards[i])%0x0E) then
			if (i%2) == 0 then
				return  i, ANDAR_BAHAR_WINTYPE.ANDAR_BAHAR_WINTYPE_ANDAR
			else
				return  i, ANDAR_BAHAR_WINTYPE.ANDAR_BAHAR_WINTYPE_BAHAR
			end
		end
	end
end