local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local rand = require(CLIBS["c_rand"])
local global = require(CLIBS["c_global"])
local cjson = require("cjson")
local mutex = require(CLIBS["c_mutex"])
local texas = require(CLIBS["c_texas"])
local g = require("luascripts/common/g")
local cfgcard = require("luascripts/servers/common/cfgcard")
require("luascripts/servers/common/uniqueid")

Room = Room or {}

local TimerID = {
    TimerID_Check = {1, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, --id, interval(ms), timestamp(ms)
    TimerID_Betting = {3, 10000}, --id, interval(ms), timestamp(ms)
    TimerID_AllinAnimation = {4, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_PrechipsRoundOver = {5, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_StartPreflop = {6, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_OnFinish = {7, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Timeout = {8, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {9, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {10, 1000},
    TimerID_Buyin = {11, 1000},
    TimerID_PreflopAnimation = {12, 1000},
    TimerID_FlopTurnRiverAnimation = {13, 1000},
    TimerID_Confirm = {14, 10000},
    TimerID_Next = {15, 1000},
    TimerID_Expense = {16, 5000},
    TimerID_CheckRobot = {17, 5000}
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
    --seatinfo.sid = seat.sid
    --seatinfo.player = {}

    local user = self.users[seat.uid]
    seatinfo.seat.playerinfo = {
        uid = seat.uid or 0,
        username = user and user.username or "",
        gender = user and user.sex or 0,
        nickurl = user and user.nickurl or ""
    }

    seatinfo.isPlaying = seat.isplaying and 1 or 0
    seatinfo.seatMoney = (seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0
    seatinfo.chipinMoney = seat.roundmoney
    seatinfo.chipinType = seat.chiptype
    seatinfo.chipinNum = (seat.roundmoney > seat.chipinnum) and (seat.roundmoney - seat.chipinnum) or 0

    local left_money = seat.chips
    local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0} -- 开局前maxraisepos == 0
    local needcall = maxraise_seat.roundmoney
    if
        self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") and
            maxraise_seat.roundmoney <= self.bigblind
     then
        needcall = 0
    else
        if maxraise_seat.roundmoney < self.bigblind and maxraise_seat.roundmoney ~= 0 then
            needcall = (left_money > self.bigblind) and self.bigblind or left_money
        else
            needcall = (left_money > maxraise_seat.roundmoney) and maxraise_seat.roundmoney or left_money
        end
    end
    seatinfo.needCall = needcall

    -- needRaise
    seatinfo.needRaise = self:minraise()

    seatinfo.needMaxRaise = self:getMaxRaise(seat)
    seatinfo.chipinTime = seat:getChipinLeftTime()
    seatinfo.onePot = self:getOnePot()
    seatinfo.reserveSeat = seat.rv:getReservation()
    seatinfo.totalTime = seat:getChipinTotalTime()
    seatinfo.addtimeCost = self.conf.addtimecost
    seatinfo.addtimeCount = seat.addon_count

    if seat:getIsBuyining() then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_BUYING")
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
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

local function onPreFlopAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onPreFlopAnimation", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_PreflopAnimation[1])
        local bbseat = self.seats[self.bbpos]
        local nextseat = self:getNextActionPosition(bbseat)
        self:betting(nextseat)
    end
    g.call(doRun)
end

local function onFlopTurnRiverAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onFlopAnimation", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
        local bbseat = self.seats[self.bbpos]
        local nextseat = self:getNextActionPosition(bbseat)
        self:betting(nextseat)
    end
    g.call(doRun)
end

local function onAllinAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onAllinAnimation", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_AllinAnimation[1])
        self:onRoundOver()
    end
    g.call(doRun)
end

local function onPotAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onPotAnimation", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_PotAnimation[1])
        self:finish()
        --self:confirm()
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
                log.info("idx(%s,%s) onCheck user logout %s %s", self.id, self.mid, user.logoutts, global.ctsec())
                self:userLeave(uid, linkid)
            end
        end
        -- check all seat users issuses
        for k, v in pairs(self.seats) do
            v:reset()
            local user = self.users[v.uid]
            if user then
                local linkid = user.linkid
                local uid = v.uid
                -- 超时两轮自动站起
                if user.is_bet_timeout and user.bet_timeout_count >= 2 then
                    -- 处理筹码为 0 的情况
                    self:stand(
                        v,
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_ReservationTimesLimit")
                    )
                    user.is_bet_timeout = nil
                    user.bet_timeout_count = 0
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

        if self:getPlayingSize() <= 1 then
            return
        end
        if self:getPlayingSize() > 1 and global.ctsec() > self.endtime then
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
        if r > 1 and all == self.conf.maxuser then  -- 如果座位已坐满且不止一个机器人
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
        log.info("idx(%s,%s) onFinish", self.id, self.mid)
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

        self:getNextState()
        self:reset()
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
    g.call(doRun)
end

local function onStartPreflop(self)
    local function doRun()
        log.info(
            "idx(%s,%s) onStartPreflop bb:%s sb:%s bb_pos:%s sb_pos:%s button_pos:%s",
            self.id,
            self.mid,
            self.bigblind,
            self.smallblind,
            self.bbpos,
            self.sbpos,
            self.buttonpos
        )
        timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])

        self.current_betting_pos = self.bbpos

        self:getNextState()
    end
    g.call(doRun)
end

local function onPrechipsRoundOver(self)
    local function doRun()
        log.info("idx(%s,%s) onPrechipsRoundOver", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
        self:roundOver()

        timer.tick(self.timer, TimerID.TimerID_StartPreflop[1], TimerID.TimerID_StartPreflop[2], onStartPreflop, self)
    end
    g.call(doRun)
end

function Room:getUserMoney(uid)
    local user = self.users[uid]
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
    for _, v in ipairs(self.seats) do
        v.rv:destroy()
    end
end

function Room:getOneCard()
    return self.poker:pop()
end

function Room:getLeftCard()
    local t = {}
    return t
end

function Room:init()
    log.info("idx(%s,%s) room init", self.id, self.mid)
    self.conf = MatchMgr:getConfByMid(self.mid)
    self.users = {}
    self.timer = timer.create()
    self.poker = SamGong:new()
    self.gameId = 0

    self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_None") --牌局状态(preflop, flop, turn...)
    self.buttonpos = -1
    self.sbpos = -1
    self.bbpos = -1
    self.straddlepos = -1
    self.ante = 0
    self.minchip = 1
    self.tabletype = self.conf.matchtype
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000
    self.bettingtime = self.conf.bettime
    self.roundcount = 0
    self.potidx = 1
    self.current_betting_pos = 0
    self.chipinpos = 0
    self.already_show_card = false
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.seats_totalbets = {}
    self.invalid_pot_sid = 0

    self.pots = {} -- 奖池
    self.seats = {} -- 座位
    for sid = 1, self.conf.maxuser do
        local s = Seat:new(self, sid)
        table.insert(self.seats, s)
        table.insert(self.pots, {money = 0, seats = {}})
    end

    self.smallblind = self.conf and self.conf.sb or 50
    self.bigblind = self.conf and self.conf.sb or 50
    self.ante = self.conf and self.conf.ante or 0

    --self.boardlog = BoardLog.new() -- 牌局记录器
    self.statistic = Statistic:new(self.id, self.conf.mid)
    self.sdata = {
        --moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }

    --self.round_finish_time = 0      -- 每一轮结束时间  (preflop - flop - ...)
    self.starttime = 0 -- 牌局开始时间
    self.endtime = 0 -- 牌局结束时间

    self.table_match_start_time = 0 -- 开赛时间
    self.table_match_end_time = 0 -- 比赛结束时间

    self.chipinset = {}
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
                0x308,
                0x209,
                0x40E,
                0x30E,
                0x10E,
                0x109,
                0x10D,
                0x10E,
                0x206,
                0x207,
                0x30E,
                0x30D,
                0x307,
                0x409,
                0x20C,
                0x20D
            }
        }
    )

    -- 主动亮牌
    self.req_show_dealcard = false --客户端请求过主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_NULL")
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
        log.info("idx(%s,%s) room logout uid:%s %s", self.id, self.mid, uid, user and user.logoutts or 0)
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
    log.info("idx(%s,%s) userLeave:%s", self.id, self.mid, uid)
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
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
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
            self.state >= pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"), 0)
                self:stand(
                    self.seats[s.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
            else
                if s.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") then
                    s:chipin(pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"), s.roundmoney)
                --self:sendPosInfoToAll(s, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"))
                end
                self:stand(
                    self.seats[s.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
                local isallfold = self:isAllFold()
                if isallfold or (s.isplaying and self:getPlayingSize() == 2) then
                    log.info("idx(%s,%s) chipin isallfold", self.id, self.mid)
                    self:roundOver()
                    timer.cancel(self.timer, TimerID.TimerID_Start[1])
                    timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                    timer.cancel(self.timer, TimerID.TimerID_AllinAnimation[1])
                    timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
                    timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])
                    timer.cancel(self.timer, TimerID.TimerID_PreflopAnimation[1])
                    timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
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
        log.info("idx(%s,%s) s.sid %s maxraisepos %s", self.id, self.mid, s.sid, self.maxraisepos)
        if s.sid == self.maxraisepos or self.maxraisepos == 0 then
            local maxraise_seat = {roundmoney = -1, sid = s.sid}
            for i = s.sid + 1, s.sid + #self.seats - 1 do
                local j = i % #self.seats > 0 and i % #self.seats or #self.seats
                local seat = self.seats[j]
                --log.info("idx(%s,%s) %s %s %s", self.id, self.mid, j, seat.roundmoney, maxraise_seat.roundmoney)
                if seat and seat.isplaying and seat.roundmoney > maxraise_seat.roundmoney then
                    maxraise_seat = seat
                end
            end
            self.maxraisepos = maxraise_seat.sid
        end
        log.info("idx(%s,%s) maxraisepos %s", self.id, self.mid, self.maxraisepos)
    end

    self.pots[self.potidx].money = self.pots[self.potidx].money + user.roundmoney
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
        log.info("idx(%s,%s) money change uid:%s val:%s", self.id, self.mid, uid, val)
    end

    --战绩
    if user.gamecount and user.gamecount > 0 then
        Statistic:appendRoomLogs(
            {
                uid = uid,
                time = global.ctsec(),
                roomtype = self.conf.roomtype,
                gameid = global.stype(),
                serverid = global.sid(),
                roomid = self.id,
                smallblind = self.smallblind,
                seconds = global.ctsec() - (user.intots or 0),
                changed = val - user.totalbuyin,
                roomname = self.conf.name,
                gamecount = user.gamecount,
                matchid = self.mid,
                api = tonumber(user.api) or 0
            }
        )
    end
    log.info("idx(%s,%s) user leave uid %s", self.id, self.mid, uid)

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
    log.info("idx(%s,%s) userLeave:%s,%s,%s", self.id, self.mid, uid, user.gamecount or 0, val - user.totalbuyin)

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
        log.info("idx(%s,%s) player:%s ip %s code %s into room failed", self.id, self.mid, uid, tostring(ip), code)
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
                log.info("idx(%s,%s) player:%s has been in another room", self.id, self.mid, uid)
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
                                self.conf.sb * self.conf.minbuyinbb,
                                self.conf.sb * self.conf.maxbuyinbb
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
                        log.info("idx(%s,%s) user %s logout or leave", self.id, self.mid, uid)
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                    end
                    if ok and not inseat and self:getUserMoney(uid) + user.chips > self.conf.maxinto then
                        ok = false
                        log.info(
                            "idx(%s,%s) user %s more than maxinto",
                            self.id,
                            self.mid,
                            uid,
                            tostring(self.conf.maxinto)
                        )
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_OverMaxInto")
                    end

                    log.info(
                        "idx(%s,%s) into room money:%s,%s,%s,%s",
                        self.id,
                        self.mid,
                        uid,
                        self:getUserMoney(uid),
                        self.conf.minbuyinbb,
                        self.bigblind
                    )

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
                        log.info("idx(%s,%s) not enough money:%s,%s,%s", self.id, self.mid, uid, ud.money, t.code)
                        return
                    end

                    self.user_cached = false
                    user.state = EnumUserState.Playing

                    log.info(
                        "idx(%s,%s) into room:%s,%s,%s,%s,%s",
                        self.id,
                        self.mid,
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

                    if not quick then
                        quick = (0x2 == (self.conf.buyin & 0x2)) and true or false
                    end
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
    self.pots = {
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}},
        {money = 0, seats = {}}
    }
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.chipinpos = 0
    self.potidx = 1
    self.roundcount = 0
    self.current_betting_pos = 0
    self.already_show_card = false
    self.chipinset = {}
    self.sdata = {
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}
    --self.boardlog:reset()
    self.poker:resetAll()

    self.req_show_dealcard = false
    self.lastchipintype = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_NULL")
    self.lastchipinpos = 0
    self.invalid_pot = 0
    for _, v in pairs(self.users) do
        v.first_chipin_type = 0
    end
    self.potrates = {}
    self.seats_totalbets = {}
    self.invalid_pot_sid = 0
end

function Room:getInvalidPot()
    local invalid_pot = 0
    local isallfold = self:isAllFold()
    local tmp = {}
    if isallfold then
        for k, v in ipairs(self.seats) do
            if v.roundmoney > 0 then
                table.insert(tmp, {k, v.roundmoney})
            end
        end
        if #tmp >= 2 then
            table.sort(
                tmp,
                function(a, b)
                    return a[2] > b[2]
                end
            )
            invalid_pot = tmp[1][2] - tmp[2][2]
        end
    end
    log.info(
        "idx(%s,%s) getInvalidPot:%s,%s,%s",
        self.id,
        self.mid,
        cjson.encode(tmp),
        invalid_pot,
        tostring(isallfold)
    )

    return invalid_pot
end

function Room:potRake(total_pot_chips)
    log.info("idx(%s,%s) into potRake:%s,%s", self.id, self.mid, cjson.encode(self.pots), tostring(self.invalid_pot))
    for k, v in ipairs(self.seats) do
        self.seats_totalbets[k] = v.total_bets or 0
        if k == self.invalid_pot_sid then
            self.seats_totalbets[k] = self.seats_totalbets[k] - (self.invalid_pot or 0)
        end
    end
    total_pot_chips = total_pot_chips - (self.invalid_pot or 0)
    local minipotrake = self.conf.minipotrake or 0
    if total_pot_chips <= minipotrake then
        return total_pot_chips
    end
    local feerate = self.conf.feerate or 0
    local feehandupper = self.conf.feehandupper or 0
    if feerate > 0 then
        log.info("idx(%s,%s) before potRake %s", self.id, self.mid, cjson.encode(self.pots))
        local hand_total_rake, potrake = 0, 0
        for i = 1, self.potidx do
            if hand_total_rake >= feehandupper then
                break
            end
            local seatnum = 0
            for _, sid in pairs(self.pots[i].seats) do
                if sid then
                    seatnum = seatnum + 1
                end
            end
            if seatnum > 1 then
                local pot = self.pots[i].money
                if i == self.potidx then
                    pot = pot - (self.invalid_pot or 0)
                end
                potrake = pot * (feerate / 100) + self.minchip * 0.5
                potrake = math.floor(potrake / self.minchip) * self.minchip
                if potrake > feehandupper then
                    potrake = feehandupper
                end
                self.potrates[i] = potrake
                --self.pots[i].money = self.pots[i].money - potrake
                hand_total_rake = hand_total_rake + potrake
            end
        end
        log.info("idx(%s,%s) after potRake:%s,%s", self.id, self.mid, cjson.encode(self.pots), hand_total_rake)
    end
end

function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s) user table info req uid:%s %s %s", self.id, self.mid, uid, self.smallblind, self.bigblind)
    local tableinfo = {
        gameId = self.gameId,
        seatCount = self.conf.maxuser,
        smallBlind = self.smallblind,
        bigBlind = self.bigblind,
        tableName = self.conf.name,
        gameState = self.state,
        buttonSid = self.buttonpos,
        roundNum = self.roundcount,
        ante = self.ante,
        bettingtime = self.bettingtime,
        matchType = self.conf.matchtype,
        roomType = self.conf.roomtype,
        addtimeCost = self.conf.addtimecost,
        peekWinnerCardsCost = self.conf.peekwinnerhandcardcost,
        toolCost = self.conf.toolcost,
        jpid = self.conf.jpid or 0,
        jp = JackpotMgr:getJackpotById(self.conf.jpid),
        jp_ratios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or {0, 0, 0})
    }

    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        tableinfo.minbuyinbb = self.conf.minbuyinbb
        tableinfo.maxbuyinbb = self.conf.maxbuyinbb
    end

    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
end

function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid then
            local seatinfo = fillSeatInfo(seat, self)
            if seat.uid == uid then
                seatinfo.handcards = seat.handcards
            else
                seatinfo.handcards = {}
                for _, v in ipairs(seat.handcards) do
                    table.insert(seatinfo.handcards, (v ~= 0) and 0 or -1) -- -1 无手手牌，0 牌背
                end
            end

            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end

    tableinfo.publicPools = {}
    for i = 1, self.potidx do
        if self.state ~= pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_None") then
            table.insert(tableinfo.publicPools, self.pots[i].money)
        end
    end

    local resp = pb.encode("network.cmd.PBSamGongTableInfoResp", {tableInfo = tableinfo})
    log.info("idx(%s,%s) user table info resp uid:%s %s", self.id, self.mid, uid, cjson.encode(tableinfo))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongTableInfoResp"),
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

function Room:getOnePot()
    local money = 0
    for i = 1, #self.seats do
        if self.seats[i].isplaying then
            money = money + self.seats[i].money + self.seats[i].roundmoney
        end
    end
    return money
end

function Room:getPotCount()
    return self.potidx
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

function Room:getNextActionPosition(seat)
    log.info("idx(%s,%s) getNextActionPosition sid:%s,%s", self.id, self.mid, seat.sid, tostring(self.maxraisepos))
    local pos = seat.sid
    for i = pos + 1, pos + #self.seats - 1 do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if
            seat and seat.isplaying and
                seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") and
                seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")
         then
            seat.addon_count = 0
            return seat
        end
    end
    return self.seats[self.maxraisepos]
end

function Room:getAllinSize()
    local allin = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if
            seat.isplaying and
                seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN")
         then
            allin = allin + 1
        end
    end
    return allin
end

function Room:setShowCard(pos, riverraise, poss)
    local seat = self.seats[pos]
    if
        seat and seat.isplaying and
            seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and
            not self:isAllFold()
     then
        seat.show = true
    end
end

function Room:isRegularMatch()
    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        return true
    else
        return false
    end
end

function Room:moveButton()
    log.info("idx(%s,%s) move button", self.id, self.mid)

    if self.bbpos == -1 then
        self.bbpos = rand.rand_between(1, #self.seats)
    end
    for i = self.bbpos + 1, self.bbpos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat.isplaying and not seat.isbuyining then
            self.bbpos = j
            break
        end
    end
    for i = self.bbpos + 1, self.bbpos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat.isplaying and not seat.isbuyining then
            self.buttonpos = j
            self.chipinpos = j
            break
        end
    end

    log.info(
        "idx(%s,%s) movebutton:%s,%s,%s,%s",
        self.id,
        self.mid,
        self.bbpos,
        self.sbpos,
        self.buttonpos,
        self.chipinpos
    )
    return true
end

function Room:getGameId()
    return self.gameId + 1
end

function Room:stand(seat, uid, stype)
    log.info("idx(%s,%s) stand uid,sid:%s,%s,%s", self.id, self.mid, uid, seat.sid, tostring(stype))
    local user = self.users[uid]
    if seat and user then
        if
            self.state >= pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish") and
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
            self.sdata.users[uid].ugameinfo.texas.leftchips = seat.chips - seat.roundmoney
            -- 实时牌局
            self.reviewlogitems[seat.uid] =
                self.reviewlogitems[seat.uid] or
                {
                    player = {
                        uid = seat.uid,
                        username = user.username or ""
                    },
                    handcards = {
                        sid = seat.sid,
                        handcards = seat.show and seat.handcards or {0, 0, 0}
                    },
                    bestcards = seat.besthand,
                    bestcardstype = seat.handtype,
                    win = self.sdata.users[uid].totalpureprofit or seat.chips - seat.last_chips - seat.roundmoney,
                    showhandcard = seat.show,
                    efshowhandcarduid = {},
                    usershowhandcard = {0, 0},
                    roundchipintypes = seat.roundchipintypes,
                    roundchipinmoneys = seat.roundchipinmoneys
                }
        end
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
end

function Room:sit(seat, uid, buyinmoney, ischangetable)
    log.info(
        "idx(%s,%s) sit uid %s,sid %s buyin %s %s",
        self.id,
        self.mid,
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

        seat:sit(uid, user.chips, 0, 0, user.totalbuyin)
        local clientBuyin =
            (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante + self.conf.fee or 0))
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
        log.info("idx(%s,%s) uid %s sid %s sit clientBuyin %s", self.id, self.mid, uid, seat.sid, tostring(clientBuyin))
        local seatinfo = fillSeatInfo(seat, self)
        pb.encode(
            "network.cmd.PBSamGongPlayerSit",
            {seatInfo = seatinfo, clientBuyin = clientBuyin, buyinTime = self.conf.buyintime},
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongPlayerSit"),
                    pointer,
                    length
                )
            end
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
            "network.cmd.PBSamGongUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongUpdateSeat"),
                    pointer,
                    length
                )
            end
        )
    end
end

function Room:start()
    self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Start")

    self.gameId = self:getGameId()
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec()
    self.logid = self.has_started and self.statistic:genLogId(self.starttime) or self.logid
    self.has_started = self.has_started or true

    self.smallblind = self.conf and self.conf.sb or 50
    self.bigblind = self.conf and self.conf.sb or 50
    self.ante = self.conf and self.conf.ante or 0
    self.minchip = self.conf and self.conf.minchip or 1
    self.has_player_inplay = false

    -- 玩家状态，金币数等数据初始化
    self:reset()
    self:moveButton()

    self.maxraisepos = self.bbpos
    self.maxraisepos_real = self.maxraisepos
    self.current_betting_pos = self.maxraisepos
    log.info(
        "idx(%s,%s) start sb:%s bb:%s ante:%s minchip:%s gameId:%s betpos:%s logid:%s",
        self.id,
        self.mid,
        self.smallblind,
        self.bigblind,
        self.ante,
        self.minchip,
        self.gameId,
        self.current_betting_pos,
        tostring(self.logid)
    )
    self.poker:start()
    --配牌处理
    if self.cfgcard_switch then
        self:setcard()
    end

    -- 服务费
    for k, v in ipairs(self.seats) do
        if v.uid and v.isplaying then
            local user = self.users[v.uid]
            if user then
                user.gamecount = (user.gamecount or 0) + 1 -- 统计数据
            end
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
            -- 统计数据
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].cards = v.handcards
            self.sdata.users[v.uid].sid = k
            self.sdata.users[v.uid].username = user and user.username or ""
            self.sdata.users[v.uid].extrainfo =
                cjson.encode(
                {
                    ip = user and user.ip or "",
                    api = user and user.api or "",
                    roomtype = self.conf.roomtype,
                    playchips = 20 * (self.conf and self.conf.fee or 0) -- 2021-12-24
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
        smallBlind = self.smallblind,
        bigBlind = self.bigblind,
        ante = self.ante,
        minChip = self.minchip,
        table_starttime = self.starttime,
        seats = fillSeats(self)
    }
    pb.encode(
        "network.cmd.PBSamGongGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongGameStart"),
                pointer,
                length
            )
        end
    )

    local curplayers = 0
    -- 同步当前状态给客户端
    for k, v in ipairs(self.seats) do
        if v.uid then
            self:sendPosInfoToAll(v)
            curplayers = curplayers + 1
        end
    end

    -- 数据统计
    self.sdata.stime = self.starttime
    self.sdata.gameinfo = self.sdata.gameinfo or {}
    self.sdata.gameinfo.texas = self.sdata.gameinfo.texas or {}
    self.sdata.gameinfo.texas.sb = self.smallblind
    self.sdata.gameinfo.texas.bb = self.bigblind
    self.sdata.gameinfo.texas.maxplayers = self.conf.maxuser
    self.sdata.gameinfo.texas.curplayers = curplayers
    self.sdata.gameinfo.texas.ante = self.conf.ante
    self.sdata.jp = {minichips = self.minchip}
    self.sdata.extrainfo =
        cjson.encode({buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0})
    if self:getPlayingSize() == 1 then
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
        return
    end

    -- 前注，大小盲处理
    self:dealPreChips()
end

function Room:checkCanChipin(seat)
    return seat and seat.uid and seat.sid == self.current_betting_pos and seat.isplaying
end

function Room:chipin(uid, type, money)
    local seat = self:getSeatByUid(uid)
    if not self:checkCanChipin(seat) then
        return false
    end

    if seat.chips < money then
        money = seat.chips
    end

    log.info(
        "idx(%s,%s) chipin pos:%s uid:%s type:%s money:%s",
        self.id,
        self.mid,
        seat.sid,
        seat.uid and seat.uid or 0,
        type,
        money
    )

    local function fold_func(seat, type, money)
        seat:chipin(type, seat.roundmoney)
        seat.rv:checkSitResultSuccInTime()
    end

    local function call_check_raise_allin_func(seat, type, money)
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
        if type == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK") and money == 0 then
            if seat.roundmoney >= maxraise_seat.roundmoney then
                type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK")
                money = seat.roundmoney
            else
                type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")
            end
        elseif
            type == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") and money < seat.chips
         then
            money = seat.chips
        elseif
            type == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_RAISE") and money == seat.chips
         then
            type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN")
        elseif money < seat.chips and money < maxraise_seat.roundmoney then
            --money = 0
            type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")
        else
            if money < seat.roundmoney then
                if type == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK") and money == 0 then
                    type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK")
                else
                    type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")
                    money = 0
                end
            elseif money > seat.roundmoney then
                if money == maxraise_seat.roundmoney then
                    type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CALL")
                else
                    type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_RAISE")
                end
            else
                type = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK")
            end
        end
        seat:chipin(type, money)
    end

    local function smallblind_func(seat, type, money)
        seat:chipin(type, money)
    end

    local function bigblind_func(seat, type, money)
        seat:chipin(type, money)
    end

    local switch = {
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")] = fold_func,
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CALL")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_RAISE")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_SMALLBLIND")] = smallblind_func,
        [pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_BIGBLIND")] = bigblind_func
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s) invalid chiptype uid:%s type:%s", self.id, self.mid, uid, type)
        return false
    end

    -- 真正操作chipin
    chipin_func(seat, type, money)

    local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
    if seat.roundmoney > maxraise_seat.roundmoney then
        self.maxraisepos = seat.sid
        if (self.seats[seat.sid].roundmoney >= self:minraise()) then
            self.maxraisepos_real = seat.sid
        end
    end

    if
        self.maxraisepos == seat.sid and
            (seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_RAISE") or
                seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN"))
     then
        self.seats[self.maxraisepos].reraise = true
    end

    self.chipinpos = seat.sid
    self:sendPosInfoToAll(seat)

    if
        type ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and
            type ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_SMALLBLIND") and
            money > 0
     then
        self.chipinset[#self.chipinset + 1] = money
    end

    return true
end

--
-- 参数 type：操作类型
-- 参数 money: 本轮要下注的金额
function Room:userchipin(uid, type, money, client)
    log.info(
        "idx(%s,%s) userchipin: uid %s, type %s, money %s",
        self.id,
        self.mid,
        tostring(uid),
        tostring(type),
        tostring(money)
    )
    uid = uid or 0
    type = type or 0
    money = money or 0
    if
        self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_None") or
            self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish")
     then
        log.info("idx(%s,%s) user chipin state invalid:%s", self.id, self.mid, self.state)
        return false
    end
    local chipin_seat = self:getSeatByUid(uid)
    if not chipin_seat then
        log.info("idx(%s,%s) invalid chipin seat", self.id, self.mid)
        return false
    end
    if self.current_betting_pos ~= chipin_seat.sid or not chipin_seat.isplaying then
        log.info(
            "idx(%s,%s) invalid chipin pos:%s %s",
            self.id,
            self.mid,
            chipin_seat.sid,
            tostring(chipin_seat.isplaying)
        )
        return false
    end
    if self.minchip == 0 then
        log.info("idx(%s,%s) chipin minchip invalid uid:%s", self.id, self.mid, uid)
        return false
    end

    if money % self.minchip ~= 0 then
        if money < self.minchip then
            money = self.minchip
        else
            money = math.floor(money / self.minchip) * self.minchip
        end
    end

    local user = self.users[uid]
    if client and user then
        user.is_bet_timeout = nil
        user.bet_timeout_count = 0
        user.first_chipin_type = user.first_chipin_type or 0
        if user.first_chipin_type == 0 then
            if type == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then --如果当前玩家弃牌
                user.first_chipin_type = 2
            else
                user.first_chipin_type = 1
            end
        end
        if type == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") then
            user.first_chipin_type = user.first_chipin_type | 4
        end
    end

    local chipin_result = self:chipin(uid, type, money)
    if not chipin_result then
        log.info("idx(%s,%s) chipin failed uid:%s", self.id, self.mid, uid)
        return false
    end
    if chipin_seat.sid == self.current_betting_pos then
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
    end

    local isallfold = self:isAllFold()
    if isallfold then
        log.info("idx(%s,%s) chipin isallfold", self.id, self.mid)
        self:roundOver()
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_AllinAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
        timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])
        timer.cancel(self.timer, TimerID.TimerID_PreflopAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
        --onPotAnimation(self)
        timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
        return true
    end

    local next_seat = self:getNextActionPosition(self.seats[self.chipinpos])
    log.info(
        "idx(%s,%s) next_seat uid:%s chipin_pos:%s chipin_uid:%s chiptype:%s chips:%s",
        self.id,
        self.mid,
        next_seat and next_seat.uid or 0,
        tostring(self.chipinpos),
        self.seats[self.chipinpos].uid,
        self.seats[self.chipinpos].chiptype,
        chipin_seat.chips
    )

    log.info(
        "idx(%s,%s) isAllCall:%s isAllAllin:%s next_seat.sid:%s self.maxraisepos:%s",
        self.id,
        self.mid,
        self:isAllCall() and 1 or 0,
        self:isAllAllin() and 1 or 0,
        next_seat.sid,
        self.maxraisepos
    )

    local maxraise_seat =
        self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {reraise = false, roundmoney = 0}
    if maxraise_seat.reraise then
        if next_seat.sid == self.maxraisepos or self:isAllCall() or self:isAllAllin() then
            timer.tick(
                self.timer,
                TimerID.TimerID_AllinAnimation[1],
                TimerID.TimerID_AllinAnimation[2],
                onAllinAnimation,
                self
            )
        else
            self:betting(next_seat)
        end
    else
        log.info("idx(%s,%s) isReraise %s", self.id, self.mid, self.maxraisepos)
        local chipin_seat = self.seats[self.chipinpos]
        local chipin_seat_chiptype = chipin_seat.chiptype
        if
            self:isAllCheck() or self:isAllAllin() or
                (self.maxraisepos == self.chipinpos and
                    (pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK") == chipin_seat_chiptype or
                        pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") ==
                            chipin_seat_chiptype))
         then
            timer.tick(
                self.timer,
                TimerID.TimerID_AllinAnimation[1],
                TimerID.TimerID_AllinAnimation[2],
                onAllinAnimation,
                self
            )
        else
            self:betting(next_seat)
        end
    end
    return true
end

function Room:getNextState()
    local oldstate = self.state

    if oldstate == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreChips") then
        self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop")
        self:dealPreFlop()
    elseif oldstate == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") then
        self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_River")
        self:dealRiver()
    elseif oldstate == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_River") then
        --        self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Confirm")
        --        self:confirm()
        --    elseif oldstate == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Confirm") then
        self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish")
        self:finish()
    elseif oldstate == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish") then
        self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_None")
    end

    log.info("idx(%s,%s) State Change: %s => %s", self.id, self.mid, oldstate, self.state)
end

function Room:dealPreChips()
    log.info("idx(%s,%s) dealPreChips ante:%s", self.id, self.mid, self.ante)
    self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreChips")
    if self.ante > 0 then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            if seat.isplaying then
                --seat的chipin, 不是self的chipin
                seat:chipin(pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_PRECHIPS"), self.ante)
                self:sendPosInfoToAll(seat)
            end
        end

        timer.tick(
            self.timer,
            TimerID.TimerID_PrechipsRoundOver[1],
            TimerID.TimerID_PrechipsRoundOver[2],
            onPrechipsRoundOver,
            self
        )
    end
end

local function dealHandCards(self)
    local dealcard = {}
    for _, seat in ipairs(self.seats) do
        table.insert(
            dealcard,
            {
                sid = seat.sid,
                state = self.state,
                handcards = {}
            }
        )
    end

    -- 旁观广播牌背
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and (not self:getSeatByUid(k) or not self:getSeatByUid(k).isplaying) then
            net.send(
                v.linkid,
                k,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongDealCard"),
                pb.encode("network.cmd.PBSamGongDealCard", {cards = dealcard})
            )
        end
    end

    for k, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user then
            if
                seat.isplaying and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")
             then
                if self.cfgcard_switch then
                    if self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") then
                        seat.handcards[1] = self.cfgcard:popHand()
                        seat.handcards[2] = self.cfgcard:popHand()
                    else
                        seat.handcards[3] = self.cfgcard:popHand()
                    end
                else
                    if self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") then
                        seat.handcards[1] = self:getOneCard()
                        seat.handcards[2] = self:getOneCard()
                    else
                        seat.handcards[3] = self:getOneCard()
                    end
                end

                local tmp = g.copy(dealcard)
                for i, dc in ipairs(tmp) do
                    if dc.sid == k then
                        table.insert(dc.handcards, seat.handcards[1])
                        table.insert(dc.handcards, seat.handcards[2])
                        table.insert(dc.handcards, seat.handcards[3])
                        if self.state ~= pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") then
                            dc.cardtype = self.poker:getHandType(seat.handcards)
                            dc.point = self.poker:getCardsPoint(seat.handcards)
                        end
                    end
                end

                net.send(
                    user.linkid,
                    seat.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongDealCard"),
                    pb.encode("network.cmd.PBSamGongDealCard", {cards = tmp})
                )
                log.info(
                    "idx(%s,%s) dealHandCards uid:%s handcard:%s",
                    self.id,
                    self.mid,
                    seat.uid,
                    string.format("0x%x,0x%x,0x%x", seat.handcards[1], seat.handcards[2], seat.handcards[3])
                )

                -- 统计数据
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].cards = seat.handcards
                self.sdata.users[seat.uid].sid = k
                self.sdata.users[seat.uid].username = user.username
                self.sdata.users[seat.uid].extrainfo =
                    cjson.encode(
                    {
                        ip = user.ip or "",
                        api = user.api or "",
                        roomtype = self.conf.roomtype,
                        playchips = 20 * (self.conf and self.conf.fee or 0) -- 2021-12-24
                    }
                )
                if k == self.buttonpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
                else
                    self.sdata.users[seat.uid].role =
                        pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
                end
            end
        end
    end
end

function Room:dealPreFlop()
    dealHandCards(self)
    if self:isAllAllin() then
        timer.tick(
            self.timer,
            TimerID.TimerID_AllinAnimation[1],
            TimerID.TimerID_AllinAnimation[2],
            onAllinAnimation,
            self
        )
    else
        timer.tick(
            self.timer,
            TimerID.TimerID_PreflopAnimation[1],
            TimerID.TimerID_PreflopAnimation[2],
            onPreFlopAnimation,
            self
        )
    end
end

function onNext(self)
    timer.cancel(self.timer, TimerID.TimerID_Next[1])
    self:getNextState()
end

function Room:dealRiver()
    dealHandCards(self) -- 第二轮发牌

    -- m_seats.dealRiver start
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.chipinset[#self.chipinset + 1] = 0

    if self:isAllAllin() then
        --self:getNextState()

        timer.tick(self.timer, TimerID.TimerID_Next[1], TimerID.TimerID_Next[2], onNext, self)
    else
        timer.tick(
            self.timer,
            TimerID.TimerID_FlopTurnRiverAnimation[1],
            TimerID.TimerID_FlopTurnRiverAnimation[2],
            onFlopTurnRiverAnimation,
            self
        )
    end
end

local function onConfirm(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Confirm[1])

        -- 检测是否确认超时
        for k, seat in ipairs(self.seats) do
            local user = self.users[seat.uid]
            if user then
                if
                    seat.isplaying and
                        seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD")
                 then
                    if not seat.confirm then
                        user.is_bet_timeout = true
                        user.bet_timeout_count = user.bet_timeout_count or 0
                        user.bet_timeout_count = user.bet_timeout_count + 1
                    end
                end
            end
        end

        self:finish()
    end
    g.call(doRun)
end

function Room:confirm()
    self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Confirm")
    self.confirm_timestamp = global.ctsec()

    local isallfold = self:isAllFold()
    if isallfold then
        onConfirm(self)
    else
        local t = {sidlist = {}}
        for k, v in ipairs(self.seats) do
            if v.isplaying and v.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
                table.insert(t.sidlist, k)
            end
        end
        log.debug("idx(%s,%s) confirm %s", self.id, self.mid, cjson.encode(t))
        pb.encode(
            "network.cmd.PBSamGongConfirmNotify",
            t,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongConfirmNotify"),
                    pointer,
                    length
                )
            end
        )
        timer.tick(self.timer, TimerID.TimerID_Confirm[1], TimerID.TimerID_Confirm[2], onConfirm, self)
    end
end

function Room:isAllAllin()
    local allin = 0
    local playing = 0
    local pos = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
                playing = playing + 1
                if seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") then
                    allin = allin + 1
                else
                    pos = i
                end
            end
        end
    end

    --log.debug("Room:isAllAllin %s,%s playing:%s allin:%s self.maxraisepos:%s pos:%s", self.id,self.mid,playing, allin, self.maxraisepos, pos)

    if playing == allin + 1 then
        if self.maxraisepos == pos or self.maxraisepos == 0 then
            return true
        end
    end

    if playing == allin then
        return true
    end

    return false
end

function Room:isAllCall()
    --log.debug("Room:isAllCall %s,%s ...", self.id,self.mid)
    local maxraise_seat = self.seats[self.maxraisepos]
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            --log.debug("Room:isAllCall chiptype:%s roundmoney:%s max_roundmoney:%s", seat.chiptype, seat.roundmoney, maxraise_seat.roundmoney)
            if
                seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CALL") and
                    seat.roundmoney < maxraise_seat.roundmoney
             then
                return false
            end

            if
                seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CALL") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN")
             then
                return false
            end
        end
    end
    return true
end

function Room:isAllFold()
    local fold_count = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
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

function Room:isAllCheck()
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if
                seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN")
             then
                return false
            end
        end
    end
    return true
end

-- 计算最小加注金额
function Room:minraise()
    local current_betting_seat = self.seats[self.current_betting_pos]
    if self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") then
        local maxdiff, maxchipin, flag = self:getMaxDiff()
        if not flag and maxdiff < self.bigblind then
            maxdiff = self.bigblind
        end
        if maxdiff + maxchipin < 2 * self.bigblind then
            if current_betting_seat and current_betting_seat.chips < 2 * self.bigblind then
                return current_betting_seat.chips
            end
            return 2 * self.bigblind
        end
        return maxdiff + maxchipin
    elseif
        self.state > pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreFlop") and
            self.state < pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish")
     then
        if #self.chipinset == 1 then
            if current_betting_seat and current_betting_seat.chips < self.bigblind then
                return current_betting_seat.chips
            end
            return self.bigblind
        else
            local maxdiff, maxchipin, flag = self:getMaxDiff()
            if not flag and maxdiff < self.bigblind then
                maxdiff = self.bigblind
            end
            if maxdiff + maxchipin < self.bigblind then
                if current_betting_seat and current_betting_seat.chips < self.bigblind then
                    return current_betting_seat.chips
                end
                return self.bigblind
            end
            return maxdiff + maxchipin
        end
    end
    return 0
end

function Room:getMaxDiff()
    local maxdiff = 0
    local maxchipin = 0
    local flag = true

    if #self.chipinset == 0 then
        return maxdiff, maxchipin, flag
    end

    local i = 2
    while i <= #self.chipinset do
        maxdiff = math.max(maxdiff, self.chipinset[i] - self.chipinset[i - 1])
        maxchipin = math.max(maxchipin, self.chipinset[i - 1])
        if self.chipinset[i - 1] >= self.bigblind then
            flag = false
        end
        i = i + 1
    end

    maxchipin = math.max(maxchipin, self.chipinset[#self.chipinset])
    if self.chipinset[#self.chipinset] >= self.bigblind then
        flag = false
    end

    --log.debug("max diff %s, chipin %s, flag %s", maxdiff, maxchipin, flag and 1 or 0)
    return maxdiff, maxchipin, flag
end

function Room:getMaxRaise(seat)
    if not seat or not seat.uid then
        return 0
    end

    local playing = 0
    local allin = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
                playing = playing + 1
                if seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") then
                    allin = allin + 1
                end
            end
        end
    end

    local minraise_ = self:minraise()
    if playing == allin + 1 then
        local maxraise_seat = self.seats[self.maxraise_seat] and self.seats[self.maxraise_seat] or {chips = 0}
        if maxraise_seat.chips < seat.chips then
            --return self:minraise()
            return minraise_
        end
    end
    --return seat.chips

    if (self.maxraisepos == self.maxraisepos_real) then
        return seat.chips
    end
    -- 出现无效加注情况
    if self.seats[self.maxraisepos_real] and seat.roundmoney <= self.seats[self.maxraisepos_real].roundmoney then
        --if (seat.roundmoney < self.seats[self.maxraisepos_real].roundmoney) then
        --出现无效加注后没行动过的玩家，可以加注
        return seat.chips
    end
    --出现无效加注前行动过的玩家，只能call or fold
    --如果出现无效加注后 再有玩家加注， m_maxraisepos_real == m_maxraisepos
    return minraise_
end

local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos]
        log.info(
            "idx(%s,%s) onBettingTimer over time bettingpos:%s uid:%s",
            self.id,
            self.mid,
            self.current_betting_pos,
            current_betting_seat and current_betting_seat.uid or 0
        )
        if not current_betting_seat then
            return
        end

        local user = self.users[current_betting_seat.uid]
        if current_betting_seat:isChipinTimeout() then
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            if user then
                --for debug
                user.is_bet_timeout = true
                user.bet_timeout_count = user.bet_timeout_count or 0
                user.bet_timeout_count = user.bet_timeout_count + 1
            end
            --self:userchipin(current_betting_seat.uid, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"), 0)
            self:userchipin(
                current_betting_seat.uid,
                pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK"),
                current_betting_seat.roundmoney
            )
        end
    end
    g.call(doRun)
end

-- 轮到某座位操作
function Room:betting(seat)
    if not seat then
        return false
    end
    seat.bettingtime = global.ctsec()
    self.current_betting_pos = seat.sid
    log.info("idx(%s,%s) it's betting pos:%s uid:%s", self.id, self.mid, self.current_betting_pos, tostring(seat.uid))

    local function notifyBetting()
        --print('notifyBetting')
        -- 统计
        --seat.si.totaljudgecount = seat.si.totaljudgecount + 1

        -- 广播某座位准备下注
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_BETING"))
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self)
    end

    -- 预操作
    local preop = seat:getPreOP()

    if preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None") then
        notifyBetting()
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_CheckOrFold") then
        self:userchipin(
            seat.uid,
            pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK"),
            seat.roundmoney
        )
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_AutoCheck") then
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
        if seat.roundmoney < maxraise_seat.roundmoney then
            notifyBetting()
        else
            self:userchipin(seat.uid, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CHECK"), 0)
        end
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny") then -- 预跟注
        -- 跟注
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
        log.info("dfr roundmoney=%s,maxraise_seat.roundmoney=%s", seat.roundmoney, maxraise_seat.roundmoney)
        if seat.roundmoney <= maxraise_seat.roundmoney then
            notifyBetting()
            self:userchipin(
                seat.uid,
                pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_CALL"),
                maxraise_seat.roundmoney
            )
        end
    end
end

function Room:onRoundOver()
    log.info("idx(%s,%s) onRoundOver", self.id, self.mid)
    self:roundOver()
    self:getNextState()
end

function Room:broadcastShowCardToAll()
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying and seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
            if seat.show then
                local showdealcard = {
                    showType = 1,
                    sid = i,
                    handcards = seat.handcards,
                    cardtype = self.poker:getHandType(seat.handcards)
                }
                if
                    showdealcard.cardtype ==
                        pb.enum_id("network.cmd.PBSamGongCardWinType", "SamGongCardWinType_PointCard")
                 then
                    showdealcard.point = self.poker:getCardsPoint(seat.handcards)
                end
                pb.encode(
                    "network.cmd.PBSamGongShowDealCard",
                    showdealcard,
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongShowDealCard"),
                            pointer,
                            length
                        )
                    end
                )
            end
        end
    end
end

function Room:finish()
    log.info("idx(%s,%s) finish potidx:%s", self.id, self.mid, self.potidx)

    for _, v in pairs(self.users) do
        if v and not Utils:isRobot(v.api) and not self.has_player_inplay then
            self.has_player_inplay = true
            break
        end
    end

    --local t_msec = (6 + self:getPotCount() * 3) * 1000

    self.state = pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish")

    -- m_seats.finish start
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    --[[ 计算在玩玩家最佳牌形和最佳手牌，用于后续比较 --]]
    for i = 1, #self.seats do
        local seat = self.seats[i]

        if seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and seat.isplaying then
            if #seat.handcards < 3 then
                log.info(
                    "[error]idx(%s,%s) cardnum=%s,seat.chiptype=%s",
                    self.id,
                    self.mid,
                    #seat.handcards,
                    seat.chiptype
                )
            end
            seat.handtype = self.poker:getHandType(seat.handcards)
            log.info("idx(%s,%s) getHandType:%s %s", self.id, self.mid, cjson.encode(seat.handcards), seat.handtype)
        end
    end
    log.info("idx(%s,%s) pots:%s", self.id, self.mid, cjson.encode(self.pots))

    local minchip = self.minchip
    local total_winner_info = {} -- 总的奖池分池信息，哪些人在哪些奖池上赢取多少钱都在里面
    local FinalGame = {potInfos = {}, profits = {}, seatMoney = {}}
    -- 查找无主奖池（已站起座位）
    local total_pot_chips = 0 -- 所有池子总和
    local bonus_pot_chips = 0 -- 所有无主奖池总和
    local bonus_pot = {} -- 无主奖池
    local bonus_seats = {} -- 参与分享无奖池的座位
    for i = self.potidx, 1, -1 do
        total_pot_chips = total_pot_chips + self.pots[i].money
        local isbonus = true
        for _, sid in pairs(self.pots[i].seats) do
            if self.seats[sid].uid ~= 0 then
                isbonus = false
            end
        end
        if isbonus then
            table.insert(bonus_pot, i)
            bonus_pot_chips = bonus_pot_chips + self.pots[i].money
        end
    end
    log.info("idx(%s,%s) pots:%s", self.id, self.mid, cjson.encode(self.pots))

    self:potRake(total_pot_chips)

    log.info(
        "idx(%s,%s) total_pot_chips:%s bonus_pot_chips:%s bonus_pot:%s",
        self.id,
        self.mid,
        total_pot_chips,
        bonus_pot_chips,
        cjson.encode(bonus_pot)
    )
    -- 无主奖池按比例分到其它奖池里
    for i = self.potidx, 1, -1 do
        if self.pots[i].money > 0 and g.find(bonus_pot, i) == -1 then
            --print('i', i, 'pots[i].money', self.pots[i].money)
            self.pots[i].money =
                self.pots[i].money +
                math.floor(self.pots[i].money / (total_pot_chips - bonus_pot_chips) * bonus_pot_chips)
        end
    end
    log.info("idx(%s,%s) pots:%s", self.id, self.mid, cjson.encode(self.pots))

    -- 计算对于每个奖池，每个参与的玩家赢多少钱
    for i = self.potidx, 1, -1 do
        local winnerlist = {} -- i号奖池的赢牌玩家列表，能同时多人赢，所以用table

        for j = 1, #self.seats do
            local seat = self.seats[j]
            if
                seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and
                    seat.isplaying
             then
                -- i号奖池，j号玩家是有份参与的
                if self.pots[i].seats[j] then
                    if #winnerlist == 0 then
                        table.insert(winnerlist, {sid = j, winmoney = 0})
                    end
                    -- 不和自己比较
                    if winnerlist[#winnerlist] and winnerlist[#winnerlist].sid ~= j then
                        local tmp_wi = winnerlist[#winnerlist]
                        local winner_seat = self.seats[tmp_wi.sid]
                        local result = self.poker:compare(seat.handcards, winner_seat.handcards)

                        -- 1：A赢牌   0：和牌   -1：A输牌
                        if result == 0 then
                            table.insert(winnerlist, {sid = j, winmoney = 0})
                        elseif result == 1 then
                            -- 发现目前为止牌形最大的人
                            winnerlist = {}
                            table.insert(winnerlist, {sid = j, winmoney = 0})
                        end
                    end
                end
            end
        end

        -- i号奖池赢钱人计算完成，下面计算赢多少钱
        if #winnerlist ~= 0 then
            local avg = math.floor((self.pots[i].money - (self.potrates[i] or 0)) / #winnerlist)
            local avg_floor = math.floor(avg / minchip) * minchip
            local remain = self.pots[i].money - (self.potrates[i] or 0) - avg_floor * #winnerlist
            local remain_floor = math.floor(remain / minchip)

            for j = self.sbpos, self.sbpos + #self.seats - 1 do
                local pos = j % #self.seats > 0 and j % #self.seats or #self.seats
                for k = 1, #winnerlist do
                    local wi = winnerlist[k]
                    if pos == wi.sid then
                        if remain_floor ~= 0 then
                            wi.winmoney = avg_floor + minchip
                            remain_floor = remain_floor - 1
                        else
                            wi.winmoney = avg_floor
                        end
                        break
                    end
                end
            end
        end

        -- 加钱
        for j = 1, #winnerlist do
            local wi = winnerlist[j]
            if wi and self.seats[wi.sid] then
                self.seats[wi.sid].chips = self.seats[wi.sid].chips + wi.winmoney
            end
        end

        for j = 1, #winnerlist do
            local wi = winnerlist[j]
            if wi and self.seats[wi.sid] then
                local potinfo = {}
                potinfo.potID = i - 1 -- i号奖池 (客户端那边potID从0开始)
                potinfo.sid = wi.sid
                potinfo.potMoney = self.pots[i].money
                potinfo.winMoney = wi.winmoney
                potinfo.seatMoney = self.seats[wi.sid].chips
                potinfo.mark = {}
                if self:isAllFold() then
                    potinfo.winType = pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_WINNING")
                else
                    potinfo.winType = self.seats[wi.sid].handtype
                end
                table.insert(FinalGame.potInfos, potinfo)

                if #bonus_pot > 0 then
                    bonus_seats[wi.sid] = true
                end
            end
        end

        -- 总的奖池分池信息获取， 用于上报等
        for j = 1, #winnerlist do
            local wi = winnerlist[j]
            local potid = i
            total_winner_info[potid] = total_winner_info[potid] or {}
            total_winner_info[potid][wi.sid] = wi.winmoney -- 第 potid 个奖池，sid 为 wi.sid 的人赢了 wi.winmoney
        end
    end

    -- 无主奖池
    for sid, _ in pairs(bonus_seats) do
        for _, potid in pairs(bonus_pot) do
            local potinfo = {}
            potinfo.potID = potid - 1 -- i号奖池 (客户端那边potID从0开始)
            potinfo.sid = sid
            table.insert(FinalGame.potInfos, potinfo)
        end
    end

    local winnerpot_potrate = {}
    -- show牌
    local poss = {} -- 记录赢钱的人的sid  (Set)
    for potid, info in pairs(total_winner_info) do
        local seatnum = 0
        for pos, _ in pairs(info) do
            poss[pos] = true
            seatnum = seatnum + 1
        end
        if seatnum > 0 then
            for pos, _ in pairs(info) do
                winnerpot_potrate[pos] = (winnerpot_potrate[pos] or 0) + (self.potrates[potid] or 0) / seatnum
            end
        end
    end

    --JackPot抽水
    if JACKPOT_CONF[self.conf.jpid] then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            local win = seat.chips - seat.last_chips
            local delta_add = JACKPOT_CONF[self.conf.jpid].deltabb * self.bigblind
            if seat.isplaying and win > JACKPOT_CONF[self.conf.jpid].profitbb * self.bigblind then
                self.sdata.jp.delta_add = (self.sdata.jp.delta_add or 0) + delta_add
                seat.chips = seat.chips > delta_add and seat.chips - delta_add or 0
                local extrainfo = cjson.decode(self.sdata.users[seat.uid].extrainfo)
                if extrainfo then
                    extrainfo["jpdelta"] = delta_add
                    self.sdata.users[seat.uid].extrainfo = cjson.encode(extrainfo)
                end
            end
        end
        if self.sdata.jp.delta_add or self.sdata.jp.delta_sub then
            self.sdata.jp.id = self.conf.jpid
        end
    end

    local showcard_players = 0
    for k, v in ipairs(self.seats) do
        table.insert(FinalGame.seatMoney, v.chips)
        if v.isplaying then
            table.insert(FinalGame.profits, v.chips - v.last_chips)
        else
            table.insert(FinalGame.profits, 0)
        end
        if v.isplaying and v.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
            self:setShowCard(v.sid, 2 == self.roundcount, poss)
        end
        if v.show then
            showcard_players = showcard_players + 1
        end
    end

    self:broadcastShowCardToAll()

    local t_msec = showcard_players * 200 + (self:getPotCount() * 200 + 4000)

    --jackpot 中奖需要额外增加下局开始时间
    if self.sdata.jp and self.sdata.jp.uid and showcard_players > 0 then
        t_msec = t_msec + 5000
        self.jackpot_and_showcard_flags = true
    end

    -- 广播结算
    log.info("idx(%s,%s) PBTexasFinalGame %s", self.id, self.mid, cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBSamGongFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongFinalGame"),
                pointer,
                length
            )
        end
    )

    self.endtime = global.ctsec()

    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            user.totalbuyin = v.totalbuyin
            user.totalwin = v.chips - (v.totalbuyin - v.currentbuyin)
            log.info(
                "idx(%s,%s) chips change uid:%s chips:%s last_chips:%s totalbuyin:%s totalwin:%s",
                self.id,
                self.mid,
                v.uid,
                v.chips,
                v.last_chips,
                user.totalbuyin,
                user.totalwin
            )

            local win = v.chips - v.last_chips --赢利
            --盈利扣水
            if win > 0 and (self.conf.rebate or 0) > 0 then
                local rebate = math.floor(win * self.conf.rebate)
                win = win - rebate
                v.chips = v.chips - rebate
            end
            -- 统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].totalpureprofit = win
            self.sdata.users[v.uid].totalfee = self.conf.fee + math.floor((winnerpot_potrate[k] or 0) + 0.01)
            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {}
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (win > 0) and 1 or 0
            if self.users[v.uid].first_chipin_type ~= 2 then -- 第一轮就弃牌
                --self.sdata.users[v.uid].ugameinfo.texas.incpreflopfoldhands = 0
                -- 入局率（VPIP）增1
                self.sdata.users[v.uid].ugameinfo.texas.incpreflopcheckhands = 1 -- 第一轮不弃牌
            else
                --self.sdata.users[v.uid].ugameinfo.texas.incpreflopfoldhands = 1  -- 第一轮弃牌
                self.sdata.users[v.uid].ugameinfo.texas.incpreflopcheckhands = 0
            end
            if (self.users[v.uid].first_chipin_type & 4) == 4 then
                --ALL IN 局数增1
                self.sdata.users[v.uid].ugameinfo.texas.incpreflopraisehands = 1
            end
            self.sdata.users[v.uid].ugameinfo.texas.bestcards = v.besthand
            self.sdata.users[v.uid].ugameinfo.texas.bestcardstype = v.handtype
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips
        end
    end

    self.sdata.etime = self.endtime

    -- 实时牌局
    local reviewlog = {
        buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0,
        pot = 0,
        items = {}
    }

    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            reviewlog.pot = reviewlog.pot + math.abs(v.chips - v.last_chips)
            table.insert(
                reviewlog.items,
                {
                    player = {
                        uid = v.uid,
                        username = user.username or ""
                    },
                    handcards = {
                        sid = v.sid,
                        handcards = v.show and v.handcards or {0, 0, 0}
                    },
                    bestcardstype = v.handtype,
                    win = v.chips - v.last_chips,
                    roundchipintypes = v.roundchipintypes,
                    roundchipinmoneys = v.roundchipinmoneys,
                    showhandcard = v.show
                }
            )
            self.reviewlogitems[v.uid] = nil
        end
    end
    for k, v in pairs(self.reviewlogitems) do
        table.insert(reviewlog.items, v)
    end
    for _, v in ipairs(reviewlog.items) do
        if v.handcards and self.seats_totalbets[v.handcards.sid] then
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.player.uid] = self.sdata.users[v.player.uid] or {}
            if v.player and self.sdata.users[v.player.uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[v.player.uid].extrainfo)
                if extrainfo then
                    extrainfo["totalbets"] = self.seats_totalbets[v.handcards.sid] or 0
                    self.sdata.users[v.player.uid].extrainfo = cjson.encode(extrainfo)
                end
            end
        end
    end
    self.reviewlogs:push(reviewlog)
    self.reviewlogitems = {}
    log.info("idx(%s,%s) reviewlog %s", self.id, self.mid, cjson.encode(reviewlog))

    if self:needLog() then
        self.statistic:appendLogs(self.sdata, self.logid)
    end

    timer.tick(self.timer, TimerID.TimerID_OnFinish[1], t_msec, onFinish, self)

    -- 牌局结束, 如果桌子上没人了，那下一局就随机大小盲。如果还剩下1人，那这个人下一局就不会让他当大盲(普通场规则)
    if self:getSitSize() == 0 then
        self.bbpos = -1
    elseif self:getSitSize() == 1 then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            if seat.uid ~= nil and not seat.rv:isReservation() then
                self.bbpos = i
                break
            end
        end
    end    
end

function Room:sendUpdatePotsToAll()
    local updatepots = {}
    updatepots.roundNum = self.roundcount
    updatepots.publicPools = {}
    for i = 1, self.potidx do
        table.insert(updatepots.publicPools, self.pots[i].money)
    end

    pb.encode(
        "network.cmd.PBTexasUpdatePots",
        updatepots,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasUpdatePots"),
                pointer,
                length
            )
        end
    )

    return true
end

function Room:roundOver()
    local isallfold = self:isAllFold()
    local allin = {}
    local allinset = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.roundmoney > 0 then
            seat.money = seat.money + seat.roundmoney
            seat.chips = seat.chips > seat.roundmoney and seat.chips - seat.roundmoney or 0

            if seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") then
                allinset[seat.roundmoney] = 1
            end
        end
    end

    for k, v in pairs(allinset) do
        table.insert(allin, k)
    end
    table.sort(allin)

    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            -- 当有人allin，potidx 要 +1， 以区分哪些奖池属于哪些人的
            -- ALLIN 位置在这一圈下注 0 ，说明是上一圈 ALLIN 的，这一圈有人下注要造一个新池
            if
                seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") and
                    seat.roundmoney == 0
             then
                if self.pots[self.potidx].seats[i] ~= nil then
                    self.potidx = self.potidx + 1
                    break
                end
            end
        end
    end

    for i = 1, #allin do
        for j = 1, #self.seats do
            local seat = self.seats[j]
            if seat.roundmoney > 0 then
                if i == 1 then
                    -- 你的下注大于别人allin， 或者别人allin 大于你的下注
                    local money = allin[i] > seat.roundmoney and seat.roundmoney or allin[i]
                    self.pots[self.potidx].money = self.pots[self.potidx].money + money
                    self.pots[self.potidx].seats[j] = j
                else
                    local pot =
                        allin[i] > seat.roundmoney and
                        (seat.roundmoney > allin[i - 1] and seat.roundmoney - allin[i - 1] or 0) or
                        allin[i] - allin[i - 1]
                    if pot > 0 then
                        self.pots[self.potidx].money = self.pots[self.potidx].money + pot
                        self.pots[self.potidx].seats[j] = j
                    end
                end
            end
        end

        self.potidx = self.potidx + 1
    end

    if isallfold then
        self.invalid_pot = self:getInvalidPot()
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        seat.roundmoney = 0
        seat.chipinnum = 0
        seat.reraise = false
        if
            seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") and
                seat.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN")
         then
            seat.chiptype = pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_NULL")
        end
        seat:setPreOP(pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None"))
    end

    if #allin > 0 and self.potidx > 1 then
        self.potidx = self.potidx - 1
    end

    if self.state > pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_PreChips") then
        self.roundcount = self.roundcount + 1
    end

    self:sendUpdatePotsToAll()
    self.chipinset = {}
    log.info("idx(%s,%s) potidx:%s roundOver", self.id, self.mid, self.potidx)
end

function Room:setcard()
    log.info("idx(%s,%s) setcard", self.id, self.mid)
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
    if cnt <= 1 then
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_AllinAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
        timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])
        timer.cancel(self.timer, TimerID.TimerID_PreflopAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
    timer.tick(self.timer, TimerID.TimerID_CheckRobot[1], TimerID.TimerID_CheckRobot[2], onCheckRobot, self) -- 启动检测定时器

end

function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s) req stand up uid:%s", self.id, self.mid, uid)

    local s = self:getSeatByUid(uid)
    local user = self.users[uid]
    --print(s, user)
    if s and user then
        if
            s.isplaying and self.state >= pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"), 0)
            else
                if s.chiptype ~= pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_ALL_IN") then
                    s:chipin(pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"), s.roundmoney)
                --self:sendPosInfoToAll(s, pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD"))
                end
                local isallfold = self:isAllFold()
                if isallfold or (s.isplaying and self:getPlayingSize() == 2) then
                    log.info("idx(%s,%s) chipin isallfold", self.id, self.mid)
                    self:roundOver()
                    timer.cancel(self.timer, TimerID.TimerID_Start[1])
                    timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                    timer.cancel(self.timer, TimerID.TimerID_AllinAnimation[1])
                    timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
                    timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])
                    timer.cancel(self.timer, TimerID.TimerID_PreflopAnimation[1])
                    timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
                    timer.tick(
                        self.timer,
                        TimerID.TimerID_PotAnimation[1],
                        TimerID.TimerID_PotAnimation[2],
                        onPotAnimation,
                        self
                    )
                end
            end
        end

        -- 站起
        self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))

        -- 最大加注位站起
        log.info("idx(%s,%s) s.sid %s maxraisepos %s", self.id, self.mid, s.sid, self.maxraisepos)
        if s.sid == self.maxraisepos or self.maxraisepos == 0 then
            local maxraise_seat = {roundmoney = -1, sid = s.sid}
            for i = s.sid + 1, s.sid + #self.seats - 1 do
                local j = i % #self.seats > 0 and i % #self.seats or #self.seats
                local seat = self.seats[j]
                log.info("idx(%s,%s) %s %s %s", self.id, self.mid, j, seat.roundmoney, maxraise_seat.roundmoney)
                if seat and seat.isplaying and seat.roundmoney > maxraise_seat.roundmoney then
                    maxraise_seat = seat
                end
            end
            self.maxraisepos = maxraise_seat.sid
        end
        log.info("idx(%s,%s) maxraisepos %s", self.id, self.mid, self.maxraisepos)
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
    log.info("idx(%s,%s) req sit down uid:%s", self.id, self.mid, uid)

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid)
    local dsts = self.seats[rev.sid]
    --local is_buyin_ok = rev.buyinMoney and user.money >= rev.buyinMoney and (rev.buyinMoney >= (self.conf.minbuyinbb*self.bigblind)) and (rev.buyinMoney <= (self.conf.maxbuyinbb*self.bigblind))
    --print(user.money,rev.buyinMoney,self.bigblind,self.conf.maxbuyinbb,self.conf.minbuyinbb, srcs,dsts)
    if not user or srcs or not dsts or (dsts and dsts.uid) --[[or not is_buyin_ok ]] then
        log.info("idx(%s,%s) sit failed uid:%s blind:%s", self.id, self.mid, uid, self.bigblind)
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
    log.info("idx(%s,%s) userBuyin uid %s buyinmoney %s", self.id, self.mid, uid, tostring(rev.buyinMoney))

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
        log.info("[error]idx(%s,%s) uid %s userBuyin invalid user", self.id, self.mid, uid)
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidUser"))
        return false
    end
    if user.buyin and coroutine.status(user.buyin) ~= "dead" then
        log.info("[error]idx(%s,%s) uid %s userBuyin is buying", self.id, self.mid, uid)
        return false
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("[error]idx(%s,%s) userBuyin invalid seat", self.id, self.mid)
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
            "[error]idx(%s,%s) userBuyin over limit: minbuyinbb %s, maxbuyinbb %s, bb %s",
            self.id,
            self.mid,
            self.conf.minbuyinbb,
            self.conf.maxbuyinbb,
            self.bigblind
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
                "idx(%s,%s) uid %s userBuyin start buyinmoney %s seatchips %s money %s coin %s",
                self.id,
                self.mid,
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
                    "idx(%s,%s) userBuyin not enough money: buyinmoney %s, user money %s",
                    self.id,
                    self.mid,
                    buyinmoney,
                    self:getUserMoney(uid)
                )
                handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney"))
                return false
            end
            seat:buyin(buyinmoney)
            seat:setIsBuyining(false)
            user.totalbuyin = seat.totalbuyin

            --当前已弃牌或者牌局未开始，筹码直接到账
            local is_immediately = true
            if
                not seat.isplaying or
                    seat.chiptype == pb.enum_id("network.cmd.PBSamGongChipinType", "PBSamGongChipinType_FOLD") or
                    self.state == pb.enum_id("network.cmd.PBSamGongTableState", "PBSamGongTableState_None")
             then
                seat:buyinToChips()
            else
                is_immediately = false
            end

            pb.encode(
                "network.cmd.PBTexasPlayerBuyin",
                {
                    sid = seat.sid,
                    chips = seat.chips,
                    money = self:getUserMoney(uid),
                    context = rev.context,
                    immediately = is_immediately
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
        end
    )
    coroutine.resume(user.buyin, user)
    return true
end

function Room:userChat(uid, linkid, rev)
    log.info("idx(%s,%s) userChat:%s", self.id, self.mid, uid)
    if not rev.type or not rev.content then
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        return
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s) user:%s is not in seat", self.id, self.mid, uid)
        return
    end
    if #rev.content > 200 then
        log.info("idx(%s,%s) content over length limit", self.id, self.mid)
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
    log.info("idx(%s,%s) userTool:%s,%s,%s", self.id, self.mid, uid, tostring(rev.fromsid), tostring(rev.tosid))
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
        log.info("idx(%s,%s) invalid fromsid %s", self.id, self.mid, rev.fromsid)
        handleFailed()
        return
    end
    if not self.seats[rev.tosid] or self.seats[rev.tosid].uid == 0 then
        log.info("idx(%s,%s) invalid tosid %s", self.id, self.mid, rev.tosid)
        handleFailed()
        return
    end
    local user = self.users[uid]
    local seat = self.seats[rev.fromsid]
    if not user then
        log.info("idx(%s,%s) invalid user %s", self.id, self.mid, uid)
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
        log.info("idx(%s,%s) user use tool: not enough money %s", self.id, self.mid, uid)
        handleFailed(1)
        return
    end

    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s) uid %s coroutine is expensing", self.id, self.mid, uid)
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
                    log.info("idx(%s,%s) expense uid %s not enough money", self.id, self.mid, uid)
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

function Room:userSituation(uid, linkid, rev)
    log.info("idx(%s,%s) userSituation uid %s", self.id, self.mid, uid)

    local t = {situations = {}}

    local function resp()
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSituationResp"),
            pb.encode("network.cmd.PBTexasSituationResp", t)
        )
    end

    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) userSituation invalid user", self.id, self.mid)
        resp()
        return
    end

    for uid, user in pairs(self.users) do
        if user.totalbuyin and user.totalbuyin > 0 then
            table.insert(
                t.situations,
                {
                    player = {
                        uid = uid,
                        username = user.username or ""
                    },
                    totalbuyin = user.totalbuyin or 0,
                    totalwin = user.totalwin or 0
                }
            )
        end
    end
    -- 排序规则：
    -- 有座位的在前；
    -- 盈利高的在前；
    -- 买入高的在前：
    table.sort(
        t,
        function(a, b)
            local isAInseat = self:getSeatByUid(a.player.uid) and true or false
            local isBInseat = self:getSeatByUid(b.player.uid) and true or false
            if isAInseat and not isBInseat then
                return true
            elseif not isAInseat and isBInseat then
                return false
            elseif isAInseat and isBInseat then
                if a.totalwin > b.totalwin then
                    return true
                elseif a.totalwin < b.totalwin then
                    return false
                else
                    return a.totalbuyin > b.totalbuyin
                end
            end
        end
    )
    resp()
end

function Room:userReview(uid, linkid, rev)
    log.info("idx(%s,%s) userReview uid %s", self.id, self.mid, uid)

    local t = {
        reviews = {}
    }
    local function resp()
        log.info("idx(%s,%s) PBSamGongReviewResp %s", self.id, self.mid, cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SamGongReviewResp"),
            pb.encode("network.cmd.PBSamGongReviewResp", t)
        )
    end

    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) userReview invalid user", self.id, self.mid)
        resp()
        return
    end

    t.reviews = self.reviewlogs:getLogs()
    resp()
end

function Room:userPreOperate(uid, linkid, rev)
    log.info("idx(%s,%s) userRreOperate uid %s preop %s", self.id, self.mid, uid, tostring(rev.preop))

    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not user then
        log.info("idx(%s,%s) userPreOperate invalid user", self.id, self.mid)
        return
    end
    if not seat then
        log.info("idx(%s,%s) userPreOperate invalid seat", self.id, self.mid)
        return
    end
    if
        not rev.preop or rev.preop < pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None") or
            rev.preop > pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny")
     then
        log.info("idx(%s,%s) userPreOperate invalid type", self.id, self.mid)
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
    log.info("idx(%s,%s) req addtime uid:%s", self.id, self.mid, uid)

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
        log.info("idx(%s,%s) user add time: seat not valid", self.id, self.mid)
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) user add time: user not valid", self.id, self.mid)
        return
    end
    if self.current_betting_pos ~= seat.sid then
        log.info("idx(%s,%s) user add time: user is not betting pos", self.id, self.mid)
        return
    end
    --print(seat, user, self.current_betting_pos, seat and seat.sid)
    if self.conf and self.conf.addtimecost and seat.addon_count >= #self.conf.addtimecost then
        log.info("idx(%s,%s) user add time: addtime count over limit %s", self.id, self.mid, seat.addon_count)
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.addtimecost[seat.addon_count + 1] or 0) then
        log.info("idx(%s,%s) user add time: not enough money %s", self.id, self.mid, uid)
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
                    log.info("idx(%s,%s) expense uid %s not enough money", self.id, self.mid, uid)
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
    --log.info("idx(%s,%s) userTableListInfoReq:%s", self.id, self.mid, uid)
    local t = {
        idx = {
            srvid = rev.serverid or 0,
            roomid = rev.roomid or 0,
            matchid = rev.matchid or 0,
            roomtype = self.conf.roomtype
        },
        ante = self.ante,
        bigBlind = self.bigblind,
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
    --log.info("idx(%s,%s) PBTexasTableListInfoResp %s", self.id, self.mid, cjson.encode(t))
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
                sb = self.smallblind,
                ante = self.ante,
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
        log.info("idx(%s,%s) not in seat %s", self.id, self.mid, uid)
        return false
    end

    log.info("idx(%s,%s) userJackPotResp:%s,%s,%s,%s", self.id, self.mid, uid, roomtype, value, jackpot)
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
            "idx(%s,%s) jackpot animation is to be playing %s,%s,%s,%s",
            self.id,
            self.mid,
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
