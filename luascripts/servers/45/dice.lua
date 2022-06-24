local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local texas = require(CLIBS["c_texas"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")


-- 骰子牌数据(共12张)
local DEFAULT_POKER_TABLE = {
	0x101, -- 1
	0x102,
	0x103,
	0x104, -- 4
	0x105, -- 5
	0x106, -- 6

	0x101, --
	0x102,
	0x103,
	0x104,
	0x105,
	0x106
}

local COLOR_MASK = 0xFF00
local VALUE_MASK = 0x00FF

local DICE_WINTYPE = {
	DICE_WINTYPE_2_6  = 1, -- A
	DICE_WINTYPE_7    = 2, -- B
	DICE_WINTYPE_8_12 = 3, -- C
}

Dice = Dice or {}
setmetatable(Dice, { __index = Poker })

function Dice:new(o)
	o = o or {}
	setmetatable(o, { __index = self })

	o:init()
	return o
end

--
function Dice:start()
	self:init(DEFAULT_POKER_TABLE, COLOR_MASK, VALUE_MASK)
end

-- 随机获取num张牌
function Dice:getCards(num)
	local poker = {} -- 要获取的扑克
	-- self:init()
	self:reset() -- 洗牌
	for i = 1, num, 1 do
		poker[i] = self.cards[i]
	end
	return poker
end

-- 根据牌数据获取赢得一方及第几张牌与第一张大小相同
-- 返回值: 第1个值是第几张牌与第一张相同，第2个值是指哪一方赢
function Dice:getWinType(cards)
	local cardnum = #cards;  -- 牌张数
	if type(cards) == "table" and #cards == 2 then
		if (cards[1] + cards[2]) % 0x100 < 7 then
			return DICE_WINTYPE.DICE_WINTYPE_2_6
		elseif (cards[1] + cards[2]) % 0x100 == 7 then
			return DICE_WINTYPE.DICE_WINTYPE_7
		else
			return DICE_WINTYPE.DICE_WINTYPE_8_12
		end
	end
end
