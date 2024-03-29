local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local rand = require(CLIBS["c_rand"])
local global = require(CLIBS["c_global"])
local mutex = require(CLIBS["c_mutex"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
require("luascripts/servers/common/statistic")
require("luascripts/servers/31/cowboy")
require("luascripts/servers/31/seat")
require("luascripts/servers/31/vtable")

cjson.encode_invalid_numbers(true)

--increment
Room = Room or { uniqueid = 0 }
local JackPot = rand.rand_between(100000, 1000000)
local EnumCowboyPokerType = {
    EnumCowboyPokerType_HighCard = 2, --高牌 Pie Card + HighCard
    EnumCowboyPokerType_Pair = 3, --对子
    EnumCowboyPokerType_TwoPair = 4, --两对
    EnumCowboyPokerType_ThreeKind = 5, --三条
    EnumCowboyPokerType_Straight = 6, --顺子
    EnumCowboyPokerType_Flush = 7, --同花
    EnumCowboyPokerType_FullHouse = 8, --葫芦
    EnumCowboyPokerType_FourKind = 9, --四条、金刚
    EnumCowboyPokerType_StraightFlush = 10,
    --同花顺
    EnumCowboyPokerType_RoyalFlush = 11
    --皇家同花顺
}
local EnumCowboyType = {
    --胜平负
    EnumCowboyType_Cowboy = 1, --牛仔
    EnumCowboyType_Bull = 2, --公牛
    EnumCowboyType_Draw = 3, --平局(赢牌独有类型)
    --任一手牌
    EnumCowboyType_FlushInRow = 4, --同花/连牌/同花连牌
    EnumCowboyType_Pair = 5, --对子(包含对A)
    EnumCowboyType_PairA = 6, --对子A
    --获胜牌型
    EnumCowboyType_HighCardPair = 7, --高牌/一对
    EnumCowboyType_TwoPair = 8, --两对
    EnumCowboyType_ThrKndStrghtFlsh = 9, --三条/顺子/同花
    EnumCowboyType_FullHouse = 10, --葫芦
    EnumCowboyType_BeyondFourKind = 11 --金刚/同花顺/皇家同花顺
}
local DEFAULT_BET_TABLE = {
    --胜平负
    [EnumCowboyType.EnumCowboyType_Cowboy] = 0, --牛仔
    [EnumCowboyType.EnumCowboyType_Bull] = 0, --公牛
    [EnumCowboyType.EnumCowboyType_Draw] = 0, --平局(赢牌独有类型)
    --任一手牌
    [EnumCowboyType.EnumCowboyType_FlushInRow] = 0, --同花/连牌/同花连牌
    [EnumCowboyType.EnumCowboyType_Pair] = 0, --对子(包含对A)
    [EnumCowboyType.EnumCowboyType_PairA] = 0, --对子A
    --获胜牌型
    [EnumCowboyType.EnumCowboyType_HighCardPair] = 0, --高牌/一对
    [EnumCowboyType.EnumCowboyType_TwoPair] = 0, --两对
    [EnumCowboyType.EnumCowboyType_ThrKndStrghtFlsh] = 0, --三条/顺子/同花
    [EnumCowboyType.EnumCowboyType_FullHouse] = 0, --葫芦
    [EnumCowboyType.EnumCowboyType_BeyondFourKind] = 0 --金刚/同花顺/皇家同花顺
}
local DEFAULT_BET_TYPE = {
    EnumCowboyType.EnumCowboyType_Cowboy,
    EnumCowboyType.EnumCowboyType_Bull,
    EnumCowboyType.EnumCowboyType_Draw,
    EnumCowboyType.EnumCowboyType_FlushInRow,
    EnumCowboyType.EnumCowboyType_Pair,
    EnumCowboyType.EnumCowboyType_PairA,
    EnumCowboyType.EnumCowboyType_HighCardPair,
    EnumCowboyType.EnumCowboyType_TwoPair,
    EnumCowboyType.EnumCowboyType_ThrKndStrghtFlsh,
    EnumCowboyType.EnumCowboyType_FullHouse,
    EnumCowboyType.EnumCowboyType_BeyondFourKind
}
local DEFAULT_BETST_TABLE = {
    --胜平负
    [EnumCowboyType.EnumCowboyType_Cowboy] = { type = EnumCowboyType.EnumCowboyType_Cowboy, hitcount = 0, lasthit = 0 }, --牛仔
    [EnumCowboyType.EnumCowboyType_Bull] = { type = EnumCowboyType.EnumCowboyType_Bull, hitcount = 0, lasthit = 0 }, --公牛
    [EnumCowboyType.EnumCowboyType_Draw] = { type = EnumCowboyType.EnumCowboyType_Draw, hitcount = 0, lasthit = 0 }, --平局(赢牌独有类型)
    --任一手牌
    [EnumCowboyType.EnumCowboyType_FlushInRow] = {
        type = EnumCowboyType.EnumCowboyType_FlushInRow,
        hitcount = 0,
        lasthit = 0
    }, --同花/连牌/同花连牌
    [EnumCowboyType.EnumCowboyType_Pair] = { type = EnumCowboyType.EnumCowboyType_Pair, hitcount = 0, lasthit = 0 }, --对子(包含对A)
    [EnumCowboyType.EnumCowboyType_PairA] = { type = EnumCowboyType.EnumCowboyType_PairA, hitcount = 0, lasthit = 0 }, --对子A
    --获胜牌型
    [EnumCowboyType.EnumCowboyType_HighCardPair] = {
        type = EnumCowboyType.EnumCowboyType_HighCardPair,
        hitcount = 0,
        lasthit = 0
    }, --高牌/一对
    [EnumCowboyType.EnumCowboyType_TwoPair] = { type = EnumCowboyType.EnumCowboyType_TwoPair, hitcount = 0, lasthit = 0 }, --两对
    [EnumCowboyType.EnumCowboyType_ThrKndStrghtFlsh] = {
        type = EnumCowboyType.EnumCowboyType_ThrKndStrghtFlsh,
        hitcount = 0,
        lasthit = 0
    }, --三条/顺子/同花
    [EnumCowboyType.EnumCowboyType_FullHouse] = {
        type = EnumCowboyType.EnumCowboyType_FullHouse,
        hitcount = 0,
        lasthit = 0
    }, --葫芦
    [EnumCowboyType.EnumCowboyType_BeyondFourKind] = {
        type = EnumCowboyType.EnumCowboyType_BeyondFourKind,
        hitcount = 0,
        lasthit = 0
    } --金刚/同花顺/皇家同花顺
}

local TimerID = {
    -- 游戏阶段
    TimerID_Check = { 1, 100 }, --id, interval(ms), timestamp(ms)
    TimerID_Start = { 2, 6 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Betting = { 3, 15 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Show = { 4, (2 + 1 + 4) * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Finish = { 5, 3 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_NotifyBet = { 6, 200, 0 }, --id, interval(ms), timestamp(ms)
    -- 协程
    TimerID_Timeout = { 7, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = { 8, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Result = { 9, 3 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Robot = { 10, 200, 0 } --id, interval(ms), timestamp(ms)
}

-- 房间状态
local EnumRoomState = {
    Check = 1,
    Start = 2,
    Betting = 3, -- 下注状态
    Show = 4,
    Finish = 5
}

-- 玩家状态
local EnumUserState = {
    Intoing = 1,
    Playing = 2,
    Logout = 3,
    Leave = 4
}

-- 获取房间配置信息
function Room:conf()
    --print(cjson.encode(MatchMgr:getConf()))
    return MatchMgr:getConfByMid(self.mid)
end

function Room:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init()
    o:check()
    return o
end

function Room:init()
    -- 定时
    self.timer = timer.create()

    -- 用户相关
    self.users = self.users or {}
    self.user_count = 0 -- 玩家数目(真实玩家数+机器人数)
    self.robot_count = 0 -- 机器人数目

    -- 牌局相关
    self.start_time = global.ctms()
    self.betting_time = global.ctms()
    self.show_time = global.ctms()
    self.finish_time = global.ctms()
    self.round_start_time = 0

    self.state = EnumRoomState.Check
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.roundid = (self.id << 32) | global.ctsec()
    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有非机器人在每个下注区下注累计值
    self.betst = {} -- 下注统计
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端, 元素类型为 PBCowboyBetData
    self.logmgr = LogMgr:new(
        self:conf() and self:conf().maxlogsavedsize,
        tostring(global.sid()) .. tostring("_") .. tostring(self.id)
    ) -- 历史记录
    self:calBetST()
    --self.lastclaerlogstime		= nil					-- 上次清历史数据时间，UTC 时间
    --self.forceclientclearlogs	= false					-- 是否强制客户端清除历史
    self.onlinelst = {} -- 在线列表
    self.sdata = { roomtype = (self:conf() and self:conf().roomtype) } -- 统计数据
    self.vtable = VTable:new({ id = 1 })

    self.poker = Cowboy:new()
    self.statistic = Statistic:new(self.id, self:conf().mid)
    self.total_bets = {}
    self.total_profit = {}
    Utils:unSerializeMiniGame(self)
    --self.betmgr = BetMgr:new(o.id, o.mid)
    --self.keepsession = KeepSessionAlive:new(o.users, o.id, o.mid)

    self.update_games = 0 -- 更新经过的局数
    self.rand_player_num = 1
    self.realPlayerUID = 0 --

    self.lastCreateRobotTime = 0 -- 上次创建机器人时刻
    self.createRobotTimeInterval = 4 -- 定时器时间间隔(秒)
    self.lastRemoveRobotTime = 0 -- 上次移除机器人时刻(秒)
    self.hasCreateTimer = false
    self.needRobotNum = 30 -- 默认需要创建30个机器人   每20分钟更新一次该值
    self.lastNeedRobotTime = 0  -- 上次需要机器人时刻
    self.calcChipsTime = 0           -- 计算筹码时刻(秒)
end

-- 一局结束重置
function Room:roundReset()
    -- 牌局相关
    self.update_games = self.update_games + 1
    self.start_time = global.ctms()
    self.betting_time = global.ctms()
    self.show_time = global.ctms()
    self.finish_time = global.ctms()
    self.round_start_time = 0
    self.bigcard_show_time_delta = 0

    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有非机器人在每个下注区下注累计值
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端
    self.sdata = { roomtype = (self:conf() and self:conf().roomtype) } -- 清空统计数据

    -- 记录每日北京时间中午 12 时（UTC 时间早上 4 时）清空一次
    --local currentime = os.date("!*t")
    --if currentime.hour == 4 and
    --( not self.lastclaerlogstime or currentime.day ~= self.lastclaerlogstime.day ) then
    --self.logs = {}
    --self.lastclaerlogstime		= os.date("!*t")
    --self.forceclientclearlogs	= true
    --log.debug("idx(%s,%s) clear log", self.id)
    --end

    -- 用户数据
    for k, v in pairs(self.users) do
        v.bets = g.copy(DEFAULT_BET_TABLE) -- 该玩家下注信息
        v.totalbet = 0 -- 总下注金额
        v.profit = 0 -- 盈利
        v.totalprofit = 0 -- 总盈利
        v.isbettimeout = false -- 是否下注超时
    end
end

-- 广播消息
function Room:broadcastCmd(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.linkid then
            net.send(v.linkid, k, maincmd, subcmd, msg)
        end
    end
end

-- 广播消息给正在玩的玩家
function Room:broadcastCmdToPlayingUsers(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and v.linkid then
            net.send(v.linkid, k, maincmd, subcmd, msg)
        end
    end
end

-- 给正在玩的玩家(非机器人)发送消息
function Room:sendCmdToPlayingUsers(maincmd, subcmd, msg, msglen)
    self.links = self.links or {}
    if not self.user_cached then
        self.links = {}
        local linkidstr = nil
        for k, v in pairs(self.users) do
            if v.state == EnumUserState.Playing and v.linkid then -- 2022-3-9
                linkidstr = tostring(v.linkid)
                self.links[linkidstr] = self.links[linkidstr] or {}
                table.insert(self.links[linkidstr], k)
            end
        end
        self.user_cached = true
        --log.debug("idx(%s,%s) is not cached %s", self.id,self.mid, cjson.encode(self.links))
    end
    net.send_users(cjson.encode(self.links), maincmd, subcmd, msg, msglen)
end

function Room:count(uid)
    local ret = self:recount(uid) -- 重新计算玩家数
    if ret and self:conf() and self:conf().single_profit_switch then
        return self.user_count - 1, self.robot_count
    else
        return self.user_count, self.robot_count
    end
end

-- 重新计算玩家数目
function Room:recount(uid)
    self.user_count = 0
    self.robot_count = 0
    local userInRoom = false
    for k, v in pairs(self.users) do
        self.user_count = self.user_count + 1
        if Utils:isRobot(v.api) then
            self.robot_count = self.robot_count + 1
        end
        if v and v.uid and uid and v.uid == uid then
            userInRoom = true
        end
    end
    return userInRoom
end

function Room:getApiUserNum()
    local t = {}
    local conf = self:conf()
    for _, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and conf and conf.roomtype then
            local api = v.api
            t[api] = t[api] or {}
            t[api][conf.roomtype] = t[api][conf.roomtype] or {}
            if v.state == EnumUserState.Playing then
                t[api][conf.roomtype].players = (t[api][conf.roomtype].players or 0) + 1
            end
        end
    end

    return t
end

function Room:lock()
    return false
end

function Room:roomtype()
    return self:conf().roomtype
end

-- 清空该服所有玩家
function Room:clearUsersBySrvId(srvid)
    for k, v in pairs(self.users) do
        if v.linkid == srvid then
            self:logout(k)
        end
    end
end

-- 玩家登出
function Room:logout(uid)
    local user = self.users[uid]
    if user then
        user.state = EnumUserState.Logout
        self.user_cached = false
        log.info("idx(%s,%s) %s room logout %s", self.id, self.mid, uid, self.user_count)
    end
end

-- 更新虚拟桌
function Room:updateSeatsInVTable(vtable)
    if vtable and type(vtable) == "table" then
        --local msg = pb.encode("network.cmd.PBGameUpdateSeats_N", { seats = vtable:getSeatsInfo()  })
        --for _, seat in ipairs(vtable:getSeats()) do
        --local uid = seat:getUid()
        --local user = self.users[uid]
        --if user then
        --net.send(user.linkid, uid, pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"), pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameUpdateSeats"), msg)
        --end
        --end
        local t = { seats = vtable:getSeatsInfo() }
        pb.encode(
            "network.cmd.PBGameUpdateSeats_N",
            t,
            function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameUpdateSeats"),
                pointer,
                length
            )
            log.debug("idx(%s,%s) PBGameUpdateSeats_N : %s", self.id, self.mid, cjson.encode(t))
        end
        )
    end
end

-- 获取指定玩家金额
function Room:getUserMoney(uid)
    local user = self.users[uid]
    --print('getUserMoney roomtype', self:conf().roomtype, 'money', 'coin', user.coin)
    return user and (user.playerinfo and user.playerinfo.balance or 0) or 0
end

-- 玩家身上金币更新
function Room:onUserMoneyUpdate(data)
    if (data and #data > 0) then
        if data[1].code == 0 then
            local resp = pb.encode("network.cmd.PBNotifyGameMoneyUpdate_N", { val = data[1].extdata.balance })
            net.send(
                data[1].acid,
                data[1].uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_NotifyGameMoneyUpdate"),
                resp
            )
        end
        log.debug(
            "idx(%s,%s) onUserMoneyUpdate user money change %s,%s,%s,%s",
            self.id,
            self.mid,
            data[1].acid,
            data[1].uid,
            data[1].extdata.balance,
            data[1].code
        )
    end
end

function Room:userQueryUserInfo(uid, ok, ud)
    local user = self.users[uid]
    if user and user.TimerID_Timeout then
        timer.cancel(user.TimerID_Timeout, TimerID.TimerID_Timeout[1])
        log.debug("idx(%s,%s) query userinfo:%s ok:%s", self.id, self.mid, tostring(uid), tostring(ok))
        coroutine.resume(user.co, ok, ud)
    end
end

function Room:userMutexCheck(uid, code)
    local user = self.users[uid]
    if user then
        timer.cancel(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1])
        log.debug("idx(%s,%s) mutex check:%s code:%s", self.id, self.mid, tostring(uid), tostring(code))
        coroutine.resume(user.mutex, code > 0)
    end
end

function Room:queryUserResult(ok, ud)
    if self.timer and self:conf().single_profit_switch then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.debug("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

-- 玩家离开
function Room:userLeave(uid, linkid)
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
    }
    log.debug("idx(%s,%s) userLeave(): uid=%s", self.id, self.mid, uid)
    if not linkid then
        return
    end

    local user = self.users[uid]
    if user == nil then
        log.debug("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
        local resp = pb.encode("network.cmd.PBLeaveGameRoomResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
                resp
            )
        end
        return
    end

    if user.state == EnumUserState.Leave then -- 若玩家已经离开
        log.info("idx(%s,%s) has leaveed:%s", self.id, self.mid, uid)
        return
    end
    --if user.totalbet and user.totalbet > 0 then
    --	log.info("idx(%s,%s) user:%s betted not allowed to leave", self.id, uid)
    --	t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed")
    --Utils:sendTipsToMe(linkid, uid, global.lang(21))
    --end

    local resp = pb.encode("network.cmd.PBLeaveGameRoomResp_S", t)
    if t.code == pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess") then
        user.state = EnumUserState.Leave
        self.user_cached = false
        mutex.request(
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
            pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
            pb.encode("network.cmd.PBMutexRemove", { uid = uid, srvid = global.sid(), roomid = self.id })
        )

        --if user.seat and not user.seat:isEmpty() then
        --user.seat:lockSeat()
        --end

        local to = {
            uid = uid,
            srvid = 0,
            roomid = 0,
            matchid = 0,
            maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            data = resp
        }
        local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)
        if linkid then
            net.shared(
                linkid,
                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                synto
            )
        end
        log.info("idx(%s,%s) userLeave(): uid=%s", self.id, self.mid, uid)
        return
    end
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
    end
    log.info("idx(%s,%s) userLeave(): uid=%s, code=%s", self.id, self.mid, uid, t.code)
end

local function onMutexTo(arg)
    arg[2]:userMutexCheck(arg[1], -1)
end

local function onTimeout(arg)
    arg[2]:userQueryUserInfo(arg[1], false, nil)
end

local function onResultTimeout(arg)
    arg[1]:queryUserResult(false, nil)
end

-- 玩家进入游戏
function Room:userInto(uid, linkid, rev)
    if not linkid then
        return
    end
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(),
        idx = {
            srvid = global.sid(),
            roomid = self.id,
            matchid = self.mid,
            roomtype = self:conf().roomtype
        },
        data = {
            state = self.state,
            lefttime = 0,
            roundid = self.roundid,
            --jackpot = JackPot,
            player = {},
            seats = {},
            logs = {},
            sta = self.betst,
            betdata = {
                uid = uid,
                usertotal = 0,
                areabet = {}
            },
            cowboy = { cards = {}, type = 0 },
            bull = { cards = {}, type = 0 },
            pub = { cards = {}, type = 0 },
            configchips = self:conf().chips,
            onlinenum = Utils:getVirtualPlayerCount(self), -- #self.onlinelst,
            odds = {},
            bestFive = { cards = {}, type = 0 }
        }
    }

    if self.isStopping then
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
        t.data = nil
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
            )
            Utils:sendTipsToMe(linkid, uid, global.lang(37), 0) -- 发送提示信息
        end
        return
    end

    for _, v in ipairs(self:conf().betarea) do -- 下注区域信息
        table.insert(t.data.odds, v[1])
    end

    local dstCards = { t.data.cowboy, t.data.bull, t.data.pub, t.data.bestFive }
    if self.sdata and self.sdata.cards then
        for i = 1, #dstCards do
            dstCards[i].type = self.sdata.cardstype[i]
            for _, v in ipairs(self.sdata.cards[i].cards) do
                table.insert(
                    dstCards[i].cards,
                    {
                    color = self.poker:cardColor(v),
                    count = self.poker:cardValue(v)
                }
                )
            end
        end
    end

    self.users[uid] = self.users[uid] or
        { TimerID_MutexTo = timer.create(), TimerID_Timeout = timer.create() --[[TimerID_UserBet = timer.create(),]] }
    local user = self.users[uid]
    user.uid = uid
    user.state = EnumUserState.Intoing
    user.linkid = linkid
    user.ip = rev.ip or ""
    user.mobile = rev.mobile
    user.roomid = self.id
    user.matchid = self.mid
    user.playerinfo = user.playerinfo or { extra = {} }
    user.totalbet = user.totalbet or 0
    user.profit = user.profit or 0
    user.totalprofit = user.totalprofit or 0
    user.totalpureprofit = user.totalpureprofit or 0
    user.totalfee = user.totalfee or 0
    user.bets = user.bets or g.copy(DEFAULT_BET_TABLE)

    user.mutex = coroutine.create(
        function(user)
        mutex.request(
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
            pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexCheck"),
            pb.encode(
                "network.cmd.PBMutexCheck",
                {
                uid = uid,
                srvid = global.sid(),
                matchid = self.mid,
                roomid = self.id,
                roomtype = self:conf() and self:conf().roomtype
            }
            )
        )
        local ok = coroutine.yield()
        if not ok then
            if self.users[uid] ~= nil then
                if user and user.TimerID_MutexTo then
                    timer.destroy(user.TimerID_MutexTo)
                end
                if user and user.TimerID_Timeout then
                    timer.destroy(user.TimerID_Timeout)
                end
                --timer.destroy(user.TimerID_UserBet)
                self.users[uid] = nil
                t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                t.data = nil
                net.send(
                    linkid,
                    uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                    pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                )
                Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
            end
            log.info("idx(%s,%s) player:%s has been in another room", self.id, self.mid, uid)
            return
        end

        user.co = coroutine.create(
            function(user)
            Utils:queryUserInfo(
                { uid = uid, roomid = self.id, matchid = self.mid, carrybound = self:conf().carrybound }
            )
            local ok, ud = coroutine.yield()
            --print('ok', ok, 'ud', cjson.encode(ud))

            if ud then
                -- userinfo
                user.uid = uid
                user.nobet_boardcnt = 0
                user.playerinfo = {
                    uid = uid,
                    username = ud.name or "",
                    nickurl = ud.nickurl or "",
                    balance = self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and
                        ud.money or
                        ud.coin,
                    extra = {
                        ip = user.ip or "",
                        api = ud.api or ""
                    }
                }
                -- 携带数据
                user.linkid = linkid
                user.intots = user.intots or global.ctsec()
                user.api = ud.api
                user.sid = ud.sid
                user.userId = ud.userId
                user.ud = ud
            end

            -- 防止协程返回时，玩家实质上已离线
            if ok and user.state ~= EnumUserState.Intoing then
                ok = false
                log.info("idx(%s,%s) user %s logout or leave", self.id, self.mid, uid)
            end

            if not ok then
                if self.users[uid] ~= nil then
                    self.users[uid].state = EnumUserState.Leave
                    t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                    t.data = nil
                    net.send(
                        linkid,
                        uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                        pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                    )
                end
                log.info("idx(%s,%s) user %s not allowed into room", self.id, self.mid, uid)
                return
            end

            -- 填写返回数据
            if self.state == EnumRoomState.Start then
                t.data.lefttime = TimerID.TimerID_Start[2] - (global.ctms() - self.start_time)
            elseif self.state == EnumRoomState.Betting then
                t.data.lefttime = TimerID.TimerID_Betting[2] - (global.ctms() - self.betting_time)
            elseif self.state == EnumRoomState.Show then
                t.data.lefttime = TimerID.TimerID_Show[2] - (global.ctms() - self.show_time) + TimerID.TimerID_Finish[2] +
                    self.bigcard_show_time_delta
            elseif self.state == EnumRoomState.Finish then
                t.data.lefttime = TimerID.TimerID_Finish[2] - (global.ctms() - self.finish_time)
            end
            t.data.lefttime = t.data.lefttime > 0 and t.data.lefttime or 0
            t.data.player = user.playerinfo
            t.data.seats = g.copy(self.vtable:getSeatsInfo())
            if self.logmgr:size() <= self:conf().maxlogshowsize then
                t.data.logs = self.logmgr:getLogs()
            else
                g.move(
                    self.logmgr:getLogs(),
                    self.logmgr:size() - self:conf().maxlogshowsize + 1,
                    self.logmgr:size(),
                    1,
                    t.data.logs
                )
            end

            t.data.betdata.uid = uid
            t.data.betdata.usertotal = user.totalbet or 0
            for k, v in pairs(self.bets) do
                if v ~= 0 then
                    table.insert(
                        t.data.betdata.areabet,
                        {
                        bettype = k,
                        betvalue = 0,
                        userareatotal = user.bets and user.bets[k] or 0,
                        areatotal = v
                        --odds			= self:conf() and self:conf().betarea and self:conf().betarea[k][1],
                    }
                    )
                end
            end
            log.info(
                "idx(%s,%s) into room: user %s linkid %s state %s balance %s user_count %s t %s",
                self.id,
                self.mid,
                uid,
                linkid,
                self.state,
                user.playerinfo and user.playerinfo.balance or 0,
                self.user_count,
                cjson.encode(t)
            )

            local resp = pb.encode("network.cmd.PBIntoCowboyRoomResp_S", t)
            local to = {
                uid = uid,
                srvid = global.sid(), -- 当前服务器ID
                roomid = self.id,
                matchid = self.mid,
                maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoCowboyRoomResp"),
                data = resp
            }
            local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)
            net.shared(
                linkid,
                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                synto
            )

            user.state = EnumUserState.Playing
            self.user_cached = false
            self:recount()
        end
        )
        timer.tick(
            user.TimerID_Timeout,
            TimerID.TimerID_Timeout[1],
            TimerID.TimerID_Timeout[2],
            onTimeout,
            { uid, self }
        )
        coroutine.resume(user.co, user)
    end
    )
    timer.tick(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1], TimerID.TimerID_MutexTo[2], onMutexTo, { uid, self })
    coroutine.resume(user.mutex, user)
end

-- 玩家下注
function Room:userBet(uid, linkid, rev)
    local t = {
        code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_Succ"),
        data = {
            uid = uid,
            usertotal = 0,
            areabet = {}
        }
    }
    local user = self.users[uid]
    local ok = true
    local user_bets = g.copy(DEFAULT_BET_TABLE) -- 玩家此次下注
    local user_totalbet = 0 -- 玩家此次总下注
    local remark = {}

    -- 非法玩家
    if user == nil then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidUser")
        ok = false
        goto labelnotok
    end
    -- 游戏下注状态
    if self.state < EnumRoomState.Betting or self.state >= EnumRoomState.Show then -- 非下注状态
        log.info(
            "idx(%s,%s) user %s, game state %s, game state is not allow to bet",
            self.id,
            self.mid,
            uid,
            self.state
        )
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidGameState")
        ok = false
        goto labelnotok
    end
    -- 下注类型及下注额校验
    if not rev.data or not rev.data.areabet then
        log.info("idx(%s,%s) user %s, bad guy", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue")
        ok = false
        goto labelnotok
    end
    for k, v in ipairs(rev.data.areabet) do
        if v and v.bettype and type(v.bettype) == "number" and v.betvalue and type(v.betvalue) == "number" then
            if not g.isInTable(DEFAULT_BET_TYPE, v.bettype) or -- 下注类型非法
                (self:conf() and not g.isInTable(self:conf().chips, v.betvalue))
            then -- 下注筹码较验
                log.info("idx(%s,%s) user %s, bettype or betvalue invalid", self.id, self.mid, uid)
                t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue")
                ok = false
                goto labelnotok
            else
                -- 单下注区游戏限红
                if self:conf() and self:conf().betarea and
                    (v.betvalue > self:conf().betarea[v.bettype][3] or
                        v.betvalue + self.bets[v.bettype] > self:conf().betarea[v.bettype][3])
                then
                    log.info("idx(%s,%s) user %s, betvalue over limits", self.id, self.mid, uid)
                    t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverLimits")
                    ok = false
                    goto labelnotok
                end
                if Utils:isRobot(user.api) and not user.linkid then
                    if v.bettype == EnumCowboyType.EnumCowboyType_Bull and v.betvalue > 0 and user.bets and
                        user.bets[EnumCowboyType.EnumCowboyType_Cowboy] > 0 then
                        v.bettype = EnumCowboyType.EnumCowboyType_Cowboy
                    elseif v.bettype == EnumCowboyType.EnumCowboyType_Cowboy and v.betvalue > 0 and user.bets and
                        user.bets[EnumCowboyType.EnumCowboyType_Bull] > 0 then
                        v.bettype = EnumCowboyType.EnumCowboyType_Bull
                    end
                end
                user_bets[v.bettype] = user_bets[v.bettype] + v.betvalue -- 该玩家此次在该下注区的下注总金额
                user_totalbet = user_totalbet + v.betvalue -- 该玩家此次总下注金额
                table.insert(remark, v.bettype)
            end
        end
    end
    -- 下注总额为 0
    if user_totalbet == 0 then
        log.info("idx(%s,%s) user %s totalbet 0", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue")
        ok = false
        goto labelnotok
    end
    -- 余额不足
    if user_totalbet > self:getUserMoney(uid) then
        log.info(
            "idx(%s,%s) user %s %s %s, totalbet over user's balance",
            self.id,
            self.mid,
            uid,
            self:getUserMoney(uid),
            user_totalbet
        )
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverBalance")
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    log.debug(
        "idx(%s,%s) user %s userBet: %s",
        self.id,
        self.mid,
        uid,
        cjson.encode(rev.data and rev.data.areabet or {})
    )
    if not ok then
        --t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
        --t.data = g.copy(rev.data) or nil
        t.data.uid = rev.data and rev.data.uid or 0
        t.data.balance = self:getUserMoney(t.data.uid) - (user and user.totalbet or 0)
        t.data.usertotal = rev.data and rev.data.usertotal or 0
        for _, v in ipairs((rev.data and rev.data.areabet) or {}) do
            table.insert(t.data.areabet, v)
        end
        local resp = pb.encode("network.cmd.PBCowboyBetResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyBetResp"),
                resp
            )
        end
        log.info("idx(%s,%s) user %s, PBCowboyBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    --扣费
    user.playerinfo = user.playerinfo or {}
    if user.playerinfo.balance and user.playerinfo.balance > user_totalbet then
        user.playerinfo.balance = user.playerinfo.balance - user_totalbet
    else
        user.playerinfo.balance = 0
    end
    self.vtable:updateMoney(uid, user.playerinfo.balance)

    if not self:conf().isib then -- 如果不可记账
        --log.info("idx(%s,%s) self:conf().isib = false", self.id, self.mid)
        -- 立即更新玩家身上金额
        if linkid then
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                -user_totalbet,
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_COWBOY_BET"),
                linkid,
                self:conf().roomtype,
                self.id,
                self.mid,
                {
                api = "debit",
                sid = user.sid,
                userId = user.userId,
                transactionId = g.uuid(),
                roundId = user.roundId,
                gameId = tostring(global.stype())
            }
            )
        end
    end

    -- 记录下注数据
    local areabet = {}
    user.bets = user.bets or g.copy(DEFAULT_BET_TABLE) -- 玩家当局在每个下注区下注累计值
    user.totalbet = user.totalbet or 0 -- 玩家当局在所有下注区下注总和
    user.totalbet = user.totalbet + user_totalbet
    for k, v in pairs(user_bets) do
        if v ~= 0 then
            user.bets[k] = user.bets[k] + v
            self.bets[k] = self.bets[k] + v -- 各下注区的总下注金额

            if not Utils:isRobot(user.api) then
                self.realPlayerUID = uid
                self.userbets[k] = self.userbets[k] + v
            end
            -- betque
            --table.insert(areabet, { bettype = k, betvalue = v, userareatotal = user.bets[k], areatotal = self.bets[k], })
        end
    end
    for k, v in ipairs(rev.data.areabet) do
        -- betque
        table.insert(
            areabet,
            {
            bettype = v.bettype,
            betvalue = v.betvalue,
            userareatotal = user.bets[v.bettype],
            areatotal = self.bets[v.bettype]
        }
        )
    end

    table.insert(
        self.betque,
        {
        uid = uid,
        balance = self:getUserMoney(uid),
        usertotal = user.totalbet,
        areabet = areabet
    }
    )

    -- 返回数据
    t.data.balance = self:getUserMoney(uid)
    t.data.usertotal = user.totalbet
    t.data.areabet = rev.data.areabet
    for k, v in pairs(t.data.areabet) do
        t.data.areabet[k].userareatotal = user.bets[v.bettype]
        t.data.areabet[k].areatotal = self.bets[v.bettype]
    end
    local resp = pb.encode("network.cmd.PBCowboyBetResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyBetResp"),
            resp
        )
    end
    log.debug("idx(%s,%s) user %s, PBCowboyBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

function Room:userHistory(uid, linkid, rev)
    if not linkid then
        return
    end
    local t = {
        logs = {},
        sta = {}
    }
    local ok = true
    local user = self.users[uid]

    -- 非法玩家
    if user == nil then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    if not ok then
        local resp = pb.encode("network.cmd.PBCowboyHistoryResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyHistoryResp"),
            resp
        )
        log.info("idx(%s,%s) user %s, PBCowboyHistoryResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    if self.logmgr:size() <= self:conf().maxlogshowsize then
        t.logs = self.logmgr:getLogs()
    else
        g.move(
            self.logmgr:getLogs(),
            self.logmgr:size() - self:conf().maxlogshowsize + 1,
            self.logmgr:size(),
            1,
            t.logs
        )
    end
    t.sta = self.betst

    local resp = pb.encode("network.cmd.PBCowboyHistoryResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyHistoryResp"),
        resp
    )
    log.debug(
        "idx(%s,%s) user %s, PBCowboyHistoryResp_S: %s, logmgr:size: %s",
        self.id,
        self.mid,
        uid,
        cjson.encode(t),
        self.logmgr:size()
    )
end

function Room:userOnlineList(uid, linkid, rev)
    if not linkid then
        return
    end

    local t = { list = {} }
    local ok = true
    local user = self.users[uid]

    -- 非法玩家
    if user == nil then
        log.info("idx(%s,%s) user %s is not in room", self.id, uid)
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    if not ok then
        local resp = pb.encode("network.cmd.PBCowboyOnlineListResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyOnlineListResp"),
            resp
        )
        log.info("idx(%s,%s) user %s, PBCowboyOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    -- 返回前 300 条
    g.move(self.onlinelst, 1, math.min(300, #self.onlinelst), 1, t.list)
    -- 返回前 300 条
    local resp = pb.encode("network.cmd.PBCowboyOnlineListResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyOnlineListResp"),
            resp
        )
    end
    log.debug("idx(%s,%s) user %s, PBCowboyOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

local function onNotifyBet(self)
    local function doRun()
        if self.state == EnumRoomState.Betting or
            (self.state == EnumRoomState.Show and global.ctms() <= self.show_time + 2000)
        then
            -- 单线程，betque 不考虑竞争问题
            local t = { bets = {} }
            for i = 1, 300 do -- 防止单个包过大，分割开
                if #self.betque == 0 then
                    break
                end
                table.insert(t.bets, table.remove(self.betque, 1))
            end
            if #t.bets > 0 then
                pb.encode(
                    "network.cmd.PBCowboyNotifyBettingInfo_N",
                    t,
                    function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyNotifyBettingInfo"),
                        pointer,
                        length
                    )
                    log.debug(
                        "idx(%s,%s) PBCowboyNotifyBettingInfo_N : %s %s",
                        self.id,
                        self.mid,
                        #t.bets,
                        cjson.encode(t)
                    )
                end
                )
            end
            --log.debug("idx:%s notifybet", self.id)
        end
    end

    g.call(doRun)
end

function Room:notifybet()
    log.debug("idx(%s,%s) notifybet room game:%s", self.id, self.mid, self.state)
    timer.tick(self.timer, TimerID.TimerID_NotifyBet[1], TimerID.TimerID_NotifyBet[2], onNotifyBet, self)
end

-- 定时检测创建机器人
local function onCreateRobot(self)
    local function doRun()
        local current_time = global.ctsec() -- 当前时刻(秒)
        local currentTimeMS = global.ctms() -- 当前时刻(毫秒)

        if current_time - self.lastNeedRobotTime > 600 then
            self.lastNeedRobotTime = current_time
            if self:conf().global_profit_switch then
                self.needRobotNum = rand.rand_between(50, 90)
            else
                --self.needRobotNum = 30
                self.needRobotNum = rand.rand_between(30, 50)
            end
        end
        Utils:checkCreateRobot(self, current_time, self.needRobotNum) -- 检测创建机器人

        -- 检测是否在下注状态
        if self.state == EnumRoomState.Betting then -- 如果是下注状态
            if (TimerID.TimerID_Betting[2] - 100 > currentTimeMS - self.stateBeginTime) and
                (currentTimeMS - self.stateBeginTime >= 1100)
            then
                Utils:robotBet(self) -- 机器人下注
            end
        elseif self.state == EnumRoomState.Start then -- 如果是开始状态
            -- 定时检测是否移除机器人
            if not self.minChips then
                local config = self:conf()
                if config and type(config.chips) == "table" and config.chips[1] then
                    self.minChips = config.chips[1]
                else
                    self.minChips = 1000
                end
            end
            if current_time - self.lastRemoveRobotTime > 100 then
                self.lastRemoveRobotTime = current_time
                for uid, user in pairs(self.users) do
                    if user and not user.linkid then   -- 如果是机器人
                        if user.playerinfo and user.playerinfo.balance <= self.minChips then
                            self.users[uid] = nil
                        elseif user.createtime and user.lifetime and current_time - user.createtime >= user.lifetime then
                            self.users[uid] = nil
                        end
                    end
                end
            end
        end
    end

    g.call(doRun)
end

local function onCheck(self)
    local function doRun()
        --if self:count() == 0 then return end
        timer.cancel(self.timer, TimerID.TimerID_Check[1])
        if self.isStopping then
            log.info("idx(%s,%s) self.isStopping=true", self.id, self.mid)
            Utils:onStopServer(self)
            return
        end
        self:start()
    end

    g.call(doRun)
end

function Room:check()
    log.debug("idx(%s,%s) check game state - %s %s", self.id, self.mid, self.state, tostring(global.stopping()))
    if global.stopping() then
        return
    end
    self.state = EnumRoomState.Check
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    if not self.hasCreateTimer then
        self.hasCreateTimer = true
        timer.tick(self.timer, TimerID.TimerID_Robot[1], TimerID.TimerID_Robot[2], onCreateRobot, self)
    end
end

local function onStart(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        self:betting()
    end

    g.call(doRun)
end

function Room:start()
    self:roundReset()
    self.roundid = (self.id << 32) | global.ctsec()
    self.state = EnumRoomState.Start
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.round_start_time = global.utcstr()
    self.start_time = global.ctms()
    self.logid = self.statistic:genLogId(self.start_time / 1000)

    pb.encode(
        "network.cmd.PBCowboyNotifyStart_N",
        -- {t = TimerID.TimerID_Start[2], roundid = self.roundid, onlinenum = #self.onlinelst},
        { t = TimerID.TimerID_Start[2], roundid = self.roundid, onlinenum = Utils:getVirtualPlayerCount(self) },
        function(pointer, length)
        self:sendCmdToPlayingUsers(
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyNotifyStart"),
            pointer,
            length
        )
    end
    )
    timer.tick(self.timer, TimerID.TimerID_Start[1], TimerID.TimerID_Start[2], onStart, self)

    log.info(
        "[idx:%s,%s] start room game, state %s roundid %s logid %s",
        self.id,
        self.mid,
        self.state,
        tostring(self.roundid),
        tostring(self.logid)
    )
    -- 重置数据
    --self.forceclientclearlogs = false
end

local function onBetting(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        self:show()
    end

    g.call(doRun)
end

function Room:betting()
    log.info("idx(%s,%s) betting state-%s", self.id, self.mid, self.state)

    self:notifybet()
    self.betting_time = global.ctms()
    self.state = EnumRoomState.Betting
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    pb.encode(
        "network.cmd.PBCowboyNotifyBet_N",
        { t = TimerID.TimerID_Betting[2] },
        function(pointer, length)
        self:sendCmdToPlayingUsers(
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyNotifyBet"),
            pointer,
            length
        )
    end
    )

    timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBetting, self)
end

local function onShow(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Show[1])
        self:finish()
    end

    g.call(doRun)
end

function Room:calBetST()
    -- 统计
    self.betst = g.copy(DEFAULT_BETST_TABLE)
    for _, v in ipairs(self.logmgr:getLogs()) do
        for _, bt in pairs(DEFAULT_BET_TYPE) do
            if g.isInTable(v.wintype, bt) then
                self.betst[bt].lasthit = 0
                self.betst[bt].hitcount = self.betst[bt].hitcount + 1
            else
                self.betst[bt].lasthit = self.betst[bt].lasthit + 1
            end
        end
    end
end

function Room:show()
    log.info("idx(%s,%s) show room game, state - %s", self.id, self.mid, self.state)

    self.state = EnumRoomState.Show
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.show_time = global.ctms()
    timer.cancel(self.timer, TimerID.TimerID_NotifyBet[1])

    onNotifyBet(self)

    if self:conf().isib then
        Utils:debit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_COWBOY_BET"))
        Utils:balance(self, EnumUserState.Playing)
        for uid, user in pairs(self.users) do
            if user and Utils:isRobot(user.api) then
                user.isdebiting = false
            end
        end
    end

    self:calcPlayChips() -- 2021-12-24

    -- 生成牌，计算牌型
    self.poker:reset()
    local cardsA, cardsB = self.poker:getMNCard(2, 2) -- 牛仔牌，公牛牌
    local cardsPub = self.poker:getNCard(5) -- 公共牌
    local profit_rate, usertotalbet_inhand, usertotalprofit_inhand = 0, 0, 0

    -- 配牌
    local is_config_card = false
    if self:conf() and self:conf().configcards and #self:conf().configcards > 0 then
        is_config_card = true
        if #self:conf().configcards[1] == 3 and #self:conf().configcards[1][1] == 2 and
            #self:conf().configcards[1][2] == 2 and
            #self:conf().configcards[1][3] == 5
        then
            g.print(self:conf().configcards[1])
            cardsA = g.copy(self:conf().configcards[1][1])
            cardsB = g.copy(self:conf().configcards[1][2])
            cardsPub = g.copy(self:conf().configcards[1][3])
            self.poker:printCards(cardsA)
            self.poker:printCards(cardsB)
            self.poker:printCards(cardsPub)
        end
        table.insert(self:conf().configcards, table.remove(self:conf().configcards, 1))
    end

    local pokertypeA = self.poker:getPokersType(cardsA, cardsPub)
    local pokertypeB = self.poker:getPokersType(cardsB, cardsPub)
    local winTypes, winPokerType, besthands = self.poker:getWinTypes(cardsA, cardsB, cardsPub)
    --根据盈利率触发胜负策略
    local usertotalbet = 0
    for k, v in pairs(EnumCowboyType) do
        usertotalbet = usertotalbet + (self.userbets[v] or 0)
    end
    if self:conf().global_profit_switch and usertotalbet > 0 then
        local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {} }
        for k, v in pairs(self.users) do
            if not Utils:isRobot(v.api) then
                table.insert(msg.data, { uid = k, chips = v.playchips or 0, betchips = v.totalbet or 0 })
            end
        end
        log.debug("idx(%s,%s) global start result request %s", self.id, self.mid, cjson.encode(msg))
        Utils:queryProfitResult(msg)

        profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(winTypes)
        local last_profitrate = profit_rate
        if not is_config_card and usertotalbet > 0 and profit_rate < self:conf().profitrate_threshold_lowerlimit then
            log.info("idx(%s,%s) tigh mode is trigger", self.mid, self.id)
            -- 计算真实玩家的输赢金额
            local realPlayerWin = self:GetRealPlayerWin(cardsA, cardsB, cardsPub)
            if realPlayerWin > self:conf().profit_max_win then
                local rnd = rand.rand_between(1, 10000)
                if profit_rate < self:conf().profitrate_threshold_minilimit or rnd <= 5000 then
                    -- 需要重新发牌
                    for i = 1, 5, 1 do
                        -- 生成牌，计算牌型
                        self.poker:reset()
                        cardsA, cardsB = self.poker:getMNCard(2, 2) -- 牛仔牌，公牛牌
                        cardsPub = self.poker:getNCard(5) -- 公共牌
                        realPlayerWin = self:GetRealPlayerWin(cardsA, cardsB, cardsPub)
                        if realPlayerWin <= 0 then
                            break
                        end
                    end
                    pokertypeA = self.poker:getPokersType(cardsA, cardsPub)
                    pokertypeB = self.poker:getPokersType(cardsB, cardsPub)
                    log.info("idx(%s,%s) swap cards is trigger", self.mid, self.id)
                    winTypes, winPokerType, besthands = self.poker:getWinTypes(cardsA, cardsB, cardsPub)
                    profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(winTypes)
                end
            end
        end
        local curday = global.cdsec()
        self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet_inhand
        self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit_inhand
    end
    if self:conf().single_profit_switch and usertotalbet > 0 then -- 单个人控制 且 有真实玩家下注了
        self.result_co = coroutine.create(
            function()
            local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {} }
            for k, v in pairs(self.users) do
                if not Utils:isRobot(v.api) then
                    table.insert(msg.data, { uid = k, chips = v.playchips or 0, betchips = v.totalbet or 0 })
                end
            end
            log.info("idx(%s,%s) start result request %s", self.id, self.mid, cjson.encode(msg))
            Utils:queryProfitResult(msg)
            local ok, res = coroutine.yield() -- 等待查询结果
            log.info("idx(%s,%s) finish result %s", self.id, self.mid, cjson.encode(res))
            if ok and res then
                for _, v in ipairs(res) do
                    local uid, r, maxwin = v.uid, v.res, v.maxwin
                    local user = self.users[uid]
                    if user then
                        user.maxwin = r * maxwin
                    end
                    --log.warn("uid=%s, r=%s, maxwin=%s", tostring(uid), tostring(r), tostring(maxwin))
                    if uid and uid == self.realPlayerUID and r then
                        for i = 0, 10, 1 do
                            -- 根据牌数据计算真实玩家的输赢值
                            local realPlayerWin = self:GetRealPlayerWin(cardsA, cardsB, cardsPub)
                            log.debug(
                                "idx(%s,%s) redeal  i=%s, realPlayerWin=%s, cardsA=%s,%s",
                                self.id,
                                self.mid,
                                tostring(i),
                                tostring(realPlayerWin),
                                tostring(cardsA[1]),
                                tostring(cardsA[2])
                            )
                            if r > 0 and maxwin then
                                if maxwin >= realPlayerWin and realPlayerWin > 0 then
                                    break
                                end
                                if i == 5 then
                                    r = -1
                                    log.info(
                                        "idx(%s,%s) maxwin maxtime is triggered %s",
                                        self.id,
                                        self.mid,
                                        tostring(self.logid)
                                    )
                                end
                            elseif r < 0 then -- 真实玩家输
                                if realPlayerWin < 0 then
                                    --log.warn("uid=%s, realPlayerWin=%s", uid, tostring(realPlayerWin))
                                    break
                                end
                            elseif r == 0 and maxwin then
                                if maxwin >= realPlayerWin then
                                    break
                                end
                            else
                                break
                            end
                            -- 未满足条件，重新发牌
                            self.poker:reset()
                            cardsA, cardsB = self.poker:getMNCard(2, 2) -- 牛仔牌，公牛牌
                            cardsPub = self.poker:getNCard(5) -- 公共牌
                        end -- for
                        pokertypeA = self.poker:getPokersType(cardsA, cardsPub) -- 重新计算牌型
                        pokertypeB = self.poker:getPokersType(cardsB, cardsPub)
                        winTypes, winPokerType, besthands = self.poker:getWinTypes(cardsA, cardsB, cardsPub)
                    end
                end
                log.info("idx(%s,%s) result success", self.id, self.mid)
            end

            for k, v in pairs({ EnumCowboyType.EnumCowboyType_BeyondFourKind, EnumCowboyType.EnumCowboyType_PairA }) do
                if g.isInTable(winTypes, v) then
                    self.bigcard_show_time_delta = 5300
                    break
                end
            end

            -- 填写返回数据
            local t = {
                cowboy = { cards = {}, type = pokertypeA },
                bull = { cards = {}, type = pokertypeB },
                pub = { cards = {} },
                areainfo = {},
                bestFive = {} -- 最佳 5 张
            }
            local srcCards = { cardsA, cardsB, cardsPub, besthands }
            local dstCards = { t.cowboy.cards, t.bull.cards, t.pub.cards, t.bestFive }
            for i = 1, #srcCards do
                for k, v in ipairs(srcCards[i]) do
                    table.insert(
                        dstCards[i],
                        {
                        color = self.poker:cardColor(v),
                        count = self.poker:cardValue(v)
                    }
                    )
                end
            end
            for k, v in pairs(DEFAULT_BET_TYPE) do
                table.insert(
                    t.areainfo,
                    {
                    bettype = v,
                    iswin = g.isInTable(winTypes, v)
                }
                )
            end

            --print("PBCowboyNotifyShow_N", cjson.encode(t))
            pb.encode(
                "network.cmd.PBCowboyNotifyShow_N",
                t,
                function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyNotifyShow"),
                    pointer,
                    length
                )
                log.debug("idx(%s,%s) PBCowboyNotifyShow_N : %s", self.id, self.mid, cjson.encode(t))
            end
            )
            timer.tick(
                self.timer,
                TimerID.TimerID_Show[1],
                TimerID.TimerID_Show[2] + self.bigcard_show_time_delta,
                onShow,
                self
            )

            --print(self:conf().maxlogsavedsize, self:conf().roomtype)
            --print(cjson.encode(self.logmgr))

            -- 生成一条记录
            local logitem = {
                wintype = winTypes,
                winpokertype = winPokerType
            }
            self.logmgr:push(logitem)
            log.debug(
                "idx(%s,%s) %s log %s",
                self.id,
                self.mid,
                self.bigcard_show_time_delta,
                cjson.encode(logitem)
            )

            self:calBetST()

            -- 牌局统计
            self.sdata.cards = {}
            for k, v in ipairs(srcCards) do
                table.insert(self.sdata.cards, { cards = v })
            end
            self.sdata.cardstype = {}
            table.insert(self.sdata.cardstype, pokertypeA)
            table.insert(self.sdata.cardstype, pokertypeB)
            self.sdata.wintypes = winTypes
            self.sdata.winpokertype = winPokerType
        end
        )
        timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, { self })
        coroutine.resume(self.result_co)
    else
        for k, v in pairs({ EnumCowboyType.EnumCowboyType_BeyondFourKind, EnumCowboyType.EnumCowboyType_PairA }) do
            if g.isInTable(winTypes, v) then
                self.bigcard_show_time_delta = 5300
                break
            end
        end

        -- 填写返回数据
        local t = {
            cowboy = { cards = {}, type = pokertypeA },
            bull = { cards = {}, type = pokertypeB },
            pub = { cards = {} },
            areainfo = {},
            bestFive = {} -- 最佳 5 张
        }
        local srcCards = { cardsA, cardsB, cardsPub, besthands }
        local dstCards = { t.cowboy.cards, t.bull.cards, t.pub.cards, t.bestFive }
        for i = 1, #srcCards do
            for k, v in ipairs(srcCards[i]) do
                table.insert(
                    dstCards[i],
                    {
                    color = self.poker:cardColor(v),
                    count = self.poker:cardValue(v)
                }
                )
            end
        end
        for k, v in pairs(DEFAULT_BET_TYPE) do
            table.insert(
                t.areainfo,
                {
                bettype = v,
                iswin = g.isInTable(winTypes, v)
            }
            )
        end

        --print("PBCowboyNotifyShow_N", cjson.encode(t))
        pb.encode(
            "network.cmd.PBCowboyNotifyShow_N",
            t,
            function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyNotifyShow"),
                pointer,
                length
            )
            log.debug("idx(%s,%s) PBCowboyNotifyShow_N : %s", self.id, self.mid, cjson.encode(t))
        end
        )
        timer.tick(
            self.timer,
            TimerID.TimerID_Show[1],
            TimerID.TimerID_Show[2] + self.bigcard_show_time_delta,
            onShow,
            self
        )

        --print(self:conf().maxlogsavedsize, self:conf().roomtype)
        --print(cjson.encode(self.logmgr))

        -- 生成一条记录
        local logitem = {
            wintype = winTypes,
            winpokertype = winPokerType
        }
        self.logmgr:push(logitem)
        log.debug("idx(%s,%s) %s log %s", self.id, self.mid, self.bigcard_show_time_delta, cjson.encode(logitem))

        self:calBetST()

        -- 牌局统计
        self.sdata.cards = {}
        for k, v in ipairs(srcCards) do
            table.insert(self.sdata.cards, { cards = v })
        end
        self.sdata.cardstype = {}
        table.insert(self.sdata.cardstype, pokertypeA)
        table.insert(self.sdata.cardstype, pokertypeB)
        self.sdata.wintypes = winTypes
        self.sdata.winpokertype = winPokerType
    end
end

local function onFinish(self)
    local function doRun()
        -- 清算在线列表
        self.onlinelst = {} -- 在线玩家列表
        local bigwinneridx = 1 --神算子(赢的次数最多的玩家)

        for k, v in pairs(self.users) do
            local totalbet = 0 -- 最近20局的总下注金额
            local wincnt = 0 -- 最近20局赢的局数
            for _, vv in ipairs(v.logmgr and v.logmgr:getLogs() or {}) do
                totalbet = totalbet + vv.bet
                wincnt = wincnt + ((vv.profit > 0) and 1 or 0)
            end
            --if totalbet > 0 then
            if v and v.state == EnumUserState.Playing then
                table.insert(
                    self.onlinelst,
                    {
                    player = {
                        uid = k,
                        username = v.playerinfo and v.playerinfo.username or "",
                        nickurl = v.playerinfo and v.playerinfo.nickurl or "",
                        --balance = self:getUserMoney(k) - (v.totalbet or 0)
                        balance = self:getUserMoney(k)
                    },
                    totalbet = totalbet,
                    wincnt = wincnt
                }
                )
                if wincnt > self.onlinelst[bigwinneridx].wincnt then
                    bigwinneridx = #self.onlinelst
                end
            end
        end

        local bigwinner = g.copy(self.onlinelst[bigwinneridx]) -- 大赢家信息
        table.remove(self.onlinelst, bigwinneridx)
        table.sort(
            self.onlinelst,
            function(a, b) -- 根据总下注金额从大到小排序
            return a.totalbet > b.totalbet
        end
        )
        table.insert(self.onlinelst, 1, bigwinner) -- 将大赢家放到第一个位置
        log.debug("idx(%s,%s) onlinelst %s", self.id, self.mid, cjson.encode(self.onlinelst))
        -- 分配座位
        self.vtable:reset()
        for i = 1, math.min(self.vtable:getSize(), #self.onlinelst) do
            local o = self.onlinelst[i]
            local uid = o.player.uid
            self.vtable:sit(uid, self.users[uid].playerinfo)
        end

        self:updateSeatsInVTable(self.vtable) -- 通知玩家更新座位信息

        -- 清除玩家
        for k, v in pairs(self.users) do
            if not v.totalbet or v.totalbet == 0 then -- 如果玩家该局未下注
                v.nobet_boardcnt = (v.nobet_boardcnt or 0) + 1 -- 未下注局数增1
            end
            local is_need_destry = false
            if v.state == EnumUserState.Leave then -- 如果该玩家已离开
                is_need_destry = true
            end
            if v.state == EnumUserState.Logout and (v.nobet_boardcnt or 0) >= 20 then
                is_need_destry = true
            end

            if is_need_destry and v.linkid then
                if v.TimerID_Timeout then
                    timer.destroy(v.TimerID_Timeout)
                end
                if v.TimerID_MutexTo then
                    timer.destroy(v.TimerID_MutexTo)
                end
                if v.state == EnumUserState.Logout then -- 退出
                    mutex.request(
                        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
                        pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
                        pb.encode("network.cmd.PBMutexRemove", { uid = k, srvid = global.sid(), roomid = self.id })
                    )
                end
                log.info("idx(%s,%s) kick user:%s state:%s", self.id, self.mid, k, tostring(v.state))
                self.users[k] = nil
                self.user_cached = false
                self:recount()
            end
        end

        -- 广播赢分大于 100 万
        --self.statistic:broadcastBigWinner()

        timer.cancel(self.timer, TimerID.TimerID_Finish[1])

        -- 检测该房间是否有真实玩家
        local playerCount, robotCount = self:count()
        local needDestroy = false
        local rm = MatchMgr:getMatchById(self.mid)
        if playerCount == robotCount and self:conf() and self:conf().single_profit_switch then
            if rm then
                local emptyRoomCount = rm:getEmptyRoomCount() -- 获取空房间数
                if emptyRoomCount > (self:conf().mintable or 3) then
                    needDestroy = true
                end
            end
        end

        if needDestroy then -- 如果需要销毁房间
            rm:destroyRoom(self.id) -- 销毁当前房间
        else
            self:check()
        end
    end

    g.call(doRun)
end

function Room:finish()
    log.info("idx(%s,%s) finish room game, state - %s", self.id, self.mid, self.state)
    self.state = EnumRoomState.Finish
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.finish_time = global.ctms()

    local lastlogitem = self.logmgr:back()
    local totalbet, usertotalbet = 0, 0        -- 所有玩家总下注，所有真实玩家总下注
    local totalprofit, usertotalprofit = 0, 0  -- 所有玩家总盈利，所有真实玩家总盈利
    local ranks = {}
    local onlinerank = {
        -- 在线排名信息
        uid = 0,
        --rank		= 0,
        --player		= v.seat and v.seat:getSeatInfo().playerinfo,
        totalprofit = 0, -- 总收益
        areas = {}
    }
    self.hasRealPlayerBet = false -- 是否有真实玩家下注了
    self.sdata.users = self.sdata.users or {}
    for k, v in pairs(self.users) do -- 遍历所有玩家
        if not v.isdebiting and v.totalbet and v.totalbet > 0 then
            if not Utils:isRobot(v.api) then
                self.hasRealPlayerBet = true
            end
            -- 牌局统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[k] = self.sdata.users[k] or {}
            self.sdata.users[k].areas = self.sdata.users[k].areas or {}
            self.sdata.users[k].stime = self.start_time / 1000
            self.sdata.users[k].etime = self.finish_time / 1000
            self.sdata.users[k].sid = v.seat and v.seat:getSid() or 0
            self.sdata.users[k].tid = v.vtable and v.vtable:getTid() or 0
            self.sdata.users[k].money = self.sdata.users[k].money or (self:getUserMoney(k) or 0)
            self.sdata.users[k].nickname = v.playerinfo and v.playerinfo.nickname
            self.sdata.users[k].username = v.playerinfo and v.playerinfo.username
            self.sdata.users[k].nickurl = v.playerinfo and v.playerinfo.nickurl
            self.sdata.users[k].currency = v.playerinfo and v.playerinfo.currency

            -- 结算
            v.totalprofit = 0
            v.totalpureprofit = 0
            v.totalfee = 0
            totalbet = totalbet + v.totalbet
            for _, bettype in ipairs(DEFAULT_BET_TYPE) do -- 遍历所有下注区
                local profit = 0 -- 玩家在当前下注区赢利
                local pureprofit = 0 -- 玩家在当前下注区纯利
                local bets = v.bets[bettype] -- 玩家在当前下注区总下注值
                if bets > 0 then -- 如果该玩家在这个下注区下注了
                    -- 计算赢利
                    if g.isInTable(lastlogitem.wintype, bettype) then -- 押中
                        profit = bets * (self:conf() and self:conf().betarea and self:conf().betarea[bettype][1])
                    end
                    pureprofit = profit - bets

                    v.totalprofit = v.totalprofit + profit
                    v.totalpureprofit = v.totalpureprofit + pureprofit

                    self.profits[bettype] = self.profits[bettype] or 0
                    self.profits[bettype] = self.profits[bettype] + profit

                    -- 牌局统计
                    table.insert(
                        self.sdata.users[k].areas,
                        {
                        bettype = bettype,
                        betvalue = bets,
                        profit = profit,
                        pureprofit = pureprofit,
                        fee = 0
                    }
                    )
                end -- end of if bets > 0 then
            end -- end of for _, bettype in ipairs(DEFAULT_BET_TYPE) do

            --盈利扣水
            if v.totalpureprofit > 0 and (self:conf().rebate or 0) > 0 then
                local rebate = math.floor(v.totalpureprofit * self:conf().rebate)
                v.totalprofit = v.totalprofit - rebate
                v.totalpureprofit = v.totalpureprofit - rebate
            end

            v.playerinfo = v.playerinfo or { }
            v.playerinfo.balance = v.playerinfo.balance or 0
            v.playerinfo.balance = v.playerinfo.balance + v.totalprofit

            if 0 == v.totalpureprofit then
                v.playchips = 0
            end

            self.sdata.users[k].extrainfo = cjson.encode(
                {
                ip = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.ip,
                api = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.api,
                roomtype = self:conf().roomtype,
                maxwin = v.maxwin or 0,
                money = self:getUserMoney(k) or 0,
                playchips = v.playchips or 0 -- 2021-12-24
            }
            )

            log.debug(
                "idx(%s,%s) uid=%s, rofit settlement profit %s, totalbets %s, totalpureprofit %s",
                self.id,
                self.mid,
                k,
                tostring(v.totalprofit),
                tostring(v.totalbet),
                tostring(v.totalpureprofit)
            )

            totalprofit = totalprofit + v.totalprofit

            -- 牌局统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[k] = self.sdata.users[k] or {} --uid为k的玩家
            self.sdata.users[k].totalbet = v.totalbet
            self.sdata.users[k].totalprofit = v.totalprofit  -- 该玩家总盈利
            self.sdata.users[k].totalpureprofit = v.totalpureprofit  -- 该玩家纯盈利
            self.sdata.users[k].totalfee = v.totalfee

            if not Utils:isRobot(v.api) then  -- 如果不是机器人
                usertotalprofit = usertotalprofit + v.totalprofit --真实玩家总盈利
                usertotalbet = usertotalbet + v.totalbet  -- 真实玩家总下注
                self.sdata.users[k].ugameinfo = {texas = {inctotalhands = 1}}
            end

            -- ranks
            -- TODO：优化
            if self.vtable:getSeat(k) then -- 如果该玩家在VIP座位中
                local rank = {
                    uid = k,
                    --rank		= 0,
                    --player		= v.seat and v.seat:getSeatInfo().playerinfo,
                    totalprofit = v.totalprofit, -- 总收益
                    areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
                }
                table.insert(ranks, rank)
            else -- 下面是不在VIP座位的玩家
                -- 在线玩家 uid 为 0
                for _, bettype in ipairs(DEFAULT_BET_TYPE) do -- 遍历各个下注区域
                    local areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
                    local area = areas[bettype]
                    if area and area.bettype then
                        onlinerank.totalprofit = (onlinerank.totalprofit or 0) + (area.profit or 0) -- 非座位上玩家在该区域的总收益(未减下注金额)
                        onlinerank.areas[area.bettype] = onlinerank.areas[area.bettype] or {}
                        onlinerank.areas[area.bettype].bettype = area.bettype
                        onlinerank.areas[area.bettype].betvalue = (onlinerank.areas[area.bettype].betvalue or 0) + (area.betvalue or 0)
                        if g.isInTable(lastlogitem.wintype, area.bettype) then -- 押中
                            onlinerank.areas[area.bettype].profit = (onlinerank.areas[area.bettype].profit or 0) + (area.profit or 0)
                            onlinerank.areas[area.bettype].pureprofit = (onlinerank.areas[area.bettype].pureprofit or 0) + (area.pureprofit or 0)
                        else
                            onlinerank.areas[area.bettype].profit = 0
                            onlinerank.areas[area.bettype].pureprofit = 0
                        end
                    end
                end
            end
            -- 最近 20 局
            v.logmgr = v.logmgr or LogMgr:new(20)
            v.logmgr:push({ bet = v.totalbet or 0, profit = v.totalprofit or 0 })
        end -- end of [if v.totalbet and v.totalbet > 0 then]
    end -- end of [for k,v in pairs(self.users) do]

    --赔率大于等于100的区域盈利最高的玩家需要广播 added by DQW 2021-9-13
    -- 遍历所有下注区，查找盈利超过100倍的区域
    for _, bettype in ipairs(DEFAULT_BET_TYPE) do
        if g.isInTable(lastlogitem.wintype, bettype) then -- 押中
            -- profit = bets * (self:conf() and self:conf().betarea and self:conf().betarea[bettype][1])
            if self:conf() and self:conf().betarea and self:conf().betarea[bettype][1] >= 100 then
                local uid = 0 -- 在该区域最大下注玩家
                local maxbet = 0 -- 在该区域的最大下注金额
                local winScoreProfit = 0
                -- 遍历所有下注玩家
                for k, v in pairs(self.users) do
                    if not v.isdebiting and v.totalbet and v.totalbet > 0 then
                        if v.bets[bettype] and v.bets[bettype] > maxbet then -- 玩家在当前下注区总下注值
                            uid = v.uid
                            maxbet = v.bets[bettype]
                            winScoreProfit = maxbet * self:conf().betarea[bettype][1] -- maxbet
                        end
                    end
                end
                if uid ~= 0 then
                    -- Marquee
                    local notify_marquee_msg = {
                        type = pb.enum_id("network.cmd.PBChatChannelType", "PBChatChannelType_Marquee"),
                        msg = cjson.encode(
                            {
                            code = 1,
                            nickname = self.users[uid].playerinfo and self.users[uid].playerinfo.username or "", -- 玩家昵称
                            betarea = bettype, -- 下注区域标志
                            winScore = winScoreProfit, -- 中奖金额
                            gameId = global.stype() -- 游戏ID  游戏名称
                        }
                        )
                    }
                    Utils:broadcastSysChatMsgToAllUsers(notify_marquee_msg)

                    log.debug("idx(%s,%s) marquee uid=%s,winScoreProfit=%s", self.id, self.mid, uid, winScoreProfit)
                end
            end
        end
    end

    Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_COWBOY_SETTLE"))

    -- ranks
    table.insert(ranks, onlinerank) -- 插入在线玩家信息(非VIP座位)
    log.debug("idx(%s,%s) ranks %s", self.id, self.mid, cjson.encode(ranks))
    log.debug("idx(%s,%s) onlinerank %s", self.id, self.mid, cjson.encode(onlinerank))
    for k, v in pairs(self.users) do
        local rank = {}
        if not v.isdebiting and v.totalbet and v.totalbet > 0 then
            rank = {
                uid = k,
                --rank		= 0,
                --player		= v.seat and v.seat:getSeatInfo().playerinfo,
                totalprofit = v.totalprofit,
                areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
            }
        end
        local t = {
            ranks = g.copy(ranks),
            log = lastlogitem,
            sta = self.betst
        }
        table.insert(t.ranks, rank)
        if v.linkid and v.state == EnumUserState.Playing then
            net.send(
                v.linkid,
                k,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CowboyNotifyFinish"),
                pb.encode("network.cmd.PBCowboyNotifyFinish_N", t)
            )
        end
        log.debug("idx(%s,%s) uid: %s, PBCowboyNotifyFinish_N : %s", self.id, self.mid, k, cjson.encode(t))
    end

    self:checkCheat() -- 2022-1-5

    -- 牌局统计数据上报
    self.sdata.areas = {}
    for _, bettype in ipairs(DEFAULT_BET_TYPE) do
        table.insert(
            self.sdata.areas,
            {
            bettype = bettype,
            betvalue = self.bets[bettype],
            profit = self.profits[bettype]
        }
        )
    end
    self.sdata.stime = self.start_time / 1000
    self.sdata.etime = self.finish_time / 1000
    self.sdata.totalbet = totalbet
    self.sdata.totalprofit = totalprofit

    self.sdata.extrainfo = cjson.encode(
        { playercount = self:getRealPlayerCount(), playerbet = usertotalbet, playerprofit = usertotalprofit }
    )
    if self.hasRealPlayerBet then
        log.debug("DQW hasRealPlayerBet")
        -- 过滤机器人下注信息
        for k, user in pairs(self.users) do -- 遍历该房间所有玩家
            if self.sdata.users and self.sdata.users[k] then
                if Utils:isRobot(user.api) then
                    self.sdata.users[k] = nil
                else
                    if self.sdata.users[k].extrainfo then
                        local extrainfo = cjson.decode(self.sdata.users[k].extrainfo)
                        extrainfo["totalmoney"] = (self:getUserMoney(user.uid) or 0) + (user.totalprofit or 0) -- 总金额
                        log.debug("self.sdata.users[uid].extrainfo uid=%s,totalmoney=%s", user.uid, extrainfo["totalmoney"])
                        self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)
                    end
                end
            end
        end

        self.statistic:appendLogs(self.sdata, self.logid)
    else
        log.debug("DQW has not RealPlayerBet")
    end
    --local curday = global.cdsec()
    --self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet
    --self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit

    Utils:serializeMiniGame(self)

    timer.tick(self.timer, TimerID.TimerID_Finish[1], TimerID.TimerID_Finish[2], onFinish, self)
end

function Room:kickout()
    log.info("Room:kickout()")
    if self.state ~= EnumRoomState.Finish then
        Utils:repay(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_COWBOY_SETTLE"))
    end
    for k, v in pairs(self.users) do
        if self.state ~= EnumRoomState.Finish and v.totalbet and v.totalbet > 0 then
            v.totalbet = 0
        end
        self:userLeave(k, v.linkid)
        if v.TimerID_Timeout then
            timer.destroy(v.TimerID_Timeout)
        end
        if v.TimerID_MutexTo then
            timer.destroy(v.TimerID_MutexTo)
        end
        log.info("idx(%s,%s) kick user:%s state:%s", self.id, self.mid, k, tostring(v.state))
    end
end

function Room:getTotalProfitRate(wintype)
    local totalbets, totalprofit = 0, 0
    local sn = 0
    for k, v in g.pairsByKeys(
        self.total_bets,
        function(arg1, arg2)
        return arg1 > arg2
    end
    ) do
        if sn >= self:conf().profitrate_threshold_maxdays then
            sn = k
            break
        end
        totalbets = totalbets + v
        sn = sn + 1
    end
    self.total_bets[sn] = nil
    sn = 0
    for k, v in g.pairsByKeys(
        self.total_profit,
        function(arg1, arg2)
        return arg1 > arg2
    end
    ) do
        if sn >= self:conf().profitrate_threshold_maxdays then
            sn = k
            break
        end
        totalprofit = totalprofit + v
        sn = sn + 1
    end
    self.total_profit[sn] = nil
    local usertotalbet_inhand, usertotalprofit_inhand = 0, 0
    for _, v in pairs(EnumCowboyType) do
        usertotalbet_inhand = usertotalbet_inhand + (self.userbets[v] or 0)
        if g.isInTable(wintype, v) then
            usertotalprofit_inhand = usertotalprofit_inhand +
                (self.userbets[v] or 0) * (self:conf() and self:conf().betarea and self:conf().betarea[v][1])
        end
    end
    totalbets = totalbets + usertotalbet_inhand
    totalprofit = totalprofit + usertotalprofit_inhand

    local profit_rate = totalbets > 0 and 1 - totalprofit / totalbets or 0
    log.info(
        "idx(%s,%s) total_bets=%s total_profit=%s totalbets=%s,totalprofit=%s,profit_rate=%s usertotalbet_inhand=%s usertotalprofit_inhand=%s",
        self.id,
        self.mid,
        cjson.encode(self.total_bets),
        cjson.encode(self.total_profit),
        totalbets,
        totalprofit,
        profit_rate,
        usertotalbet_inhand,
        usertotalprofit_inhand
    )
    return profit_rate, usertotalbet_inhand, usertotalprofit_inhand
end

function Room:phpMoneyUpdate(uid, rev)
    log.debug("(%s,%s)phpMoneyUpdate %s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user and user.playerinfo then
        local balance =
        self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and rev.money or rev.coin
        user.playerinfo.balance = user.playerinfo.balance + balance
        log.debug("(%s,%s)phpMoneyUpdate %s,%s,%s", self.id, self.mid, uid, tostring(rev.money), tostring(rev.coin))
    end
end

function Room:tools(jdata)
    log.debug("(%s,%s) tools>>>>>>>> %s", self.id, self.mid, jdata)
    local data = cjson.decode(jdata)
    if data then
        log.debug("(%s,%s) handle tools %s", self.id, self.mid, cjson.encode(data))
        if data["api"] == "kickout" then
            self.isStopping = true
        end
    end
end

-- 玩家金额 修改
function Room:userWalletResp(rev)
    if not rev.data or #rev.data == 0 then
        return
    end
    for _, v in ipairs(rev.data) do
        local user = self.users[v.uid]
        if user and not Utils:isRobot(user.api) then
            log.debug("(%s,%s) userWalletResp %s", self.id, self.mid, cjson.encode(rev))
        end
        if v.code >= 0 then
            if user then
                if not Utils:isRobot(user.api) then -- 如果不是机器人
                    user.playerinfo = user.playerinfo or {}
                    if self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
                        user.playerinfo.balance = v.money
                    elseif self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
                        user.playerinfo.balance = v.coin
                    end
                end
            end
            Utils:debitRepay(
                self,
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_COWBOY_SETTLE"),
                v,
                user,
                EnumRoomState.Show
            )
        end
    end
end

-- 获取真实玩家数目
function Room:getRealPlayerCount()
    local realPlayerCount = 0
    for _, user in pairs(self.users) do
        --if user and user.state == EnumUserState.Playing then
        if user then
            if not Utils:isRobot(user.api) then
                if not user.isdebiting and user.totalbet and user.totalbet > 0 then -- 如果该玩家下注了
                    realPlayerCount = realPlayerCount + 1
                end
            end
        end
    end

    return realPlayerCount
end

function Room:userTableInfo(uid, linkid, rev)
    log.debug("idx(%s,%s) user table info req uid:%s", self.id, self.mid, uid)
    if not linkid then -- 2022-3-11
        return
    end

    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(),
        idx = {
            srvid = global.sid(),
            roomid = self.id,
            matchid = self.mid
        },
        data = {
            state = self.state,
            lefttime = 0,
            roundid = self.roundid,
            --jackpot = JackPot,
            player = {},
            seats = {},
            logs = {},
            sta = self.betst,
            betdata = {
                uid = uid,
                usertotal = 0,
                areabet = {}
            },
            cowboy = { cards = {}, type = 0 },
            bull = { cards = {}, type = 0 },
            pub = { cards = {}, type = 0 },
            configchips = self:conf().chips,
            onlinenum = Utils:getVirtualPlayerCount(self), -- #self.onlinelst,
            odds = {},
            bestFive = { cards = {}, type = 0 }
        }
    }

    for _, v in ipairs(self:conf().betarea) do
        table.insert(t.data.odds, v[1])
    end

    local dstCards = { t.data.cowboy, t.data.bull, t.data.pub, t.data.bestFive }
    if self.sdata and self.sdata.cards then
        for i = 1, #dstCards do
            dstCards[i].type = self.sdata.cardstype[i]
            if self.sdata.cards[i] then
                self.sdata.cards[i].cards = self.sdata.cards[i].cards or {}
                for _, v in ipairs(self.sdata.cards[i].cards) do
                    table.insert(
                        dstCards[i].cards,
                        {
                        color = self.poker:cardColor(v),
                        count = self.poker:cardValue(v)
                    }
                    )
                end
            end
        end
    end

    -- 填写返回数据
    if self.state == EnumRoomState.Start then
        t.data.lefttime = TimerID.TimerID_Start[2] - (global.ctms() - self.start_time)
    elseif self.state == EnumRoomState.Betting then
        t.data.lefttime = TimerID.TimerID_Betting[2] - (global.ctms() - self.betting_time)
    elseif self.state == EnumRoomState.Show then
        t.data.lefttime = TimerID.TimerID_Show[2] - (global.ctms() - self.show_time) + TimerID.TimerID_Finish[2]
    elseif self.state == EnumRoomState.Finish then
        t.data.lefttime = TimerID.TimerID_Finish[2] - (global.ctms() - self.finish_time) + self.bigcard_show_time_delta
    end
    t.data.lefttime = t.data.lefttime > 0 and t.data.lefttime or 0

    -- 拷贝玩家信息
    -- t.data.player = user.playerinfo
    local user = self.users[uid]
    if user and user.playerinfo then
        user.playerinfo = user.playerinfo or {}
        t.data.player.uid = uid -- 玩家UID
        t.data.player.nickname = user.playerinfo.nickname or "" -- 昵称
        t.data.player.username = user.playerinfo.username or ""
        t.data.player.viplv = user.playerinfo.viplv or 0
        t.data.player.nickurl = user.playerinfo.nickurl or ""
        t.data.player.gender = user.playerinfo.gender
        t.data.player.balance = user.playerinfo.balance
        t.data.player.currency = user.playerinfo.currency
        t.data.player.extra = user.playerinfo.extra or {}

        t.data.seats = g.copy(self.vtable:getSeatsInfo())
        if self.logmgr:size() <= self:conf().maxlogshowsize then
            t.data.logs = self.logmgr:getLogs()
        else
            g.move(
                self.logmgr:getLogs(),
                self.logmgr:size() - self:conf().maxlogshowsize + 1,
                self.logmgr:size(),
                1,
                t.data.logs
            )
        end

        t.data.betdata.uid = uid
        t.data.betdata.usertotal = user.totalbet or 0
        for k, v in pairs(self.bets) do
            if v ~= 0 then
                table.insert(
                    t.data.betdata.areabet,
                    {
                    bettype = k,
                    betvalue = 0,
                    userareatotal = user.bets and user.bets[k] or 0,
                    areatotal = v
                    --odds			= self:conf() and self:conf().betarea and self:conf().betarea[k][1],
                }
                )
            end
        end
    end

    local resp = pb.encode("network.cmd.PBIntoCowboyRoomResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoCowboyRoomResp"),
            pb.encode("network.cmd.PBIntoCowboyRoomResp_S", t)
        )
    end
end

-- 2021-12-16
-- 根据牌数据及各玩家的下注情况计算真实玩家输赢金额   总是系统坐庄
-- 参数 cardsBoy:  牛娃的牌2张
-- 参数 cardsBull: 公牛的牌2张
-- 参数 cardsPub: 公共牌5张
-- 返回值: 返回真实玩家赢取到的金额
function Room:GetRealPlayerWin(cardsBoy, cardsBull, cardsPub)
    -- self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区下注累计值
    -- self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有非机器人在每个下注区下注累计值

    -- 根据牌数据计算各下注区的输赢情况
    local pokertypeBoy = self.poker:getPokersType(cardsBoy, cardsPub) -- 获取牌型
    local pokertypeBull = self.poker:getPokersType(cardsBull, cardsPub)
    local winTypes, winPokerType, besthands = self.poker:getWinTypes(cardsBoy, cardsBull, cardsPub)
    --根据盈利率触发胜负策略
    local usertotalbet = 0 -- 在所有下注区的下注金额
    for k, v in pairs(EnumCowboyType) do -- 遍历所有下注区
        usertotalbet = usertotalbet + (self.userbets[v] or 0)
    end

    local winMoney = 0 -- 真实玩家赢取到的总金额
    for _, type in pairs(winTypes) do -- 遍历所有赢的区域
        if type and self.userbets[type] > 0 then -- 如果在该下注区下注了
            if self:conf() and self:conf().betarea and self:conf().betarea[type][1] then
                winMoney = winMoney + self.userbets[type] * self:conf().betarea[type][1]
            end
        end
    end
    winMoney = winMoney - usertotalbet
    return winMoney -- 返回真实玩家总的输赢情况
end

function Room:destroy()
    self:kickout()
    -- 销毁定时器
    timer.destroy(self.timer)
end

-- 计算每个玩家的注码量  2021-12-24
function Room:calcPlayChips()
    --[[
    胜平负游戏注码量 = 
    (1)胜平负盘口投注总量 - 胜盘口投注量*胜盘口赔率 + 其它盘口投注总量
    (2)胜平负盘口投注总量 - 平盘口投注量*胜盘口赔率 + 其它盘口投注总量
    (3)胜平负盘口投注总量 - 负盘口投注量*胜盘口赔率 + 其它盘口投注总量
    --]]
    for _, user in pairs(self.users) do -- 遍历每个玩家
        local totalBet = 0 -- 胜平负盘口投注总量+其它盘口投注总量
        local maxChips = nil
        if not Utils:isRobot(user.api) then
            for k, v in pairs(EnumCowboyType) do -- 遍历每个下注区
                if user.bets and user.bets[v] then
                    totalBet = totalBet + user.bets[v]
                end
            end

            if totalBet > 0 then -- 如果该玩家下注了
                for k, v in pairs(EnumCowboyType) do -- 遍历每个下注区
                    if v and v <= EnumCowboyType.EnumCowboyType_Draw then
                        if user.bets[v] == 0 then
                            maxChips = totalBet
                            break
                        else
                            local value =
                            totalBet -
                                user.bets[v] * (self:conf() and self:conf().betarea and self:conf().betarea[v][1] or 0)
                            if (not maxChips) or (maxChips < value) then
                                maxChips = value
                            end
                        end
                    end
                end
                user.playchips = maxChips
            else
                user.playchips = 0
            end
        end
    end
end

function Room:checkCheat()
    self.sdata.users = self.sdata.users or {}
    local uid_list = {}
    for _, user in pairs(self.users) do
        -- 判断是否在胜负区域下注了
        if user and not user.isdebiting and user.totalbet and user.totalbet > 0 then
            self.sdata.users[user.uid] = self.sdata.users[user.uid] or {}
            if not Utils:isRobot(user.api) then -- 如果不是机器人
                local extrainfo = cjson.decode(self.sdata.users[user.uid].extrainfo)
                extrainfo["cheat"] = false
                self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)
                if user.bets and
                    (user.bets[EnumCowboyType.EnumCowboyType_Cowboy] > 0 or
                        user.bets[EnumCowboyType.EnumCowboyType_Bull] > 0)
                then --
                    table.insert(uid_list, user.uid)
                end
            end
        end
    end

    local ipList = {}
    for idx = 1, #uid_list, 1 do
        local user = self.users[uid_list[idx]]
        -- 判断user.ip是否在ipList列表中
        local inTable = false
        for i = 1, #ipList do
            if ipList[i] == user.ip then
                inTable = true
                break
            end
        end
        if not inTable then
            local totalBetA = user.bets[EnumCowboyType.EnumCowboyType_Cowboy] or 0
            local totalBetB = user.bets[EnumCowboyType.EnumCowboyType_Bull] or 0
            local hasCheat = false -- 默认没有作弊
            for idx2 = idx + 1, #uid_list, 1 do
                local user2 = self.users[uid_list[idx2]]
                if user and user2 and user.ip == user2.ip then
                    -- 投注游戏每局投注的所有玩家中IP相同的玩家按照ip分组，每组玩家中既有投胜也有投负的时，改组所有玩家进行标记
                    -- 增加条件：胜负区域分别累加总和   总和少的区域/总和多的区域 >= 50%
                    totalBetA = totalBetA + (user2.bets[EnumCowboyType.EnumCowboyType_Cowboy] or 0)
                    totalBetB = totalBetB + (user2.bets[EnumCowboyType.EnumCowboyType_Bull] or 0)
                end
            end
            ipList[#ipList] = user.ip
            if totalBetA <= totalBetB then
                if totalBetA * 2 >= totalBetB then
                    hasCheat = true
                end
            else
                if totalBetB * 2 >= totalBetA then
                    hasCheat = true
                end
            end

            if hasCheat then
                for idx2 = idx + 1, #uid_list, 1 do
                    local user2 = self.users[uid_list[idx2]]
                    if user and user2 and user.ip == user2.ip then
                        log.debug(
                            "ip=%s, uid=%s, uid2=%s",
                            tostring(user.ip),
                            tostring(uid_list[idx]),
                            tostring(uid_list[idx2])
                        )
                        local extrainfo = cjson.decode(self.sdata.users[user.uid].extrainfo)
                        extrainfo["cheat"] = true
                        self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)

                        extrainfo = cjson.decode(self.sdata.users[user2.uid].extrainfo)
                        extrainfo["cheat"] = true
                        self.sdata.users[user2.uid].extrainfo = cjson.encode(extrainfo)
                    end
                end
            end
        end
    end
end

-- 创建机器人结果
-- 参数 robotsInfo: 机器人信息
function Room:createRobotResult(robotsInfo)
    if not robotsInfo then
        return
    end
    log.debug("createRobotResult(.) robotsInfo=%s", cjson.encode(robotsInfo))
    for _, robot in ipairs(robotsInfo) do
        log.debug("robotInfo: uid=%s, api=%s, name=%s, nickurl=%s", robot.uid, robot.api, robot.name, robot.nickurl)
    end
    Utils:addRobot(self, robotsInfo) -- 增加机器人
end


