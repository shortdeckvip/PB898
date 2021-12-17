local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

local conf = {
	{
		mid		= 1,
		name	= '初级场',
		roomtype = 2,
		mintable = 1,
		maxtable = 4,
		carrybound = {100000,1500000},
		chips = {100,500,1000,2000,5000,10000,50000,100000,1000000}, -- 筹码设置
		betarea	= { -- 下注区域设置
			-- 赔率, limit-min, limit-max, retry-prob
			{2.02, 1, 5000000},		--牛仔
			{2.02, 1, 5000000},		--公牛
			{22, 1, 1000000},		--平局(赢牌独有类型)	
			{1.6, 1, 5000000},	--同花/连牌/同花连牌
			{8.5, 1, 5000000},	--对子(包含对A)
			{100, 1, 500000},	--对子A
			{2.2, 1, 5000000},	--高牌/一对
			{3.1, 1, 5000000},	--两对
			{4.7, 1, 5000000},	--三条/顺子/同花
			{20, 1, 1000000},	--葫芦
			{248, 1, 500000},	--金刚/同花顺/皇家同花顺
		},
		maxlogsavedsize = 1000,	-- 历史记录最多留存
		maxlogshowsize = 50,	-- 历史记录最多显示
		profitrate_threshold_minilimit = 0.1, -- 最低盈利率
		profitrate_threshold_lowerlimit = 0.15, -- 盈利阈值触发收紧策略
		profitrate_threshold_upperlimit = 0.3, -- 盈利阈值触发防水策略
		profitrate_threshold_maxdays = 3, -- 盈利阈值触发盈利天数
		configcards = {--配牌
			--{{0x102, 0x103,}, { 0x40D, 0x30e}, {0x104, 0x105, 0x106, 0x308, 0x40B}},
			--{{0x102, 0x103,}, { 0x40D, 0x30e}, {0x202, 0x302, 0x402, 0x308, 0x40B}},
			--{{0x102, 0x103,}, { 0x40D, 0x30e}, {0x202, 0x303, 0x403, 0x308, 0x40B}},
			--{{0x10E, 0x20E,}, { 0x40D, 0x30e}, {0x202, 0x303, 0x403, 0x308, 0x40B}},
		},

		min_player_num = 1,   -- 随机最少人数 
		max_player_num = 5,  -- 随机最大人数
		update_interval = 5,  -- 多少局更新一次 
	},
}

CheckMiniGameConfig(conf)
MatchMgr:init(conf)