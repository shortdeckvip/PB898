local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")


-- 牌数据(共12张)
local DEFAULT_POKER_TABLE = {
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

local COLOR_MASK = 0x00F0
local VALUE_MASK = 0x000F

-- 下注区域
local PVE_BetArea = {
	PVE_BetArea_1 = 1,  --下注区1(A赢)
    PVE_BetArea_2 = 2,  --下注区2(和)
    PVE_BetArea_3 = 3,  --下注区3(A输)
    PVE_BetArea_4 = 4,  --下注区4(3·8광땡  3.8光牌)
    PVE_BetArea_5 = 5,  --下注区5(광땡  光牌)
    PVE_BetArea_6 = 6,  --下注区6(땡  对子)
    PVE_BetArea_7 = 7,  --下注区7(장사/세륙)
    PVE_BetArea_8 = 8,  --下注区8(알리/독사/구삥/장삥)
}


-- 牌型
local EnumSeotdaCardsType = {
    EnumSeotdaCardsType_End_0      = 1, -- 망통(两张牌月份之和个的位数数值大小为0)
    EnumSeotdaCardsType_End_1_8    = 2, -- 끗(两张牌月份之和个的位数数值大小为1~8)
    EnumSeotdaCardsType_End_9      = 3, -- 갑오(月份加在一起时最后一位数字为 9 的任何牌组合)（例如 1+8、2+7、3+6、4+5、9+10）
    EnumSeotdaCardsType_4_6        = 4, -- 세륙(4月和6月的组合)
    EnumSeotdaCardsType_4_10       = 5, -- 장사(4月和10月的组合)
    EnumSeotdaCardsType_1_10       = 6, -- 장삥(1月和10月的组合)
    EnumSeotdaCardsType_1_9        = 7, -- 구삥(1月和9月的组合)
    EnumSeotdaCardsType_1_4        = 8, -- 독사(1月和4月的组合)
    EnumSeotdaCardsType_1_2        = 9, -- 알리(1月和2月的组合)
    EnumSeotdaCardsType_DuiZi      = 10, -- 땡 对子(相同月份的两张牌组合，按月份大小排序)
    EnumSeotdaCardsType_GuangDui   = 11, -- 광땡 光对(0x11+0x31 或 0x11+0x81)  13光对或18光对
    EnumSeotdaCardsType_38GuangDui = 12, -- 3·8광땡 38光对(0x31+0x81)
}




SeotdaWar = SeotdaWar or {}
setmetatable(SeotdaWar, { __index = Poker })

function SeotdaWar:new(o)
	o = o or {}
	setmetatable(o, { __index = self })

	o:init()
	return o
end

--
function SeotdaWar:start()
	self:init(DEFAULT_POKER_TABLE, COLOR_MASK, VALUE_MASK)
end

-- 随机获取num张牌
function SeotdaWar:getCards(num)
	local poker = {} -- 要获取的扑克
	-- self:init()
	self:reset() -- 洗牌
	for i = 1, num, 1 do
		poker[i] = self.cards[i]
	end
	return poker
end

-- 根据牌数据获取所有赢的区域及赢方牌型
-- 返回值: 返回所有赢的区域及赢的牌型 
function SeotdaWar:getWinType(cardsA, cardsB)
	local wintypes = {} -- 存放所有赢的区域
    local winpokertype = -1
	local cardnum = #cardsA;  -- 牌张数(必须为2张)
	if type(cardsA) ~= "table" or #cardsA < 2 or type(cardsB) ~= "table" or #cardsB < 2 then
		return wintypes, winpokertype
	end

	-- 比较2手牌
	local ret = Seotda:Compare(cardsA, cardsB)
	if ret > 0 then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_1)
		winpokertype = Seotda:GetCardsType(cardsA)
	elseif ret == 0 then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_3)
		winpokertype = Seotda:GetCardsType(cardsA)
	else
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_2)
		winpokertype = Seotda:GetCardsType(cardsB)		
	end

	if winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_38GuangDui then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_4)
	elseif winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_GuangDui then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_5)
	elseif winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_DuiZi then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_6)
	elseif winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_4_10 or winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_4_6  then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_7)  --下注区7(장사/세륙)
	elseif winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_1_2 or winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_1_4
	 or winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_1_9 or winpokertype == EnumSeotdaCardsType.EnumSeotdaCardsType_1_10  then
		table.insert(wintypes, PVE_BetArea.PVE_BetArea_8)  --下注区8(알리/독사/구삥/장삥)
	end

	return wintypes, winpokertype
end
