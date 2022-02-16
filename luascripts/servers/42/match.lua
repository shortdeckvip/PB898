local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

local conf = {
    {
        mid = 1,
        name = "初级场",
        roomtype = 2,
        mintable = 3,
        maxtable = 400,
        carrybound = {100000, 1500000},
        chips = {100, 500, 1000, 2000, 5000, 10000, 50000, 100000, 1000000}, -- 筹码设置
        betarea = {
            -- 下注区域设置
            -- 赔率, limit-min, limit-max, retry-prob
            {1.95, 1, 100000000}, --牛仔
            {1.95, 1, 100000000}, --公牛
            {100, 1, 100000000}, --平局(赢牌独有类型)
            {3.5, 1, 1000000}, -- 对子
            {10, 1, 1000000}, -- 同花
            {15, 1, 1000000}, -- 顺子
            {100, 1, 1000000}, -- 同花顺
            {100, 1, 1000000} -- 三条
        },
        maxlogsavedsize = 1000, -- 历史记录最多留存
        maxlogshowsize = 50, -- 历史记录最多显示
        profitrate_threshold_minilimit = 0.1, -- 最低盈利率
        profitrate_threshold_lowerlimit = 0.15, -- 盈利阈值触发收紧策略
        profitrate_threshold_upperlimit = 0.3, -- 盈利阈值触发防水策略
        profitrate_threshold_maxdays = 3, -- 盈利阈值触发盈利天数
        configcards = {},
        min_player_num = 1, -- 随机最少人数
        max_player_num = 5, -- 随机最大人数
        update_interval = 5, -- 多少局更新一次
        global_profit_switch = false,
        single_profit_switch = true -- 单人输赢控制
    }
}

CheckMiniGameConfig(conf)
MatchMgr:init(conf)
