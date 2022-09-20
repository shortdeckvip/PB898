local global = require(CLIBS["c_global"])
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
require(string.format("luascripts/servers/%d/room", global.stype()))

local conf = {
    {
        mid = 1,
        name = "初级场",
        roomtype = 2, -- 房间类型1金币 2豆子
        mintable = 3,
        maxtable = 400,
        carrybound = {100000, 1500000},
        chips = {100, 500, 1000, 5000, 10000, 50000, 100000, 500000}, -- 筹码设置
        robotBetChipProb = {1000, 1000, 2000, 1000, 2000, 1000, 1000, 1000}, -- 机器人下注筹码概率
        betarea = {
            -- 下注区域设置
            -- 赔率, limit-min, limit-max
            {2, 1, 10000000}, --dragon
            {2, 1, 10000000}, --tiger
            {17, 1, 1000000} --draw
        },
        maxlogsavedsize = 1000, -- 历史记录最多留存
        maxlogshowsize = 50, -- 历史记录最多显示
        fee = 0.05, -- 收取盈利服务费率
        max_bank_list_size = 10, -- 上庄申请列表最大申请人数
        max_bank_successive_cnt = 10, -- 上庄连庄最大次数
        min_onbank_moneycnt = 5000000, -- 上庄需要最低金币数量
        min_outbank_moneycnt = 2000000, -- 下庄需要最低金币数量
        init_banker_money = 1000000000, -- 系统庄初始金币数量
        profitrate_threshold_minilimit = 0.1, -- 最低盈利率
        banker_profitrate_threshold_minilimit = 0.1, --庄家最低盈利率
        profitrate_threshold_lowerlimit = 0.15, -- 盈利阈值触发收紧策略
        profitrate_threshold_upperlimit = 0.3, -- 盈利阈值触发防水策略
        banker_profitrate_threshold_lowerlimit = 0.15, -- 庄家盈利阈值触发收紧策略
        profitrate_threshold_maxdays = 3, -- 盈利阈值触发盈利天数
        min_player_num = 1, -- 随机最少人数
        max_player_num = 5, -- 随机最大人数
        update_interval = 5, -- 多少局更新一次
        global_profit_switch = false,
        single_profit_switch = false, -- 单人输赢控制
        --robotBetAreaProb = {3000,3000，500} -- 机器人下注区域概率
    }
}

CheckMiniGameConfig(conf)
MatchMgr:init(conf)
log.info(cjson.encode(conf))
