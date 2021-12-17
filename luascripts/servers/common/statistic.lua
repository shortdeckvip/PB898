local log = require(CLIBS["c_log"])
local pb = require("protobuf")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local timer = require(CLIBS["c_timer"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
local mutex = require(CLIBS["c_mutex"])
Statistic = Statistic or {}

cjson.encode_max_depth(100)
cjson.encode_sparse_array(true)

local MAX_ROBOT_UID = 1000 -- 最大的机器人账号 UID
local PACKAGE_SIZE = 1 -- 打包条目数
local PUREPROFIT_NOTIFY_LIMIT = 1000 -- 净盈利广播门限
local MONEY_RATIO = 1 -- 以分作为金币单位

local STATISTIC_SERVER_TYPE = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Statistic") << 16

local TimerID = {
    -- id, interval
    TimerID_UserAction = {1, 5 * 60 * 1000}, -- 用户行为
    TimerID_Coin = {2, 5 * 60 * 1000}, -- 金币平衡
    TimerID_MoneyChange = {3, 5 * 60 * 1000}, -- 账变
    TimerID_GameLogRpt = {4, 5 * 60 * 1000}, -- 牌局日志
    TimerID_UserLogRpt = {5, 5 * 60 * 1000}, -- 用户牌局日志
    TimerID_RoomLogRpt = {6, 5 * 60 * 1000}, -- 战绩日志
    TimerID_GameUserLogRpt = {7, 5 * 60 * 1000} -- 牌局日志 + 用户日志 打包
}

local NOTIFY_TYPE = {
    None = 0,
    Jackpot = 1,
    BigJackpot = 2,
    SpecialPrize = 3,
    BigWin = 4
}

local GAME_TYPE = {
    TEXAS = 26 -- 德州
}

local GAME_NAME = {
    [GAME_TYPE.TEXAS] = "德州"
}

local bet_code = {
    --下注类型编码
    [GAME_TYPE.TEXAS] = {
        "无",
        "弃牌",
        "看牌",
        "跟注",
        "加注",
        "小盲",
        "大盲",
        "全下",
        "下注中",
        "等待下一輪入局",
        "清空下注狀態",
        "等待rebuy",
        "交前注",
        "正在买入",
        "补交大盲"
    }
}

local event_code = {}

local result_code = {}

local role_code = {"庄", "闲", "和", "黑", "白", "地主", "农民", "小盲", "大盲", "普通玩家"}

local cards_code = {
    [GAME_TYPE.TEXAS] = {
        [0x102] = "♦2",
        [0x103] = "♦3",
        [0x104] = "♦4",
        [0x105] = "♦5",
        [0x106] = "♦6",
        [0x107] = "♦7",
        [0x108] = "♦8",
        [0x109] = "♦9",
        [0x10A] = "♦10",
        [0x10B] = "♦J",
        [0x10C] = "♦Q",
        [0x10D] = "♦K",
        [0x10E] = "♦A",
        [0x202] = "♣2",
        [0x203] = "♣3",
        [0x204] = "♣4",
        [0x205] = "♣5",
        [0x206] = "♣6",
        [0x207] = "♣7",
        [0x208] = "♣8",
        [0x209] = "♣9",
        [0x20A] = "♣10",
        [0x20B] = "♣J",
        [0x20C] = "♣Q",
        [0x20D] = "♣K",
        [0x20E] = "♣A",
        [0x302] = "♥2",
        [0x303] = "♥3",
        [0x304] = "♥4",
        [0x305] = "♥5",
        [0x306] = "♥6",
        [0x307] = "♥7",
        [0x308] = "♥8",
        [0x309] = "♥9",
        [0x30A] = "♥10",
        [0x30B] = "♥J",
        [0x30C] = "♥Q",
        [0x30D] = "♥K",
        [0x30E] = "♥A",
        [0x402] = "♠2",
        [0x403] = "♠3",
        [0x404] = "♠4",
        [0x405] = "♠5",
        [0x406] = "♠6",
        [0x407] = "♠7",
        [0x408] = "♠8",
        [0x409] = "♠9",
        [0x40A] = "♠10",
        [0x40B] = "♠J",
        [0x40C] = "♠Q",
        [0x40D] = "♠K",
        [0x40E] = "♠A"
    }
}

local cards_type = {
    [GAME_TYPE.TEXAS] = {[0] = "无", "未亮牌赢", "高牌", "對子", "兩對", "三條", "順子", "同花", "葫蘆", "四條", "同花順", "皇家同花顺"} -- 德州
}

--PBUserActionReq
local user_action = {
    actions = {}
}
--PBCoinReq
local coin_req = {
    gameid = global.stype(),
    data = {}
}
--PBMoneyChangeReportReq
local money_change = {
    mcs = {}
}
--PBGameLogReportReq
local game_log = {
    logs = {}
}
--PBUserLogReportReq
local user_log = {
    logs = {}
}
--PBRoomLogReportReq
local room_log = {
    logs = {}
}
--BGameUserLogReportReq
local game_user_log = {
    logs = {}
}

-- 广播用户赢分/赢利缓存
local big_winner_cache = {}

local function reportUserAction()
    if #user_action.actions > 0 then
        local msg = pb.encode("network.inter.PBUserActionReq", user_action)
        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_UserActionReq"),
            msg
        )

        log.info("reportUserAction %s", cjson.encode(user_action))
        user_action.actions = {}
    end
end

local function reportCoin()
    if #coin_req.data > 0 then
        local msg = pb.encode("network.inter.PBCoinReq", coin_req)
        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_GameCoinReq"),
            msg
        )

        log.info("reportCoin %s", cjson.encode(coin_req))
        coin_req.data = {}
    end
end

local function reportGameLogs()
    if #game_log.logs > 0 then
        local msg = pb.encode("network.inter.PBGameLogReportReq", game_log)
        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_GameLogReportReq"),
            msg
        )
        log.info("reportGameLogs %s", cjson.encode(game_log))
        game_log.logs = {}
    end
end

local function reportUserLogs()
    if #user_log.logs > 0 then
        local msg = pb.encode("network.inter.PBUserLogReportReq", user_log)
        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_UserLogReportReq"),
            msg
        )
        log.info("reportUserLogs %s", cjson.encode(user_log))
        user_log.logs = {}
    end
end

local function reportRoomLogs()
    if #room_log.logs > 0 then
        local msg = pb.encode("network.inter.PBRoomLogReportReq", room_log)
        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_RoomLogReportReq"),
            msg
        )
        log.info("reportRoomLogs %s", cjson.encode(room_log))
        room_log.logs = {}
    end
end

-- 上报玩家日志
local function reportGameUserLogs()
    if #game_user_log.logs > 0 then
        --log.info("game_user_log=%s", cjson.encode(game_user_log))
        local msg = pb.encode("network.inter.PBGameUserLogReportReq", game_user_log)

        -- 获取最后一个
        local key =
            game_user_log.logs[#game_user_log.logs].gamelog.jp and game_user_log.logs[#game_user_log.logs].gamelog.jp.id or
            0

        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_GameUserLogReportReq"),
            msg,
            key or 0
        )

        --log.info("reportGameUserLogs %s", cjson.encode(game_user_log))
        game_user_log.logs = {}
    end
end

local function reportMoneyChange()
    if #money_change.mcs > 0 then
        --print('money_change', cjson.encode(money_change))
        local msg = pb.encode("network.inter.PBMoneyChangeReportReq", money_change)
        net.forward(
            STATISTIC_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
            pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_MoneyChangedReq"),
            msg
        )
        log.info("reportMoneyChange %s", cjson.encode(money_change))
        money_change.mcs = {}
    end
end

local function convertBetType(gameid, t)
    if not gameid or not t then
        return nil
    end
    if type(t) ~= "table" then
        return nil
    end

    local tmp = {}
    for k, v in ipairs(t) do
        table.insert(tmp, bet_code[gameid][v])
    end
    return tmp
end

local function convertEventType(gameid, event)
    if not gameid or not event then
        return nil
    end

    return event_code[gameid][event]
end

local function convertResult(gameid, result)
    if not gameid or not result then
        return nil
    end
    if type(result) ~= "table" then
        return nil
    end

    local tmp = {}
    for k, v in ipairs(result) do
        table.insert(tmp, result_code[gameid][v])
        --table.insert(tmp, v)
    end
    return tmp
end

local function convertCards(gameid, cards)
    if not gameid or not cards then
        return nil
    end
    if type(cards) ~= "table" then
        return nil
    end

    local tmp = {}
    for k, v in ipairs(cards) do
        table.insert(tmp, cards_code[gameid][v])
        --table.insert(tmp, v)
    end
    return tmp
end

local function convertCardsType(gameid, cardstype)
    if not gameid or not cardstype then
        return nil
    end
    if type(cardstype) ~= "table" then
        return nil
    end

    local tmp = {}
    for k, v in ipairs(cardstype) do
        table.insert(tmp, cards_type[gameid][v])
    end
    return tmp
end

local function getGameName(gameid)
    if not gameid then
        return nil
    end
    return GAME_NAME[gameid]
end

-- 缓存 bigwinner 数据
-- @param data: 同 appendLogs 参数
local function cacheBigWinner(data)
    local tmp = {}

    for k, v in pairs(data.users) do
        if v.pureprofit and v.pureprofit >= PUREPROFIT_NOTIFY_LIMIT then
            table.insert(
                tmp,
                {
                    notifytype = NOTIFY_TYPE.BigWin,
                    nickname = v.nickname,
                    loginname = v.username,
                    pureprofit = v.pureprofit,
                    profit = v.profit,
                    gametype = data.gametype,
                    vid = data.gamevid,
                    seatnum = v.sid,
                    resulttype = "",
                    amount = v.pureprofit,
                    icon = tonumber(v.nickurl),
                    currency = v.currency
                }
            )
        end
    end

    table.sort(
        tmp,
        function(a, b)
            if a.pureprofit == b.pureprofit then
                return a.profit > b.profit
            else
                return a.pureprofit > b.pureprofit
            end
        end
    )
    table.insert(big_winner_cache, tmp[1])
end

-- 预处理公共牌信息
-- @param data table: 同 appendLogs 参数
-- @return table
local function preprocessPubCards(gameid, cards)
    if not gameid or not cards then
        return nil
    end
    if type(cards) ~= "table" then
        return nil
    end

    local tmp = {}
    for _, v in ipairs(cards) do
        table.insert(tmp, {cards = convertCards(gameid, v)})
    end
    return tmp
end

-- 抽取座位信息
-- @param data table: 同 appendLogs 参数
-- @return table
--		table.sid int32
--		table.uid int64
--		table.nickname string
--		table.role string
local function extractSeatInfo(data)
    local seatinfo = {}
    for k, v in pairs(data.users) do
        if v.sid then
            table.insert(
                seatinfo,
                {
                    uid = k,
                    sid = v.sid,
                    name = v.nickname,
                    role = role_code[v.role]
                }
            )
        end
    end
    return seatinfo
end

local function extractHandCards(data)
    local handcards = {}
    for k, v in pairs(data.users) do
        if v.cards then
            table.insert(handcards, {uid = k, cards = convertCards(global.stype(), v.cards)})
        end
    end
    return handcards
end

-- 预处理 gameinfo 自已详细信息
-- @param data table: 同 appendLogs 参数
-- @return json string
local function preprocessGameInfo(data)
    if data.gameinfo then
        return cjson.encode(data.gameinfo)
    end
    return nil
end

local function transferMoneyUnit(t)
    local tmp = {}
    for _, v in ipairs(t) do
        table.insert(tmp, v * MONEY_RATIO)
    end
    return tmp
end

-- 由业务逻辑在 onFinish 时主动调用
-- 彼时使用 big_winner_cache 中的缓存
function Statistic:broadcastBigWinner()
    for k, v in ipairs(big_winner_cache) do
        -- 推送平台广播
        mutex.request(
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
            pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexPlazaNotification"),
            pb.encode(
                "network.cmd.PBMutexPlazaNotification",
                {
                    notifytype = v.notifytype or 0, --
                    loginname = v.loginname or "",
                    nickname = v.nickname or "",
                    gametype = v.gametype or "",
                    vid = v.vid or 0,
                    seatnum = v.seatnum or 0,
                    resulttype = v.resulttype or "",
                    amount = v.amount or 0,
                    icon = v.icon or 0,
                    currency = v.currency or ""
                }
            )
        )
    end
    big_winner_cache = {}
end

-- @param : data {}
-- data.gamename：		游戏名称
-- data.gametype：		YoPlay game type
-- data.jp{}：			JP 彩金
--		data.jp{}.id:			JP ID
--		data.jp{}.delta_add:	JP 增加值(玩家盈利加入JP奖池)
--		data.jp{}.delta_sub:	JP 减少值百分比数值(玩家中奖JP奖池)
--	uid			= 5;	//< JP中奖UID
-- data.event：			特殊事件
-- data.cards{{},..}：	公共牌
-- data.cardstype{}：	公共牌牌型
-- data.roomtype：		场次类型
-- data.tag：			Texas EnumTexasTableTag
-- data.moneytype:		"money"-金币 "diamond"-钻石
-- data.stime:			牌局开始时间
-- data.etime:			牌局结束时间
-- data.wintypes{}：	开奖结果、获胜下注区
-- data.winpokertype：	获胜牌型
-- data.totalbet：		当局总下注
-- data.totalprofit：	当局总盈亏
-- data.areas{}：		下注区信息
--		data.areas{}.bettype：		下注类型
-- 		data.areas{}.betvalue:		下注值
-- 		data.areas{}.profit:		盈亏
-- 		data.areas{}.pureprofit:	纯盈亏
-- 		data.areas{}.fee:			台费
-- data.gameinfo{}: 	牌局详细记录
--      data.gameinfo.texas {}:		德州
--			data.gameinfo.texas.sb			 小盲
--			data.gameinfo.texas.bb			 大盲
--			data.gameinfo.texas.maxplayers	 最大玩牌人数
--			data.gameinfo.texas.curplayers	 当前玩牌人数
--			data.gameinfo.texas.ante		 前注
--      data.gameinfo.lord {}:		斗地主
--      data.gameinfo.mahjong {}:	麻将
-- data.users {}: 本局所有用户数据
--		data.users[uid].stime:			牌局开始时间
--		data.users[uid].etime:			牌局结束时间
--      data.users[uid].sid:			玩家座位 id
--      data.users[uid].tid:			玩家桌子 id
--      data.users[uid].nickname:		玩家昵称
--      data.users[uid].username:		玩家名称
--      data.users[uid].role:			庄、闲、和、黑(五子棋)、白(五子棋)、地主、农民、小盲、大盲
--      data.users[uid].nickurl:		头像
--      data.users[uid].money:			扣费前金币数/钻石（开局时金币/钻石数）
--      data.users[uid].currency:		货币
--      data.users[uid].cards {}:		手牌
--      data.users[uid].cardstype{}:	手牌类型
--      data.users[uid].totalbet：		总下注
--      data.users[uid].totalprofit：	总赢分
--      data.users[uid].totalpureprofit:总纯赢利
--      data.users[uid].totalfee：		总服务费
--		data.users[uid].areas{}：		下注区信息
--			data.users[uid].areas{}.bettype：	下注类型
-- 			data.users[uid].areas{}.betvalue:	下注值
-- 			data.users[uid].areas{}.profit:		盈亏
-- 			data.users[uid].areas{}.pureprofit:	纯盈亏
-- 			data.users[uid].areas{}.fee:		台费
--      data.users[uid].extrainfo:		JSON 附加信息
--			data.users[uid].extrainfo.ip：	客户端 IP
--      	data.users[uid].extrainfo.api：	客户端版本
--      	data.users[uid].extrainfo.platuid：	第三方 platuid
--      data.users[uid].ugameinfo{}:	用户牌局详细记录
--			data.users[uid].ugameinfo.texas{}:	德州
--				data.users[uid].ugameinfo.texas.inctotalhands:			玩家总手数自增（始终为 1）
--				data.users[uid].ugameinfo.texas.inctotalwinhands:       胜利总手数自增
--				data.users[uid].ugameinfo.texas.incpreflopfoldhands:    翻牌前 FOLD 手数自增（翻牌前第一次操作就 FOLD 牌）
--				data.users[uid].ugameinfo.texas.incpreflopraisehands:   翻牌前 RAISE 手数自增
--				data.users[uid].ugameinfo.texas.incpreflopcheckhands:   翻牌前 CHECK 手数自增（翻牌前第一次操作就 CHECK，即大盲位下大盲后过牌）
--				data.users[uid].ugameinfo.texas.pre_bets	{}:			翻牌前下注次序
--				data.users[uid].ugameinfo.texas.flop_bets	{}:			翻牌后下注次序
--				data.users[uid].ugameinfo.texas.turn_bets	{}:			转牌下注次序
--				data.users[uid].ugameinfo.texas.river_bets	{}:			河牌下注次序
--				data.users[uid].ugameinfo.texas.bestcards{}:			最优 5 张牌
--				data.users[uid].ugameinfo.texas.bestcardstype:			最优牌型
--				data.users[uid].ugameinfo.texas.leftchips：				剩余筹码

function Statistic:appendLogs(data, logid)
    -- 游戏币数据
    --local totalbets = 0
    --local totalfee  = 0
    --local totalrecycle = 0
    --local totalrobot= 0
    --local robotbets	= 0
    --local robotfee	= 0
    --local robotrecycle= 0

    -- 牌局 id
    local time = global.ctms()

    logid = logid or self:genLogId(data.stime)
    --log.info('Statistic:appendLogs logid:%s sdata:%s', logid, cjson.encode(data))

    local gameuserlog = {
        gamelog = {
            logid = logid,
            stime = data.stime,
            etime = data.etime,
            gameid = global.stype(),
            serverid = global.sid(),
            matchid = self.matchid,
            roomid = self.roomid,
            roomtype = data.roomtype,
            tag = data.tag or 0,
            jp = data.jp or {},
            cards = data.cards or {},
            cardstype = data.cardstype or {},
            gameinfo = data.gameinfo or {},
            wintypes = data.wintypes,
            winpokertype = data.winpokertype or 0,
            totalbet = data.totalbet or 0,
            totalprofit = data.totalprofit or 0,
            areas = data.areas,
            extrainfo = data.extrainfo
        },
        userlog = {}
    }

    for k, v in pairs(data.users or {}) do
        table.insert(
            gameuserlog.userlog,
            {
                -- 插入玩家日志
                uid = k,
                logid = logid,
                stime = v.stime,
                etime = v.etime,
                gameid = global.stype(),
                serverid = global.sid(),
                matchid = self.matchid,
                roomid = self.roomid,
                role = v.role or 0,
                tid = v.tid or 0,
                sid = v.sid or 0,
                username = v.username or "",
                nickurl = v.nickurl or "",
                --ip				= v.ip,
                --api				= v.api,
                totalbet = v.totalbet or 0,
                totalprofit = v.totalprofit or 0,
                totalpureprofit = v.totalpureprofit or 0,
                totalfee = v.totalfee or 0,
                --profits			= v.profits,
                --pureprofits		= v.pureprofits,
                --fees			= v.fees,
                --betypes			= v.betypes,
                --betvalues		= v.betvalues,
                areas = v.areas or {},
                cards = v.cards or {},
                cardstype = v.cardstype or {},
                ugameinfo = v.ugameinfo or {},
                extrainfo = v.extrainfo or ""
            }
        )
    end

    self:appendGameUserlogs(gameuserlog)

    --cacheBigWinner(data)

    -- 未有真实玩家参与, 不上报任何数据
    --local isvalidlog = false
    --for k, v in pairs(data.users) do
    --if k > MAX_ROBOT_UID then isvalidlog = true end
    --end
    --if not isvalidlog then return end

    --if not data.users then
    --goto labelgamelog
    --end
    --for k, v in pairs(data.users) do
    -- 用户牌局
    --local userlog = {
    --uid		= k,
    --logid	= logid,
    --time	= time,
    --gameid	= global.stype(),
    --roomid	= self.roomid,
    --roomtype= data.roomtype,
    --role	= role_code[v.role],
    --cards= convertCards(global.stype(), v.cards),
    --cardstype=convertCardsType(global.stype(), v.cardstype),
    --betype	= convertBetType(global.stype(), v.betype),
    --betvalue= v.betvalue and transferMoneyUnit(v.betvalue) or nil,
    --prize = v.prize and transferMoneyUnit(v.prize) or nil,
    --profit  = v.profit and v.profit * MONEY_RATIO or nil,
    --pureprofit= v.pureprofit and v.pureprofit * MONEY_RATIO or nil,
    --fee		= v.fee and v.fee * MONEY_RATIO or nil,
    --fees	= v.fees and transferMoneyUnit(v.fees) or nil,
    --}
    --self:appendUeserLogs(userlog)

    -- 上报游戏输赢
    --if userlog.pureprofit and userlog.pureprofit >= 0 then
    --self:appendUserAction(k, pb.enum_id("network.inter.STATISTIC_ACTION_TYPE", "ACTION_TYPE_WINGAME"))
    --else
    --self:appendUserAction(k, pb.enum_id("network.inter.STATISTIC_ACTION_TYPE", "ACTION_TYPE_LOSEGAME"))
    --end

    -- 统计游戏币相关数据
    --totalbets    = totalbets + g.sum(v.betvalue)
    --totalfee     = totalfee + (v.fee or g.sum(v.fees))
    --totalrecycle = totalrecycle - (v.pureprofit or 0)
    --if k <= MAX_ROBOT_UID then
    --totalrobot		= totalrobot + (v.pureprofit or 0)
    --robotbets		= robotbets + g.sum(v.betvalue)
    --robotfee		= robotfee + (v.fee or g.sum(v.fees))
    --robotrecycle	= robotrecycle - (v.pureprofit or 0)
    --end

    -- 账变信息
    --if v.money and v.money > 0 then
    --if v.fee and v.fee > 0 then
    --self:appendMoneyChange(k, time, v.money * MONEY_RATIO, -1 * v.fee * MONEY_RATIO, logid, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_FEE"), data.moneytype)
    --v.money = v.money - v.fee
    --elseif v.fees and g.sum(v.fees) > 0 then
    --for _, fee in ipairs(v.fees) do
    --self:appendMoneyChange(k, time, v.money * MONEY_RATIO, -1 * fee * MONEY_RATIO, logid, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_FEE"), data.moneytype)
    --v.money = v.money - v.fee
    --end
    --end
    --self:appendMoneyChange(k, time + 1, v.money * MONEY_RATIO, v.pureprofit and v.pureprofit * MONEY_RATIO or 0, logid, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_GAME"), data.moneytype) -- 强制让游戏输赢账变排在服务费后面
    --end

    --end

    --::labelgamelog::

    -- 游戏牌局
    --local gamelog = {
    --logid = logid,
    --time  = time,
    --gameid= global.stype(),
    --roomid= self.roomid,
    --jp    = data.jp and data.jp * MONEY_RATIO or nil,
    --event = convertEventType(global.stype(), data.event),
    --cards = preprocessPubCards(global.stype(), data.cards),
    --cardstype	= convertCardsType(global.stype(), data.cardstype),
    --result		= convertResult(global.stype(), data.result),
    --totalbet	= totalbets * MONEY_RATIO,
    --gameinfostr = preprocessGameInfo(data),
    --}
    --self:appendGameLogs(gamelog)

    -- 游戏币数据
    --self:appendCoin({bets=totalbets * MONEY_RATIO, fee=totalfee * MONEY_RATIO, recycle=totalrecycle * MONEY_RATIO, robot=totalrobot * MONEY_RATIO, robotbets=robotbets * MONEY_RATIO, robotfee=robotfee * MONEY_RATIO, robotrecycle=robotrecycle * MONEY_RATIO})
end

-- 用户日志
function Statistic:appendUeserLogs(userlog)
    table.insert(user_log.logs, userlog)
    if #user_log.logs >= PACKAGE_SIZE then
        reportUserLogs()
    end
end

-- 战绩
function Statistic:appendRoomLogs(roomlog)
    table.insert(room_log.logs, roomlog)
    if #room_log.logs >= PACKAGE_SIZE then
        reportRoomLogs()
    end
end

-- 玩家日志信息
function Statistic:appendGameUserlogs(gameuserlog)
    table.insert(game_user_log.logs, gameuserlog)
    if #game_user_log.logs >= PACKAGE_SIZE then
        reportGameUserLogs()
    end
end

-- 牌局日志
function Statistic:appendGameLogs(gamelog)
    table.insert(game_log.logs, gamelog)
    if #game_log.logs >= PACKAGE_SIZE then
        reportGameLogs()
    end
end

-- @param from : 变动前金额
-- @param change: 变动金额
-- @param logid: 牌局 id
-- @param reason: 账变原因
-- @parma moneytype: "money"-金币 "diamond"-钻石
function Statistic:appendMoneyChange(uid, time, from, change, logid, reason, moneytype)
    if not uid or not time or not from or not change or not logid then
        return
    end
    --if change == 0 then return end

    table.insert(
        money_change.mcs,
        {
            uid = uid,
            time = time,
            gameid = global.stype(),
            svid = global.sid(),
            roomid = self.roomid,
            type = (moneytype and moneytype == "diamond") and
                pb.enum_id("network.inter.MONEY_CHANGE_TYPE", "MONEY_CHANGE_TOOL") or
                pb.enum_id("network.inter.MONEY_CHANGE_TYPE", "MONEY_CHANGE_COIN"),
            reason = reason or pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_GAME"),
            from = from,
            cto = from + change,
            changed = change,
            logid = logid
        }
    )
    if #money_change.mcs >= PACKAGE_SIZE then
        reportMoneyChange()
    end
end

-- @param : coin
-- coin.bets: 总下注/流通量
-- coin.fee：服务费
-- coin.recycle：系统回收
-- coin.robot：机器人输赢
function Statistic:appendCoin(coin)
    if not coin.bets then
        coin.bets = 0
    end
    if not coin.fee then
        coin.fee = 0
    end
    if not coin.recycle then
        coin.recycle = 0
    end
    if not coin.robot then
        coin.robot = 0
    end
    if not coin.robotbets then
        coin.robotbets = 0
    end
    if not coin.robotfee then
        coin.robotfee = 0
    end
    if not coin.robotrecycle then
        coin.recycle = 0
    end

    if coin.bets ~= 0 or coin.fee ~= 0 or coin.recycle ~= 0 or coin.robot ~= 0 then -- 防止无意义的数据上报
        table.insert(
            coin_req.data,
            {
                date = global.cdsec(),
                bets = coin.bets,
                fee = coin.fee,
                recycle = coin.recycle,
                robot = coin.robot,
                robotbets = coin.robotbets,
                robotfee = coin.robotfee,
                robotrecycle = coin.robotrecycle
            }
        )
        if #coin_req.data >= PACKAGE_SIZE then
            reportCoin()
        end
    end
end

function Statistic:appendUserAction(uid, action)
    --print('uid', uid, 'action', action)
    if not uid or not action then
        return false
    end
    table.insert(
        user_action.actions,
        {
            date = global.cdsec(),
            uid = uid,
            action = action,
            gameid = global.stype()
        }
    )
    log.info("appendUserAction %s", cjson.encode(user_action))
    if #user_action.actions >= PACKAGE_SIZE then
        reportUserAction()
    end
end

function Statistic:genLogId(time)
    -- svid|roomid|time
    if not time then
        time = global.ctsec()
    end
    local strLogId = string.format("%x%x%x%x", global.stype(), global.lowsid(), self.roomid, math.floor(time))
    return strLogId
end

function Statistic:new(roomid, matchid)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o.roomid = roomid
    o.matchid = matchid
    return o
end

--Static_Timer = Static_Timer or timer.create()
--timer.tick(Static_Timer, TimerID.TimerID_UserAction[1],		TimerID.TimerID_UserAction[2],	reportUserAction)
--timer.tick(Static_Timer, TimerID.TimerID_Coin[1],			TimerID.TimerID_Coin[2],		reportCoin)
--timer.tick(Static_Timer, TimerID.TimerID_MoneyChange[1],	TimerID.TimerID_MoneyChange[2], reportMoneyChange)
--timer.tick(Static_Timer, TimerID.TimerID_GameLogRpt[1],		TimerID.TimerID_GameLogRpt[2],	reportGameLogs)
--timer.tick(Static_Timer, TimerID.TimerID_UserLogRpt[1],		TimerID.TimerID_UserLogRpt[2],	reportUserLogs)
--timer.tick(Static_Timer, TimerID.TimerID_RoomLogRpt[1],		TimerID.TimerID_RoomLogRpt[2],	reportRoomLogs)
--timer.tick(Static_Timer, TimerID.TimerID_GameUserLogRpt[1], TimerID.TimerID_GameUserLogRpt[2], reportGameUserLogs)
