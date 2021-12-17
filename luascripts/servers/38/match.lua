-- 博定房间配置
local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype())) -- global.stype()返回游戏ID 38

MatchMgr:init(TABLECONF)


-- 房间配置信息
local conf = {
    {
        mid = 1, -- 房间级别ID (标识是初级场、中级场、高级场)
        name = "初级场", -- 房间名
        roomtype = 2, -- 房间类型1金币 2豆子
        mintable = 1,
        maxtable = 4,
        carrybound = {200000, 2000000}, --
        chips = {10, 20, 50, 100}, -- 筹码设置

        maxlogsavedsize = 1000, -- 历史记录最多留存
        maxlogshowsize = 50, -- 历史记录最多显示
        fee = 0.05, -- 收取盈利服务费率

        max_bank_list_size = 10, 		-- 上庄申请列表最大申请人数
		max_bank_successive_cnt = 10,	-- 上庄连庄最大次数
		min_onbank_moneycnt = 5000000,		-- 上庄需要最低金币数量
		min_outbank_moneycnt = 2000000,		-- 下庄需要最低金币数量
		init_banker_money = 1000000000,		-- 系统庄初始金币数量

        profitrate_threshold_lowerlimit = -0.05, -- 盈利阈值触发收紧策略
        profitrate_threshold_upperlimit = 0.3, -- 盈利阈值触发防水策略
        profitrate_threshold_maxdays = 3, -- 盈利阈值触发盈利天数
        time_per_card = 300 -- 每发一张牌需要多长时间  300ms
    }
}

-- CheckMiniGameConfig(conf) -- 检测小游戏配置
CheckMiniGameConfig(TABLECONF)
--CheckMiniGameConfigNew(TABLECONF)

-- MatchMgr:init(conf)

