local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local cjson = require("cjson")
local mutex = require(CLIBS["c_mutex"])
local rand = require(CLIBS["c_rand"])
local g = require("luascripts/common/g")
local cfgcard = require("luascripts/servers/common/cfgcard")
require("luascripts/servers/common/uniqueid")
require("luascripts/servers/41/seat")
require("luascripts/servers/41/teempatti")

Room = Room or {}

local TimerID = {
    TimerID_Check = {1, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, --id, interval(ms), timestamp(ms)
    TimerID_PrechipsOver = {3, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_StartHandCards = {4, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_HandCardsAnimation = {5, 1000},
    TimerID_Betting = {6, 12000}, --id, interval(ms), timestamp(ms)
    TimerID_Dueling = {7, 4000},
    TimerID_OnFinish = {8, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Timeout = {9, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {10, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {11, 1000},
    TimerID_Buyin = {12, 1000},
    TimerID_Expense = {14, 5000},
    TimerID_RobotLeave = {15, 1000},
    TimerID_CheckRobot = {16, 5000},
    TimerID_Result = {17, 1200}
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
    seatinfo.seatMoney = (seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0
    seatinfo.totalChipin = seat.totalChipin
    seatinfo.chipinType = seat.chiptype
    seatinfo.chipinMoney = seat.chipinnum
    seatinfo.chipinTime = seat:getChipinLeftTime()
    seatinfo.totalTime = seat:getChipinTotalTime()
    seatinfo.addtimeCost = self.conf.addtimecost
    seatinfo.addtimeCount = seat.addon_count
    seatinfo.pot = self:getOnePot()
    seatinfo.isckeck = seat.ischeck
    seatinfo.currentBetPos = self.current_betting_pos

    seatinfo.needcall = seat.ischeck and self.m_needcall * 2 or self.m_needcall
    local max_chaal_limit =
        seat.ischeck and TEEMPATTICONF.max_chaal_limit * self.conf.ante or
        TEEMPATTICONF.max_chaal_limit / 2 * self.conf.ante
    seatinfo.needcall = seatinfo.needcall >= max_chaal_limit and max_chaal_limit or seatinfo.needcall
    seatinfo.needraise = 2 * seatinfo.needcall
    seatinfo.needraise = seatinfo.needraise >= max_chaal_limit and max_chaal_limit or seatinfo.needraise

    local playingnum, checknum = self:getPlayingAndCheckNum()
    if playingnum == 2 then
        seatinfo.duelcard = 2
    elseif checknum >= 2 and seat.ischeck then
        seatinfo.duelcard = 1
    else
        seatinfo.duelcard = 0
    end

    if seatinfo.needcall + seatinfo.pot >= TEEMPATTICONF.max_pot_limit * self.conf.ante then
        seatinfo.needraise = 0
        seatinfo.duelcard = 2
    elseif seatinfo.needcall == seatinfo.needraise and seatinfo.needcall == max_chaal_limit then
        seatinfo.needraise = 0
    end
    seatinfo.duelcard = (self.m_dueled_pos or 0) == seat.sid and 3 or seatinfo.duelcard
    if seat:getIsBuyining() then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BUYING")
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
    end
    seatinfo.ischall = false
    if
        seat.ischeck and seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CALL") or
            seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_RAISE")
     then
        seatinfo.ischall = true
    end

    return seatinfo
end

local function fillSeats(self)
    local seats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        local seatinfo = fillSeatInfo(seat, self)
        table.insert(seats, seatinfo)
    end
    return seats
end

local function onHandCardsAnimation(self)
    local function doRun()
        log.debug(
            "idx(%s,%s,%s) onHandCardsAnimation:%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            self.current_betting_pos,
            self.buttonpos
        )
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        local bbseat = self.seats[self.buttonpos]
        local nextseat = self:getNextActionPosition(bbseat)
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting")
        self:betting(nextseat)
    end
    g.call(doRun)
end

local function onPotAnimation(self)
    local function doRun()
        log.debug("idx(%s,%s,%s) onPotAnimation", self.id, self.mid, tostring(self.logid))
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
            local user = self.users[uid]
            if user and user.buyin and coroutine.status(user.buyin) == "suspended" then
                coroutine.resume(user.buyin, false)
            else
                self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_BuyinFailed"))
            end
        end
    end
    g.call(doRun)
end

local function onRobotLeave(self)
    local function doRun()
        local c = self:count()
        if not self.needCancelTimer then
            return
        end
        self.needCancelTimer = false
        timer.cancel(self.timer, TimerID.TimerID_RobotLeave[1])

        if c == self.conf.maxuser then
            self.max_leave_count = (self.max_leave_count or 0) + 1
            self.rand_leave_count = self.rand_leave_count or rand.rand_between(0, 1)

            if self.rand_leave_count <= self.max_leave_count and self.willLeaveRobot then
                local user = self.users[self.willLeaveRobot]
                if user then
                    log.info("robot uid = %s will leave", self.willLeaveRobot)
                    self:userLeave(self.willLeaveRobot, user.linkid)
                end
            end
        end
        c = self:count()
        if c < self.conf.maxuser then
            self.max_leave_count = nil
            self.rand_leave_count = nil
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
        for uid, user in pairs(self.users) do
            local linkid = user.linkid
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
                self:userLeave(uid, linkid)
            end
        end
        -- check all seat users issuses
        for k, v in pairs(self.seats) do
            local user = self.users[v.uid]
            if user then
                local uid = v.uid
                user.check_call_num = nil
                -- 超时两轮自动站起
                if user.is_bet_timeout and user.bet_timeout_count >= 2 then
                    -- 处理筹码为 0 的情况
                    self:stand(
                        v,
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_ReservationTimesLimit")
                    )
                else
                    v:reset()
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
                    if v.chips > (self.conf and self.conf.ante + self.conf.fee or 0) then
                        v.isplaying = true
                    elseif v.chips <= (self.conf and self.conf.ante + self.conf.fee or 0) then
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
                        --客户端超时站起
                        end
                    end
                end
            end
        end

        --log.info("idx(%s,%s,%s) onCheck playing size=%s", self.id, self.mid, self:getPlayingSize())

        if self:getPlayingSize() < 2 then
            return
        end
        if self:getPlayingSize() >= 2 and global.ctsec() > self.endtime then
            timer.cancel(self.timer, TimerID.TimerID_Check[1])
            self:start()
        end
    end
    g.call(doRun)
end

local function onCheckRobot(self)
    local function doRun()
        local all, r = self:count()
        -- 检测机器人离开
        if r > 1 and all == self.conf.maxuser then -- 如果座位已坐满且不止一个机器人
            for k, v in ipairs(self.seats) do
                local user = self.users[v.uid]
                if user and Utils:isRobot(user.api) then
                    user.state = EnumUserState.Logout
                    user.logoutts = global.ctsec() - 60
                    break
                end
            end
        end
        if r == 0 then
            log.debug(
                "idx(%s,%s,%s) notify create robot,all=%s,maxuser=%s",
                self.id,
                self.mid,
                tostring(self.logid),
                all,
                self.conf.maxuser
            )
            if all < self.conf.maxuser - 1 then
                Utils:notifyCreateRobot(
                    self.conf.roomtype,
                    self.mid,
                    self.id,
                    rand.rand_between(1, self.conf.maxuser - 1 - all)
                )
            end
        end
    end
    g.call(doRun)
end

local function onFinish(self)
    local function doRun()
        log.info("idx(%s,%s,%s) onFinish", self.id, self.mid, tostring(self.logid))
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])

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
        if self.needCancelTimer then
            onRobotLeave(self)
        end

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
    self.poker = TeemPatti:new()
    self.gameId = 0

    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_None") --牌局状态(preflop, flop, turn...)
    self.buttonpos = 0
    self.tabletype = self.conf.matchtype
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000
    self.bettingtime = self.conf.bettime
    self.current_betting_pos = 0
    self.already_show_card = false
    self.maxraisepos = 0
    self.m_needcall = self.conf.ante

    self.pot = 0 -- 奖池
    self.seats = {} -- 座位
    for sid = 1, self.conf.maxuser do
        local s = Seat:new(self, sid)
        table.insert(self.seats, s)
    end

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

    self.reviewlogs = LogMgr:new(5)
    --实时牌局
    self.reviewlogitems = {} --暂存站起玩家牌局
    --self.recentboardlog = RecentBoardlog.new() -- 最近牌局

    -- 配牌
    self.cfgcard_switch = false
    self.cfgcard =
        cfgcard:new(
        {
            handcards = {
                0x20E,
                0x40E,
                0x30E,
                0x30D,
                0x10D,
                0x20D,
                0x209,
                0x20d,
                0x10d,
                0x402,
                0x30b,
                0x202,
                0x102,
                0x203,
                0x30E
            }
        }
    )
    -- 主动亮牌
    self.req_show_dealcard = false --客户端请求过主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_NULL")
    self.lastchipinpos = 0

    self.tableStartCount = 0
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
        log.debug(
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
        log.debug(
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

function Room:queryUserResult(ok, ud)
    if self.timer then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.debug("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

function Room:userLeave(uid, linkid)
    log.info("idx(%s,%s,%s) userLeave:%s", self.id, self.mid, tostring(self.logid), uid)
    local function handleFailed()
        local resp =
            pb.encode(
            "network.cmd.PBLeaveGameRoomResp_S",
            {
                code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed")
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
            self.state >= pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
                self:stand(
                    self.seats[s.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
            else
                s:chipin(pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
                self:stand(
                    self.seats[s.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
                local isallfold = self:isAllFold()
                if isallfold or (s.isplaying and self:getPlayingSize() == 2) then
                    log.info("idx(%s,%s,%s) chipin isallfold", self.id, self.mid, tostring(self.logid))
                    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish")
                    timer.cancel(self.timer, TimerID.TimerID_Start[1])
                    timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                    timer.cancel(self.timer, TimerID.TimerID_PrechipsOver[1])
                    timer.cancel(self.timer, TimerID.TimerID_StartHandCards[1])
                    timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
                    timer.tick(
                        self.timer,
                        TimerID.TimerID_PotAnimation[1],
                        TimerID.TimerID_PotAnimation[2],
                        onPotAnimation,
                        self
                    )
                end
            end
        else
            -- 站起
            self:stand(
                self.seats[s.sid],
                uid,
                pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
            )
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
    end

    -- 结算
    --local val = s.chips - s.last_chips
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

    if user.gamecount and user.gamecount > 0 then
        Statistic:appendRoomLogs(
            {
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
        )
    end
    log.info(
        "idx(%s,%s,%s) user leave uid %s %s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        user.chips or 0,
        user.currentbuyin or 0,
        user.totalbuyin or 0
    )

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

    self.users[uid] = nil
    self.user_cached = false

    local resp =
        pb.encode(
        "network.cmd.PBLeaveGameRoomResp_S",
        {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess"),
            hands = user.gamecount or 0,
            profits = val - user.totalbuyin,
            roomtype = self.conf.roomtype
        }
    )
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
        resp
    )
    log.info(
        "idx(%s,%s,%s) userLeave:%s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        user.gamecount or 0,
        val - user.totalbuyin
    )

    if not next(self.users) then
        MatchMgr:getMatchById(self.conf.mid):shrinkRoom()
    end

    local c, r = self:count()
    if c == 1 and r == 1 then
        for _, v in ipairs(self.seats) do
            local robot = self.users[v.uid]
            if robot then
                self:userLeave(v.uid, robot.linkid)
            end
        end
    end
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

                        --seat info
                        user.chips = user.chips or 0
                        user.currentbuyin = user.currentbuyin or 0
                        user.roundmoney = user.roundmoney or 0

                        -- 从坐下到站起期间总买入和总输赢
                        user.totalbuyin = user.totalbuyin or 0
                        user.totalwin = user.totalwin or 0

                        -- 携带数据
                        user.linkid = linkid
                        user.intots = user.intots or global.ctsec()
                        user.sid = ud.sid
                        user.userId = ud.userId
                        user.roundId = user.roundId or self.statistic:genLogId()
                    end

                    -- 防止协程返回时，玩家实质上已离线
                    if ok and user.state ~= EnumUserState.Intoing then
                        ok = false
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                        log.info("idx(%s,%s,%s) user %s logout or leave", self.id, self.mid, tostring(self.logid), uid)
                    end
                    if ok and not inseat and self:getUserMoney(uid) > self.conf.maxinto then
                        ok = false
                        log.info(
                            "idx(%s,%s,%s) user %s more than maxinto",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            uid,
                            tostring(self.conf.maxinto)
                        )
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_OverMaxInto")
                    end

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
                        return
                    end

                    self.user_cached = false
                    user.state = EnumUserState.Playing

                    log.info(
                        "idx(%s,%s,%s) into room:%s,%s,%s,%s,%s",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        uid,
                        linkid,
                        self.state,
                        self:getUserMoney(uid),
                        self:getSitSize()
                    )

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
                    quick = (0x2 == (self.conf.buyin & 0x2)) and true or false
                    if not inseat and self:count() < self.conf.maxuser and quick and not user.active_stand then
                        self:sit(seat, uid, self:getRecommandBuyin(self:getUserMoney(uid)))
                    end
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
    self.poker:reset()
    self.pots = {money = 0, seats = {}}
    --奖池中包含哪些人共享
    self.maxraisepos = 0
    self.m_needcall = self.conf.ante
    self.roundcount = 0
    self.current_betting_pos = 0
    self.already_show_card = false
    self.sdata = {
        --moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}
    --self.boardlog:reset()
    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_None")

    self.req_show_dealcard = false
    self.lastchipintype = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_NULL")
    self.lastchipinpos = 0
    self.m_dueled_pos, self.m_dueler_pos = 0, 0
    self.has_cheat = false
    self.round_player_num = 0
    self.is_trigger_fold = false
    self.willLeaveRobot = nil
    self.isOverPot = false
    for k, seat in ipairs(self.seats) do
        if seat then
            seat.totalChipin = 0
        end
    end
end

function Room:potRake(total_pot_chips)
    log.info("idx(%s,%s,%s) into potRake:%s", self.id, self.mid, tostring(self.logid), total_pot_chips)
    local minipotrake = self.conf.minipotrake or 0
    local potrake = 0
    if total_pot_chips <= minipotrake then
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
        log.info("idx(%s,%s,%s) after potRake:%s %s", self.id, self.mid, tostring(self.logid), total_pot_chips, potrake)
    end
    return total_pot_chips, potrake
end

function Room:userTableInfo(uid, linkid, rev)
    log.debug(
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
        minbuyin = self.conf.minbuyinbb,
        maxbuyin = self.conf.maxbuyinbb,
        bettingtime = self.bettingtime,
        matchType = self.conf.matchtype,
        roomType = self.conf.roomtype,
        addtimeCost = self.conf.addtimecost,
        toolCost = self.conf.toolcost,
        jpid = self.conf.jpid or 0,
        jp = JackpotMgr:getJackpotById(self.conf.jpid),
        jpRatios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or {0, 0, 0}),
        betLimit = TEEMPATTICONF.max_chaal_limit * self.conf.ante,
        potLimit = TEEMPATTICONF.max_pot_limit * self.conf.ante,
        duelerPos = self.m_dueler_pos,
        dueledPos = self.m_dueled_pos,
        middlebuyin = self.conf.referrerbb * self.conf.ante
    }
    log.debug(
        "idx(%s,%s,%s) uid:%s userTableInfo:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        cjson.encode(tableinfo)
    )
    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
end

function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid then
            local seatinfo = fillSeatInfo(seat, self)
            if seat.uid == uid and seat.ischeck then
                seatinfo.handcards = g.copy(seat.handcards)
            else
                seatinfo.handcards = {}
                for _, v in ipairs(seat.handcards) do
                    table.insert(seatinfo.handcards, v ~= 0 and 0 or -1) -- -1 无手手牌，0 牌背
                end
            end
            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end

    local resp = pb.encode("network.cmd.PBTeemPattiTableInfoResp", {tableInfo = tableinfo})
    --print("PBTeemPattiTableInfoResp=", cjson.encode(tableinfo))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiTableInfoResp"),
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

function Room:getPlayingAndCheckNum()
    local count, checknum = 0, 0
    for i = 1, #self.seats do
        if
            self.seats[i].isplaying and
                self.seats[i].chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
         then
            count = count + 1
            if self.seats[i].ischeck then
                checknum = checknum + 1
            end
        end
    end
    return count, checknum
end

function Room:getNextNoFlodPosition(pos)
    for i = pos + 1, pos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if
            seat.isplaying and
                seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
         then
            return seat
        end
    end
    return nil
end

function Room:getNextActionPosition(seat)
    local pos = seat and seat.sid or 0
    log.debug(
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
                seati.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
         then
            seati.addon_count = 0
            return seati
        end
    end
    return self.seats[self.maxraisepos]
end

function Room:getNextDuelPosition(seat)
    --两人明牌
    local nonfolds = self:getNonFoldSeats()
    if #nonfolds == 2 then
        for _, v in ipairs(nonfolds) do
            if v.sid ~= seat.sid then
                return v
            end
        end
    end

    --两人以上比牌
    local j = (seat.sid - 1) % #self.seats > 0 and (seat.sid - 1) % #self.seats or #self.seats
    repeat
        local seati = self.seats[j]
        if
            seati and seati.isplaying and seati.ischeck and
                seati.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
         then
            return seati
        end
        j = (j - 1) % #self.seats > 0 and (j - 1) % #self.seats or #self.seats
    until (seat.sid == (j % #self.seats))
    log.debug(
        "idx(%s,%s,%s) getNextDuelPosition sid:%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        seat.sid,
        tostring(self.maxraisepos)
    )
    return nil
end

function Room:getNoFoldCnt()
    local nfold = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if
            seat and seat.isplaying and
                seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
         then
            nfold = nfold + 1
        end
    end
    return nfold
end

function Room:moveButton()
    log.debug("idx(%s,%s,%s) move button", self.id, self.mid, tostring(self.logid))
    for i = self.buttonpos + 1, self.buttonpos + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seati = self.seats[j]
        if seati and seati.isplaying then
            self.buttonpos = j
            break
        end
    end

    log.debug(
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
        "idx(%s,%s,%s) stand uid,sid:%s,%s,%s,%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        seat.sid,
        tostring(stype),
        seat.totalbuyin,
        tostring(self.state)
    )
    local user = self.users[uid]
    if seat and user then
        if
            self.state >= pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish") and
                seat.isplaying
         then
            -- 统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[uid] = self.sdata.users[uid] or {}
            self.sdata.users[uid].totalpureprofit =
                self.sdata.users[uid].totalpureprofit or seat.chips - seat.last_chips - seat.roundmoney
            self.sdata.users[uid].ugameinfo = self.sdata.users[uid].ugameinfo or {}
            self.sdata.users[uid].ugameinfo.texas = self.sdata.users[uid].ugameinfo.texas or {}
            self.sdata.users[uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[uid].ugameinfo.texas.inctotalwinhands =
                self.sdata.users[uid].ugameinfo.texas.inctotalwinhands or 0
            --第一次下注是盲注的手数
            self.sdata.users[uid].ugameinfo.texas.incpreflopfoldhands =
                self.sdata.users[uid].ugameinfo.texas.incpreflopfoldhands or 0
            --看牌加注的手数
            self.sdata.users[uid].ugameinfo.texas.incpreflopraisehands =
                self.sdata.users[uid].ugameinfo.texas.incpreflopraisehands or 0
            self.sdata.users[uid].ugameinfo.texas.leftchips = seat.chips - seat.roundmoney

            --输家防倒币行为
            if self.sdata.users[uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
                if
                    not Utils:isRobot(user.api) and extrainfo and self.sdata.users[uid].totalpureprofit < 0 and
                        math.abs(self.sdata.users[uid].totalpureprofit) >= 100 * self.conf.ante and
                        seat.last_active_chipintype ==
                            pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
                        not user.is_bet_timeout and
                        (user.check_call_num or 0) >= 3 and
                        (self.round_player_num or 0) >= 2 and
                        self.is_trigger_fold
                 then
                    extrainfo["cheat"] = true
                    self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
                    self.has_cheat = true
                end
            end

            self.reviewlogitems[seat.uid] =
                self.reviewlogitems[seat.uid] or
                {
                    player = {
                        uid = seat.uid,
                        username = user.username or ""
                    },
                    sid = seat.sid,
                    handcards = g.copy(seat.handcards),
                    cardtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards)),
                    win = -seat.roundmoney,
                    showcard = seat.show
                }

            log.info(
                "idx(%s,%s,%s) stand uid,sid:%s,%s,%s",
                self.id,
                self.mid,
                tostring(self.logid),
                uid,
                seat.sid,
                cjson.encode(self.reviewlogitems)
            )
        end

        -- 备份座位数据
        user.chips = seat.chips > seat.roundmoney and seat.chips - seat.roundmoney or 0
        user.currentbuyin = seat.currentbuyin
        user.roundmoney = seat.roundmoney
        user.totalbuyin = seat.totalbuyin
        user.is_bet_timeout = nil
        user.bet_timeout_count = 0
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
        --机器人只有在有空余1个座位以上才能坐下
        local empty = self.conf.maxuser - self:count()
        if Utils:isRobot(user.api) and empty <= 1 then
            net.send(
                user.linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitFailed"),
                pb.encode(
                    "network.cmd.PBTexasSitFailed",
                    {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")}
                )
            )
            return
        end
        log.info(
            "idx(%s,%s,%s) sit uid %s,sid %s %s %s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            seat.sid,
            seat.totalbuyin,
            user.totalbuyin
        )
        seat:sit(uid, user.chips, 0, user.totalbuyin)
        local clientBuyin =
            (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante + self.conf.fee or 0))
        --print('clientBuyin', clientBuyin)
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
            "network.cmd.PBTeemPattiPlayerSit",
            sitcmd,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiPlayerSit"),
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
        log.debug(
            "idx(%s,%s,%s) chiptype:%s seatinfo:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(chiptype),
            cjson.encode(updateseat.seatInfo)
        )
        pb.encode(
            "network.cmd.PBTeemPattiUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiUpdateSeat"),
                    pointer,
                    length
                )
            end
        )
    end
end

function Room:sendPosInfoToMe(seat)
    local user = self.users[seat.uid]
    local updateseat = {}
    if user then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        if seat.ischeck then
            updateseat.seatInfo.handcards = g.copy(seat.handcards)
        else
            for _, v in ipairs(seat.handcards) do
                table.insert(updateseat.seatInfo.handcards, v ~= 0 and 0 or -1) -- -1 无手手牌，0 牌背
            end
        end
        log.debug("idx(%s,%s,%s) checkcard:%s", self.id, self.mid, tostring(self.logid), cjson.encode(updateseat))
        net.send(
            user.linkid,
            seat.uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiUpdateSeat"),
            pb.encode("network.cmd.PBTeemPattiUpdateSeat", updateseat)
        )
    end
end

function Room:start()
    self:reset()
    self.hasFind = false
    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Start")
    self.gameId = self:getGameId()
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec()
    self.has_player_inplay = false
    self.logid = self.has_started and self.statistic:genLogId(self.starttime) or self.logid
    self.has_started = self.has_started or true

    -- 玩家状态，金币数等数据初始化
    self:moveButton()

    --self.maxraisepos = self.buttonpos
    --self.current_betting_pos = self.buttonpos
    log.info(
        "idx(%s,%s,%s) start ante:%s gameId:%s betpos:%s,%s logid:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self.conf.ante,
        self.gameId,
        self.current_betting_pos,
        self.buttonpos,
        tostring(self.logid)
    )
    --配牌处理
    if self.cfgcard_switch then
        self:setcard()
    end

    -- GameLog
    --self.boardlog:appendStart(self)
    -- 服务费
    for k, v in ipairs(self.seats) do
        if v.uid and v.isplaying then
            local user = self.users[v.uid]
            if user and not Utils:isRobot(user.api) and not self.has_player_inplay then
                self.has_player_inplay = true
            end

            if self.conf and self.conf.fee and v.chips > self.conf.fee then
                v.last_chips = v.chips
                v.chips = v.chips - self.conf.fee
                -- 统计
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
                self.sdata.users[v.uid].totalfee = self.conf.fee
            end
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
                    roundid = user and user.roundId or "",
                    playchips = 20 * (self.conf and self.conf.fee or 0) -- 2021-12-24
                }
            )
            if k == self.buttonpos then
                self.sdata.users[v.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
            else
                self.sdata.users[v.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
            end
            if user and not Utils:isRobot(user.api) then
                self.round_player_num = (self.round_player_num or 0) + 1
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
        seats = fillSeats(self)
    }
    pb.encode(
        "network.cmd.PBTeemPattiGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiGameStart"),
                pointer,
                length
            )
        end
    )
    log.info("idx(%s,%s,%s) gamestart:%s", self.id, self.mid, tostring(self.logid), cjson.encode(gamestart))

    local curplayers = 0
    -- 同步当前状态给客户端
    for k, v in ipairs(self.seats) do
        if v.uid then
            --self:sendPosInfoToAll(v)
            curplayers = curplayers + 1
        end
    end

    -- 数据统计
    self.sdata.stime = self.starttime
    self.sdata.gameinfo = self.sdata.gameinfo or {}
    self.sdata.gameinfo.texas = self.sdata.gameinfo.texas or {}
    self.sdata.gameinfo.texas.maxplayers = self.conf.maxuser
    self.sdata.gameinfo.texas.curplayers = curplayers
    self.sdata.gameinfo.texas.ante = self.conf.ante
    self.sdata.jp = {minichips = self.conf.minchip}
    self.sdata.extrainfo =
        cjson.encode({buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0})

    if self:getPlayingSize() == 1 then
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
        return
    end

    -- 底注
    self:dealPreChips()

    -- 防逃盲
    --self:dealAntiEscapeBB()

    --if self.conf.ante <= 0 then
    --   onStartPreflop(self)
    --end
end

function Room:checkCanChipin(seat)
    return seat and seat.uid and seat.sid == self.current_betting_pos and seat.isplaying and
        --        self.state == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_BETTING") and
        seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
end

function Room:checkFinish()
    local isallfold = self:isAllFold()
    local isoverpot = self:isOverPotLimit()
    if isallfold or isoverpot then
        if isallfold then
            for _, seat in ipairs(self.seats) do
                if seat.isplaying then
                    if seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") then
                        self.is_trigger_fold = true
                        break
                    end
                end
            end
        end
        log.info(
            "idx(%s,%s,%s) chipin isallfold:%s isoverpot:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(isallfold),
            tostring(isoverpot)
        )
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish")
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_StartHandCards[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        onPotAnimation(self)
        --timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
        return true
    end
    return false
end

local function onDuelCard(self, nofold)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Dueling[1])
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting")
        local dueler = self.seats[self.m_dueler_pos]
        local loser = self.seats[self.m_duel_loser_pos]
        if loser then
            loser:chipin(pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
            if not nofold then
                self:sendPosInfoToAll(loser)
            end
            self.m_duel_loser_pos = 0
        end
        self.m_dueled_pos, self.m_dueler_pos = 0, 0
        if self:checkFinish() then
            return true
        else
            local next = self:getNextActionPosition(dueler)
            self:betting(next)
        end
    end
    g.call(doRun)
end

function Room:chipin(uid, type, money)
    local seat = self:getSeatByUid(uid)
    if
        (type ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK") and
            type ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_PRECHIPS"))
     then
        if not self:checkCanChipin(seat) then
            return false
        end
    end

    local is_enough_money = ((seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0) >= money
    log.info(
        "idx(%s,%s,%s) chipin pos:%s uid:%s type:%s money:%s,%s",
        self.id,
        self.mid,
        tostring(self.logid),
        seat.sid,
        seat.uid and seat.uid or 0,
        type,
        money,
        tostring(is_enough_money)
    )

    local res = false

    local function fold_func(seat, type, money)
        if self.state == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Dueling") then
            self.m_duel_loser_pos = self.m_dueled_pos
            onDuelCard(self)
            return false
        end

        seat:chipin(type, 0)
        res = true
        return true
    end

    local function prechips_func(seat, type, money)
        seat:chipin(type, money)
        return true
    end

    local function check_func(seat, type, money)
        if not seat.ischeck then
            seat.ischeck = true
            seat:chipin(type, 0)
            self:sendPosInfoToMe(seat)
            seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
        end
        return true
    end

    local function call_raise_func(seat, type, money)
        if not is_enough_money then
            return false
        end

        --玩家看牌后跟注次数
        local user = self.users[uid]
        if user and seat.ischeck then
            user.check_call_num = (user.check_call_num or 0) + 1
        end

        self.sdata.users = self.sdata.users or {}
        self.sdata.users[uid] = self.sdata.users[uid] or {ugameinfo = {texas = {}}}
        local needcall = self.m_needcall
        if seat.ischeck then
            needcall = 2 * needcall
        else
            seat.blindcnt = seat.blindcnt + 1
            if seat.blindcnt == 1 then
                self.sdata.users[uid].ugameinfo.texas.incpreflopfoldhands = 1
            end
        end

        local max_chaal_limit =
            seat.ischeck and TEEMPATTICONF.max_chaal_limit * self.conf.ante or
            TEEMPATTICONF.max_chaal_limit / 2 * self.conf.ante

        needcall = needcall >= max_chaal_limit and max_chaal_limit or needcall

        local needraise = 2 * needcall
        needraise =
            needraise >= TEEMPATTICONF.max_chaal_limit * self.conf.ante and
            TEEMPATTICONF.max_chaal_limit * self.conf.ante or
            needraise

        log.info(
            "idx(%s,%s,%s) call_raise_func:%s uid:%s type:%s money:%s needcall:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            seat.sid,
            seat.uid and seat.uid or 0,
            type,
            money,
            needcall
        )
        if type == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CALL") then
            --if not is_enough_money or needcall ~= money then
            if needcall ~= money then
                type = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
                money = 0
            end
        elseif type == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_RAISE") then
            --if not is_enough_money or needraise ~= money then
            if needraise ~= money then
                type = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
                money = 0
            else
                if seat.ischeck then
                    self.sdata.users[uid].ugameinfo.texas.incpreflopraisehands = 1
                end
                self.m_needcall = 2 * self.m_needcall
            end
        end
        seat:chipin(type, money)

        res = true
        return true
    end

    local function duel_yes_func(seat, type, money, noduel)
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting")
        if (self.m_dueled_pos or 0) == seat.sid then
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            seat:chipin(type, 0)

            local duelCardCmd = {type = 0, winnerSid = 0, loserSid = 0}
            local dueler = self.seats[self.m_dueler_pos]
            local dueled = self.seats[self.m_dueled_pos]
            if dueler and dueler.isplaying and dueled and dueled.isplaying then
                if self.poker:isBankerWin(g.copy(dueler.handcards), g.copy(dueled.handcards)) > 0 then --发起比牌玩家输
                    duelCardCmd.winnerSid = self.m_dueler_pos
                    duelCardCmd.loserSid = self.m_dueled_pos
                else
                    duelCardCmd.winnerSid = self.m_dueled_pos
                    duelCardCmd.loserSid = self.m_dueler_pos
                end
                self.m_duel_loser_pos = duelCardCmd.loserSid
            end

            if not noduel then
                duelCardCmd.type = 1
                timer.tick(self.timer, TimerID.TimerID_Dueling[1], TimerID.TimerID_Dueling[2], onDuelCard, self)
                pb.encode(
                    "network.cmd.PBTeemPattiNotifyDuelCard_N",
                    duelCardCmd,
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiNotifyDuelCard"),
                            pointer,
                            length
                        )
                    end
                )
            else
                --明牌需要show牌
                dueler.show, dueled.show = true, true
                --timer.tick(self.timer, TimerID.TimerID_Dueling[1], TimerID.TimerID_Dueling[2], onDuelCard, self)
                duelCardCmd.type = 2
                pb.encode(
                    "network.cmd.PBTeemPattiNotifyDuelCard_N",
                    duelCardCmd,
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiNotifyDuelCard"),
                            pointer,
                            length
                        )
                    end
                )
                self:sendPosInfoToAll(seat)
                onDuelCard(self, true)
                return false
            end
        end
        return true
    end

    local function duel_no_func(seat, type, money)
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting")
        local dueler = self.seats[self.m_dueler_pos]
        if (self.m_dueled_pos or 0) == seat.sid and dueler then
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            seat:chipin(type, 0)
            self:sendPosInfoToAll(seat)
            self.m_dueled_pos, self.m_dueler_pos = 0, 0
            local next = self:getNextActionPosition(dueler)
            self:betting(next)
        end
        return true
    end

    local function duel_func(seat, type, money)
        local playingnum, checknum = self:getPlayingAndCheckNum()
        if is_enough_money then
            local next = self:getNextDuelPosition(seat)
            if next then
                self.m_dueler_pos = seat.sid
                self.m_dueled_pos = next.sid
                self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Dueling")
                if playingnum == 2 then
                    seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
                    next.handtype = self.poker:getPokerTypebyCards(g.copy(next.handcards))
                    seat:chipin(type, money)
                    self:sendPosInfoToAll(seat)
                    duel_yes_func(
                        next,
                        pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL_YES"),
                        0,
                        true
                    )
                elseif checknum >= 2 and seat.ischeck then
                    seat:chipin(type, money)
                    self:sendPosInfoToAll(seat)
                    if not self:checkFinish() then
                        self:betting(next)
                    end
                end
            end
        end
        return false
    end

    local switch = {
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")] = fold_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CALL")] = call_raise_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK")] = check_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_RAISE")] = call_raise_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL")] = duel_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL_YES")] = duel_yes_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL_NO")] = duel_no_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_WAIT")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CLEAR_STATUS")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_REBUYING")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_PRECHIPS")] = prechips_func,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BUYING")] = nil
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, tostring(self.logid), uid, type)
        return false
    end

    -- 真正操作chipin
    if chipin_func(seat, type, money) then
        log.info("idx(%s,%s,%s) chipin_func chipintype:%s", self.id, self.mid, tostring(self.logid), type)
        self:sendPosInfoToAll(seat)
    end

    -- GameLog
    --self.boardlog:appendChipin(self, seat)
    return res
end

function Room:userchipin(uid, type, money)
    log.info(
        "idx(%s,%s,%s) userchipin: uid %s, type %s, money %s",
        self.id,
        self.mid,
        tostring(self.logid),
        tostring(uid),
        tostring(type),
        tostring(money)
    )
    uid = uid or 0
    type = type or 0
    money = money or 0
    if
        self.state == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_None") or
            (self.state == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish") and
                type ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK"))
     then
        log.info("idx(%s,%s,%s) user chipin state invalid:%s", self.id, self.mid, tostring(self.logid), self.state)
        return false
    end
    local chipin_seat = self:getSeatByUid(uid)
    if not chipin_seat then
        log.info("idx(%s,%s,%s) invalid chipin seat", self.id, self.mid, tostring(self.logid))
        return false
    end
    if
        type ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK") and
            self.current_betting_pos ~= chipin_seat.sid
     then
        log.info("idx(%s,%s,%s) invalid chipin pos:%s", self.id, self.mid, tostring(self.logid), chipin_seat.sid)
        return false
    end
    if self.conf.minchip == 0 or (money > 0 and money < self.conf.minchip) then
        log.info("idx(%s,%s,%s) chipin minchip invalid uid:%s", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    if
        not chipin_seat.isplaying or
            chipin_seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
     then
        log.info(
            "idx(%s,%s,%s) %s chipin has not been playing:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            tostring(chipin_seat.isplaying)
        )
        return false
    end

    if money % self.conf.minchip ~= 0 then
        if money < self.conf.minchip then
            money = self.conf.minchip
        else
            money = math.floor(money / self.conf.minchip) * self.conf.minchip
        end
    end

    chipin_seat.last_active_chipintype = type
    local chipin_result = self:chipin(uid, type, money)
    if not chipin_result then
        --log.info("idx(%s,%s,%s) chipin failed uid:%s",self.id,self.mid,uid)
        return false
    end
    if type == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") then -- 如果当前是弃牌操作
        -- 判断该玩家是否是机器人
        if self.users[uid] and Utils:isRobot(self.users[uid].api) then -- 如果是机器人
            if not self.willLeaveRobot then -- 如果还没有机器人要离开
                self.willLeaveRobot = uid
                timer.tick(
                    self.timer,
                    TimerID.TimerID_RobotLeave[1],
                    TimerID.TimerID_RobotLeave[2] + rand.rand_between(0, 20000),
                    onRobotLeave,
                    self
                )
                self.needCancelTimer = true
            else
                if rand.rand_between(1, 10000) < 5000 then
                    self.willLeaveRobot = uid -- 随机更改要离开的机器人
                end
            end
        end
    end
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    if self:checkFinish() then
        return true
    end

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

    if
        chipin_seat.blindcnt >= TEEMPATTICONF.max_blind_cnt and not chipin_seat.ischeck and
            chipin_seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
     then
        self:chipin(chipin_seat.uid, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK"), 0)
    end
    return true
end

function Room:getNextState()
    local oldstate = self.state

    if oldstate == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_PreChips") then
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_HandCard")
        self:dealHandCards()
    elseif oldstate == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish") then
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_None")
    end

    log.info("idx(%s,%s,%s) State Change: %s => %s", self.id, self.mid, tostring(self.logid), oldstate, self.state)
end

local function onStartHandCards(self)
    local function doRun()
        log.debug(
            "idx(%s,%s,%s) onStartHandCards button_pos:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            self.buttonpos
        )
        timer.cancel(self.timer, TimerID.TimerID_StartHandCards[1])

        self:getNextState()
    end
    g.call(doRun)
end
local function onPrechipsOver(self)
    local function doRun()
        log.debug("idx(%s,%s,%s) onPrechipsRoundOver", self.id, self.mid, tostring(self.logid))
        timer.cancel(self.timer, TimerID.TimerID_PrechipsOver[1])

        timer.tick(
            self.timer,
            TimerID.TimerID_StartHandCards[1],
            TimerID.TimerID_StartHandCards[2],
            onStartHandCards,
            self
        )
    end
    g.call(doRun)
end
function Room:dealPreChips()
    log.debug("idx(%s,%s,%s) dealPreChips ante:%s", self.id, self.mid, tostring(self.logid), self.conf.ante)
    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_PreChips")
    if self.conf.ante > 0 then
        for i = self.buttonpos + 1, self.buttonpos + #self.seats do
            local j = i % #self.seats > 0 and i % #self.seats or #self.seats
            local seati = self.seats[j]
            if seati and seati.isplaying then
                self:chipin(
                    seati.uid,
                    pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_PRECHIPS"),
                    self.conf.ante
                )
            end
        end

        -- GameLog
        --self.boardlog:appendPreChips(self)

        timer.tick(self.timer, TimerID.TimerID_PrechipsOver[1], TimerID.TimerID_PrechipsOver[2], onPrechipsOver, self)
    else
        onStartHandCards(self)
    end
end

function Room:dealHandCardsCommon(seatcards, needredeal, robotfire)
    if needredeal then
        for k, seat in ipairs(self.seats) do
            local user = self.users[seat.uid]
            if user and seat.isplaying then
                if self.cfgcard_switch then
                    seat.handcards[1] = self.cfgcard:popHand()
                    seat.handcards[2] = self.cfgcard:popHand()
                    seat.handcards[3] = self.poker:getJokerCard(seat.handcards)
                else
                    seat.handcards = self.poker:getNCard(3)
                    seat.handcards[3] = self.poker:getJokerCard(seat.handcards)
                end
            end
        end
    end
    for k, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user then
            if seat.isplaying then
                for _, dc in ipairs(seatcards) do
                    if dc.sid == k then
                        dc.handcards[1] = seat.handcards[1]
                        dc.handcards[2] = seat.handcards[2]
                        dc.handcards[3] = seat.handcards[3]
                        break
                    end
                end

                log.info(
                    "idx(%s,%s,%s) sid:%s,uid:%s deal handcard:%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    k,
                    seat.uid,
                    cjson.encode(seat.handcards)
                )

                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].cards =
                    self.sdata.users[seat.uid].cards or {seat.handcards[1], seat.handcards[2], seat.handcards[3]}
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

    if robotfire then
        for _, seat in ipairs(self.seats) do
            local user = self.users[seat.uid]
            if user and Utils:isRobot(user.api) and seat.isplaying then
                net.send(
                    user.linkid,
                    seat.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiDealCardOnlyRobot"),
                    pb.encode("network.cmd.PBTeemPattiDealCardOnlyRobot", {cards = seatcards, isJoker = true, isSpecial = false})
                )
            end
        end
    end
end
--deal handcards
function Room:dealHandCards()
    local dealcard = {}
    local robotlist = {}
    local hasplayer = false
    for _, seat in ipairs(self.seats) do
        table.insert(
            dealcard,
            {
                sid = seat.sid,
                handcards = {0, 0, 0}
            }
        )
        local user = self.users[seat.uid]
        if user and seat.isplaying then
            if Utils:isRobot(user.api) then
                table.insert(robotlist, seat.uid)
            else
                hasplayer = true
            end
        end
    end

    -- 广播牌背给所有在玩玩家
    for k, v in pairs(self.users) do
        --if v.state == EnumUserState.Playing and (not self:getSeatByUid(k) or not self:getSeatByUid(k).isplaying) then
        if v.state == EnumUserState.Playing then
            net.send(
                v.linkid,
                k,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiDealCard"),
                pb.encode("network.cmd.PBTeemPattiDealCard", {cards = dealcard})
            )
        end
    end

    local seatcards = g.copy(dealcard)

    if self.conf.single_profit_switch and hasplayer then -- 单个人控制 且 有真实玩家下注了
        self.result_co =
            coroutine.create(
            function()
                local msg = {ctx = 0, matchid = self.mid, roomid = self.id, data = {}, ispvp = true}
                for _, seat in ipairs(self.seats) do
                    local v = self.users[seat.uid]
                    if v and not Utils:isRobot(v.api) and seat.isplaying then
                        table.insert(msg.data, {uid = seat.uid, chips = 0, betchips = 0})
                    end
                end
                log.info("idx(%s,%s) start result request %s", self.id, self.mid, cjson.encode(msg))
                Utils:queryProfitResult(msg)
                local ok, res = coroutine.yield() -- 等待查询结果
                local winlist, loselist = {}, {}
                if ok and res then
                    for _, v in ipairs(res) do
                        local uid, r, maxwin = v.uid, v.res, v.maxwin
                        if self.sdata.users[uid] and self.sdata.users[uid].extrainfo then
                            local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
                            if extrainfo then
                                extrainfo["maxwin"] = r * maxwin
                                self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
                            end
                        end
                        log.info("idx(%s,%s) finish result %s,%s", self.id, self.mid, uid, r)
                        if r > 0 then
                            table.insert(winlist, uid)
                        elseif r < 0 then
                            table.insert(loselist, uid)
                        end
                    end
                end
                log.info(
                    "idx(%s,%s) ok %s winlist loselist robotlist %s,%s,%s",
                    self.id,
                    self.mid,
                    tostring(ok),
                    cjson.encode(winlist),
                    cjson.encode(loselist),
                    cjson.encode(robotlist)
                )
                local winner, loser
                if #winlist > 0 then
                    winner = self:getSeatByUid(winlist[rand.rand_between(1, #winlist)])
                end
                if #loselist > 0 then
                    loser = self:getSeatByUid(loselist[rand.rand_between(1, #loselist)])
                end
                if not winner and loser and #robotlist > 0 then
                    winner = self:getSeatByUid(table.remove(robotlist))
                elseif winner and not loser and #robotlist > 0 then
                    loser = self:getSeatByUid(table.remove(robotlist))
                end
                if winner and loser then
                    log.info("idx(%s,%s) find the best cards", self.id, self.mid)
                    for retrytime = 1, 20 do
                        local handcards_rank = {}
                        local pairnum = 0
                        self.poker:reset()
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying then
                                local hcards = {0, 0, 0}
                                if self.cfgcard_switch then
                                    hcards[1] = self.cfgcard:popHand()
                                    hcards[2] = self.cfgcard:popHand()
                                    hcards[3] = self.poker:getJokerCard(hcards)
                                else
                                    hcards = self.poker:getNCard(3)
                                    hcards[3] = self.poker:getJokerCard(hcards)
                                end
                                local htype = self.poker:getPokerTypebyCards(hcards)
                                if
                                    htype >=
                                        pb.enum_id(
                                            "network.cmd.PBTeemPattiCardWinType",
                                            "PBTeemPattiCardWinType_ONEPAIR"
                                        )
                                 then
                                    pairnum = pairnum + 1
                                end
                                table.insert(handcards_rank, {htype, hcards})
                            end
                        end
                        table.sort(
                            handcards_rank,
                            function(a, b)
                                return self.poker:isBankerWin(a[2], b[2]) < 0
                            end
                        )
                        log.info(
                            "idx(%s,%s) find the result %s,%s",
                            self.id,
                            self.mid,
                            pairnum,
                            cjson.encode(handcards_rank)
                        )
                        --分配最大牌赢家
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying then
                                if winner == seat then
                                    seat.handcards = handcards_rank[#handcards_rank][2]
                                    table.remove(handcards_rank)
                                    break
                                end
                            end
                        end
                        --分配第二大牌输家
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying then
                                if loser == seat then
                                    seat.handcards = handcards_rank[#handcards_rank][2]
                                    table.remove(handcards_rank)
                                    break
                                end
                            end
                        end
                        --剩余分配给其他玩家
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying and seat ~= winner and seat ~= loser then
                                seat.handcards = handcards_rank[#handcards_rank][2]
                                table.remove(handcards_rank)
                            end
                        end
                        if pairnum >= 2 then
                            log.info("idx(%s,%s) result success %s", self.id, self.mid, pairnum)
                            break
                        end
                    end
                    self:dealHandCardsCommon(seatcards, false, false)
                else
                    self:dealHandCardsCommon(seatcards, true, true)
                end
            end
        )
        timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, {self})
        coroutine.resume(self.result_co)
    else
        self:dealHandCardsCommon(seatcards, true, true)
    end

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
            if seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") then
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

function Room:isOverPotLimit()
    local sum = 0
    for _, v in ipairs(self.seats) do
        if v.isplaying then
            sum = sum + v.roundmoney
        end
    end
    return sum >= TEEMPATTICONF.max_pot_limit * self.conf.ante
end

function Room:getOnePot()
    local sum = 0
    for _, v in ipairs(self.seats) do
        if v.isplaying then
            sum = sum + v.roundmoney
        end
    end
    for _, v in pairs(self.reviewlogitems) do
        sum = sum + math.abs(v.win)
    end
    return sum
end

function Room:getNonFoldSeats()
    local nonfoldseats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") then
                table.insert(nonfoldseats, seat)
            end
        end
    end
    return nonfoldseats
end

function Room:isAllCheck()
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if
                seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_ALL_IN")
             then
                return false
            end
        end
    end
    return true
end

local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos]
        if current_betting_seat then
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
                if user and self.m_dueled_pos ~= self.current_betting_pos then
                    user.is_bet_timeout = true
                    user.bet_timeout_count = user.bet_timeout_count or 0
                    user.bet_timeout_count = user.bet_timeout_count + 1
                end
                self:userchipin(
                    current_betting_seat.uid,
                    self.m_dueled_pos == self.current_betting_pos and
                    pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL_NO") or
                    pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"),
                    0
                )
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
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING"))
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self)
    end

    -- 预操作
    local preop = seat:getPreOP()
    if preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_CheckOrFold") then
        self:userchipin(seat.uid, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
        seat:setPreOP(pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None"))
    else
        notifyBetting()
    end
end

function Room:broadcastShowCardToAll()
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying and seat.show then
            local showdealcard = {
                showType = 1,
                sid = i,
                handcards = g.copy(seat.handcards)
            }
            pb.encode(
                "network.cmd.PBTeemPattiShowDealCard",
                showdealcard,
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiShowDealCard"),
                        pointer,
                        length
                    )
                end
            )
        end
    end
end

function Room:broadcastCanShowCardToAll(poss)
    local showpos = {}
    for i = 1, #self.seats do
        showpos[i] = false
    end

    --摊牌前最后一个弃牌的玩家可以主动亮牌
    if
        self.lastchipintype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
            self.lastchipinpos ~= 0 and
            self.lastchipinpos <= #self.seats and
            not self.seats[self.lastchipinpos].show
     then
        showpos[self.lastchipinpos] = true
    end

    --获取底池的玩家可以主动亮牌
    for pos, _ in pairs(poss) do
        if not self.seats[pos].show then
            showpos[pos] = true
        end
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        local user = self.users[seat.uid]
        if seat.isplaying and seat.uid and user then
            --系统盖牌的玩家有权主动亮牌
            if
                not showpos[i] and not seat.show and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_REBUYING") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
             then
                showpos[i] = true
            end

            local send = {}
            send.sid = i
            send.canReqShow = showpos[i]

            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_RespCanShowDealCard"),
                pb.encode("network.cmd.PBTeemPattiCanShowDealCard", send)
            )
        end
    end
end

function Room:finish()
    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish")

    -- m_seats.finish start
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    for _, v in pairs(self.users) do
        if v and not Utils:isRobot(v.api) and not self.has_player_inplay then
            self.has_player_inplay = true
            break
        end
    end

    --获取或者玩家座位列表
    local winners = {}
    local nonfolds = self:getNonFoldSeats()
    local isoverpot = self:isOverPotLimit()
    for i = 1, #nonfolds do
        local seat = nonfolds[i]
        seat.show = isoverpot and true or seat.show
        for j = 1, #nonfolds do
            local other = nonfolds[j]
            if other then
                if self.poker:isBankerWin(g.copy(seat.handcards), g.copy(other.handcards)) < 0 then
                    break
                end
            end
            --全赢或者平手
            if j == #nonfolds then
                table.insert(winners, seat)
            end
        end
    end
    local srcpot = self:getOnePot()
    local pot, potrate = self:potRake(srcpot)

    local avg_win = math.floor(pot / #winners)
    if avg_win % self.conf.minchip ~= 0 then
        avg_win = math.floor(avg_win / self.conf.minchip) * self.conf.minchip
    end

    log.info(
        "idx(%s,%s,%s) finish pot:%s %s avg_win:%s winners:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        srcpot,
        pot,
        avg_win,
        #winners
    )

    local FinalGame = {potInfos = {}, potMoney = pot}

    self.sdata.jp.uid = nil
    for _, v in ipairs(self.seats) do
        log.info(
            "idx(%s,%s,%s) user finish %s %s %s",
            self.id,
            self.mid,
            tostring(self.logid),
            v.roundmoney,
            v.chips,
            v.last_chips
        )
        v.last_chips = v.chips + self.conf.fee
        if g.isInTable(winners, v) then --盈利玩家
            --奖池抽水服务费
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].totalfee = self.conf.fee + potrate
            v.chips = (v.chips > v.roundmoney) and (v.chips - v.roundmoney) or 0
            v.chips = v.chips + avg_win
            table.insert(
                FinalGame.potInfos,
                {
                    sid = v.sid,
                    winMoney = v.chips - v.last_chips,
                    seatMoney = v.chips,
                    winType = self.poker:getPokerTypebyCards(g.copy(v.handcards))
                }
            )

            --JackPot中奖
            if
                JACKPOT_CONF[self.conf.jpid] and
                    v.handtype >=
                        pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_STRAIGHTFLUSH")
             then
                if not self.sdata.jp.uid or self.sdata.winpokertype < v.handtype then -- 2021-10-29
                    self.sdata.jp.uid = v.uid
                    self.sdata.jp.username =
                        self.users[v.uid] and self.users[v.uid].username or
                        (self.reviewlogitems[v.uid] and self.reviewlogitems[v.uid].player.username or "")
                    local jp_percent_size =
                        pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_STRAIGHTFLUSH")
                    self.sdata.jp.delta_sub = JACKPOT_CONF[self.conf.jpid].percent[(v.handtype % jp_percent_size) + 1]
                    self.sdata.winpokertype = v.handtype
                end
            end
        else --亏损玩家
            v.chips = (v.chips > v.roundmoney) and (v.chips - v.roundmoney) or 0
        end
    end

    --JackPot抽水
    if JACKPOT_CONF[self.conf.jpid] then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            local win = seat.chips - seat.last_chips
            local delta_add = JACKPOT_CONF[self.conf.jpid].deltabb * self.conf.ante
            if
                seat.isplaying and win > JACKPOT_CONF[self.conf.jpid].profitbb * self.conf.ante and
                    self.sdata.users[seat.uid].extrainfo
             then
                self.sdata.jp.delta_add = (self.sdata.jp.delta_add or 0) + delta_add
                seat.chips = seat.chips > delta_add and seat.chips - delta_add or 0
                local extrainfo = cjson.decode(self.sdata.users[seat.uid].extrainfo)
                if extrainfo then
                    extrainfo["jpdelta"] = delta_add
                    self.sdata.users[seat.uid].extrainfo = cjson.encode(extrainfo)
                end
                for _, v in ipairs(FinalGame.potInfos) do
                    if v.sid and v.sid == i then
                        v.winMoney = seat.chips - seat.last_chips
                        v.seatMoney = seat.chips
                        break
                    end
                end
            end
        end
        if self.sdata.jp.delta_add or self.sdata.jp.delta_sub then
            self.sdata.jp.id = self.conf.jpid
        end
    end

    local showcard_players = 1
    self:broadcastShowCardToAll()

    local t_msec = showcard_players * 200 + (1 * 200 + 4000) + 1000

    --jackpot 中奖需要额外增加下局开始时间
    if self.sdata.jp and self.sdata.jp.uid and showcard_players > 0 then
        t_msec = t_msec + 5000
        self.jackpot_and_showcard_flags = true
    end

    -- 广播结算
    log.info("idx(%s,%s,%s) PBTeemPattiFinalGame %s", self.id, self.mid, tostring(self.logid), cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBTeemPattiFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiFinalGame"),
                pointer,
                length
            )
        end
    )

    self.endtime = global.ctsec()

    local reviewlog = {
        buttonsid = self.buttonpos,
        ante = self.conf.ante,
        pot = srcpot,
        items = {}
    }

    self:checkCheat() -- 防倒币行为

    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            local win = v.chips - v.last_chips --赢利
            user.totalbuyin = v.totalbuyin
            user.totalwin = v.chips - (v.totalbuyin - v.currentbuyin)
            log.info(
                "idx(%s,%s,%s) chips change uid:%s chips:%s last_chips:%s totalbuyin:%s totalwin:%s roundmoney:%s win:%s",
                self.id,
                self.mid,
                tostring(self.logid),
                v.uid,
                v.chips,
                v.last_chips,
                user.totalbuyin,
                user.totalwin,
                v.roundmoney,
                win
            )

            --盈利扣水
            if win > 0 and (self.conf.rebate or 0) > 0 then
                local rebate = math.floor(win * self.conf.rebate)
                win = win - rebate
                v.chips = v.chips - rebate
            end
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].totalpureprofit = win
            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {}
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (win > 0) and 1 or 0
            self.sdata.users[v.uid].ugameinfo.texas.bestcards = g.copy(v.handcards)
            self.sdata.users[v.uid].ugameinfo.texas.bestcardstype = v.handtype
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips

            -- --输家防倒币行为
            -- --1.输最多玩家输币 >= 100底注
            -- --2.输最多玩家看牌后跟注次数大于3次
            -- --3.输最多玩家主动弃牌
            -- --4.弃牌时仅两个玩家
            -- --5.有两个或两个以上真人
            -- if self.sdata.users[v.uid].extrainfo then
            --     local extrainfo = cjson.decode(self.sdata.users[v.uid].extrainfo)
            --     if
            --         not Utils:isRobot(user.api) and extrainfo and self.sdata.users[v.uid].totalpureprofit < 0 and
            --             math.abs(self.sdata.users[v.uid].totalpureprofit) >= 100 * self.conf.ante and
            --             v.last_active_chipintype ==
            --                 pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
            --             not user.is_bet_timeout and
            --             (user.check_call_num or 0) >= 3 and
            --             (self.round_player_num or 0) >= 2 and
            --             self.is_trigger_fold
            --      then
            --         extrainfo["cheat"] = true
            --         self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
            --         self.has_cheat = true
            --     end
            -- end

            table.insert(
                reviewlog.items,
                {
                    player = {
                        uid = v.uid,
                        username = user.username or ""
                    },
                    sid = k,
                    handcards = g.copy(v.handcards),
                    cardtype = self.poker:getPokerTypebyCards(g.copy(v.handcards)),
                    win = win,
                    showcard = v.show
                }
            )
            self.reviewlogitems[v.uid] = nil
        end
    end
    log.info(
        "idx(%s,%s,%s) review %s %s",
        self.id,
        self.mid,
        tostring(self.logid),
        cjson.encode(reviewlog),
        cjson.encode(self.reviewlogitems)
    )

    for _, v in pairs(self.reviewlogitems) do
        table.insert(reviewlog.items, v)
    end
    for _, v in ipairs(reviewlog.items) do
        self.sdata.users = self.sdata.users or {}
        self.sdata.users[v.player.uid] = self.sdata.users[v.player.uid] or {}
        local seat = self.seats[v.sid]
        if seat then
            if seat.roundmoney > 0 then
                if self.sdata.users[v.player.uid].extrainfo then
                    local extrainfo = cjson.decode(self.sdata.users[v.player.uid].extrainfo)
                    if extrainfo then
                        extrainfo["totalbets"] = seat.roundmoney
                        self.sdata.users[v.player.uid].extrainfo = cjson.encode(extrainfo)
                    end
                end
            end
        else
            if self.sdata.users[v.player.uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[v.player.uid].extrainfo)
                if extrainfo then
                    extrainfo["totalbets"] = math.abs(v.win)
                    self.sdata.users[v.player.uid].extrainfo = cjson.encode(extrainfo)
                end
            end
        end
    end
    self.reviewlogs:push(reviewlog)
    self.reviewlogitems = {}

    --设置剩余筹码是否有效
    for k, v in pairs(self.sdata.users) do
        local user = self.users[k]
        if v.extrainfo and not user then
            local extrainfo = cjson.decode(v.extrainfo)
            if extrainfo and not Utils:isRobot(extrainfo.api) then
                extrainfo["leftchips"] = true
                self.sdata.users[k].extrainfo = cjson.encode(extrainfo)
            end
        end
    end
    --赢家防倒币行为
    for _, v in ipairs(self.seats) do
        -- local user = self.users[v.uid]
        -- if user and v.isplaying then
        --     if self.has_cheat and self.sdata.users[v.uid].extrainfo and self.sdata.users[v.uid].totalpureprofit > 0 then --盈利玩家
        --         local extrainfo = cjson.decode(self.sdata.users[v.uid].extrainfo)
        --         if not Utils:isRobot(user.api) and extrainfo then
        --             extrainfo["cheat"] = true
        --             self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
        --         end
        --     end
        -- end
        --解决结算后马上离开，计算战绩多扣导致显示不正确的问题
        v.roundmoney = 0
    end

    self.sdata.etime = self.endtime

    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and seat.isplaying then
            if not Utils:isRobot(user.api) and self.sdata.users[seat.uid].extrainfo then -- 盈利玩家
                local extrainfo = cjson.decode(self.sdata.users[seat.uid].extrainfo)
                if  extrainfo then
                    extrainfo["totalmoney"] = (self:getUserMoney(seat.uid) or 0) + seat.chips -- 总金额                    
                    log.debug("self.sdata.users[seat.uid].extrainfo uid=%s,totalmoney=%s", seat.uid, extrainfo["totalmoney"])
                    self.sdata.users[seat.uid].extrainfo = cjson.encode(extrainfo)
                end
            end
        end
    end
    if self:needLog() then
        self.statistic:appendLogs(self.sdata, self.logid)
    end
    timer.tick(self.timer, TimerID.TimerID_OnFinish[1], t_msec, onFinish, self)
end

function Room:sendUpdatePotsToAll()
    local updatepots = {pot = self:getOnePot()}
    pb.encode(
        "network.cmd.PBTeemPattiUpdatePots",
        updatepots,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiUpdatePots"),
                pointer,
                length
            )
        end
    )

    return true
end

function Room:setcard()
    log.debug("idx(%s,%s,%s) setcard", self.id, self.mid, tostring(self.logid))
    self.cfgcard:init()
end

function Room:check()
    if global.stopping() then
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
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_PrechipsOver[1])
        timer.cancel(self.timer, TimerID.TimerID_StartHandCards[1])
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
    timer.tick(self.timer, TimerID.TimerID_CheckRobot[1], TimerID.TimerID_CheckRobot[2], onCheckRobot, self) -- 启动检测定时器
end

function Room:userShowCard(uid, linkid, rev)
    log.debug(
        "idx(%s,%s,%s) req show deal card uid:%s sid:%s card1:%s card2:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        tostring(rev.sid),
        tostring(rev.card1),
        tostring(rev.card2)
    )
    -- 下一局开始了，屏蔽主动亮牌
    if self.state ~= pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish") then
        log.info("idx(%s,%s,%s) user show card: state not valid", self.id, self.mid, tostring(self.logid))
        return
    end
    local seat = self.seats[rev.sid]
    if not seat then
        log.info("idx(%s,%s,%s) user show card: seat not valid", self.id, self.mid, tostring(self.logid))
        return
    end
    if seat.uid ~= uid then
        log.info(
            "idx(%s,%s,%s) user show card: seat uid and req uid not match",
            self.id,
            self.mid,
            tostring(self.logid)
        )
        return
    end
    if seat.show then
        log.info("idx(%s,%s,%s) user show card: system already show", self.id, self.mid, tostring(self.logid))
        return
    end
    if not rev.card1 and not rev.card2 then
        log.info("idx(%s,%s,%s) user show card: no card recevie valid", self.id, self.mid, tostring(self.logid))
        return
    end
    if rev.card1 and rev.card1 ~= 0 and not g.isInTable(seat.handcards, rev.card1) then
        log.info("idx(%s,%s,%s) user show card: client req wrong card", self.id, self.mid, tostring(self.logid))
        return
    end
    if rev.card2 and rev.card2 ~= 0 and not g.isInTable(seat.handcards, rev.card2) then
        log.info("idx(%s,%s,%s) user show card: client req wrong card", self.id, self.mid, tostring(self.logid))
        return
    end

    self.req_show_dealcard = true

    -- review log
    local reviewlog = self.reviewlogs:back()
    for k, v in ipairs(reviewlog.items) do
        if v.player.uid == uid then
            v.usershowhandcard = {rev.card1 or 0, rev.card2 or 0}
            break
        end
    end
    -- 亮牌
    local send = {
        showType = 2,
        sid = rev.sid,
        card1 = 0,
        card2 = 0
    }
    if rev.card1 and rev.card1 ~= 0 then
        send.card1 = rev.card1
    end
    if rev.card2 and rev.card2 ~= 0 then
        send.card2 = rev.card2
    end
    pb.encode(
        "network.cmd.PBTeemPattiShowDealCard",
        send,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiShowDealCard"),
                pointer,
                length
            )
        end
    )
end

function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req stand up uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local s = self:getSeatByUid(uid)
    local user = self.users[uid]
    --print(s, user)
    if s and user then
        if
            s.isplaying and self.state >= pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
                self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
            else
                s:chipin(pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
                self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
                local isallfold = self:isAllFold()
                if isallfold or (s.isplaying and self:getPlayingSize() == 2) then
                    log.info("idx(%s,%s,%s) chipin isallfold", self.id, self.mid, tostring(self.logid))
                    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Finish")
                    timer.cancel(self.timer, TimerID.TimerID_Start[1])
                    timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                    timer.cancel(self.timer, TimerID.TimerID_PrechipsOver[1])
                    timer.cancel(self.timer, TimerID.TimerID_StartHandCards[1])
                    timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
                    timer.tick(
                        self.timer,
                        TimerID.TimerID_PotAnimation[1],
                        TimerID.TimerID_PotAnimation[2],
                        onPotAnimation,
                        self
                    )
                end
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
            "idx(%s,%s,%s) userBuyin over limit: minbuyinbb %s, maxbuyinbb %s, ante %s",
            self.id,
            self.mid,
            tostring(self.logid),
            self.conf.minbuyinbb,
            self.conf.maxbuyinbb,
            self.conf.ante
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
    log.debug(
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
            pb.encode("network.cmd.PBGameToolSendResp_S", {code = code or 0, toolID = rev.toolID, leftNum = 0})
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
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) invalid user %s", self.id, self.mid, tostring(self.logid), uid)
        handleFailed()
        return
    end
    if Utils:isRobot(user.api) then
        pb.encode(
            "network.cmd.PBGameNotifyTool_N",
            {
                fromsid = rev.fromsid,
                tosid = rev.tosid,
                toolID = rev.toolID
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
        -- 余额不足时则只扣除筹码(如果筹码足够)
        local leftChips = self.seats[rev.fromsid].chips - self.seats[rev.fromsid].roundmoney
        if leftChips < (self.conf and self.conf.toolcost or 0) then -- 如果筹码不够
            log.info("idx(%s,%s,%s) not enough money %s", self.id, self.mid, tostring(self.logid), uid)
            handleFailed(1)
        else
            log.info("idx(%s,%s,%s) userTool() enough chips %s", self.id, self.mid, tostring(self.logid), uid)
            -- 筹码足够
            self.seats[rev.fromsid].chips = self.seats[rev.fromsid].chips - (self.conf and self.conf.toolcost or 0)
            pb.encode(
                "network.cmd.PBGameNotifyTool_N",
                {
                    fromsid = rev.fromsid,
                    tosid = rev.tosid,
                    toolID = rev.toolID
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
            -- 广播该座位信息(更新玩家身上筹码)
            self:sendPosInfoToAll(self.seats[rev.fromsid])
        end
        return
    end
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s,%s) uid %s coroutine is expensing", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    -- 扣钱
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
                        toolID = rev.toolID
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
    log.debug("idx(%s,%s,%s) userReview uid %s", self.id, self.mid, tostring(self.logid), uid)

    local t = {
        reviews = {}
    }
    local function resp()
        log.debug("idx(%s,%s,%s) PBTeemPattiReviewResp %s", self.id, self.mid, tostring(self.logid), cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiReviewResp"),
            pb.encode("network.cmd.PBTeemPattiReviewResp", t)
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
        local tmp = g.copy(reviewlog)
        for _, item in ipairs(tmp.items) do
            if item.player.uid ~= uid and not item.showcard then
                item.handcards = {0, 0, 0}
                item.cardtype = 0
            end
        end
        table.insert(t.reviews, tmp)
    end
    resp()
end

function Room:userPreOperate(uid, linkid, rev)
    log.debug(
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
    log.debug("idx(%s,%s,%s) req addtime uid:%s", self.id, self.mid, tostring(self.logid), uid)

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
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s,%s) uid %s coroutine is expensing", self.id, self.mid, tostring(self.logid), uid)
        return false
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
        -- 如果身上金额不足，则只扣除筹码
        local leftChips = seat.chips - seat.roundmoney
        -- 检测身上筹码是否足够
        if leftChips < (self.conf and self.conf.addtimecost[seat.addon_count + 1] or 0) then
            log.info("idx(%s,%s,%s) user add time: not enough money %s", self.id, self.mid, tostring(self.logid), uid)
            handleFailed(1)
        else
            log.info("idx(%s,%s,%s) userAddTime() has enough chips %s", self.id, self.mid, tostring(self.logid), uid)

            -- 如果有足够筹码，则扣除筹码
            seat.chips = seat.chips - (self.conf and self.conf.addtimecost[seat.addon_count + 1] or 0)

            seat.addon_time = seat.addon_time + (self.conf.addtime or 0)
            seat.addon_count = seat.addon_count + 1
            seat.total_time = seat:getChipinLeftTime() -- 本次操作剩余时长
            self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING"))
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            timer.tick(self.timer, TimerID.TimerID_Betting[1], seat.total_time * 1000, onBettingTimer, self)
        end
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
                self:sendPosInfoToAll(
                    seat,
                    pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING")
                )
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
    --log.info("idx(%s,%s,%s) userTableListInfoReq:%s", self.id, self.mid, uid)
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
    --log.info("idx(%s,%s,%s) resp userTableListInfoReq %s", self.id, self.mid, cjson.encode(t))
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
    log.info("(%s,%s,%s)notify client for jackpot change %s", self.id, self.mid, tostring(self.logid), jackpot)
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
    log.info("(%s,%s,%s)phpMoneyUpdate %s", self.id, self.mid, tostring(self.logid), uid)
    local user = self.users[uid]
    if user then
        user.money = user.money + rev.money
        user.coin = user.coin + rev.coin
        log.info(
            "(%s,%s,%s)phpMoneyUpdate %s,%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            tostring(rev.money),
            tostring(rev.coin)
        )
    end
end

function Room:needLog()
    return self.has_player_inplay or (self.sdata and self.sdata.jp and self.sdata.jp.id)
end

function Room:getUserIp(uid)
    local user = self.users[uid]
    if user then
        return user.ip
    end
    return ""
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

-- 防倒币行为  2022-3-2
function Room:checkCheat()
    --[[
TeenPatti
规则1：
	1.输赢最多玩家均非AI
	2.输最多玩家牌小于KJ10
	3.输最多玩家看牌后下注/加注总额度 >= 50底注
	4.输最多玩家看牌后下注/加注次数 >= 2
	
规则2:
	1.输赢最多玩家均非AI
	2.输最多玩家盲下注/盲加注总额度 >= 50底注
	3.输最多玩家不看牌弃牌
--]]
    self.maxWinnerUID = 0 -- 最大赢家UID
    self.maxLoserUID = 0 -- 最大输家UID

    self:checkWinnerAndLoserAreAllReal()

    -- for k, seat in ipairs(self.seats) do
    --     local user = self.users[seat.uid]
    --     if user and seat.isplaying then
    --     end
    -- end

    if self.maxWinnerLoserAreAllReal then -- 如果输赢最多玩家均非AI
        local user = self.users[self.maxLoserUID]
        local seat = self:getSeatByUid(self.maxLoserUID)
        local hasCheat = false
        if (seat and seat.ischeck) then -- 如果已经看牌
            -- 规则1：
            -- 1.输赢最多玩家均非AI
            -- 2.输最多玩家牌小于KJ10
            -- 3.输最多玩家看牌后下注/加注总额度 >= 50底注
            -- 4.输最多玩家看牌后下注/加注次数 >= 2

            -- 判断输最多玩家的牌是否小于 KKA
            local cards = {0x10D, 0x20D, 0x30E}
            if self.poker:isBankerWin(seat.handcards, cards) < 0 then
                -- 输最多玩家看牌后下注/加注总额度 >= 50底注
                if -- self.sdata.users[self.maxLoserUID].totalpureprofit < 0 and
                    --     math.abs(self.sdata.users[self.maxLoserUID].totalpureprofit) >= 50 * self.conf.ante
                    (seat.chips - seat.last_chips) < 0 and math.abs(seat.chips - seat.last_chips) >= 50 * self.conf.ante then
                    -- 输最多玩家看牌后下注/加注次数 >= 2
                    if (user.check_call_num or 0) >= 2 then
                        hasCheat = true
                    end
                end
            else
                -- 规则3:
                -- 1.输赢最多玩家均非AI
                -- 2.输最多玩家看牌后下注/盲加注总额度 >= 50底注
                -- 3.输最多玩家大于对子
                -- 4.输最多玩家主动弃牌
                log.debug("DQW card larger KJ10")
                local cards = {0x10D, 0x10B, 0x10E} -- 最大的对子
                if
                    seat and
                        seat.last_active_chipintype ==
                            pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
                 then
                    if self.poker:isBankerWin(seat.handcards, cards) > 0 then
                        if
                            (seat.chips - seat.last_chips) < 0 and
                                math.abs(seat.chips - seat.last_chips) >= 50 * self.conf.ante
                         then
                            log.debug("DQW hasCheat 3")
                            hasCheat = true
                        end
                    end
                end
            end
        else -- 该玩家未看牌
            -- 规则2:
            -- 1.输赢最多玩家均非AI
            -- 2.输最多玩家盲下注/盲加注总额度 >= 50底注
            -- 3.输最多玩家不看牌弃牌

            -- 输最多玩家弃牌
            if
                seat and
                    seat.last_active_chipintype ==
                        pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
                    (seat.chips - seat.last_chips) < 0 and
                    math.abs(seat.chips - seat.last_chips) >= 50 * self.conf.ante
             then
                hasCheat = true
            end
        end

        if hasCheat then
            log.debug("has player cheat, maxWinnerUID=%s,maxLoserUID=%s", self.maxWinnerUID, self.maxLoserUID)
            if self.sdata.users[self.maxLoserUID].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[self.maxLoserUID].extrainfo)
                if extrainfo then
                    extrainfo["cheat"] = true
                    self.sdata.users[self.maxLoserUID].extrainfo = cjson.encode(extrainfo)
                end
            end

            if self.sdata.users[self.maxWinnerUID].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[self.maxWinnerUID].extrainfo)
                if extrainfo then
                    extrainfo["cheat"] = true
                    self.sdata.users[self.maxWinnerUID].extrainfo = cjson.encode(extrainfo)
                end
            end
        end
    end
end

-- 判断该局输赢最多的两个玩家是否都是真人
function Room:checkWinnerAndLoserAreAllReal()
    if not self.hasFind then -- 如果还未查找
        self.hasFind = true
        self.maxWinnerLoserAreAllReal = false -- 最大赢家和输家是否都是真人（默认不全是真人）

        self.maxWinnerUID = 0 -- 最大的赢家uid
        self.maxLoserUID = 0 -- 最大输家uid
        local maxWin = 0 -- 赢到的最大金额
        local maxLoss = 0 -- 输掉的最大金额
        for k, seat in ipairs(self.seats) do
            local user = self.users[seat.uid or 0]
            if user and seat.isplaying then
                -- local totalwin = seat.chips - (seat.totalbuyin - seat.currentbuyin) -- 该玩家总输赢
                local totalwin = seat.chips - seat.last_chips -- 该玩家总盈利
                if totalwin > maxWin then
                    maxWin = totalwin
                    self.maxWinnerUID = seat.uid
                elseif totalwin < maxLoss then
                    maxLoss = totalwin
                    self.maxLoserUID = seat.uid
                end
            end -- ~if
        end -- ~for

        -- 判断最大输家和最大赢家是否都是真人
        if 0 ~= self.maxWinnerUID and 0 ~= self.maxLoserUID then
            local user = self.users[self.maxWinnerUID]
            if user then
                if not Utils:isRobot(user.api) then -- 如果该玩家不是机器人
                    user = self.users[self.maxLoserUID]
                    if user then
                        if not Utils:isRobot(user.api) then
                            self.maxWinnerLoserAreAllReal = true
                        end
                    end
                end
            end
        end
    end

    return self.maxWinnerLoserAreAllReal -- 默认都是真人
end
