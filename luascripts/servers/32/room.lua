local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local rand = require(CLIBS["c_rand"])
local global = require(CLIBS["c_global"])
local mutex = require(CLIBS["c_mutex"])
local cjson = require("cjson")
local redis = require(CLIBS["c_hiredis"])
local utils = require(CLIBS["c_utils"])
local g = require("luascripts/common/g")
require("luascripts/servers/32/dragontiger")
require("luascripts/servers/32/seat")
require("luascripts/servers/32/vtable")
require("luascripts/servers/common/statistic")

cjson.encode_invalid_numbers(true)

--increment
Room = Room or { uniqueid = 0 }
local EnumDragonTigerType = {
    --胜平负
    EnumDragonTigerType_Dragon = 1,
    EnumDragonTigerType_Tiger = 2,
    EnumDragonTigerType_Draw = 3
}
local DEFAULT_BET_TABLE = {
    --胜平负
    [EnumDragonTigerType.EnumDragonTigerType_Dragon] = 0,
    [EnumDragonTigerType.EnumDragonTigerType_Tiger] = 0,
    [EnumDragonTigerType.EnumDragonTigerType_Draw] = 0
}
local DEFAULT_BET_TYPE = {
    EnumDragonTigerType.EnumDragonTigerType_Dragon,
    EnumDragonTigerType.EnumDragonTigerType_Tiger,
    EnumDragonTigerType.EnumDragonTigerType_Draw
}
local DEFAULT_BETST_TABLE = {
    --胜平负
    [EnumDragonTigerType.EnumDragonTigerType_Dragon] = {
        type = EnumDragonTigerType.EnumDragonTigerType_Dragon,
        hitcount = 0,
        lasthit = 0
    },
    [EnumDragonTigerType.EnumDragonTigerType_Tiger] = {
        type = EnumDragonTigerType.EnumDragonTigerType_Tiger,
        hitcount = 0,
        lasthit = 0
    },
    [EnumDragonTigerType.EnumDragonTigerType_Draw] = {
        type = EnumDragonTigerType.EnumDragonTigerType_Draw,
        hitcount = 0,
        lasthit = 0
    }
}

local TimerID = {
    -- 游戏阶段
    TimerID_Check = { 1, 100 }, --id, interval(ms), timestamp(ms)
    TimerID_Start = { 2, 6 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Betting = { 3, 15 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Show = { 4, 7 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Finish = { 5, 4 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_NotifyBet = { 6, 200, 0 }, --id, interval(ms), timestamp(ms)
    -- 协程
    TimerID_Timeout = { 7, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = { 8, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Result = { 9, 3 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Robot = { 10, 200, 0 } --id, interval(ms), timestamp(ms)
}

local EnumRoomState = {
    Check = 1,
    Start = 2,
    Betting = 3,
    Show = 4,
    Finish = 5
}

local EnumUserState = {
    Intoing = 1,
    Playing = 2,
    Logout = 3,
    Leave = 4
}

function Room:conf()
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
    self.user_count = 0

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
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有真实玩家在每个下注区下注累计值
    self.robotbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有AI在每个下注区下注累计值
    self.betst = {} -- 下注统计
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端, 元素类型为 PBDragonTigerBetData
    self.logmgr = LogMgr:new(
        self:conf() and self:conf().maxlogsavedsize,
        tostring(global.sid()) .. tostring("_") .. tostring(self.id)
    ) -- 历史记录
    self:calBetST()
    --self.lastclaerlogstime		= nil				-- 上次清历史数据时间，UTC 时间
    --self.forceclientclearlogs	= false					-- 是否强制客户端清除历史
    self.onlinelst = {} -- 在线列表
    self.sdata = { roomtype = (self:conf() and self:conf().roomtype) } -- 统计数据
    self.vtable = VTable:new({ id = 1 })

    self.poker = DragonTiger:new() --每个房间一副牌
    self.statistic = Statistic:new(self.id, self:conf().mid)
    self.bankmgr = BankMgr:new()
    self.total_bets = {}
    self.total_profit = {}
    self.robottotal_bets = {}
    self.robottotal_profit = {}
    Utils:unSerializeMiniGame(self)
    --self.betmgr = BetMgr:new(o.id, o.mid)
    --self.keepsession = KeepSessionAlive:new(o.users, o.id, o.mid)

    self.update_games = 0 -- 更新经过的局数
    self.rand_player_num = 1
    self.realPlayerUID = 0

    self.lastCreateRobotTime = 0 -- 上次创建机器人时刻
    self.createRobotTimeInterval = 5 -- 定时器时间间隔(秒)
    self.lastRemoveRobotTime = 0 -- 上次移除机器人时刻(秒)
end

function Room:roundReset()
    -- 牌局相关
    self.update_games = self.update_games + 1
    self.start_time = global.ctms()
    self.betting_time = global.ctms()
    self.show_time = global.ctms()
    self.finish_time = global.ctms()
    self.round_start_time = 0

    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有真实玩家在每个下注区下注累计值
    self.robotbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有AI在每个下注区下注累计值
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端
    self.sdata = { roomtype = (self:conf() and self:conf().roomtype) } -- 清空统计数据

    -- 记录每日北京时间中午 12 时（UTC 时间早上 4 时）清空一次
    --local currentime = os.date("!*t")
    --if currentime.hour == 4 and
    --( not self.lastclaerlogstime or currentime.day ~= self.lastclaerlogstime.day ) then
    --self.logs = {}
    --self.lastclaerlogstime		= os.date("!*t")
    --self.forceclientclearlogs	= true
    --log.info("[idx:%s] clear log", self.id)
    --end

    -- 用户数据
    for k, v in pairs(self.users) do
        v.bets = g.copy(DEFAULT_BET_TABLE)
        v.totalbet = 0
        v.profit = 0
        v.totalprofit = 0
        v.isbettimeout = false
    end
end

function Room:broadcastCmd(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.linkid then
            net.send(v.linkid, k, maincmd, subcmd, msg)
        end
    end
end

function Room:broadcastCmdToPlayingUsers(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and v.linkid then
            net.send(v.linkid, k, maincmd, subcmd, msg)
        end
    end
end

function Room:sendCmdToPlayingUsers(maincmd, subcmd, msg, msglen)
    self.links = self.links or {}
    if not self.user_cached then
        self.links = {}
        local linkidstr = nil
        for k, v in pairs(self.users) do
            if v.state == EnumUserState.Playing and v.linkid then
                linkidstr = tostring(v.linkid)
                self.links[linkidstr] = self.links[linkidstr] or {}
                table.insert(self.links[linkidstr], k)
            end
        end
        self.user_cached = true
        --log.info("[idx:%s] is not cached %s", self.id, cjson.encode(self.links))
    end
    net.send_users(cjson.encode(self.links), maincmd, subcmd, msg, msglen)
end

function Room:count(uid)
    local ret = self:recount(uid)
    if ret and self:conf() and self:conf().single_profit_switch then
        return self.user_count - 1, self.robot_count
    else
        return self.user_count, self.robot_count
    end
end

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

function Room:clearUsersBySrvId(srvid)
    for k, v in pairs(self.users) do
        if v.linkid == srvid then
            self:logout(k)
        end
    end
end

function Room:logout(uid)
    local user = self.users[uid]
    if user then
        user.state = EnumUserState.Logout
        self.user_cached = false
        log.info("idx(%s,%s) %s room logout %s", self.id, self.mid, uid, self.user_count)
    end
end

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
            log.info("idx(%s,%s) PBGameUpdateSeats_N : %s", self.id, self.mid, cjson.encode(t))
        end
        )
    end
end

function Room:getUserMoney(uid)
    local user = self.users[uid]
    --print('getUserMoney roomtype', self:conf().roomtype, 'money', 'coin', user.coin)
    return user and (user.playerinfo and user.playerinfo.balance or 0) or 0
end

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
        log.info(
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
        log.info("idx(%s,%s) query userinfo:%s ok:%s", self.id, self.mid, tostring(uid), tostring(ok))
        coroutine.resume(user.co, ok, ud)
    end
end

function Room:userMutexCheck(uid, code)
    local user = self.users[uid]
    if user then
        timer.cancel(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1])
        log.info("idx(%s,%s) mutex check:%s code:%s", self.id, self.mid, tostring(uid), tostring(code))
        coroutine.resume(user.mutex, code > 0)
    end
end

function Room:userLeave(uid, linkid)
    if not linkid then
        return
    end
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
    }
    log.info("idx(%s,%s) userLeave:%s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user == nil then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
        local resp = pb.encode("network.cmd.PBLeaveGameRoomResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
        return
    end

    if user.state == EnumUserState.Leave then
        log.info("idx(%s,%s) has leaveed:%s", self.id, self.mid, uid)
        return
    end

    if self.bankmgr:banker() == uid then
        log.info("idx(%s,%s) is on bank:%s", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed")
    end
    --if user.totalbet and user.totalbet > 0 then
    --	log.info("[idx:%s] user:%s betted not allowed to leave", self.id, uid)
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
        net.shared(
            linkid,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
            pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
            synto
        )
        return
    end
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
        resp
    )
    log.info("idx(%s,%s) userLeave:%s,%s", self.id, self.mid, uid, t.code)
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
            player = {},
            seats = {},
            logs = {},
            sta = self.betst,
            betdata = {
                uid = uid,
                usertotal = 0,
                areabet = {}
            },
            dragon = {
                color = self.poker:cardColor(self.sdata.cards and self.sdata.cards[1].cards[1] or 0),
                count = self.poker:cardValue(self.sdata.cards and self.sdata.cards[1].cards[1] or 0)
            },
            tiger = {
                color = self.poker:cardColor(self.sdata.cards and self.sdata.cards[2].cards[1] or 0),
                count = self.poker:cardValue(self.sdata.cards and self.sdata.cards[2].cards[1] or 0)
            },
            bank = self:getBankerInfo(),
            configchips = self:conf().chips,
            odds = {},
            playerCount = Utils:getVirtualPlayerCount(self)
        }
    }

    if self.isStopping then
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
        t.data = nil
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
        )
        return
    end

    for _, v in ipairs(self:conf().betarea) do
        table.insert(t.data.odds, v[1])
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
                if user.TimerID_MutexTo then
                    timer.destroy(user.TimerID_MutexTo)
                end
                if user.TimerID_Timeout then
                    timer.destroy(user.TimerID_Timeout)
                end
                --timer.destroy(user.TimerID_UserBet)
                self.users[uid] = nil
                t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
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
                t.data.lefttime = TimerID.TimerID_Show[2] - (global.ctms() - self.show_time) + TimerID.TimerID_Finish[2]
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

            local resp = pb.encode("network.cmd.PBIntoDragonTigerRoomResp_S", t)
            local to = {
                uid = uid,
                srvid = global.sid(),
                roomid = self.id,
                matchid = self.mid,
                maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoDragonTigerRoomResp"),
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
    --庄家余额
    local banker_money =
    self.users[self.bankmgr:banker()] and self.users[self.bankmgr:banker()].playerinfo.balance or
        self:conf().init_banker_money
    local betype_bets = 0

    -- 非法玩家
    if not user then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidUser")
        ok = false
        goto labelnotok
    end
    -- 庄家不允许下注
    if uid == self.bankmgr:banker() then
        log.info("idx(%s,%s) user %s is not is banker", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_IsBanker")
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
                user_bets[v.bettype] = user_bets[v.bettype] + v.betvalue
                user_totalbet = user_totalbet + v.betvalue
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
    -- 如果玩家上庄，需要判定庄家余额是否Cover此下注
    if banker_money and banker_money > 0 then
        betype_bets = self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw] +
            user_bets[EnumDragonTigerType.EnumDragonTigerType_Draw]
        if betype_bets * (self:conf().betarea[EnumDragonTigerType.EnumDragonTigerType_Draw][1] - 1) >
            banker_money + self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] +
            self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger]
        then
            log.info("idx(%s,%s) user %s, draw bets over user's balance", self.id, self.mid, uid)
            t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverLimits")
            ok = false
            goto labelnotok
        end
        betype_bets = self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] +
            user_bets[EnumDragonTigerType.EnumDragonTigerType_Dragon]
        if betype_bets * (self:conf().betarea[EnumDragonTigerType.EnumDragonTigerType_Dragon][1] - 1) >
            banker_money + self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw] +
            self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger]
        then
            log.info("idx(%s,%s) user %s, dragon bets over user's balance", self.id, self.mid, uid)
            t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverLimits")
            ok = false
            goto labelnotok
        end
        betype_bets = self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] +
            user_bets[EnumDragonTigerType.EnumDragonTigerType_Tiger]
        if betype_bets * (self:conf().betarea[EnumDragonTigerType.EnumDragonTigerType_Tiger][1] - 1) >
            banker_money + self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw] +
            self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon]
        then
            log.info("idx(%s,%s) user %s, tiger bets over user's balance", self.id, self.mid, uid)
            t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverLimits")
            ok = false
            goto labelnotok
        end
    end

    ::labelnotok::
    log.info(
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
        local resp = pb.encode("network.cmd.PBDragonTigerBetResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerBetResp"),
                resp
            )
        end
        log.info("idx(%s,%s) user %s, PBDragonTigerBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    --扣费
    user.playerinfo = user.playerinfo or {}
    if user.playerinfo.balance and user.playerinfo.balance > user_totalbet then
        user.playerinfo.balance = user.playerinfo.balance - user_totalbet
    else
        user.playerinfo.balance = 0
    end
    if not self:conf().isib then
        if linkid then
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                -user_totalbet,
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_DRAGONTIGER_BET"),
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
            self.bets[k] = self.bets[k] + v

            if not Utils:isRobot(user.api) then
                self.userbets[k] = self.userbets[k] + v
                self.realPlayerUID = uid
            elseif self.bankmgr:banker() > 0 then
                self.robotbets[k] = self.robotbets[k] + v
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
    local resp = pb.encode("network.cmd.PBDragonTigerBetResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerBetResp"),
            resp
        )
    end
    log.info("idx(%s,%s) user %s, PBDragonTigerBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
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
        local resp = pb.encode("network.cmd.PBDragonTigerHistoryResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerHistoryResp"),
            resp
        )
        log.info("idx(%s,%s) user %s, PBDragonTigerHistoryResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
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

    local resp = pb.encode("network.cmd.PBDragonTigerHistoryResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerHistoryResp"),
        resp
    )
    log.info(
        "idx(%s,%s) user %s, PBDragonTigerHistoryResp_S: %s, logmgr:size: %s",
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
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    if not ok then
        local resp = pb.encode("network.cmd.PBDragonTigerOnlineListResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerOnlineListResp"),
            resp
        )
        log.info("idx(%s,%s) user %s, PBDragonTigerOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    -- 返回前 300 条
    g.move(self.onlinelst, 1, math.min(300, #self.onlinelst), 1, t.list)
    -- 返回前 300 条
    local resp = pb.encode("network.cmd.PBDragonTigerOnlineListResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerOnlineListResp"),
        resp
    )
    log.info("idx(%s,%s) user %s, PBDragonTigerOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

function Room:getBankerInfo()
    local res = {
        onbank_minimoney = self:conf().min_onbank_moneycnt,
        successive_cnt = self.bankmgr:successiveCnt(),
        banklist_size = self.bankmgr:count(),
        is_going_down = self.bankmgr:isGoingDown(),
        successive_max_cnt = self:conf().max_bank_successive_cnt,
        onbank_max_cnt = self:conf().max_bank_list_size
    }
    local u = self.users[self.bankmgr:banker()]
    if u then
        res.banker = {
            uid = u.uid,
            nickurl = u.playerinfo.nickurl,
            nickname = u.playerinfo.username,
            balance = u.playerinfo.balance
        }
    end
    return res
end

function Room:userBankOpReq(uid, linkid, rev)
    if not linkid then
        return
    end
    local t = { op = rev.op, code = 0, list = {} }
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
        t.code = pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Failed")
        local resp = pb.encode("network.cmd.PBGameOpBank_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameOpBankResp"),
            resp
        )
        log.info("idx(%s,%s) user %s, PBGameOpBank_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    local function f_on_bank_req()
        if self.bankmgr:count() > self:conf().max_bank_list_size then
            t.code = pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_OverListSize")
            return
        end

        if user.playerinfo.balance < self:conf().min_onbank_moneycnt then
            t.code = pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_NotEnoughMoney")
            return
        end

        t.code = self.bankmgr:add(uid)
    end

    local function f_cancel_bank_req()
        t.code = self.bankmgr:remove(uid) and pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Success") or
            pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Failed")
    end

    local function f_out_bank_req()
        t.code = self.bankmgr:down(uid) and pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Success") or
            pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Failed")
    end

    local function f_list_bank_req()
        local uidlist = self.bankmgr:getBankList()
        for _, v in ipairs(uidlist) do
            local u = self.users[v]
            if u and u.playerinfo then
                table.insert(
                    t.list,
                    {
                    uid = u.uid,
                    nickurl = u.playerinfo.nickurl,
                    nickname = u.playerinfo.username,
                    balance = u.playerinfo.balance
                }
                )
            end
        end
    end

    local switch = {
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_OnBank")] = f_on_bank_req,
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_CancelBank")] = f_cancel_bank_req,
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_OutBank")] = f_out_bank_req,
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_BankList")] = f_list_bank_req
    }

    local callback_fn = switch[rev.op]
    if not callback_fn then
        log.info("idx(%s,%s) it's not valid optype uid:%s type:%s", self.id, self.mid, uid, rev.op)
        return false
    end

    callback_fn()

    local resp = pb.encode("network.cmd.PBGameOpBank_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameOpBankResp"),
        resp
    )
    if rev.op == pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_OnBank") or
        rev.op == pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_CancelBank")
    then
        if t.code == 0 then
            pb.encode(
                "network.cmd.PBGameNotifyOnBankCnt_N",
                { cnt = self.bankmgr:count() },
                function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyOnBankCnt"),
                    pointer,
                    length
                )
            end
            )
        end
    end

    log.info("idx(%s,%s) user %s, PBGameOpBank_S: %s", self.id, self.mid, uid, cjson.encode(t))
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
                    "network.cmd.PBDragonTigerNotifyBettingInfo_N",
                    t,
                    function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerNotifyBettingInfo"),
                        pointer,
                        length
                    )
                    --log.info("idx(%s,%s) PBDragonTigerNotifyBettingInfo_N : %s %s", self.id, #t.bets, cjson.encode(t))
                end
                )
            end
            --log.info("idx:%s notifybet", self.id)
        end
    end

    g.call(doRun)
end

function Room:notifybet()
    log.info("idx(%s,%s) notifybet room game:%s", self.id, self.mid, self.state)
    timer.tick(self.timer, TimerID.TimerID_NotifyBet[1], TimerID.TimerID_NotifyBet[2], onNotifyBet, self)
end

-- 定时检测创建机器人
local function onCreateRobot(self)
    local function doRun()
        local current_time = global.ctsec() -- 当前时刻(秒)
        local currentTimeMS = global.ctms() -- 当前时刻(毫秒)
        Utils:checkCreateRobot(self, current_time) -- 检测创建机器人

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
                    if user and not user.linkid then
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
        timer.cancel(self.timer, TimerID.TimerID_Check[1])
        if self.isStopping then
            Utils:onStopServer(self)
            return
        end
        self:start()
    end

    g.call(doRun)
end

function Room:check()
    log.info("idx(%s,%s) check game state - %s %s", self.id, self.mid, self.state, tostring(global.stopping()))
    if global.stopping() then
        local banker = self.users[self.bankmgr:banker()]
        if banker then
            log.info("idx(%s,%s) is on bank kickout:%s", self.id, self.mid, self.mid, banker.uid)
            self.bankmgr:checkSwitch(0, false, false)
            self:userLeave(banker.uid, banker.linkid)
        end
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

    local old_onbankcnt = self.bankmgr:count()
    local banker_money =
    self.bankmgr:banker() > 0 and self:getUserMoney(self.bankmgr:banker()) or self:conf().min_outbank_moneycnt
    self.bankmgr:checkSwitch(
        self:conf().max_bank_successive_cnt,
        self.users[self.bankmgr:banker()] and true or false,
        banker_money >= self:conf().min_outbank_moneycnt and true or false
    )

    if old_onbankcnt ~= self.bankmgr:count() then
        pb.encode(
            "network.cmd.PBGameNotifyOnBankCnt_N",
            { cnt = self.bankmgr:count() },
            function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyOnBankCnt"),
                pointer,
                length
            )
        end
        )
    end

    local t = {
        t = TimerID.TimerID_Start[2],
        roundid = self.roundid,
        --[[needclearlog = self.forceclientclearlogs ]]
        bank = self:getBankerInfo(),
        playerCount = Utils:getVirtualPlayerCount(self)
    }

    pb.encode(
        "network.cmd.PBDragonTigerNotifyStart_N",
        t,
        function(pointer, length)
        self:sendCmdToPlayingUsers(
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerNotifyStart"),
            pointer,
            length
        )
    end
    )
    timer.tick(self.timer, TimerID.TimerID_Start[1], TimerID.TimerID_Start[2], onStart, self)

    log.info(
        "idx(%s,%s) start room game, state %s roundid %s logid %s",
        self.id,
        self.mid,
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
        "network.cmd.PBDragonTigerNotifyBet_N",
        { t = TimerID.TimerID_Betting[2] },
        function(pointer, length)
        self:sendCmdToPlayingUsers(
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerNotifyBet"),
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
    self.betst = g.copy(DEFAULT_BETST_TABLE)
    for _, v in ipairs(self.logmgr:getLogs()) do
        for _, bt in ipairs(DEFAULT_BET_TYPE) do
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
        Utils:debit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_DRAGONTIGER_BET"))
        Utils:balance(self, EnumUserState.Playing)
        for uid, user in pairs(self.users) do
            if user and Utils:isRobot(user.api) then
                user.isdebiting = false
            end
        end
    end

    self:calcPlayChips()

    -- 生成牌，计算牌型
    self.poker:reset()
    local cards = self.poker:getNCard(2) -- dragon tiger
    local dragon = cards[1]
    local tiger = cards[2]
    local wintype = self.poker:getWinType(dragon, tiger)
    local profit_rate, usertotalbet_inhand, usertotalprofit_inhand = 0, 0, 0
    --根据盈利率触发胜负策略
    local usertotalbet, robottotalbet = 0, 0
    for k, v in pairs(EnumDragonTigerType) do
        usertotalbet = usertotalbet + (self.userbets[v] or 0) -- 玩家下注总金额
        robottotalbet = robottotalbet + (self.robotbets[v] or 0)
    end

    local needSendResult = true
    -- 下面是根据盈利率控制输赢
    if self:conf().global_profit_switch then
        if self.bankmgr:banker() == 0 and usertotalbet > 0 then
            profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(wintype)
            local rnd = rand.rand_between(1, 10000)
            if profit_rate < self:conf().profitrate_threshold_lowerlimit then
                log.info("idx(%s,%s) tigh mode is trigger", self.id, self.mid)
                -- 真实玩家该局总收益
                local realPlayerWin = self:GetRealPlayerWin(true, dragon, tiger) -- 真实玩家赢取到的金额
                if realPlayerWin > 10000 then
                    if profit_rate < self:conf().profitrate_threshold_minilimit or rnd <= 5000 then
                        -- 确保系统赢，换牌系统不一定赢(待优化)
                        for i = 0, 3, 1 do
                            -- 生成牌，计算牌型
                            self.poker:reset()
                            cards = self.poker:getNCard(2) -- dragon tiger
                            dragon = cards[1]
                            tiger = cards[2]
                            realPlayerWin = self:GetRealPlayerWin(true, dragon, tiger) -- 真实玩家赢取到的金额
                            if realPlayerWin <= 0 then
                                break
                            end
                        end

                        log.info("idx(%s,%s) swap cards is trigger", self.id, self.mid)
                        wintype = self.poker:getWinType(dragon, tiger)
                        profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(wintype)
                    end
                end
            end
            local curday = global.cdsec()
            self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet_inhand
            self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit_inhand
        elseif self.bankmgr:banker() > 0 and robottotalbet > 0 then
            local rnd = rand.rand_between(1, 10000)
            profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getRobotTotalProfitRate(wintype)
            if profit_rate < self:conf().banker_profitrate_threshold_lowerlimit then
                log.info("idx(%s,%s) banker tigh mode is trigger", self.id, self.mid)
                local realPlayerWin = self:GetRealPlayerWin(false, dragon, tiger) -- 真实玩家赢取到的金额
                if realPlayerWin > 10000 then -- 系统输超过10000时才控制玩家输赢
                    if profit_rate < self:conf().banker_profitrate_threshold_minilimit or rnd <= 5000 then
                        -- 确保系统赢，换牌系统不一定赢，所以需要重新发牌
                        for i = 0, 10, 1 do
                            -- 生成牌，计算牌型
                            self.poker:reset()
                            cards = self.poker:getNCard(2) -- dragon tiger
                            dragon = cards[1]
                            tiger = cards[2]
                            realPlayerWin = self:GetRealPlayerWin(false, dragon, tiger) -- 真实玩家赢取到的金额
                            if realPlayerWin <= 0 then
                                break
                            end
                        end

                        log.info("idx(%s,%s) banker swap cards is trigger", self.id, self.mid)
                        wintype = self.poker:getWinType(dragon, tiger)
                        profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(wintype)
                    end
                end
            end
            local curday = global.cdsec()
            self.robottotal_bets[curday] = (self.robottotal_bets[curday] or 0) + usertotalbet_inhand
            self.robottotal_profit[curday] = (self.robottotal_profit[curday] or 0) + usertotalprofit_inhand
        end
        local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {} }
        for k, v in pairs(self.users) do
            if not Utils:isRobot(v.api) then
                table.insert(msg.data, { uid = k, chips = v.playchips or 0, betchips = v.totalbet or 0 })
            end
        end
        if #msg.data > 0 then
            Utils:queryProfitResult(msg)
        end
    end

    if self:conf().single_profit_switch then -- 单人控制
        local bankerIsSystem = true
        local bankerUID = self.bankmgr:banker() or 0
        local user = self.users[bankerUID]

        if bankerUID == 0 then
            bankerIsSystem = true
        elseif user and not Utils:isRobot(user.api) then
            bankerIsSystem = false
            self.realPlayerUID = bankerUID
        end

        local needControl = false
        if bankerIsSystem then --如果是系统或机器人坐庄
            if usertotalbet > 0 then
                needControl = true
            end
        else -- 真实玩家坐庄
            if robottotalbet > 0 then
                needControl = true
            end
        end

        if needControl then
            needSendResult = false
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
                        if uid and uid == self.realPlayerUID and r then
                            local user = self.users[uid]
                            if user then
                                user.maxwin = r * maxwin
                            end
                            log.debug("uid=%s, r=%s, maxwin=%s", uid, tostring(r), tostring(maxwin))
                            for i = 0, 10, 1 do
                                -- 根据牌数据计算真实玩家的输赢值
                                local realPlayerWin = self:GetRealPlayerWin(bankerIsSystem, dragon, tiger)
                                log.debug(
                                    "idx(%s,%s) redeal  i=%s, realPlayerWin=%s, dragon=%s,tiger=%s",
                                    self.id,
                                    self.mid,
                                    tostring(i),
                                    tostring(realPlayerWin),
                                    dragon,
                                    tiger
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
                                cards = self.poker:getNCard(2) -- dragon tiger
                                dragon = cards[1]
                                tiger = cards[2]
                                wintype = self.poker:getWinType(dragon, tiger)
                            end -- for
                        end
                    end
                    log.info("idx(%s,%s) result success", self.id, self.mid)
                end

                -- 填写返回数据
                local t = {
                    dragon = { color = self.poker:cardColor(dragon), count = self.poker:cardValue(dragon) },
                    tiger = { color = self.poker:cardColor(tiger), count = self.poker:cardValue(tiger) },
                    areainfo = {}
                }
                for _, v in pairs(DEFAULT_BET_TYPE) do
                    table.insert(
                        t.areainfo,
                        {
                        bettype = v,
                        iswin = wintype == v
                    }
                    )
                end

                --print("PBDragonTigerNotifyShow_N", cjson.encode(t))
                pb.encode(
                    "network.cmd.PBDragonTigerNotifyShow_N",
                    t,
                    function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerNotifyShow"),
                        pointer,
                        length
                    )
                    log.info("idx(%s,%s) PBDragonTigerNotifyShow_N : %s", self.id, self.mid, cjson.encode(t))
                end
                )
                timer.tick(self.timer, TimerID.TimerID_Show[1], TimerID.TimerID_Show[2], onShow, self)

                --print(self:conf().maxlogsavedsize, self:conf().roomtype)
                --print(cjson.encode(self.logmgr))

                -- 生成一条记录
                local logitem = { wintype = { wintype } }
                self.logmgr:push(logitem)
                log.info("idx(%s,%s) log %s", self.id, self.mid, cjson.encode(logitem))

                self:calBetST()

                -- 牌局统计
                self.sdata.cards = { { cards = { dragon } }, { cards = { tiger } } }
                self.sdata.cardstype = {}
                --table.insert(self.sdata.cardstype, pokertypeA)
                --table.insert(self.sdata.cardstype, pokertypeB)
                self.sdata.wintypes = { wintype }
                --self.sdata.winpokertype = winPokerType
            end
            )
            timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, { self })
            coroutine.resume(self.result_co)
        end
    end

    if needSendResult then
        -- 填写返回数据
        local t = {
            dragon = { color = self.poker:cardColor(dragon), count = self.poker:cardValue(dragon) },
            tiger = { color = self.poker:cardColor(tiger), count = self.poker:cardValue(tiger) },
            areainfo = {}
        }
        for _, v in pairs(DEFAULT_BET_TYPE) do
            table.insert(
                t.areainfo,
                {
                bettype = v,
                iswin = wintype == v
            }
            )
        end

        --print("PBDragonTigerNotifyShow_N", cjson.encode(t))
        pb.encode(
            "network.cmd.PBDragonTigerNotifyShow_N",
            t,
            function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerNotifyShow"),
                pointer,
                length
            )
            log.info("idx(%s,%s) PBDragonTigerNotifyShow_N : %s", self.id, self.mid, cjson.encode(t))
        end
        )
        timer.tick(self.timer, TimerID.TimerID_Show[1], TimerID.TimerID_Show[2], onShow, self)

        --print(self:conf().maxlogsavedsize, self:conf().roomtype)
        --print(cjson.encode(self.logmgr))

        -- 生成一条记录
        local logitem = { wintype = { wintype } }
        self.logmgr:push(logitem)
        log.info("idx(%s,%s) log %s", self.id, self.mid, cjson.encode(logitem))

        self:calBetST()

        -- 牌局统计
        self.sdata.cards = { { cards = { dragon } }, { cards = { tiger } } }
        self.sdata.cardstype = {}
        --table.insert(self.sdata.cardstype, pokertypeA)
        --table.insert(self.sdata.cardstype, pokertypeB)
        self.sdata.wintypes = { wintype }
        --self.sdata.winpokertype = winPokerType
    end
end

local function onFinish(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Finish[1])
        -- 清算在线列表
        self.onlinelst = {}
        local bigwinneridx = 1 --神算子
        for k, v in pairs(self.users) do
            local totalbet = 0
            local wincnt = 0
            for _, l in ipairs(v.logmgr and v.logmgr:getLogs() or {}) do
                totalbet = totalbet + l.bet
                wincnt = wincnt + ((l.profit > 0) and 1 or 0)
            end
            if totalbet > 0 then
                table.insert(
                    self.onlinelst,
                    {
                    player = {
                        uid = k,
                        username = v.playerinfo and v.playerinfo.username or "",
                        nickurl = v.playerinfo and v.playerinfo.nickurl or "",
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
        local bigwinner = g.copy(self.onlinelst[bigwinneridx])
        table.remove(self.onlinelst, bigwinneridx)
        table.sort(
            self.onlinelst,
            function(a, b)
            return a.totalbet > b.totalbet
        end
        )
        table.insert(self.onlinelst, 1, bigwinner)
        --log.info("[idx:%s] onlinelst %s", self.id, cjson.encode(self.onlinelst))
        -- 分配座位
        self.vtable:reset()
        for i = 1, math.min(self.vtable:getSize(), #self.onlinelst) do
            local o = self.onlinelst[i]
            local uid = o.player.uid
            self.vtable:sit(uid, self.users[uid].playerinfo)
        end
        self:updateSeatsInVTable(self.vtable)
        -- 清除玩家
        for k, v in pairs(self.users) do
            if not v.totalbet or v.totalbet == 0 then
                v.nobet_boardcnt = (v.nobet_boardcnt or 0) + 1
            end
            local is_need_destry = false
            if v.state == EnumUserState.Leave then
                is_need_destry = true
            end
            if v.state == EnumUserState.Logout and (v.nobet_boardcnt or 0) >= 1 then
                is_need_destry = true
            end
            if is_need_destry then
                timer.destroy(v.TimerID_Timeout)
                timer.destroy(v.TimerID_MutexTo)
                if v.state == EnumUserState.Logout then
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

        --清除不在线或者离开了的上庄列表成员
        local banklist = self.bankmgr:getBankList()
        for _, v in ipairs(banklist) do
            if not self.users[v] then
                self.bankmgr:remove(v)
            end
        end
        -- 广播赢分大于 100 万
        --self.statistic:broadcastBigWinner()
        -- self:check()

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
            --log.warn("gameid=32,needDestroy,emptyRoomCount=%s", tostring(rm:getEmptyRoomCount()))
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
    local totalbet, usertotalbet, robottotalbet = 0, 0, 0
    local totalprofit, usertotalprofit, robottotalprofit, realbankerProfit = 0, 0, 0, 0
    local totalfee = 0
    local ranks = {}
    local onlinerank = {
        uid = 0,
        totalprofit = 0,
        areas = {}
    }

    -- 结算庄家盈利
    local banker_profit, banker_fee = 0, 0
    for _, bettype in ipairs(DEFAULT_BET_TYPE) do
        if g.isInTable(lastlogitem.wintype, bettype) then -- 押中
            if bettype == EnumDragonTigerType.EnumDragonTigerType_Draw then
                banker_profit = self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] +
                    self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] -
                    self.bets[bettype] * (self:conf().betarea[bettype][1] - 1)
                banker_fee = math.floor(
                    (self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] +
                        self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger]) *
                    (self:conf() and (self:conf().fee or 0) or 0)
                )
                break
            elseif bettype == EnumDragonTigerType.EnumDragonTigerType_Dragon then
                banker_profit = self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] +
                    self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw] -
                    self.bets[bettype] * (self:conf().betarea[bettype][1] - 1)
                banker_fee = math.floor(
                    (self.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] +
                        self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw]) *
                    (self:conf() and (self:conf().fee or 0) or 0)
                )
                break
            elseif bettype == EnumDragonTigerType.EnumDragonTigerType_Tiger then
                banker_profit = self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] +
                    self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw] -
                    self.bets[bettype] * (self:conf().betarea[bettype][1] - 1)
                banker_fee = math.floor(
                    (self.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] +
                        self.bets[EnumDragonTigerType.EnumDragonTigerType_Draw]) *
                    (self:conf() and (self:conf().fee or 0) or 0)
                )
                break
            end
        end
    end
    banker_profit = banker_profit - banker_fee

    self.hasRealPlayerBet = false
    self.sdata.users = self.sdata.users or {}
    for k, v in pairs(self.users) do
        -- 计算下注的闲家以及庄位玩家
        if (not v.isdebiting and v.totalbet and v.totalbet > 0) or self.bankmgr:banker() == k then
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
            local dragon_tiger_bets = 0
            -- 计算闲家盈利
            for _, bettype in ipairs(DEFAULT_BET_TYPE) do
                local profit = 0 -- 玩家在当前下注区赢利
                local pureprofit = 0 -- 玩家在当前下注区纯利
                local bets = v.bets[bettype] -- 玩家在当前下注区总下注值
                local fee = 0
                if bets > 0 then
                    -- dragon & tiger 下注区下注总额
                    if bettype == EnumDragonTigerType.EnumDragonTigerType_Dragon or
                        bettype == EnumDragonTigerType.EnumDragonTigerType_Tiger
                    then
                        dragon_tiger_bets = dragon_tiger_bets + bets
                    end
                    -- 计算赢利
                    if g.isInTable(lastlogitem.wintype, bettype) then -- 押中
                        profit = bets * (self:conf() and self:conf().betarea and self:conf().betarea[bettype][1])
                        --扣除服务费 盈利下注区的5%
                        --fee = math.floor((profit - bets) * (self:conf() and (self:conf().fee or 0) or 0))
                        v.totalfee = v.totalfee + fee
                        profit = profit - fee
                        -- 如果结果为平，那么返还dragon & tiger下注区的下注额给玩家
                        --if bettype == EnumDragonTigerType.EnumDragonTigerType_Draw then
                        --	profit = profit + dragon_tiger_bets
                        --end
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
                        fee = fee
                    }
                    )
                end -- end of if bets > 0 then
            end -- end of for _, bettype in ipairs(DEFAULT_BET_TYPE) do

            if self.bankmgr:banker() == k then
                v.totalprofit = banker_profit
                v.totalpureprofit = banker_profit
                v.totalfee = banker_fee
                if v.linkid then
                    Utils:walletRpc(
                        k,
                        v.api,
                        v.ip,
                        v.totalprofit,
                        pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_DRAGONTIGER_SETTLE"),
                        v.linkid,
                        self:conf().roomtype,
                        self.id,
                        self.mid,
                        {
                        api = "credit",
                        sid = v.sid,
                        userId = v.userId,
                        transactionId = g.uuid(k),
                        roundId = tostring(self.logid),
                        gameId = tostring(global.stype())
                    }
                    )
                end
            end
            if 0 == v.totalpureprofit then
                v.playchips = 0
            end
            self.sdata.users[k].extrainfo = cjson.encode(
                {
                ip = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.ip,
                api = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.api,
                roomtype = self:conf().roomtype,
                bankeruid = self.bankmgr:banker(),
                money = self:getUserMoney(k) or 0,
                maxwin = v.maxwin or 0,
                playchips = v.playchips or 0 -- 2021-12-24
            }
            )
            log.info(
                "idx(%s,%s) player %s, rofit settlement profit %s, totalbets %s, totalpureprofit %s",
                self.id,
                self.mid,
                k,
                tostring(v.totalprofit),
                tostring(v.totalbet),
                tostring(v.totalpureprofit)
            )

            totalprofit = totalprofit + v.totalprofit
            totalfee = totalfee + v.totalfee

            --盈利扣水
            if v.totalpureprofit > 0 and (self:conf().rebate or 0) > 0 then
                local rebate = math.floor(v.totalpureprofit * self:conf().rebate)
                v.totalprofit = v.totalprofit - rebate
                v.totalpureprofit = v.totalpureprofit - rebate
            end
            -- 牌局统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[k] = self.sdata.users[k] or {}
            self.sdata.users[k].totalbet = v.totalbet
            self.sdata.users[k].totalprofit = v.totalprofit
            self.sdata.users[k].totalpureprofit = v.totalpureprofit
            self.sdata.users[k].totalfee = v.totalfee

            if not Utils:isRobot(v.api) then
                usertotalprofit = usertotalprofit + v.totalprofit
                usertotalbet = usertotalbet + v.totalbet
                -- 非机器人的庄家盈利
                if self.bankmgr:banker() == k then
                    realbankerProfit = v.totalprofit
                end
                self.sdata.users[k].ugameinfo = { texas = { inctotalhands = 1 } }
            else
                robottotalprofit = robottotalprofit + v.totalprofit
                robottotalbet = robottotalbet + v.totalbet
            end

            -- ranks
            -- TODO：优化
            if self.vtable:getSeat(k) then
                local rank = {
                    uid = k,
                    totalprofit = v.totalprofit,
                    areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
                }
                table.insert(ranks, rank)
            else
                -- 在线玩家 uid 为 0
                for _, bettype in ipairs(DEFAULT_BET_TYPE) do
                    local areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
                    local area = areas[bettype]
                    if area and area.bettype then
                        onlinerank.totalprofit = (onlinerank.totalprofit or 0) + (area.profit or 0)
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
        end -- end of [if (v.totalbet and v.totalbet > 0) or self.bankmgr:banker == k then]
    end -- end of [for k,v in pairs(self.users) do]

    self:checkCheat()

    Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_DRAGONTIGER_SETTLE"))

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

    -- ranks
    table.insert(ranks, onlinerank)
    --log.info('ranks %s', cjson.encode(ranks))
    --log.info('onlinerank %s', cjson.encode(onlinerank))
    for k, v in pairs(self.users) do
        local rank = {}
        if (not v.isdebiting and v.totalbet and v.totalbet > 0) or self.bankmgr:banker() == k then
            rank = {
                uid = k,
                totalprofit = v.totalprofit,
                areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
            }
        end
        local t = {
            ranks = g.copy(ranks),
            log = lastlogitem,
            sta = self.betst,
            banker = { uid = self.bankmgr:banker(), totalprofit = banker_profit, areas = self.sdata.areas }
        }
        table.insert(t.ranks, rank)
        if v.linkid and v.state == EnumUserState.Playing then
            net.send(
                v.linkid,
                k,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerNotifyFinish"),
                pb.encode("network.cmd.PBDragonTigerNotifyFinish_N", t)
            )
        end
        log.info("idx(%s,%s) uid: %s, PBDragonTigerNotifyFinish_N : %s", self.id, self.mid, k, cjson.encode(t))
    end

    self.sdata.stime = self.start_time / 1000
    self.sdata.etime = self.finish_time / 1000
    self.sdata.totalbet = totalbet
    self.sdata.totalprofit = totalprofit
    self.sdata.extrainfo = cjson.encode(
        {
        bankeruid = self.bankmgr:banker(),
        bankerprofit = banker_profit,
        totalfee = totalfee,
        playercount = self:getRealPlayerCount(),
        playerbet = usertotalbet,
        playerprofit = usertotalprofit - realbankerProfit
    }
    )
    if self.hasRealPlayerBet then
        -- 过滤机器人下注信息
        for k, user in pairs(self.users) do -- 遍历该房间所有玩家
            if self.sdata.users and self.sdata.users[k] then
                if Utils:isRobot(user.api) then
                    self.sdata.users[k] = nil
                else
                    if self.sdata.users[k].extrainfo then
                        local extrainfo = cjson.decode(self.sdata.users[k].extrainfo)
                        extrainfo["totalmoney"] = (self:getUserMoney(user.uid) or 0) + (user.totalprofit or 0) -- 总金额
                        self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)
                    end
                end
            end
        end
        log.info("idx(%s,%s) appendLogs(),self.sdata=%s", self.id, self.mid, cjson.encode(self.sdata))
        self.statistic:appendLogs(self.sdata, self.logid)
    end

    --local curday = global.cdsec()
    --if self.bankmgr:banker() == 0 then
    --    self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet
    --    self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit
    --else
    --    self.robottotal_bets[curday] = (self.robottotal_bets[curday] or 0) + robottotalbet
    --    self.robottotal_profit[curday] = (self.robottotal_profit[curday] or 0) + robottotalprofit
    --end
    Utils:serializeMiniGame(self)

    timer.tick(self.timer, TimerID.TimerID_Finish[1], TimerID.TimerID_Finish[2], onFinish, self)
end

function Room:kickout()
    if self.state ~= EnumRoomState.Finish then
        Utils:repay(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_DRAGONTIGER_SETTLE"))
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
        self.users[k] = nil
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
    for _, v in pairs(EnumDragonTigerType) do
        usertotalbet_inhand = usertotalbet_inhand + (self.userbets[v] or 0)
        if wintype == v then
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

function Room:getRobotTotalProfitRate(wintype)
    local totalbets, totalprofit = 0, 0
    local sn = 0
    for k, v in g.pairsByKeys(
        self.robottotal_bets,
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
    self.robottotal_bets[sn] = nil
    sn = 0
    for k, v in g.pairsByKeys(
        self.robottotal_profit,
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
    self.robottotal_profit[sn] = nil
    local robottotalbet_inhand, robottotalprofit_inhand = 0, 0
    for _, v in pairs(EnumDragonTigerType) do
        local totalwin = 0
        for _, vv in pairs(EnumDragonTigerType) do
            if v == vv then
                totalwin = totalwin +
                    (self.robotbets[vv] or 0) * (self:conf() and self:conf().betarea and self:conf().betarea[vv][1] - 1)
            else
                totalwin = totalwin - (self.robotbets[vv] or 0)
            end
        end
        robottotalbet_inhand = math.max(totalwin, robottotalbet_inhand)
    end
    for _, v in pairs(EnumDragonTigerType) do
        if wintype == v then
            robottotalprofit_inhand = robottotalprofit_inhand +
                (self.robotbets[v] or 0) * (self:conf() and self:conf().betarea and self:conf().betarea[v][1] - 1)
        else
            robottotalprofit_inhand = robottotalprofit_inhand - (self.robotbets[v] or 0)
        end
    end
    totalbets = totalbets + robottotalbet_inhand
    totalprofit = totalprofit + robottotalprofit_inhand

    local profit_rate = totalbets ~= 0 and totalprofit / totalbets or 0
    log.info(
        "idx(%s,%s) total_bets=%s total_profit=%s totalbets=%s,totalprofit=%s,profit_rate=%s robottotalbet_inhand=%s robottotalprofit_inhand=%s",
        self.id,
        self.mid,
        cjson.encode(self.robottotal_bets),
        cjson.encode(self.robottotal_profit),
        totalbets,
        totalprofit,
        profit_rate,
        robottotalbet_inhand,
        robottotalprofit_inhand
    )
    return profit_rate, robottotalbet_inhand, robottotalprofit_inhand
end

function Room:phpMoneyUpdate(uid, rev)
    log.info("(%s,%s)phpMoneyUpdate %s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user and user.playerinfo then
        local balance =
        self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and rev.money or rev.coin
        user.playerinfo.balance = user.playerinfo.balance + balance
        log.info("(%s,%s)phpMoneyUpdate %s,%s,%s", self.id, self.mid, uid, tostring(rev.money), tostring(rev.coin))
    end
end

function Room:tools(jdata)
    log.info("(%s,%s) tools>>>>>>>> %s", self.id, self.mid, jdata)
    local data = cjson.decode(jdata)
    if data then
        log.info("(%s,%s) handle tools %s", self.id, self.mid, cjson.encode(data))
        if data["api"] == "kickout" then
            self.isStopping = true
        end
    end
end

function Room:userWalletResp(rev)
    if not rev.data or #rev.data == 0 then
        return
    end
    for _, v in ipairs(rev.data) do
        local user = self.users[v.uid]
        if user and not Utils:isRobot(user.api) then
            log.info("(%s,%s) userWalletResp %s", self.id, self.mid, cjson.encode(rev))
        end
        if v.code >= 0 then
            if user then
                if not Utils:isRobot(user.api) then
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
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_DRAGONTIGER_SETTLE"),
                v,
                user,
                EnumRoomState.Show
            )
        end
    end
end

-- 获取参与游戏的真实玩家数目
function Room:getRealPlayerCount()
    local realPlayerCount = 0
    for k, user in pairs(self.users) do
        -- if user and user.state == EnumUserState.Playing then
        if user then
            if not Utils:isRobot(user.api) then
                if not user.isdebiting and user.totalbet and user.totalbet > 0 then -- 如果该玩家下注了
                    realPlayerCount = realPlayerCount + 1
                elseif self.bankmgr:banker() == k then
                    realPlayerCount = realPlayerCount + 1
                end
            end
        end
    end

    return realPlayerCount
end

function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s) user table info req uid:%s", self.id, self.mid, uid)

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
            player = {},
            seats = {},
            logs = {},
            sta = self.betst,
            betdata = {
                uid = uid,
                usertotal = 0,
                areabet = {}
            },
            dragon = {
                color = self.poker:cardColor(self.sdata.cards and self.sdata.cards[1].cards[1] or 0),
                count = self.poker:cardValue(self.sdata.cards and self.sdata.cards[1].cards[1] or 0)
            },
            tiger = {
                color = self.poker:cardColor(self.sdata.cards and self.sdata.cards[2].cards[1] or 0),
                count = self.poker:cardValue(self.sdata.cards and self.sdata.cards[2].cards[1] or 0)
            },
            bank = self:getBankerInfo(),
            configchips = self:conf().chips,
            odds = {},
            playerCount = Utils:getVirtualPlayerCount(self)
        }
    }

    for _, v in ipairs(self:conf().betarea) do
        table.insert(t.data.odds, v[1])
    end

    -- 填写返回数据
    if self.state == EnumRoomState.Start then
        t.data.lefttime = TimerID.TimerID_Start[2] - (global.ctms() - self.start_time)
    elseif self.state == EnumRoomState.Betting then
        t.data.lefttime = TimerID.TimerID_Betting[2] - (global.ctms() - self.betting_time)
    elseif self.state == EnumRoomState.Show then
        t.data.lefttime = TimerID.TimerID_Show[2] - (global.ctms() - self.show_time) + TimerID.TimerID_Finish[2]
    elseif self.state == EnumRoomState.Finish then
        t.data.lefttime = TimerID.TimerID_Finish[2] - (global.ctms() - self.finish_time)
    end
    t.data.lefttime = t.data.lefttime > 0 and t.data.lefttime or 0

    local user = self.users[uid] or {}

    if user then
        --t.data.player = user.playerinfo
        t.data.player.uid = uid -- 玩家UID
        t.data.player.nickname = user.playerinfo.nickname or "" -- 昵称
        t.data.player.username = user.playerinfo.username or ""
        t.data.player.viplv = user.playerinfo.viplv or 0
        t.data.player.nickurl = user.playerinfo.nickurl or ""
        t.data.player.gender = user.playerinfo.gender
        -- t.data.player.balance = user.playerinfo.balance
        t.data.player.currency = user.playerinfo.currency
        t.data.player.extra = user.playerinfo.extra or {}
        if self:conf().isib then
            t.data.player.balance = user.playerinfo.balance + (user.totalbet or 0)
        else
            t.data.player.balance = user.playerinfo.balance
        end

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

    -- local resp = pb.encode("network.cmd.PBGameSubCmdID_IntoDragonTigerRoomResp", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoDragonTigerRoomResp"),
            pb.encode("network.cmd.PBIntoDragonTigerRoomResp_S", t)
        )
    end
end

-- 参数 bankerIsSystem: 是否是系统坐庄, true表示是系统坐庄
-- 参数 cardDragon: 龙对应的牌数据
-- 参数 cardTiger: 虎对应的牌数据
-- 返回值: 返回真实玩家赢取到的金额
function Room:GetRealPlayerWin(bankerIsSystem, cardDragon, cardTiger)
    local realPlayerWin = 0
    -- 根据牌数据获取输赢情况
    local wintype = self.poker:getWinType(cardDragon, cardTiger)
    if bankerIsSystem then -- 如果是系统坐庄
        local userTotalBet = 0 -- 真实玩家下注总金额
        for _, v in pairs(EnumDragonTigerType) do
            userTotalBet = userTotalBet + (self.userbets[v] or 0)
            if wintype == v then
                realPlayerWin = realPlayerWin +
                    (self.userbets[v] or 0) * (self:conf() and self:conf().betarea and self:conf().betarea[v][1])
            end
        end
        realPlayerWin = realPlayerWin - userTotalBet
    else
        local robotTotalBet = 0
        for _, v in pairs(EnumDragonTigerType) do
            robotTotalBet = robotTotalBet + (self.robotbets[v] or 0)
            if wintype == v then
                realPlayerWin = realPlayerWin -
                    (self.robotbets[v] or 0) * (self:conf() and self:conf().betarea and self:conf().betarea[v][1])
            end
        end
        realPlayerWin = realPlayerWin + robotTotalBet
    end
    return realPlayerWin
end

function Room:queryUserResult(ok, ud)
    if self.timer and self:conf().single_profit_switch then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.info("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

function Room:destroy()
    self:kickout() -- 踢出所有玩家
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
        local totalBet = 0 -- 胜平负盘口投注总量   该游戏没有其它盘口
        local maxChips = nil
        if not Utils:isRobot(user.api) then
            for k, v in pairs(EnumDragonTigerType) do -- 遍历每个下注区，计算总下注金额
                if user.bets and user.bets[v] then
                    totalBet = totalBet + user.bets[v]
                end
            end
            if totalBet > 0 then -- 如果该玩家下注了
                for k, v in pairs(EnumDragonTigerType) do -- 遍历每个下注区
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
                user.playchips = maxChips
            end
        end
    end
end

function Room:checkCheat()
    self.sdata.users = self.sdata.users or {}
    local uid_list = {}
    for _, user in pairs(self.users) do
        if user and self.bankmgr:banker() == user.uid then
            table.insert(uid_list, user.uid)
        end
        -- 判断是否在胜负区域下注了
        if user and not user.isdebiting and user.totalbet and user.totalbet > 0 then
            self.sdata.users[user.uid] = self.sdata.users[user.uid] or {}
            if not Utils:isRobot(user.api) then -- 如果不是机器人
                local extrainfo = cjson.decode(self.sdata.users[user.uid].extrainfo)
                extrainfo["cheat"] = false
                self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)
                if user.bets and
                    (user.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] > 0 or
                        user.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] > 0)
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
            local totalBetA = user.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] or 0
            local totalBetB = user.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] or 0
            local hasCheat = false -- 默认没有作弊
            for idx2 = idx + 1, #uid_list, 1 do
                local user2 = self.users[uid_list[idx2]]
                if user and user2 and user.ip == user2.ip then
                    -- 投注游戏每局投注的所有玩家中IP相同的玩家按照ip分组，每组玩家中既有投胜也有投负的时，改组所有玩家进行标记
                    -- 增加条件：胜负区域分别累加总和   总和少的区域/总和多的区域 >= 50%
                    totalBetA = totalBetA + (user2.bets[EnumDragonTigerType.EnumDragonTigerType_Dragon] or 0)
                    totalBetB = totalBetB + (user2.bets[EnumDragonTigerType.EnumDragonTigerType_Tiger] or 0)
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
