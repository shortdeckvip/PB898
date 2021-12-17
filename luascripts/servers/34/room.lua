local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local cjson = require("cjson")
local mutex = require(CLIBS["c_mutex"])
local rand = require(CLIBS["c_rand"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/uniqueid")
require("luascripts/servers/34/rummy")
require("luascripts/servers/34/seat")

Room = Room or {}

local TimerID = {
    TimerID_Check = {1, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, --id, interval(ms), timestamp(ms)
    TimerID_PrechipsOver = {3, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_StartHandCards = {4, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_HandCardsAnimation = {5, 5000},
    TimerID_Betting = {6, 20000}, --id, interval(ms), timestamp(ms)
    TimerID_Settlement = {7, 30000},
    TimerID_OnFinish = {8, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Timeout = {9, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {10, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {11, 1000},
    TimerID_Buyin = {12, 1000},
    TimerID_Ready = {13, 5},
    TimerID_Expense = {14, 5000}
}

local EnumUserState = {
    Playing = 1,
    Leave = 2,
    Logout = 3,
    Intoing = 4
}

local function fillSeatInfo(seat, self)
    local seatinfo = {}
    seatinfo.seat = {
        sid = seat.sid,
        playerinfo = {}
    }

    local user = self.users[seat.uid]
    seatinfo.seat.playerinfo = {
        uid = seat.uid or 0,
        username = user and user.username or "",
        gender = user and user.sex or 0,
        nickurl = user and user.nickurl or ""
    }

    seatinfo.isPlaying = seat.isplaying and 1 or 0
    seatinfo.seatMoney = seat.chips
    seatinfo.chipinType = seat.chiptype
    seatinfo.chipinValue = seat.chipinnum
    seatinfo.chipinTime = seat:getChipinLeftTime()
    seatinfo.totalTime = seat:getChipinTotalTime()
    seatinfo.pot = self:getOnePot()
    seatinfo.currentBetPos = self.current_betting_pos
    seatinfo.addtimeCost = self.conf.addtimecost
    seatinfo.addtimeCount = seat.addon_count
    seatinfo.discardCard = self.poker:getTopFoldCard()
    seatinfo.score = seat.score
    seatinfo.drawcard =
        (seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW2") or
        seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DISCARD")) and
        seat.drawcard or
        0
    seatinfo.foldcards = self.poker:getLeftFoldCardCnt()
    seatinfo.leftcards =
        self.state ~= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None") and
        self.poker:getLeftCardsCnt() or
        0
    seatinfo.leftDeclareTime =
        self.declare_start_time and TimerID.TimerID_Settlement[2] - (global.ctms() - self.declare_start_time) or 0

    if
        seatinfo.score == 0 and self.state >= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Start") and
            self.state < pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Declare")
     then
        if not seat.is_drawcard then
            seatinfo.score = RUMMYCONF.NOT_DRAW_SCORE
        else
            seatinfo.score = RUMMYCONF.HAS_DRAWED_SCORE
        end
    end
    if seat:getIsBuyining() then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_BUYING")
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
    end

    return seatinfo
end

local function fillSeats(self)
    local seats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            local seatinfo = fillSeatInfo(seat, self)
            table.insert(seats, seatinfo)
        end
    end
    return seats
end

local function onHandCardsAnimation(self)
    local function doRun()
        log.info(
            "idx(%s,%s,%s) onHandCardsAnimation:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(self.logid),
            self.current_betting_pos
        )
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        local bbseat = self.seats[self.current_betting_pos]
        local nextseat = self:getNextActionPosition(bbseat)
        self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Betting")
        self:betting(nextseat)
    end
    g.call(doRun)
end

local function onPotAnimation(self)
    local function doRun()
        log.info("idx(%s,%s,%s) onPotAnimation", self.id, self.mid, tostring(self.logid), tostring(self.logid))
        timer.cancel(self.timer, TimerID.TimerID_PotAnimation[1])
        self:finish()
    end
    g.call(doRun)
end

local function onBuyin(t)
    local function doRun()
        local self = t[1]
        local uid = t[2]
        timer.cancel(self.timer, TimerID.TimerID_Buyin[1] + 100 + uid)
        local seat = self:getSeatByUid(uid)
        if seat then
            seat:setIsBuyining(false)
            local user = self.users[uid]
            if user and user.buyin and coroutine.status(user.buyin) == "suspended" then
                coroutine.resume(user.buyin, false)
            else
                log.info("idx(%s,%s,%s) user buyin timeout %s", self.id, self.mid, tostring(self.logid), uid)
                -- self:userLeave(
                --     uid,
                --     user.linkid,
                --     pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_BuyinOverTime")
                -- )
                --seat:reset()

                self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_BuyinFailed"))
            end
        end
    end
    g.call(doRun)
end

local function onCheck(self)
    local function doRun()
        if self.isStopping then
            Utils:onStopServer(self)
            return
        end

        -- check all users issuses
        local hasuser, robotid = false
        for uid, user in pairs(self.users) do
            -- clear logout users after 10 mins
            if user.state == EnumUserState.Logout and global.ctsec() >= user.logoutts + MYCONF.logout_to_kickout_secs then
                log.info(
                    "idx(%s,%s,%s) onCheck user logout %s %s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    user.logoutts,
                    global.ctsec()
                )
                self:userLeave(uid, user.linkid)
            end
            if user.state == EnumUserState.Playing then
                hasuser = true
            end
            if Utils:isRobot(user.api) then
                robotid = robotid or uid
            end
        end
        -- check all seat users issuses
        for k, v in ipairs(self.seats) do
            v.isplaying = false
            local user = self.users[v.uid]
            if user then
                local uid = v.uid
                -- 超时两轮自动站起
                if v.bet_timeout_count >= 2 then
                    log.info(
                        "idx(%s,%s,%s) onCheck user(%s,%s) betting timeout",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        v.uid,
                        k
                    )
                    self:stand(
                        v,
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_ReservationTimesLimit")
                    )
                else
                    if v.chips >= (self.conf and self.conf.ante * 80 + self.conf.fee or 0) then
                        v:reset()
                        v.isplaying = true
                    else
                        if v:hasBuyin() then -- 上局正在玩牌（非 fold）且已买入成功则下局生效
                            v:buyinToChips()
                            pb.encode(
                                "network.cmd.PBTexasPlayerBuyin",
                                {sid = v.sid, chips = v.chips, money = self:getUserMoney(v.uid), immediately = true},
                                function(pointer, length)
                                    self:sendCmdToPlayingUsers(
                                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerBuyin"),
                                        pointer,
                                        length
                                    )
                                end
                            )
                        end
                        v.isplaying = false
                        if v:getIsBuyining() then --正在买入
                        elseif v:totalBuyin() > 0 then --非第一次坐下待买入，弹窗补币
                            v:setIsBuyining(true)
                            pb.encode(
                                "network.cmd.PBTexasPopupBuyin",
                                {clientBuyin = true, buyinTime = self.conf.buyintime, sid = k},
                                function(pointer, length)
                                    self:sendCmdToPlayingUsers(
                                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPopupBuyin"),
                                        pointer,
                                        length
                                    )
                                end
                            )

                            timer.tick(
                                self.timer,
                                TimerID.TimerID_Buyin[1] + 100 + uid,
                                self.conf.buyintime * 1000,
                                onBuyin,
                                {self, uid}
                            )
                        end
                    end
                end
            end
        end

        --log.info("idx(%s,%s,%s) onCheck playing size=%s", self.id, self.mid, tostring(self.logid), self:getPlayingSize())
        if self:getPlayingSize() < 2 then
            self.ready_start_time = nil
            local _, r = self:count()
            if hasuser and r == 0 and not self.notify_createrobot then
                self.notify_createrobot = true
                log.info("idx(%s,%s,%s) notify create robot", self.id, self.mid, tostring(self.logid))
                Utils:notifyCreateRobot(self.conf.roomtype, self.mid, self.id, 1)
            end
            if r == 1 then
                local robot = self.users[robotid or 0]
                if robot and global.ctsec() > (robot.intots or 0) + rand.rand_between(30, 60) then
                    self:userLeave(robotid, robot.linkid)
                    self.notify_createrobot = false
                end
            end
            return
        end
        if self:getPlayingSize() >= 2 then
            self.notify_createrobot = false
            --timer.cancel(self.timer, TimerID.TimerID_Check[1])
            self:ready()
        end
    end
    g.call(doRun)
end

local function onFinish(self)
    local function doRun()
        log.info("idx(%s,%s,%s) onFinish", self.id, self.mid, tostring(self.logid))
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])

        --self:checkLeave()

        Utils:broadcastSysChatMsgToAllUsers(self.notify_jackpot_msg)
        self.notify_jackpot_msg = nil

        -- notify all client to clear table
        pb.encode(
            "network.cmd.PBTexasClearTable",
            {},
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasClearTable"),
                    pointer,
                    length
                )
            end
        )

        self:getNextState()
        self:reset()
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
    g.call(doRun)
end

function Room:getUserMoney(uid)
    local user = self.users[uid]
    --print('getUserMoney roomtype', self.conf.roomtype, 'money', user.money, 'coin', user.coin)
    if self.conf and user then
        if not self.conf.roomtype or self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
            return user.money
        elseif self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
            return user.coin
        end
    end
    return 0
end

--room start
function Room:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init()
    o:check()
    return o
end

function Room:destroy()
    timer.destroy(self.timer)
end

function Room:init()
    log.info("idx(%s,%s,%s) room init", self.id, self.mid, tostring(self.logid))
    self.conf = MatchMgr:getConfByMid(self.mid)
    self.users = {}
    self.timer = timer.create()
    self.poker = Rummy:new()
    self.gameId = 0

    self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None") --牌局状态(preflop, flop, turn...)
    self.buttonpos = 0
    self.tabletype = self.conf.matchtype
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000
    self.bettingtime = self.conf.bettime
    self.current_betting_pos = 0
    self.maxraisepos = 0

    self.pot = 0 -- 奖池
    self.seats = {} -- 座位
    for sid = 1, self.conf.maxuser do
        local s = Seat:new(self, sid)
        table.insert(self.seats, s)
    end

    self.config_switch = false
    --self.boardlog = BoardLog.new() -- 牌局记录器
    self.statistic = Statistic:new(self.id, self.conf.mid)
    self.sdata = {
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }

    self.starttime = 0 -- 牌局开始时间
    self.endtime = 0 -- 牌局结束时间

    self.table_match_start_time = 0 -- 开赛时间
    self.table_match_end_time = 0 -- 比赛结束时间

    self.last_playing_users = {} -- 上一局参与的玩家列表

    self.finishstate = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None")

    self.reviewlogs = LogMgr:new(1)
    --实时牌局
    self.reviewlogitems = {} --暂存站起玩家牌局
    --self.recentboardlog = RecentBoardlog.new() -- 最近牌局

    -- 主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_NULL")
    self.lastchipinpos = 0

    self.tableStartCount = 0
    self.m_winner_sid = 0
    self.logid = self.statistic:genLogId()
end

function Room:reload()
    self.conf = MatchMgr:getConfByMid(self.mid)
end

function Room:sendCmdToPlayingUsers(maincmd, subcmd, msg, msglen)
    self.links = self.links or {}
    if not self.user_cached then
        self.links = {}
        local linkidstr = nil
        for k, v in pairs(self.users) do
            if v.state == EnumUserState.Playing then
                linkidstr = tostring(v.linkid)
                self.links[linkidstr] = self.links[linkidstr] or {}
                table.insert(self.links[linkidstr], k)
            end
        end
        self.user_cached = true
    --log.debug("idx:%s,%s is not cached", self.id,self.mid)
    end

    net.send_users(cjson.encode(self.links), maincmd, subcmd, msg, msglen)
end

function Room:getUserNum()
    return self:count()
end

function Room:getApiUserNum()
    local t = {}
    for k, v in pairs(self.users) do
        if v.api and self.conf and self.conf.roomtype then
            t[v.api] = t[v.api] or {}
            t[v.api][self.conf.roomtype] = t[v.api][self.conf.roomtype] or {}
            if v.state == EnumUserState.Playing then
                if self:getSeatByUid(k) then
                    t[v.api][self.conf.roomtype].players = (t[v.api][self.conf.roomtype].players or 0) + 1
                else
                    t[v.api][self.conf.roomtype].viewplayers = (t[v.api][self.conf.roomtype].viewplayers or 0) + 1
                end
            end
        end
    end

    return t
end

function Room:lock()
    return self.islock
end

function Room:roomtype()
    return self.conf.roomtype
end

function Room:robotCount()
    local c = 0
    for k, v in pairs(self.users) do
        if Utils:isRobot(v.api) then
            c = c + 1
        end
    end
    return c
end

function Room:count()
    local c, r = 0, 0
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user then
            c = c + 1
            if Utils:isRobot(user.api) then
                r = r + 1
            end
        end
    end
    return c, r
end

function Room:checkLeave()
    local c = self:count()
    if c > 2 then
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if user then
                if Utils:isRobot(user.api) then
                    self:userLeave(v.uid, user.linkid)
                    break
                end
            end
        end
    end
end

function Room:logout(uid)
    local user = self.users[uid]
    if user then
        user.state = EnumUserState.Logout
        user.logoutts = global.ctsec()
        log.info(
            "idx(%s,%s,%s) room logout uid:%s %s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            user and user.logoutts or 0
        )
    end
end

function Room:clearUsersBySrvId(srvid)
    for k, v in pairs(self.users) do
        if v.linkid == srvid then
            self:logout(k)
        end
    end
end

function Room:userQueryUserInfo(uid, ok, ud)
    local user = self.users[uid]
    if user and user.TimerID_Timeout then
        timer.cancel(user.TimerID_Timeout, TimerID.TimerID_Timeout[1])
        log.info(
            "idx(%s,%s,%s) query userinfo:%s ok:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(uid),
            tostring(ok)
        )
        coroutine.resume(user.co, ok, ud)
    end
end

function Room:userMutexCheck(uid, code)
    local user = self.users[uid]
    if user then
        timer.cancel(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1])
        log.info(
            "idx(%s,%s,%s) mutex check:%s code:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(uid),
            tostring(code)
        )
        coroutine.resume(user.mutex, code > 0)
    end
end

function Room:userLeave(uid, linkid, code)
    log.info("idx(%s,%s,%s) userLeave:%s", self.id, self.mid, tostring(self.logid), uid)
    local function handleFailed()
        local resp =
            pb.encode(
            "network.cmd.PBLeaveGameRoomResp_S",
            {
                code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed"),
                gameid = global.stype()
            }
        )
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) user:%s is not in room", self.id, self.mid, tostring(self.logid), uid)
        handleFailed()
        return
    end

    local s
    for k, v in ipairs(self.seats) do
        if v.uid == uid then
            s = v
            break
        end
    end
    user.state = EnumUserState.Leave
    if s then
        if
            s.isplaying and self.state >= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD"), 0)
                s = self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
            else
                self:chipin(uid, pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD"), 0)
                s = self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
                self:checkFinish()
            end
        else
            -- 站起
            s = self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
        end

        -- 最大加注位站起
        log.info(
            "idx(%s,%s,%s) s.sid %s maxraisepos %s",
            self.id,
            self.mid,
            tostring(self.logid),
            s.sid,
            self.maxraisepos
        )
        if s.sid == self.m_winner_sid then
            user.chips = user.chips + self:getOnePot()
            s.room_delta = s.room_delta + self:getOnePot()
            self.winner_seats = s
            self.winner_seats.api = user.api
        end
    end

    -- 结算
    local val = (user.chips or 0) + (user.currentbuyin or 0)
    if val ~= 0 then
        Utils:walletRpc(
            uid,
            user.api,
            user.ip,
            val,
            pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_RETURNCHIPS"),
            linkid,
            self.conf.roomtype,
            self.id,
            self.mid,
            {
                api = "transfer",
                sid = user.sid,
                userId = user.userId,
                transactionId = g.uuid(),
                roundId = user.roundId
            }
        )
        log.info("idx(%s,%s,%s) money change uid:%s val:%s", self.id, self.mid, tostring(self.logid), uid, val)
    end

    if (user.gamecount or 0) > 0 then
        local logdata = {
            uid = uid,
            time = global.ctsec(),
            roomtype = self.conf.roomtype,
            gameid = global.stype(),
            serverid = global.sid(),
            roomid = self.id,
            smallblind = self.conf.ante,
            seconds = global.ctsec() - (user.intots or 0),
            changed = val - user.totalbuyin,
            roomname = self.conf.name,
            gamecount = user.gamecount,
            matchid = self.mid,
            api = tonumber(user.api) or 0
        }
        Statistic:appendRoomLogs(logdata)
        log.info(
            "idx(%s,%s,%s) user(%s) upload roomlogs %s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            cjson.encode(logdata)
        )
    end

    mutex.request(
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
        pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
        pb.encode("network.cmd.PBMutexRemove", {uid = uid, srvid = global.sid(), roomid = self.id})
    )
    if user.TimerID_Timeout then
        timer.destroy(user.TimerID_Timeout)
    end
    if user.TimerID_MutexTo then
        timer.destroy(user.TimerID_MutexTo)
    end
    if user.TimerID_Expense then
        timer.destroy(user.TimerID_Expense)
    end

    local resp =
        pb.encode(
        "network.cmd.PBLeaveGameRoomResp_S",
        {
            code = code or pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess"),
            hands = user.gamecount or 0,
            profits = val - user.totalbuyin,
            roomtype = self.conf.roomtype,
            gameid = global.stype()
        }
    )
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
        resp
    )
    log.info("idx(%s,%s,%s) userLeave:%s,%s", self.id, self.mid, tostring(self.logid), uid, user.gamecount or 0)
    self.users[uid] = nil
    self.user_cached = false

    if not next(self.users) then
        MatchMgr:getMatchById(self.conf.mid):shrinkRoom()
    end
end

local function onMutexTo(arg)
    arg[2]:userMutexCheck(arg[1], -1)
end

local function onTimeout(arg)
    arg[2]:userQueryUserInfo(arg[1], false, nil)
end

local function onExpenseTimeout(arg)
    timer.cancel(arg[2].timer, TimerID.TimerID_Expense[1])
    local user = arg[2].users[arg[1]]
    if user and user.expense then
        coroutine.resume(user.expense, false)
    end
    return false
end

function Room:getRecommandBuyin(balance)
    local referrer = self.conf.ante * self.conf.referrerbb
    if referrer > balance then
        referrer = balance
    elseif referrer < self.conf.ante * self.conf.minbuyinbb then
        referrer = self.conf.ante * self.conf.minbuyinbb
    end
    return referrer
end

function Room:userInto(uid, linkid, mid, quick, ip, api)
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(),
        idx = {
            srvid = global.sid(),
            roomid = self.id,
            matchid = self.mid,
            roomtype = self.conf.roomtype or 0
        },
        maxuser = self.conf and self.conf.maxuser
    }

    local function handleFail(code)
        t.code = code
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
        )
        log.info(
            "idx(%s,%s,%s) player:%s ip %s code %s into room failed",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            tostring(ip),
            code
        )
    end

    if self.isStopping then
        handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail"))
        return
    end
    if Utils:hasIP(self, uid, ip, api) then
        handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_SameIp"))
        return
    end

    self.users[uid] =
        self.users[uid] or
        {TimerID_MutexTo = timer.create(), TimerID_Timeout = timer.create(), TimerID_Expense = timer.create()}
    local user = self.users[uid]
    user.money = 0
    user.diamond = 0
    user.linkid = linkid
    user.ip = ip
    user.totalbuyin = user.totalbuyin or 0
    user.state = EnumUserState.Intoing
    --座位互斥
    local seat, inseat = nil, false
    for k, v in ipairs(self.seats) do
        if v.uid then
            if v.uid == uid then
                inseat = true
                seat = v
                break
            end
        else
            seat = v
        end
    end
    if not seat then
        log.info(
            "idx(%s,%s,%s) the room has been full uid %s fail to sit",
            self.id,
            self.mid,
            tostring(self.logid),
            uid
        )
        return false
    end

    user.mutex =
        coroutine.create(
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
                        roomtype = self.conf and self.conf.roomtype
                    }
                )
            )
            local ok = coroutine.yield()
            if not ok then
                if self.users[uid] ~= nil then
                    timer.destroy(user.TimerID_MutexTo)
                    timer.destroy(user.TimerID_Timeout)
                    timer.destroy(user.TimerID_Expense)
                    self.users[uid] = nil
                    t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                    net.send(
                        linkid,
                        uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                        pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                    )
                --Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
                end
                log.info(
                    "idx(%s,%s,%s) player:%s has been in another room",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    uid
                )
                return
            end

            user.co =
                coroutine.create(
                function(user)
                    Utils:queryUserInfo(
                        {
                            uid = uid,
                            roomid = self.id,
                            matchid = self.mid,
                            jpid = self.conf.jpid,
                            carrybound = {
                                self.conf.ante * self.conf.minbuyinbb,
                                self.conf.ante * self.conf.maxbuyinbb
                            }
                        }
                    )
                    --print("start coroutine", self, user, uid)
                    local ok, ud = coroutine.yield()
                    --print('ok', ok, 'ud', ud)
                    if ud then
                        -- userinfo
                        user.uid = uid
                        user.money = ud.money or 0
                        user.coin = ud.coin or 0
                        user.diamond = ud.diamond or 0
                        user.nickurl = ud.nickurl or ""
                        user.username = ud.name or ""
                        user.viplv = ud.viplv or 0
                        --user.tomato = 0
                        --user.kiss = 0
                        user.sex = ud.sex or 0
                        user.api = ud.api or ""
                        user.ip = ip or ""
                        --print('ud.money', ud.money, 'ud.coin', ud.coin, 'ud.diamond', ud.diamond, 'ud.nickurl', ud.nickurl, 'ud.name', ud.name, 'ud.viplv', ud.viplv)
                        --user.addon_timestamp = ud.addon_timestamp

                        -- 携带数据
                        user.linkid = linkid
                        user.intots = user.intots or global.ctsec()
                        user.sid = ud.sid
                        user.userId = ud.userId

                        user.chips = user.chips or 0
                        user.currentbuyin = user.currentbuyin or 0
                        user.roundmoney = user.roundmoney or 0
                        -- 从坐下到站起期间总买入和总输赢
                        user.totalbuyin = user.totalbuyin or 0
                        user.roundId = user.roundId or self.statistic:genLogId()
                    end

                    -- 防止协程返回时，玩家实质上已离线
                    if ok and user.state ~= EnumUserState.Intoing then
                        ok = false
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                        log.info("idx(%s,%s,%s) user %s logout or leave", self.id, self.mid, tostring(self.logid), uid)
                    end
                    if ok and not inseat and self:getUserMoney(uid) + user.chips > self.conf.maxinto then
                        ok = false
                        log.info(
                            "idx(%s,%s,%s) user %s more than maxinto %s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            uid,
                            tostring(self.conf.maxinto)
                        )
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_OverMaxInto")
                    end

                    -- if ok and not inseat and self.conf.minbuyinbb * self.conf.ante > self:getUserMoney(uid) + user.chips then
                    --     log.info(
                    --         "idx(%s,%s,%s) userBuyin not enough money: buyinmoney %s, user money %s",
                    --         self.id,
                    --         self.mid,
                    --         self.conf.minbuyinbb * self.conf.ante,
                    --         self:getUserMoney(uid)
                    --     )
                    --     ok = false
                    --     t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                    -- end

                    if not ok then
                        if self.users[uid] ~= nil then
                            timer.destroy(user.TimerID_MutexTo)
                            timer.destroy(user.TimerID_Timeout)
                            timer.destroy(user.TimerID_Expense)
                            self.users[uid] = nil
                            net.send(
                                linkid,
                                uid,
                                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                                pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                            )
                            mutex.request(
                                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
                                pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
                                pb.encode(
                                    "network.cmd.PBMutexRemove",
                                    {uid = uid, srvid = global.sid(), roomid = self.id}
                                )
                            )
                        end
                        log.info(
                            "idx(%s,%s,%s) not enough money:%s,%s,%s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            uid,
                            ud.money,
                            t.code
                        )
                        if Utils:isRobot(user.api) then
                            self.notify_createrobot = false
                        end
                        return
                    end

                    self.user_cached = false
                    user.state = EnumUserState.Playing

                    local resp, e = pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                    local to = {
                        uid = uid,
                        srvid = global.sid(),
                        roomid = self.id,
                        matchid = self.mid,
                        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                        data = resp
                    }

                    local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)

                    net.shared(
                        linkid,
                        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                        pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                        synto
                    )

                    quick = (0x2 == self.conf.buyin & 0x2) and true or false
                    if not inseat and self:count() < self.conf.maxuser and quick and not user.active_stand then
                        self:sit(seat, uid, self:getRecommandBuyin(self:getUserMoney(uid)))
                    end
                    log.info(
                        "idx(%s,%s,%s) into room:%s,%s,%s,%s,%s",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        uid,
                        linkid,
                        seat.chips,
                        self:getUserMoney(uid),
                        self:getSitSize()
                    )
                end
            )
            timer.tick(
                user.TimerID_Timeout,
                TimerID.TimerID_Timeout[1],
                TimerID.TimerID_Timeout[2],
                onTimeout,
                {uid, self}
            )
            coroutine.resume(user.co, user)
        end
    )
    timer.tick(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1], TimerID.TimerID_MutexTo[2], onMutexTo, {uid, self})
    coroutine.resume(user.mutex, user)
end

function Room:reset()
    self.pots = {money = 0, seats = {}}
    --奖池中包含哪些人共享
    self.maxraisepos = 0
    self.roundcount = 0
    self.current_betting_pos = 0
    self.sdata = {
        --moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}
    --self.boardlog:reset()
    self.finishstate = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None")

    self.lastchipintype = pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_NULL")
    self.lastchipinpos = 0
    self.poker:resetAll()
    self.pot = 0
    self.winner_seats = nil
    self.m_winner_sid = 0
    self.buttonpos = 0
    self.declare_start_time = nil
    self.notify_createrobot = nil
end

function Room:potRake(total_pot_chips)
    log.info("idx(%s,%s,%s) into potRake:%s", self.id, self.mid, tostring(self.logid), total_pot_chips)
    local minipotrate = self.conf.minipotrate or 0
    local potrake = 0
    if total_pot_chips <= minipotrate then
        return total_pot_chips, potrake
    end
    local feerate = self.conf.feerate or 0
    local feehandupper = self.conf.feehandupper or 0
    if feerate > 0 then
        potrake = total_pot_chips * (feerate / 100) + self.conf.minchip * 0.5
        potrake = math.floor(potrake / self.conf.minchip) * self.conf.minchip
        if potrake > feehandupper then
            potrake = feehandupper
        end
        total_pot_chips = total_pot_chips - potrake
        log.info("idx(%s,%s,%s) after potRake:%s", self.id, self.mid, tostring(self.logid), total_pot_chips)
    end
    return total_pot_chips, potrake
end

function Room:userTableInfo(uid, linkid, rev)
    log.info(
        "idx(%s,%s,%s) user table info req uid:%s ante:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        self.conf.ante
    )
    local tableinfo = {
        gameId = self.gameId,
        seatCount = self.conf.maxuser,
        tableName = self.conf.name,
        gameState = self.state,
        buttonSid = self.buttonpos,
        pot = self:getOnePot(),
        ante = self.conf.ante,
        bettingtime = self.bettingtime,
        matchType = self.conf.matchtype,
        roomType = self.conf.roomtype,
        addtimeCost = self.conf.addtimecost,
        toolCost = self.conf.toolcost,
        jpid = self.conf.jpid or 0,
        jp = JackpotMgr:getJackpotById(self.conf.jpid),
        jpRatios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or {0, 0, 0}),
        discardCard = self.poker:getTopFoldCard(),
        magicCard = self.poker:getMagicCard(),
        magicCardList = g.copy(self.poker:getMagicCardList()),
        readyLeftTime = ((self.t_msec or 0) / 1000 + TimerID.TimerID_Ready[2] + TimerID.TimerID_Check[2] / 1000) -
            (global.ctsec() - self.endtime),
        leftDeclareTime = self.declare_start_time and
            TimerID.TimerID_Settlement[2] - (global.ctms() - self.declare_start_time) or
            0,
        minbuyinbb = self.conf.minbuyinbb,
        maxbuyinbb = self.conf.maxbuyinbb,
        foldcards = self.poker:getLeftFoldCardCnt(),
        leftcards = self.state ~= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None") and
            self.poker:getLeftCardsCnt() or
            0,
        middlebuyin = self.conf.referrerbb * self.conf.ante
    }
    tableinfo.readyLeftTime =
        self.ready_start_time and TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time) or
        tableinfo.readyLeftTime
    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    log.info(
        "idx(%s,%s,%s) uid:%s userTableInfo:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        cjson.encode(tableinfo)
    )
end

function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid then
            local seatinfo = fillSeatInfo(seat, self)
            if seat.uid == uid then
                seatinfo.handcards = g.copy(seat.handcards)
                seatinfo.drawcard = seat.drawcard > 0 and seat.drawcard or 0
                seatinfo.group = seat.groupcards and g.copy(seat.groupcards) or {}
            end
            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end

    local resp = pb.encode("network.cmd.PBRummyTableInfoResp", {tableInfo = tableinfo})
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyTableInfoResp"),
        resp
    )
end

function Room:inTable(uid)
    for i = 1, #self.seats do
        if self.seats[i].uid == uid then
            return true
        end
    end
    return false
end

function Room:getSeatByUid(uid)
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid == uid then
            return seat
        end
    end
    return nil
end

function Room:distance(seat_a, seat_b)
    local dis = 0
    for i = seat_a.sid, seat_b.sid - 1 + #self.seats do
        dis = dis + 1
    end
    return dis % #self.seats
end

function Room:getSitSize()
    local count = 0
    for i = 1, #self.seats do
        if self.seats[i].uid then
            count = count + 1
        end
    end
    return count
end

-- 非留座 + 非买入
function Room:getNonRsrvSitSize()
    local count = 0
    for i = 1, #self.seats do
        if self.seats[i].uid and not self.seats[i].isbuyining then
            count = count + 1
        end
    end
    return count
end

function Room:getCurrentBoardSitSize()
    local count = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid and seat.isplaying then
            count = count + 1
        end
    end

    return count
end

function Room:getPlayingSize()
    local count = 0
    for i = 1, #self.seats do
        if self.seats[i].isplaying then
            count = count + 1
        end
    end
    return count
end

function Room:getValidDealPos()
    for i = self.buttonpos + 1, self.buttonpos + #self.seats - 1 do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat and seat.isplaying then
            return j
        end
    end
    return -1
end

function Room:getNextNoFlodPosition(pos)
    for i = pos + 1, pos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat.isplaying and seat.chiptype ~= pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") then
            return seat
        end
    end
    return nil
end

function Room:getNextActionPosition(seat)
    local pos = seat and seat.sid or 0
    log.info(
        "idx(%s,%s,%s) getNextActionPosition sid:%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        pos,
        tostring(self.maxraisepos)
    )
    for i = pos + 1, pos + #self.seats - 1 do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seati = self.seats[j]
        if
            seati and seati.isplaying and
                seati.chiptype ~= pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD")
         then
            seati.addon_count = 0
            return seati
        end
    end
    return self.seats[self.maxraisepos]
end

function Room:getNoFoldCnt()
    local nfold = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if
            seat and seat.isplaying and
                seat.chiptype ~= pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD")
         then
            nfold = nfold + 1
        end
    end
    return nfold
end

function Room:moveButton()
    local idxes = {}
    for k, v in ipairs(self.seats) do
        if v.isplaying then
            table.insert(idxes, k)
        end
    end
    if #idxes > 0 then
        self.buttonpos = idxes[rand.rand_between(1, #idxes)]
    end
    log.info(
        "idx(%s,%s,%s) movebutton:%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self.buttonpos,
        self.current_betting_pos
    )
end

function Room:getGameId()
    return self.gameId + 1
end

function Room:stand(seat, uid, stype)
    log.info(
        "idx(%s,%s,%s) stand uid,sid:%s,%s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        seat.sid,
        tostring(stype),
        tostring(seat.totalbuyin)
    )
    local backup_seat = seat
    local user = self.users[uid]
    if seat and user then
        if
            self.state >= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish") and
                seat.isplaying
         then
            -- 统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[uid] = self.sdata.users[uid] or {}
            self.sdata.users[uid].totalpureprofit = self.sdata.users[uid].totalpureprofit or seat.room_delta
            self.sdata.users[uid].ugameinfo = self.sdata.users[uid].ugameinfo or {}
            self.sdata.users[uid].ugameinfo.texas = self.sdata.users[uid].ugameinfo.texas or {}
            self.sdata.users[uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[uid].ugameinfo.texas.inctotalwinhands =
                self.sdata.users[uid].ugameinfo.texas.inctotalwinhands or 0
            self.sdata.users[uid].ugameinfo.texas.leftchips = seat.chips
            self.sdata.users[uid].extrainfo =
                cjson.encode(
                {
                    ip = user.ip or "",
                    api = user.api or "",
                    roomtype = self.conf.roomtype,
                    roundid = user.roundId,
                    groupcard = cjson.encode(seat:formatGroupCards())
                }
            )

            self.reviewlogitems[seat.uid] =
                self.reviewlogitems[seat.uid] or
                {
                    player = {
                        uid = seat.uid,
                        username = user.username or "",
                        nickurl = user.nickurl or "",
                        balance = seat.chips
                    },
                    sid = seat.sid,
                    handcards = g.copy(seat.groupcards),
                    win = -seat.score * self.conf.ante,
                    showcard = false,
                    wintype = 1,
                    score = seat.score
                }
        end

        if seat.isplaying then
            backup_seat = {
                uid = seat.uid,
                sid = seat.sid,
                chips = seat.chips,
                last_chips = seat.last_chips,
                isplaying = seat.isplaying,
                handcards = g.copy(seat.handcards),
                chiptype = seat.chiptype,
                chipinnum = seat.chipinnum,
                score = seat.score,
                gamecount = user.gamecount,
                buyinToMoney = seat.buyinToMoney,
                bet_timeout_count = seat.bet_timeout_count,
                intots = seat.intots,
                show = seat.show,
                room_delta = seat.room_delta
            }
        end
        backup_seat.linkid = user.linkid
        -- 备份座位数据
        user.chips = seat.chips - seat.roundmoney
        user.currentbuyin = seat.currentbuyin
        user.roundmoney = seat.roundmoney
        user.totalbuyin = seat.totalbuyin
        user.active_stand = true

        seat:stand(uid)

        pb.encode(
            "network.cmd.PBTexasPlayerStand",
            {sid = seat.sid, type = stype},
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerStand"),
                    pointer,
                    length
                )
            end
        )
        MatchMgr:getMatchById(self.conf.mid):shrinkRoom()
    end
    log.info(
        "idx(%s,%s,%s) stand uid,sid:%s,%s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        seat.sid,
        tostring(stype),
        seat.totalbuyin
    )
    return backup_seat
end

function Room:sit(seat, uid, buyinmoney, ischangetable)
    log.info(
        "idx(%s,%s,%s) sit uid %s,sid %s buyin %s %s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        seat.sid,
        buyinmoney,
        self:getUserMoney(uid)
    )
    local user = self.users[uid]
    if user then
        if buyinmoney > self:getUserMoney(uid) + user.chips then
            net.send(
                user.linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasBuyinFailed"),
                pb.encode(
                    "network.cmd.PBTexasBuyinFailed",
                    {
                        code = pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney"),
                        context = 0
                    }
                )
            )
            return
        end
        log.info(
            "idx(%s,%s,%s) sit uid %s,sid %s %s %s %s %s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            seat.sid,
            seat.totalbuyin,
            user.totalbuyin,
            user.chips,
            tostring(Utils:isRobot(user.api))
        )
        seat:sit(uid, user.chips, 0, user.totalbuyin)
        local clientBuyin =
            (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante * 80 + self.conf.fee or 0))
        if clientBuyin then
            if (0x4 == (self.conf.buyin & 0x4) or Utils:isRobot(user.api)) and user.chips == 0 and user.totalbuyin == 0 then
                clientBuyin = false
                if not self:userBuyin(uid, user.linkid, {buyinMoney = buyinmoney}, true) then
                    seat:stand(uid)
                    return
                end
            else
                seat:setIsBuyining(true)
                timer.tick(
                    self.timer,
                    TimerID.TimerID_Buyin[1] + 100 + uid,
                    self.conf.buyintime * 1000,
                    onBuyin,
                    {self, uid},
                    1
                )
            end
        else
            --客户端超时站起
            seat.chips = user.chips
            user.chips = 0
        end
        log.info(
            "idx(%s,%s,%s) uid %s sid %s sit clientBuyin %s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            seat.sid,
            tostring(clientBuyin)
        )
        local seatinfo = fillSeatInfo(seat, self)
        local sitcmd = {seatInfo = seatinfo, clientBuyin = clientBuyin, buyinTime = self.conf.buyintime}
        pb.encode(
            "network.cmd.PBRummyPlayerSit",
            sitcmd,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyPlayerSit"),
                    pointer,
                    length
                )
            end
        )
        log.info(
            "idx(%s,%s,%s) player sit in seatinfo:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            cjson.encode(sitcmd)
        )

        MatchMgr:getMatchById(self.conf.mid):expandRoom()
    end
end

function Room:sendPosInfoToAll(seat, chiptype)
    local updateseat = {}
    if chiptype then
        seat.chiptype = chiptype
    end

    if seat.uid then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        pb.encode(
            "network.cmd.PBRummyUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyUpdateSeat"),
                    pointer,
                    length
                )
            end
        )
        log.info(
            "idx(%s,%s,%s) updateseat chiptype:%s seatinfo:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(chiptype),
            cjson.encode(updateseat.seatInfo)
        )
    end
end

function Room:sendPosInfoToMe(seat)
    local user = self.users[seat.uid]
    local updateseat = {}
    if user then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        updateseat.seatInfo.drawcard = seat.drawcard
        net.send(
            user.linkid,
            seat.uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyUpdateSeat"),
            pb.encode("network.cmd.PBRummyUpdateSeat", updateseat)
        )
        log.info("idx(%s,%s,%s) checkcard:%s", self.id, self.mid, tostring(self.logid), cjson.encode(updateseat))
    end
end

function Room:ready()
    if not self.ready_start_time then
        self.ready_start_time = global.ctsec()

        -- 广播准备
        local gameready = {
            readyLeftTime = TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time)
        }
        pb.encode(
            "network.cmd.PBRummyGameReady",
            gameready,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyGameReady"),
                    pointer,
                    length
                )
            end
        )
        log.info(
            "idx(%s,%s,%s) gameready:%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            self:getPlayingSize(),
            cjson.encode(gameready)
        )
    end
    if global.ctsec() - self.ready_start_time >= TimerID.TimerID_Ready[2] then
        timer.cancel(self.timer, TimerID.TimerID_Check[1])
        self.ready_start_time = nil
        self:start()
    end
end

function Room:start()
    self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Start")
    self:reset()
    self.gameId = self:getGameId()
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec()
    self.logid = self.has_started and self.statistic:genLogId(self.starttime) or self.logid
    self.has_started = self.has_started or true

    -- 玩家状态，金币数等数据初始化
    self:moveButton()

    self.current_betting_pos = self.buttonpos
    log.info(
        "idx(%s,%s,%s) start ante:%s gameId:%s betpos:%s robotcnt:%s logid:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self.conf.ante,
        self.gameId,
        self.current_betting_pos,
        self:robotCount(),
        tostring(self.logid)
    )

    self.poker:start()

    --给机器人两条命
    self.robot_handcards = nil
    local _, r = self:count()
    local pro = rand.rand_between(1, 10000)
    local robotconf = ROBOTAI_CONF[self.conf.robotid] or {}
    if r > 0 and pro <= (robotconf.firerate or 0) then
        log.info(
            "idx(%s,%s,%s) trigger robotfire pro %s firerate %s",
            self.id,
            self.mid,
            tostring(self.logid),
            pro,
            robotconf.firerate or 0
        )
        local handcards = {}
        local robot_handcards = {0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e}
        local color = rand.rand_between(1, 4)
        local count = rand.rand_between(1, 9)
        for i = count, count + 3 do
            table.insert(handcards, (color << 8) | robot_handcards[i])
        end
        color = (color + 1) % 4
        count = rand.rand_between(1, 9)
        for i = count, count + 4 do
            table.insert(handcards, (color << 8) | robot_handcards[i])
        end
        self.robot_handcards = self.poker:removes(handcards)
    end
    -- GameLog
    --self.boardlog:appendStart(self)
    -- 服务费
    for k, v in ipairs(self.seats) do
        if v.uid and v.isplaying then
            if self.conf and self.conf.fee and v.chips > self.conf.fee then
                v.last_chips = v.chips
                v.chips = v.chips - self.conf.fee
                v.room_delta = v.room_delta - self.conf.fee
                -- 统计
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
                self.sdata.users[v.uid].totalfee = self.conf.fee
            end
            local user = self.users[v.uid]
            if user then
                user.gamecount = (user.gamecount or 0) + 1 -- 统计数据
            end
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].sid = k
            self.sdata.users[v.uid].username = user and user.username or ""
            self.sdata.users[v.uid].extrainfo =
                cjson.encode(
                {
                    ip = user and user.ip or "",
                    api = user and user.api or "",
                    roomtype = self.conf.roomtype,
                    roundid = user.roundId
                }
            )
            if k == self.buttonpos then
                self.sdata.users[v.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
            else
                self.sdata.users[v.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
            end
        end
    end

    -- 广播开赛
    local gamestart = {
        gameId = self.gameId,
        gameState = self.state,
        buttonSid = self.buttonpos,
        ante = self.conf.ante,
        minChip = self.conf.minchip,
        tableStarttime = self.starttime,
        seats = fillSeats(self),
        discardCard = self.poker:getTopFoldCard(),
        magicCard = self.poker:getMagicCard(),
        magicCardList = g.copy(self.poker:getMagicCardList())
    }
    pb.encode(
        "network.cmd.PBRummyGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyGameStart"),
                pointer,
                length
            )
        end
    )
    log.info(
        "idx(%s,%s,%s) gamestart:%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self:getPlayingSize(),
        cjson.encode(gamestart)
    )

    -- 数据统计
    self.sdata.stime = self.starttime
    self.sdata.gameinfo = self.sdata.gameinfo or {}
    self.sdata.gameinfo.texas = self.sdata.gameinfo.texas or {}
    self.sdata.gameinfo.texas.maxplayers = self.conf.maxuser
    self.sdata.gameinfo.texas.curplayers = self:getSitSize()
    self.sdata.gameinfo.texas.ante = self.conf.ante
    self.sdata.jp = {minichips = self.conf.minchip}
    self.sdata.extrainfo =
        cjson.encode(
        {
            buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0,
            ante = self.conf.ante,
            magiccard = self.poker:getMagicCard() & 0xFFFF
        }
    )

    -- 底注
    self:dealPreChips()
end

function Room:checkCanChipin(seat, type)
    return seat and seat.uid and seat.isplaying and
        ((seat.sid == self.current_betting_pos and
            seat.chiptype ~= pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD")) or
            (type == seat.chiptype and type == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARE")) or
            (type == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD")))
end

function Room:checkFinish()
    local isallfold = self:isAllFold()
    if isallfold then
        self.finishstate = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish")

        if self.m_winner_sid == 0 then
            self.m_winner_sid = self:getNonFoldSeats()[1].sid
        end
        log.info(
            "idx(%s,%s,%s) chipin isallfold:%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(isallfold),
            self.m_winner_sid
        )

        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_Settlement[1])
        onPotAnimation(self)
        --timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
        return true
    end
    return false
end

local function onSettlement(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Settlement[1])
        self.declare_start_time = nil
        for _, v in ipairs(self.seats) do
            if v.isplaying and v.score == 0 and v.sid ~= self.m_winner_sid then
                v:chipin(pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARED"), 0)
                v.score = self.poker:calScore(v:getGroupCards())
                v.chips = v.chips - v.score * self.conf.ante
                v.room_delta = v.room_delta - v.score * self.conf.ante
                self.pot = self.pot + v.score * self.conf.ante

                log.info(
                    "idx(%s,%s,%s) has declare and lose score : %s,%s,%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    v.score,
                    v.room_delta,
                    self.pot
                )
                self:sendPosInfoToAll(v)
            end
        end
        self:finish()
    end
    g.call(doRun)
end

function Room:chipin(uid, type, value)
    local seat = self:getSeatByUid(uid)

    log.info(
        "idx(%s,%s,%s) chipin pos:%s uid:%s type:%s value:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        seat.sid,
        seat.uid and seat.uid or 0,
        type,
        value
    )

    local res = false

    --drop handcards
    local function fold_func(seat, type, value)
        if not seat.is_drawcard then
            seat.score = RUMMYCONF.NOT_DRAW_SCORE
        elseif seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARE") then
            seat.score = self.poker:calScore(seat:getGroupCards())
        else
            seat.score = RUMMYCONF.HAS_DRAWED_SCORE
        end
        seat:chipin(type, 0)
        seat.chips = seat.chips - seat.score * self.conf.ante
        seat.room_delta = seat.room_delta - seat.score * self.conf.ante
        self.pot = self.pot + seat.score * self.conf.ante
        seat.drawcard = 0
        res = true
        self.sdata.users = self.sdata.users or {}
        self.sdata.users[uid] = self.sdata.users[uid] or {}
        self.sdata.users[uid].ugameinfo = {texas = {river_bets = {{uid = seat.uid, bv = 0, bt = type}}}}
        self.sdata.users[uid].ugameinfo.texas.incpreflopfoldhands = 1
        return true
    end

    local function draw_func(seat, type, value)
        local reshuffle
        if
            seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW1") or
                seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW2") or
                seat.drawcard > 0
         then
            log.error(
                "idx(%s,%s,%s) draw_func uid (%s,%s) has drawed card %s",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                seat.sid,
                seat.drawcard
            )
            return false
        end
        if type == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW1") then
            seat.drawcard, reshuffle = self.poker:draw(true)
            seat.is_drawcard = seat.is_drawcard or true
            seat:chipin(type, 0)
            self:sendPosInfoToMe(seat)
        elseif type == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW2") then
            seat.is_drawcard = seat.is_drawcard or true
            seat:chipin(type, 0)
            seat.drawcard, reshuffle = self.poker:draw(false)
        else
            log.error(
                "idx(%s,%s,%s) draw_func uid (%s,%s) has no drawed card type",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                seat.sid
            )
            return false
        end

        if reshuffle then
            local msg = {
                discardCard = self.poker:getTopFoldCard(),
                foldcards = self.poker:getLeftFoldCardCnt(),
                leftcards = self.poker:getLeftCardsCnt()
            }
            pb.encode(
                "network.cmd.PBRummyReShuffleCard",
                msg,
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyReShuffleCard"),
                        pointer,
                        length
                    )
                end
            )
            log.info(
                "idx(%s,%s,%s) uid (%s,%s) reshuffle cards %s",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                seat.sid,
                cjson.encode(msg)
            )
        end
        return true
    end

    local function discard_or_finish_func(seat, type, value)
        if not seat.drawcard or seat.drawcard == 0 and not seat:isChipinTimeout() then
            log.error(
                "idx(%s,%s,%s) discard_or_finish_func uid %s has not drawed card",
                self.id,
                self.mid,
                tostring(self.logid),
                uid
            )
            return false
        end
        if seat.drawcard == value then
        else
            local idx = seat:getIdxByCardValue(value)
            if idx > 0 then
                local tmpcard = seat.handcards[idx]
                seat.handcards[idx] = seat.drawcard
                seat.drawcard = tmpcard
            else
                log.error(
                    "idx(%s,%s,%s) discard_or_finish_func uid (%s,%s) not find a valid card %s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    uid,
                    seat.sid,
                    tostring(value)
                )
            end
        end

        seat:chipin(type, seat.drawcard)
        if seat.drawcard > 0 then
            self.poker:discard(seat.drawcard)
            local ok = false
            for _, v in ipairs(seat.groupcards) do
                for kk, vv in ipairs(v.cards) do
                    if seat.drawcard == vv then
                        table.remove(v.cards, kk)
                        ok = true
                        break
                    end
                end
                if ok then
                    break
                end
            end
            log.info(
                "idx(%s,%s,%s) save cards %s,%s",
                self.id,
                self.mid,
                tostring(self.logid),
                tostring(ok),
                cjson.encode(seat.groupcards)
            )
        end
        res = true

        --在发送Finish之前需要先发送存档信息
        if type == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FINISH") then
            res = false
            local is_the_same = seat:isTheSameHandCard()
            if is_the_same then
                --检测剩下三张以内的赖子作为一组
                local score = self.poker:calScore(seat:getGroupCards())
                log.info(
                    "idx(%s,%s,%s) uid(%s,%s) has finish and win score : %s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    uid,
                    seat.sid,
                    score
                )
                if score == 0 then --赢了
                    seat.score = score
                    self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Declare")
                    self.declare_start_time = global.ctms()
                    timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                    self.m_winner_sid = seat.sid
                    timer.tick(
                        self.timer,
                        TimerID.TimerID_Settlement[1],
                        TimerID.TimerID_Settlement[2],
                        onSettlement,
                        self
                    )
                    for _, v in ipairs(self.seats) do
                        if v ~= seat and v.isplaying then
                            v:chipin(pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARE"), 0)
                        end
                    end
                else
                    log.error(
                        "idx(%s,%s,%s) uid(%s,%s) score %s not win",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        uid,
                        seat.sid,
                        score
                    )
                    seat:chipin(pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DISCARD"), seat.drawcard)
                    res = true
                end
            else
                log.error(
                    "idx(%s,%s,%s) uid(%s,%s) it's not the same cards gc %s hc %s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    uid,
                    seat.sid,
                    cjson.encode(seat.groupcards),
                    cjson.encode(seat.handcards)
                )
                seat:chipin(pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DISCARD"), seat.drawcard)
                res = true
            end
        end
        self:sendPosInfoToAll(seat)
        seat.drawcard = 0
        return false
    end

    local function declare_func(seat, type, value)
        if seat.chiptype ~= pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARE") then
            log.error(
                "idx(%s,%s,%s) uid(%s,%s) has not in declare state : %s",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                seat.sid
            )
            return false
        end
        seat:chipin(pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARED"), 0)
        seat.score = self.poker:calScore(seat:getGroupCards())
        seat.chips = seat.chips - seat.score * self.conf.ante
        seat.room_delta = seat.room_delta - seat.score * self.conf.ante
        self.pot = self.pot + seat.score * self.conf.ante
        log.info(
            "idx(%s,%s,%s) uid(%s,%s) has declared and lose score : %s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            seat.sid,
            seat.score
        )
        if seat.score >= 40 then
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[uid] = self.sdata.users[uid] or {ugameinfo = {texas = {}}}
            self.sdata.users[uid].ugameinfo = self.sdata.users[uid].ugameinfo or {texas = {}}
            self.sdata.users[uid].ugameinfo.texas.incpreflopraisehands = 1
        end
        self:sendPosInfoToAll(seat)
        self:checkFinish()
        return false
    end

    local switch = {
        [pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD")] = fold_func,
        [pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW1")] = draw_func,
        [pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DRAW2")] = draw_func,
        [pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DISCARD")] = discard_or_finish_func,
        [pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FINISH")] = discard_or_finish_func,
        [pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARE")] = declare_func
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, tostring(self.logid), uid, type)
        return false
    end

    -- 真正操作chipin
    if chipin_func(seat, type, value) then
        log.info("idx(%s,%s,%s) chipin_func chipintype:%s", self.id, self.mid, tostring(self.logid), type)
        self:sendPosInfoToAll(seat)
    end

    -- GameLog
    --self.boardlog:appendChipin(self, seat)
    return res
end

function Room:userchipin(uid, type, values, client)
    log.info(
        "idx(%s,%s,%s) userchipin: uid %s, type %s, value %s",
        self.id,
        self.mid,
        tostring(self.logid),
        tostring(uid),
        tostring(type),
        tostring(values)
    )
    uid = uid or 0
    type = type or 0
    values = values or 0
    if
        self.state == pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None") or
            self.state == pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish")
     then
        log.info(
            "idx(%s,%s,%s) uid %s user chipin state invalid:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            self.state
        )
        return false
    end
    local chipin_seat = self:getSeatByUid(uid)
    if not chipin_seat then
        log.info("idx(%s,%s,%s) uid %s invalid chipin seat", self.id, self.mid, tostring(self.logid), uid)
        return false
    end
    if
        chipin_seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") or
            chipin_seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FINISH")
     then
        log.info(
            "idx(%s,%s,%s) chipin (%s,%s) has folded or finish:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            chipin_seat.sid,
            chipin_seat.chiptype
        )
        return false
    end

    if not self:checkCanChipin(chipin_seat, type) then
        log.info("idx(%s,%s,%s) invalid chipin pos:%s", self.id, self.mid, tostring(self.logid), chipin_seat.sid)
        return false
    end
    if self.conf.minchip == 0 then
        log.info("idx(%s,%s,%s) chipin minchip invalid uid:%s", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    if client then
        chipin_seat.bet_timeout_count = 0
    end
    local chipin_result = self:chipin(uid, type, values)
    if not chipin_result then
        --log.info("idx(%s,%s,%s) chipin failed uid:%s",self.id,self.mid,uid)
        return false
    end

    if self:checkFinish() then
        return true
    end

    if self.current_betting_pos ~= chipin_seat.sid then
        return true
    end

    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    local next_seat = self:getNextActionPosition(self.seats[self.current_betting_pos])
    log.info(
        "idx(%s,%s,%s) next_seat uid:%s chipin_pos:%s chipin_uid:%s chiptype:%s chips:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        next_seat and next_seat.uid or 0,
        tostring(self.current_betting_pos),
        self.seats[self.current_betting_pos].uid,
        self.seats[self.current_betting_pos].chiptype,
        chipin_seat.chips
    )

    self:betting(next_seat)

    return true
end

function Room:userGroupSave(uid, linkid, rev)
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) invalid chipin seat", self.id, self.mid, tostring(self.logid))
        return false
    end

    if g.isEmptyTable(rev.group) then
        log.error("idx(%s,%s,%s) user %s group save failed, empty group", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    local debug_table = {}
    for _, v in ipairs(rev.group) do
        local str = ""
        for _, vv in ipairs(v.cards) do
            str = str .. string.format("0x%x,", vv)
        end
        if str then
            table.insert(debug_table, str)
        end
    end

    seat.groupcards = rev.group
    log.info(
        "idx(%s,%s,%s) user %s group save:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        cjson.encode(debug_table)
    )
    return true
end

function Room:getNextState()
    local oldstate = self.state

    if oldstate == pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_PreChips") then
        self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_HandCard")
        self:dealHandCards()
    elseif oldstate == pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish") then
        self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_None")
    end

    log.info("idx(%s,%s,%s) State Change: %s => %s", self.id, self.mid, tostring(self.logid), oldstate, self.state)
end

local function onStartHandCards(self)
    local function doRun()
        log.info(
            "idx(%s,%s,%s) onStartHandCards button_pos:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            self.buttonpos
        )

        self:getNextState()
    end
    g.call(doRun)
end

function Room:dealPreChips()
    log.info("idx(%s,%s,%s) dealPreChips ante:%s", self.id, self.mid, tostring(self.logid), self.conf.ante)
    self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_PreChips")
    onStartHandCards(self)
end

--deal handcards
function Room:dealHandCards()
    pb.encode(
        "network.cmd.PBRummyDealCard",
        {},
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyDealCard"),
                pointer,
                length
            )
        end
    )
    local cfgcardidx = 0
    for k, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user then
            if seat.isplaying then
                cfgcardidx = cfgcardidx + 1
                if self.config_switch and RUMMYCONF.CONFCARDS.groupcards[cfgcardidx] then
                    for _, v in ipairs(RUMMYCONF.CONFCARDS.groupcards[cfgcardidx]) do
                        for _, vv in ipairs(v) do
                            table.insert(seat.handcards, vv)
                        end
                    end
                    seat.groupcards = g.copy(RUMMYCONF.CONFCARDS.groupcards[cfgcardidx])
                else
                    if Utils:isRobot(user.api) and self.robot_handcards then
                        seat.handcards = g.copy(self.robot_handcards)
                        local leftcards = self.poker:getNCard(13 - #seat.handcards)
                        for _, v in ipairs(leftcards) do
                            table.insert(seat.handcards, v)
                        end
                    else
                        seat.handcards = self.poker:getNCard(13)
                    end
                    seat.groupcards = self.poker:group(seat.handcards)
                end

                local cards = {
                    cards = {{sid = k, handcards = g.copy(seat.handcards), group = g.copy(seat.groupcards)}}
                }
                net.send(
                    user.linkid,
                    seat.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyDealCard"),
                    pb.encode("network.cmd.PBRummyDealCard", cards)
                )

                log.info(
                    "idx(%s,%s,%s) sid:%s,uid:%s deal handcard:%s,%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    k,
                    seat.uid,
                    cjson.encode(cards),
                    cjson.encode(seat.groupcards)
                )

                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].sid = k
                self.sdata.users[seat.uid].username = user.username
                if k == self.buttonpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
                else
                    self.sdata.users[seat.uid].role =
                        pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
                end
            end
        end
    end
    -- GameLog
    --self.boardlog:appendPreFlop(self)

    timer.tick(
        self.timer,
        TimerID.TimerID_HandCardsAnimation[1],
        TimerID.TimerID_HandCardsAnimation[2],
        onHandCardsAnimation,
        self
    )
end

function Room:isAllFold()
    local fold_count = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if
                seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") or
                    seat.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DECLARED")
             then
                fold_count = fold_count + 1
            end
        end
    end
    if fold_count == self:getPlayingSize() or fold_count + 1 == self:getPlayingSize() then
        return true
    else
        return false
    end
end

function Room:getOnePot()
    return self.pot
end

function Room:getNonFoldSeats()
    local nonfoldseats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype ~= pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") then
                table.insert(nonfoldseats, seat)
            end
        end
    end
    return nonfoldseats
end

local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos]
        log.info(
            "idx(%s,%s,%s) onBettingTimer over time bettingpos:%s uid:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            self.current_betting_pos,
            current_betting_seat.uid or 0
        )
        local user = self.users[current_betting_seat.uid]
        if current_betting_seat:isChipinTimeout() then
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            current_betting_seat.bet_timeout_count = current_betting_seat.bet_timeout_count + 1
            self:userchipin(
                current_betting_seat.uid,
                pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_DISCARD"),
                current_betting_seat.drawcard
            )
            -- 超时两轮自动离开
            if user and current_betting_seat.bet_timeout_count >= 3 then
                if Utils:isRobot(user.api) then
                    self:userLeave(current_betting_seat.uid, user.linkid)
                else
                    self:userStand(current_betting_seat.uid, user.linkid)
                end
            end
        end
    end
    g.call(doRun)
end

function Room:betting(seat)
    if not seat then
        return false
    end
    seat.bettingtime = global.ctsec()
    self.current_betting_pos = seat.sid
    log.info(
        "idx(%s,%s,%s) it's betting pos:%s uid:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self.current_betting_pos,
        tostring(seat.uid)
    )

    local function notifyBetting()
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_BETING"))
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self)
    end

    notifyBetting()
end

function Room:finish()
    log.info("idx(%s,%s,%s) finish", self.id, self.mid, tostring(self.logid))

    self.state = pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish")
    self.declare_start_time = nil
    self.endtime = global.ctsec()
    self.t_msec = self:getPlayingSize() * 1000 + 5000

    -- m_seats.finish start
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    local srcpot = self:getOnePot()
    local pot, potrate = self:potRake(srcpot)

    log.info("idx(%s,%s,%s) finish pot:%s %s", self.id, self.mid, tostring(self.logid), srcpot, pot)
    self.winner_seats = self.winner_seats or self.seats[self.m_winner_sid]
    self.winner_seats.chips = self.winner_seats.chips + pot
    self.winner_seats.room_delta = self.winner_seats.room_delta + pot

    local FinalGame = {
        potInfos = {},
        potMoney = pot,
        readyLeftTime = (self.t_msec / 1000 + TimerID.TimerID_Ready[2] + TimerID.TimerID_Check[2] / 1000) -
            (global.ctsec() - self.endtime)
    }

    local reviewlog = {
        buttonsid = self.buttonpos,
        ante = self.conf.ante,
        pot = self:getOnePot(),
        items = {},
        magicCardList = g.copy(self.poker:getMagicCardList())
    }
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].totalpureprofit = v.room_delta
            local win = -v.score * self.conf.ante
            local totalbets = math.abs(win)
            if k == self.m_winner_sid then
                win = pot
                self.sdata.users[v.uid].totalfee = self.conf.fee + potrate
                totalbets = 0
            end
            log.info(
                "idx(%s,%s,%s) chips change uid:%s chips:%s last_chips:%s totalwin:%s, roomdelta:%s",
                self.id,
                self.mid,
                tostring(self.logid),
                v.uid,
                v.chips,
                v.last_chips,
                win,
                v.room_delta
            )

            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {}
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (v.room_delta > 0) and 1 or 0
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips
            self.sdata.users[v.uid].extrainfo =
                cjson.encode(
                {
                    ip = user.ip or "",
                    api = user.api or "",
                    roomtype = self.conf.roomtype,
                    groupcard = cjson.encode(v:formatGroupCards()),
                    roundid = user.roundId,
                    totalbets = totalbets
                }
            )

            table.insert(
                FinalGame.potInfos,
                {
                    sid = v.sid,
                    winMoney = v.room_delta,
                    seatMoney = v.chips,
                    score = v.score,
                    winType = v.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") and 1 or
                        (k == self.m_winner_sid and 0 or 2),
                    nickname = user.username,
                    nickurl = user.nickurl,
                    group = v.groupcards
                }
            )
            table.insert(
                reviewlog.items,
                {
                    player = {
                        uid = v.uid,
                        username = user.username or "",
                        nickurl = user.nickurl or ""
                    },
                    sid = k,
                    handcards = g.copy(v.groupcards),
                    wintype = v.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") and 1 or
                        (k == self.m_winner_sid and 0 or 2),
                    win = v.room_delta,
                    score = v.score,
                    showcard = true
                }
            )
            self.reviewlogitems[v.uid] = nil
        end
    end
    for _, v in pairs(self.reviewlogitems) do
        table.insert(reviewlog.items, v)
        table.insert(
            FinalGame.potInfos,
            {
                sid = v.sid,
                winMoney = v.win,
                seatMoney = v.player.balance,
                score = math.floor(v.win / self.conf.ante),
                winType = v.chiptype == pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD") and 1 or
                    (v.win > 0 and 0 or 2),
                nickname = v.player.username,
                nickurl = v.player.nickurl,
                group = v.handcards
            }
        )
    end
    self.reviewlogs:push(reviewlog)
    self.reviewlogitems = {}
    self.winner_seats = nil

    -- 广播结算
    log.info("idx(%s,%s,%s) PBRummyFinalGame %s", self.id, self.mid, tostring(self.logid), cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBRummyFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyFinalGame"),
                pointer,
                length
            )
        end
    )

    self.m_winner_sid = 0
    self.sdata.etime = self.endtime
    self.statistic:appendLogs(self.sdata, self.logid)
    timer.tick(self.timer, TimerID.TimerID_OnFinish[1], self.t_msec, onFinish, self)
end

function Room:sendUpdatePotsToAll()
    local updatepots = {pot = self:getOnePot()}
    pb.encode(
        "network.cmd.PBRummyUpdatePots",
        updatepots,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyUpdatePots"),
                pointer,
                length
            )
        end
    )

    return true
end

function Room:check()
    if global.stopping() then
        timer.destroy(self.timer)
        return
    end
    local cnt = 0
    for k, v in ipairs(self.seats) do
        if v.isplaying then
            cnt = cnt + 1
        end
    end
    log.info("idx(%s,%s,%s) room:check playing size=%s", self.id, self.mid, tostring(self.logid), cnt)
    if cnt <= 1 then
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
end

function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req stand up uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local s = self:getSeatByUid(uid)
    local user = self.users[uid]
    if s and user then
        if
            s.isplaying and self.state >= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD"), 0)
                self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
            else
                self:chipin(uid, pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_FOLD"), 0)
                self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
                self:checkFinish()
            end
        else
            self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
        end

        -- 最大加注位站起
        log.info(
            "idx(%s,%s,%s) s.sid %s maxraisepos %s",
            self.id,
            self.mid,
            tostring(self.logid),
            s.sid,
            self.maxraisepos
        )
    else
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasStandFailed"),
            pb.encode(
                "network.cmd.PBTexasStandFailed",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")}
            )
        )
    end
end

function Room:userSit(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req sit down uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid)
    local dsts = self.seats[rev.sid]
    if not user or srcs or not dsts or (dsts and dsts.uid) --[[or not is_buyin_ok ]] then
        log.info(
            "idx(%s,%s,%s) sit failed uid:%s srcuid:%s dstuid:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            srcs and srcs.uid or 0,
            dsts and dsts.uid or 0
        )
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitFailed"),
            pb.encode(
                "network.cmd.PBTexasSitFailed",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")}
            )
        )
    else
        self:sit(dsts, uid, self:getRecommandBuyin(self:getUserMoney(uid)))
    end
end

function Room:userBuyin(uid, linkid, rev, system)
    log.info(
        "idx(%s,%s,%s) userBuyin uid %s buyinmoney %s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        tostring(rev.buyinMoney)
    )

    local buyinmoney = rev.buyinMoney or 0
    local function handleFailed(code)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasBuyinFailed"),
            pb.encode("network.cmd.PBTexasBuyinFailed", {code = code, context = rev.context})
        )
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) uid %s userBuyin invalid user", self.id, self.mid, tostring(self.logid), uid)
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidUser"))
        return false
    end

    if user.buyin and coroutine.status(user.buyin) ~= "dead" then
        log.info("idx(%s,%s,%s) uid %s userBuyin is buying", self.id, self.mid, tostring(self.logid), uid)
        return false
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) userBuyin invalid seat", self.id, self.mid, tostring(self.logid))
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidSeat"))
        return false
    end
    if Utils:isRobot(user.api) and (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.ante) then
        buyinmoney = self.conf.maxbuyinbb * self.conf.ante - (seat.chips - seat.roundmoney)
    end
    if
        (buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.ante) or
            (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.ante) or
            (buyinmoney == 0 and (seat.chips - seat.roundmoney) >= self.conf.maxbuyinbb * self.conf.ante)
     then
        log.info(
            "idx(%s,%s,%s) userBuyin over limit: minbuyinbb %s, maxbuyinbb %s, chips %s",
            self.id,
            self.mid,
            tostring(self.logid),
            self.conf.minbuyinbb,
            self.conf.maxbuyinbb,
            seat.chips
        )
        if (buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.ante) then
            handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney"))
        else
            handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_OverLimit"))
        end
        return false
    end

    user.buyin =
        coroutine.create(
        function(user)
            log.info(
                "idx(%s,%s,%s) uid %s userBuyin start buyinmoney %s seatchips %s money %s coin %s",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                buyinmoney,
                seat.chips,
                user.money,
                user.coin
            )
            -- 扣钱买筹码
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                -1 * buyinmoney,
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_BUYINCHIPS"),
                linkid,
                self.conf.roomtype,
                self.id,
                self.mid,
                {
                    api = "transfer",
                    sid = user.sid,
                    userId = user.userId,
                    transactionId = g.uuid(),
                    roundId = user.roundId
                }
            )
            local ok = coroutine.yield()
            timer.cancel(self.timer, TimerID.TimerID_Buyin[1] + 100 + uid)
            if not ok then
                log.info(
                    "idx(%s,%s,%s) userBuyin not enough money: buyinmoney %s, user money %s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    buyinmoney,
                    self:getUserMoney(uid)
                )
                handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney"))
                return false
            end
            seat:buyin(buyinmoney)
            seat:setIsBuyining(false)
            user.totalbuyin = seat.totalbuyin
            seat:buyinToChips()

            pb.encode(
                "network.cmd.PBTexasPlayerBuyin",
                {
                    sid = seat.sid,
                    chips = seat.chips > seat.roundmoney and seat.chips - seat.roundmoney or 0,
                    money = self:getUserMoney(uid),
                    context = rev.context,
                    immediately = true
                },
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerBuyin"),
                        pointer,
                        length
                    )
                end
            )
            log.info(
                "idx(%s,%s,%s) uid %s userBuyin result buyinmoney %s seatchips %s money %s coin %s",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                buyinmoney,
                seat.chips,
                user.money,
                user.coin
            )
            return true
        end
    )
    coroutine.resume(user.buyin, user)
    return true
end

function Room:userChat(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userChat:%s", self.id, self.mid, tostring(self.logid), uid)
    if not rev.type or not rev.content then
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) user:%s is not in room", self.id, self.mid, tostring(self.logid), uid)
        return
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) user:%s is not in seat", self.id, self.mid, tostring(self.logid), uid)
        return
    end
    if #rev.content > 200 then
        log.info("idx(%s,%s,%s) content over length limit", self.id, self.mid, tostring(self.logid))
        return
    end
    pb.encode(
        "network.cmd.PBGameNotifyChat_N",
        {sid = seat.sid, type = rev.type, content = rev.content},
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyChat"),
                pointer,
                length
            )
        end
    )
end

function Room:userTool(uid, linkid, rev)
    log.info(
        "idx(%s,%s,%s) userTool:%s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        tostring(rev.fromsid),
        tostring(rev.tosid)
    )
    local function handleFailed(code)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameToolSendResp"),
            pb.encode(
                "network.cmd.PBGameToolSendResp_S",
                {
                    code = code or 0,
                    toolID = rev.toolID,
                    leftNum = 0
                }
            )
        )
    end
    if not self.seats[rev.fromsid] or self.seats[rev.fromsid].uid ~= uid then
        log.info("idx(%s,%s,%s) invalid fromsid %s", self.id, self.mid, tostring(self.logid), rev.fromsid)
        handleFailed()
        return
    end
    if not self.seats[rev.tosid] or self.seats[rev.tosid].uid == 0 then
        log.info("idx(%s,%s,%s) invalid tosid %s", self.id, self.mid, tostring(self.logid), rev.tosid)
        handleFailed()
        return
    end
    local seat = self.seats[rev.fromsid]
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) invalid user %s", self.id, self.mid, tostring(self.logid), uid)
        handleFailed()
        return
    end
    if Utils:isRobot(user.api) then
        if seat.chips < (self.conf and self.conf.toolcost or 0) + self.conf.ante * RUMMYCONF.MAX_SCORE_VALUE then
            return
        end
        seat.chips = seat.chips - self.conf.toolcost
        pb.encode(
            "network.cmd.PBGameNotifyTool_N",
            {
                fromsid = rev.fromsid,
                tosid = rev.tosid,
                toolID = rev.toolID,
                seatMoney = seat.chips
            },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyTool"),
                    pointer,
                    length
                )
            end
        )
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.toolcost or 0) then
        log.info("idx(%s,%s,%s) user use tool: not enough money %s", self.id, self.mid, tostring(self.logid), uid)
        handleFailed(1)
        return
    end

    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s,%s) uid %s coroutine is expensing", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    if self.conf and self.conf.toolcost > 0 then
        user.expense =
            coroutine.create(
            function(user)
                Utils:walletRpc(
                    uid,
                    user.api,
                    user.ip,
                    -1 * self.conf.toolcost,
                    pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_INTERACTTOOL"),
                    linkid,
                    self.conf.roomtype,
                    self.id,
                    self.mid,
                    {
                        api = "expense",
                        sid = user.sid,
                        userId = user.userId,
                        transactionId = g.uuid()
                    }
                )
                local ok = coroutine.yield()
                if not ok then
                    log.info(
                        "idx(%s,%s,%s) expense uid %s not enough money",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        uid
                    )
                    handleFailed(1)
                    return false
                end
                pb.encode(
                    "network.cmd.PBGameNotifyTool_N",
                    {
                        fromsid = rev.fromsid,
                        tosid = rev.tosid,
                        toolID = rev.toolID,
                        seatMoney = seat.chips
                    },
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyTool"),
                            pointer,
                            length
                        )
                    end
                )
            end
        )
        timer.tick(
            user.TimerID_Expense,
            TimerID.TimerID_Expense[1],
            TimerID.TimerID_Expense[2],
            onExpenseTimeout,
            {uid, self}
        )
        coroutine.resume(user.expense, user)
    end
end

function Room:userReview(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userReview uid %s", self.id, self.mid, tostring(self.logid), uid)

    local t = {
        reviews = {}
    }
    local function resp()
        log.info("idx(%s,%s,%s) PBRummyReviewResp %s", self.id, self.mid, tostring(self.logid), cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RummyReviewResp"),
            pb.encode("network.cmd.PBRummyReviewResp", t)
        )
    end

    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not user then
        log.info("idx(%s,%s,%s) userReview invalid user", self.id, self.mid, tostring(self.logid))
        resp()
        return
    end

    for _, reviewlog in ipairs(self.reviewlogs:getLogs()) do
        table.insert(t.reviews, reviewlog)
    end
    resp()
end

function Room:userPreOperate(uid, linkid, rev)
    log.info(
        "idx(%s,%s,%s) userRreOperate uid %s preop %s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        tostring(rev.preop)
    )

    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not user then
        log.info("idx(%s,%s,%s) userPreOperate invalid user", self.id, self.mid, tostring(self.logid))
        return
    end
    if not seat then
        log.info("idx(%s,%s,%s) userPreOperate invalid seat", self.id, self.mid, tostring(self.logid))
        return
    end
    if
        not rev.preop or rev.preop < pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None") or
            rev.preop >= pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny")
     then
        log.info("idx(%s,%s,%s) userPreOperate invalid type", self.id, self.mid, tostring(self.logid))
        return
    end

    seat:setPreOP(rev.preop)

    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPreOperateResp"),
        pb.encode(
            "network.cmd.PBTexasPreOperateResp",
            {
                preop = seat:getPreOP()
            }
        )
    )
end

function Room:userAddTime(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req addtime uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local function handleFailed(code)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasAddTimeResp"),
            pb.encode(
                "network.cmd.PBTexasAddTimeResp",
                {
                    idx = rev.idx,
                    code = code or 0
                }
            )
        )
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) user add time: seat not valid", self.id, self.mid, tostring(self.logid))
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) user add time: user not valid", self.id, self.mid, tostring(self.logid))
        return
    end
    if self.current_betting_pos ~= seat.sid then
        log.info("idx(%s,%s,%s) user add time: user is not betting pos", self.id, self.mid, tostring(self.logid))
        return
    end
    --print(seat, user, self.current_betting_pos, seat and seat.sid)
    if self.conf and self.conf.addtimecost and seat.addon_count >= #self.conf.addtimecost then
        log.info(
            "idx(%s,%s,%s) user add time: addtime count over limit %s",
            self.id,
            self.mid,
            tostring(self.logid),
            seat.addon_count
        )
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.addtimecost[seat.addon_count + 1] or 0) then
        log.info("idx(%s,%s,%s) user add time: not enough money %s", self.id, self.mid, tostring(self.logid), uid)
        handleFailed(1)
        return
    end

    if self.conf.addtimecost[seat.addon_count + 1] > 0 then
        user.expense =
            coroutine.create(
            function(user)
                Utils:walletRpc(
                    uid,
                    user.api,
                    user.ip,
                    -1 * self.conf.addtimecost[seat.addon_count + 1],
                    pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_ADDTIME"),
                    linkid,
                    self.conf.roomtype,
                    self.id,
                    self.mid,
                    {
                        api = "expense",
                        sid = user.sid,
                        userId = user.userId,
                        transactionId = g.uuid()
                    }
                )
                local ok = coroutine.yield()
                if not ok then
                    log.info(
                        "idx(%s,%s,%s) expense uid %s not enough money",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        uid
                    )
                    handleFailed(1)
                    return false
                end
                seat.addon_time = seat.addon_time + (self.conf.addtime or 0)
                seat.addon_count = seat.addon_count + 1
                seat.total_time = seat:getChipinLeftTime()
                self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBRummyChipinType", "PBRummyChipinType_BETING"))
                timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                timer.tick(self.timer, TimerID.TimerID_Betting[1], seat.total_time * 1000, onBettingTimer, self)
            end
        )
        timer.tick(
            user.TimerID_Expense,
            TimerID.TimerID_Expense[1],
            TimerID.TimerID_Expense[2],
            onExpenseTimeout,
            {uid, self}
        )
        coroutine.resume(user.expense, user)
    end
end

function Room:userTableListInfoReq(uid, linkid, rev)
    --log.info("idx(%s,%s,%s) userTableListInfoReq:%s", self.id, self.mid, tostring(self.logid), uid)
    local t = {
        idx = {
            srvid = rev.serverid or 0,
            roomid = rev.roomid or 0,
            matchid = rev.matchid or 0,
            roomtype = self.conf.roomtype
        },
        ante = self.conf.ante,
        miniBuyin = self.conf.minbuyinbb * self.conf.ante,
        seatInfos = {}
    }
    for i = 1, #self.seats do
        local seat = self.seats[i]
        local user = self.users[seat.uid]
        if user then
            table.insert(
                t.seatInfos,
                {
                    sid = seat.sid,
                    tid = self.id,
                    playerinfo = {
                        uid = seat.uid or 0,
                        username = user and user.username or "",
                        viplv = user and user.viplv or 0,
                        gender = user and user.sex or 0,
                        nickurl = user and user.nickurl or "",
                        balance = (seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0,
                        currency = tostring(self.conf.roomtype)
                    }
                }
            )
        end
    end
    --log.info("idx(%s,%s,%s) resp userTableListInfoReq %s", self.id, self.mid, tostring(self.logid), cjson.encode(t))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasTableListInfoResp"),
        pb.encode("network.cmd.PBTexasTableListInfoResp", t)
    )
end

function Room:userJackPotResp(uid, rev)
    local roomtype, value, jackpot = rev.roomtype or 0, rev.value or 0, rev.jp or 0
    self.notify_jackpot_msg = {
        type = pb.enum_id("network.cmd.PBChatChannelType", "PBChatChannelType_Jackpot"),
        msg = cjson.encode(
            {
                nickname = rev.nickname,
                bonus = rev.value,
                roomtype = rev.roomtype,
                sb = self.ante,
                ante = self.conf.ante,
                pokertype = rev.wintype,
                gameid = global.stype()
            }
        )
    }
    local user = self.users[uid]
    if not user then
        return true
    end

    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) not in seat %s", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    log.info(
        "idx(%s,%s,%s) userJackPotResp:%s,%s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        roomtype,
        value,
        jackpot
    )
    seat.chips = seat.chips + value
    --self:sendPosInfoToAll(seat)

    if self.sdata.jp and self.sdata.jp.uid and self.sdata.jp.uid == uid and self.jackpot_and_showcard_flags then
        self.jackpot_and_showcard_flags = false
        pb.encode(
            "network.cmd.PBGameJackpotAnimation_N",
            {data = {sid = seat.sid, uid = uid, delta = value, wintype = seat.handtype}},
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyJackPotAnimation"),
                    pointer,
                    length
                )
            end
        )
        log.info(
            "idx(%s,%s,%s) jackpot animation is to be playing %s,%s,%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            seat.sid,
            uid,
            value,
            seat.handtype
        )
    end

    return true
end

function Room:getJackpotId(id)
    return id == self.conf.jpid and self or nil
end

function Room:onJackpotUpdate(jackpot)
    log.info("(%s,%s)notify client for jackpot change %s", self.id, self.mid, jackpot)
    pb.encode(
        "network.cmd.PBGameNotifyJackPot_N",
        {jackpot = jackpot},
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyJackPot"),
                pointer,
                length
            )
        end
    )
end

function Room:kickout()
    for k, v in pairs(self.users) do
        self:userLeave(k, v.linkid)
    end
end

function Room:phpMoneyUpdate(uid, rev)
    log.info("(%s,%s)phpMoneyUpdate %s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user then
        user.money = user.money + rev.money
        user.coin = user.coin + rev.coin
        log.info("(%s,%s)phpMoneyUpdate %s,%s,%s", self.id, self.mid, uid, tostring(rev.money), tostring(rev.coin))
    end
end

function Room:isInStartOrDeclardState()
    return self.state < pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Start") or
        self.state >= pb.enum_id("network.cmd.PBRummyTableState", "PBRummyTableState_Declare")
end

function Room:getUserIp(uid)
    local user = self.users[uid]
    if user then
        return user.ip
    end
    return ""
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
        local seat = self:getSeatByUid(v.uid)
        local user = self.users[v.uid]
        log.info("(%s,%s,%s) userWalletResp %s", self.id, self.mid, tostring(self.logid), cjson.encode(rev))
        if user and seat then
            if v.code > 0 then
                if
                    not self.conf.roomtype or
                        self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money")
                 then
                    user.money = v.money
                elseif self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
                    user.coin = v.coin
                end
            end
            if user.buyin and coroutine.status(user.buyin) == "suspended" then
                coroutine.resume(user.buyin, v.code > 0)
            elseif user.buyin and coroutine.status(user.buyin) == "dead" then
                Utils:transferRepay(
                    self,
                    pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_RETURNCHIPS"),
                    v
                )
            end
            if user.expense and coroutine.status(user.expense) == "suspended" then
                coroutine.resume(user.expense, v.code > 0)
            end
        else
            Utils:transferRepay(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_RETURNCHIPS"), v)
        end
    end
end
