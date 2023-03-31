local global = require(CLIBS["c_global"])
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
require(string.format("luascripts/servers/%d/room", global.stype())) -- global.stype()返回游戏ID 35

-- dqw 房间配置信息
local conf = {
    {
        mid = 1, -- 房间级别ID (标识是初级场、中级场、高级场)
        name = "初级场", -- 房间名
        roomtype = 2, -- 房间类型1金币 2豆子
        mintable = 3,
        maxtable = 400,
        carrybound = {100000, 1500000}, --
        chips = {100, 500, 1000, 5000, 10000, 50000, 100000, 500000}, -- 筹码设置
        robotBetChipProb = {1000, 1000, 2000, 1000, 2000, 1000, 1000, 1000}, -- 机器人下注筹码概率
        betarea = {
            -- 下注区域设置
            -- 赔率, limit-min, limit-max   下注限额
            {2, 1, 10000000}, -- 2_6点下注区
            {5, 1, 10000000}, -- 7点下注区
            {2, 1, 10000000}  -- 8_12点下注区
        },
        maxlogsavedsize = 1000, -- 历史记录最多留存
        maxlogshowsize = 50, -- 历史记录最多显示
        fee = 0.05, -- 收取盈利服务费率
        init_banker_money = 1000000000, -- 系统庄初始金币数量
        profitrate_threshold_minilimit = 0.1, -- 最低盈利率
        profitrate_threshold_lowerlimit = 0.15, -- 盈利阈值触发收紧策略   系统盈利率
        profitrate_threshold_upperlimit = 0.3, -- 盈利阈值触发放水策略
        profit_max_win = 10,
        profitrate_threshold_maxdays = 3, -- 盈利阈值触发盈利天数
        time_per_card = 300, -- 每发一张牌需要多长时间  300ms
        min_player_num = 1, -- 随机最少人数
        max_player_num = 5, -- 随机最大人数
        update_interval = 5, -- 多少局更新一次
        global_profit_switch = false, -- 根据盈利率控制
        single_profit_switch = false, -- 单人输赢控制
        --robotBetAreaProb = {3000,3000，500} -- 机器人下注区域概率
    }
}

CheckMiniGameConfig(conf) -- 检测小游戏配置
MatchMgr:init(conf)
log.info(cjson.encode(conf))
