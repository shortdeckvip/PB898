local global = require(CLIBS["c_global"])
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
require(string.format("luascripts/servers/%d/room", global.stype())) -- global.stype()返回游戏ID 43

-- dqw 房间配置信息
local conf = {
    {
        mid = 1, -- 房间级别ID (标识是初级场、中级场、高级场)
        name = "初级场", -- 房间名
        roomtype = 2, -- 房间类型1金币 2豆子
        mintable = 1, -- 最少桌子数
        maxtable = 400,
        carrybound = {100000, 1500000}, --
        chips = {100, 500, 1000, 2000, 5000, 10000, 50000, 100000, 1000000}, -- 筹码设置
        betarea = {
            -- 下注区域设置
            -- 赔率, limit-min, limit-max   下注限额
            {1.90, 1, 10000000}, -- andar
            {2, 1, 10000000} -- bahar
        },
        maxlogsavedsize = 1000, -- 历史记录最多留存
        maxlogshowsize = 50, -- 历史记录最多显示
        fee = 0.05, -- 收取盈利服务费率
        profitrate_threshold_minilimit = 0.1, -- 最低盈利率
        profitrate_threshold_lowerlimit = 0.15, -- 盈利阈值触发收紧策略
        profitrate_threshold_upperlimit = 0.3, -- 盈利阈值触发防水策略
        profitrate_threshold_maxdays = 3, -- 盈利阈值触发盈利天数
        min_player_num = 1, -- 随机最少人数
        max_player_num = 1, -- 随机最大人数
        update_interval = 5, -- 多少局更新一次
        maxuser = 1, -- 每桌最大玩家数目
        jpid = 31,
        jpminbet = 10000, -- 超过该下注额才会有机会触发jackpot奖励
        autoSPinList = {10, 20, 50, 100}, -- 自动旋转次数列表
        --lineNum = 10,   -- 线条总条数
        single_profit_switch = true -- 单人输赢控制
    }
}

CheckMiniGameConfig(conf) -- 检测小游戏配置

MatchMgr:init(conf)
--MatchMgr:init(TABLECONF)
