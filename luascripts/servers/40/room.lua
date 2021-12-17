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

Room = Room or {}

local TimerID = {
    TimerID_Check = {1, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, --id, interval(ms), timestamp(ms)
    TimerID_PrechipsOver = {3, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_StartHandCards = {4, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_HandCardsAnimation = {5, 3000},
    TimerID_Betting = {6, 20000}, --id, interval(ms), timestamp(ms)
    TimerID_Settlement = {7, 30000},
    TimerID_OnFinish = {8, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Timeout = {9, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {10, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {11, 1000},
    TimerID_Buyin = {12, 1000},
    TimerID_Ready = {13, 1},
    TimerID_Expense = {14, 5000}
}

local EnumUserState = {
    Playing = 1,
    Leave = 2,
    Logout = 3,
    Intoing = 4
}

local function getShow2Q(seat, self)
    local cards = {}
    if seat.show2q then
        for _, v in ipairs(seat.handcards) do
            if self.poker:isSpecialCard(v) then
                table.insert(cards, v)
            end
        end
    end
    return cards
end

local function calcSeatScore(seat, self)
    local score, mutiple = 0, 0
    local basescore, zonescore, handscore = 0, 0, 0
    --生牌/放牌/存牌
    for k, v in ipairs(self.seats) do
        for _, vv in ipairs(v.zone) do
            score = score + self.poker:calZoneScore(vv, seat.sid)
        end
    end
    zonescore = score
    --手牌
    handscore = self.poker:calHandScore(seat.handcards)
    if self.m_winner_sid > 0 then
        score = score - handscore
    end
    --特殊附加分
    for _, v in pairs(seat.additional) do
        if math.abs(v) >= 50 then
            score = score + v
        else
            if v > 0 then
                v = v - 1
            else
                v = v + 1
            end
            mutiple = mutiple + v
        end
    end
    basescore = basescore + score
    seat.score = score + math.abs(score) * mutiple
    return seat.score, basescore, zonescore, handscore
end

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
    seatinfo.seatMoney = self.chips
    seatinfo.chipinType = seat.chiptype
    seatinfo.chipinValue = seat.chipinnum
    seatinfo.chipinTime = seat:getChipinLeftTime()
    seatinfo.totalTime = seat:getChipinTotalTime()
    seatinfo.pot = seat.additional[seat.chiptype] or 0
    seatinfo.currentBetPos = self.current_betting_pos
    seatinfo.addtimeCost = self.conf.addtimecost
    seatinfo.addtimeCount = seat.addon_count
    seatinfo.discardCard = self.poker:getFoldCard()
    seatinfo.score = calcSeatScore(seat, self)
    seatinfo.leftcards = self.poker:getLeftCardsCnt()
    seatinfo.iscreate = seat.iscreate
    seatinfo.handcreate = seat.handcreate

    if seat:getIsBuyining() then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_BUYING")
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
    end
    seatinfo.zone = seat:getZone()
    seatinfo.showcards = getShow2Q(seat, self)
    seatinfo.handcardcnt = #seat.handcards
    seatinfo.canshow2q = seat.canshow2q or false

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
        log.info("idx(%s,%s) onHandCardsAnimation:%s", self.id, self.mid, self.current_betting_pos)
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        local bbseat = self.seats[self.current_betting_pos]
        self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Betting")
        self:betting(bbseat)
    end
    g.call(doRun)
end

local function onPotAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onPotAnimation", self.id, self.mid)
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
                log.info("idx(%s,%s) user buyin timeout %s", self.id, self.mid, uid)
                self:userLeave(uid, user.linkid, 0, true)
                seat:reset()
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
            -- clear logout users after 10 mins
            if
                (user.state == EnumUserState.Logout and global.ctsec() >= user.logoutts + MYCONF.logout_to_kickout_secs) or
                    user.tobe_leave
             then
                log.info("idx(%s,%s) onCheck user logout %s %s", self.id, self.mid, user.logoutts, global.ctsec())
                self:userLeave(uid, user.linkid, 0, true)
            end
        end
        -- check all seat users issuses
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if user then
                local uid = v.uid
                -- 超时两轮自动站起
                if v.bet_timeout_count >= 2 then
                    log.info("idx(%s,%s) onCheck user(%s,%s) betting timeout", self.id, self.mid, v.uid, k)
                    self:userLeave(v.uid, user.linkid, 0, true)
                else
                    if v.chips >= (self.conf and self.conf.ante * 80 + self.conf.fee or 0) then
                        v:reset()
                        v.isplaying = true
                    else
                        if self:getUserMoney(uid) < self.conf.ante * self.conf.minbuyinbb then
                            log.info("idx(%s,%s) onCheck user(%s,%s) not enough chips", self.id, self.mid, v.uid, k)
                            self:userLeave(v.uid, user.linkid, 0, true)
                            v:reset()
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
        end

        --log.info("idx(%s,%s) onCheck playing size=%s", self.id, self.mid, self:getPlayingSize())
        if self:getPlayingSize() < 2 then
            self.ready_start_time = nil
            return
        end
        if self:getPlayingSize() >= 2 then
            --timer.cancel(self.timer, TimerID.TimerID_Check[1])
            self:ready()
        end
    end
    g.call(doRun)
end

local function onFinish(self)
    local function doRun()
        log.info("idx(%s,%s) onFinish", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])

        self:checkLeave()

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
    log.info("idx(%s,%s) room init", self.id, self.mid)
    self.conf = MatchMgr:getConfByMid(self.mid)
    self.users = {}
    self.timer = timer.create()
    self.poker = Dummy:new()
    self.gameId = 0

    self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_None") --牌局状态(preflop, flop, turn...)
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

    self.finishstate = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_None")

    self.reviewlogs = LogMgr:new(1)
    --实时牌局
    self.reviewlogitems = {} --暂存站起玩家牌局
    --self.recentboardlog = RecentBoardlog.new() -- 最近牌局

    -- 主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_NULL")
    self.lastchipinpos = 0

    self.tableStartCount = 0
    self.m_winner_sid = 0
    self.mdir = 1
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
    end

    net.send_users(cjson.encode(self.links), maincmd, subcmd, msg, msglen)
end

function Room:sendCmdToPlayingUsersExceptMe(maincmd, subcmd, msg, msglen, exceptme)
    local exceptme_links = {}
    local linkidstr = nil
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and (not exceptme or exceptme ~= k) then
            linkidstr = tostring(v.linkid)
            exceptme_links[linkidstr] = exceptme_links[linkidstr] or {}
            table.insert(exceptme_links[linkidstr], k)
        end
    end

    net.send_users(cjson.encode(exceptme_links), maincmd, subcmd, msg, msglen)
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
                    self:userLeave(v.uid, user.linkid, 0, true)
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

function Room:userLeave(uid, linkid, opcode, force)
    log.info("idx(%s,%s) userLeave:%s %s", self.id, self.mid, uid, tostring(force))
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
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        handleFailed()
        return
    end

    local s = self:getSeatByUid(uid)
    if s then
        if
            self.state == pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_None") or
                self.state == pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Finish") or
                force
         then
            self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
        else
            log.info("idx(%s,%s) can not leave cause inplaying %s,%s", self.id, self.mid, s.sid, uid)
            user.tobe_leave = opcode > 0
            handleFailed()
            return false
        end
    end

    user.state = EnumUserState.Leave
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
        log.info(
            "idx(%s,%s) money change uid:%s val:%s %s,%s",
            self.id,
            self.mid,
            uid,
            val,
            s and s.chips or 0,
            s and s.buyinToMoney or 0
        )
    end

    if user.gamecount and user.gamecount > 0 then
        local logdata = {
            uid = uid,
            time = global.ctsec(),
            roomtype = self.conf.roomtype,
            gameid = global.stype(),
            serverid = global.sid(),
            roomid = self.id,
            smallblind = self.conf.ante,
            seconds = global.ctsec() - (s and (s.intots or 0) or 0),
            changed = val - user.totalbuyin,
            roomname = self.conf.name,
            gamecount = user.gamecount,
            matchid = self.mid,
            api = tonumber(user.api) or 0
        }
        Statistic:appendRoomLogs(logdata)
        log.info(
            "idx(%s,%s) user(%s,%s) upload roomlogs %s",
            self.id,
            self.mid,
            uid,
            s and s.sid or 0,
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

    self.users[uid] = nil
    self.user_cached = false
    local resp =
        pb.encode(
        "network.cmd.PBLeaveGameRoomResp_S",
        {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess"),
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
    log.info("idx(%s,%s) userLeave:%s,%s", self.id, self.mid, uid, user.gamecount or 0)

    if not next(self.users) then
        MatchMgr:getMatchById(self.conf.mid):shrinkRoom()
    end

    --test debug
    for k, v in ipairs(self.seats) do
        if v.uid ~= uid then
            self.m_winner_sid = v.uid or 0
        end
    end
    self:checkFinish()
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
    if not seat then
        log.info("idx(%s,%s) the room has been full uid %s fail to sit", self.id, self.mid, uid)
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

                    if ok and not inseat and self.conf.minbuyinbb * self.conf.ante > self:getUserMoney(uid) then
                        log.info(
                            "idx(%s,%s) userBuyin not enough money: buyinmoney %s, user money %s",
                            self.id,
                            self.mid,
                            self.conf.minbuyinbb * self.conf.ante,
                            self:getUserMoney(uid)
                        )
                        ok = false
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                    end

                    if not ok then
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
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
                    if not inseat and self:count() < self.conf.maxuser and quick then
                        self:sit(seat, uid, self:getRecommandBuyin(self:getUserMoney(uid)))
                    end
                    log.info(
                        "idx(%s,%s) into room:%s,%s,%s,%s,%s",
                        self.id,
                        self.mid,
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
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}
    self.finishstate = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_None")

    self.lastchipintype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_NULL")
    self.lastchipinpos = 0
    self.poker:resetAll()
    self.pot = 0
    self.buttonpos = 0
    self.declare_start_time = nil
    self.m_nextfinish_sid = nil
    self.m_winner_sid = 0
end

function Room:potRake(total_pot_chips)
    log.info("idx(%s,%s) into potRake:%s", self.id, self.mid, total_pot_chips)
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
        log.info("idx(%s,%s) after potRake:%s", self.id, self.mid, total_pot_chips)
    end
    return total_pot_chips, potrake
end

function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s) user table info req uid:%s ante:%s", self.id, self.mid, uid, self.conf.ante)
    local tableinfo = {
        gameId = self.gameId,
        seatCount = self.conf.maxuser,
        tableName = self.conf.name,
        gameState = self.state,
        buttonSid = self.buttonpos,
        pot = 0,
        ante = self.conf.ante,
        bettingtime = self.bettingtime,
        matchType = self.conf.matchtype,
        roomType = self.conf.roomtype,
        addtimeCost = self.conf.addtimecost,
        toolCost = self.conf.toolcost,
        jpid = self.conf.jpid or 0,
        jp = JackpotMgr:getJackpotById(self.conf.jpid),
        jpRatios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or {0, 0, 0}),
        discardCard = self.poker:getFoldCard(),
        readyLeftTime = ((self.t_msec or 0) / 1000 + TimerID.TimerID_Ready[2] + TimerID.TimerID_Check[2] / 1000) -
            (global.ctsec() - self.endtime),
        minbuyinbb = self.conf.minbuyinbb,
        maxbuyinbb = self.conf.maxbuyinbb
    }
    tableinfo.readyLeftTime =
        self.ready_start_time and TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time) or
        tableinfo.readyLeftTime
    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    log.info("idx(%s,%s) uid:%s userTableInfo:%s", self.id, self.mid, uid, cjson.encode(tableinfo))
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
            end
            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end

    local resp = pb.encode("network.cmd.PBDummyTableInfoResp", {tableInfo = tableinfo})
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyTableInfoResp"),
        resp
    )
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
    local pos = seat and seat.sid or 0
    log.info(
        "idx(%s,%s) getNextActionPosition sid:%s,%s,%s",
        self.id,
        self.mid,
        pos,
        tostring(self.maxraisepos),
        self.mdir
    )
    --self.mdir 1为顺时针 -1为逆时针
    for i = pos + self.mdir, pos + (#self.seats - 1) * self.mdir, self.mdir do
        local j = i % #self.seats
        j = j > 0 and j or j + #self.seats
        local seati = self.seats[j]
        if seati and seati.isplaying then
            seati.addon_count = 0
            return seati
        end
    end
    return self.seats[self.maxraisepos]
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
    if self.m_winner_sid > 0 and self.m_winner_sid < #self.seats then
        self.buttonpos = self.m_winner_sid
    end
    self.m_winner_sid = 0
    log.info(
        "idx(%s,%s) movebutton:%s,%s,%s",
        self.id,
        self.mid,
        self.buttonpos,
        self.current_betting_pos,
        tostring(self.m_winner_sid)
    )
end

function Room:getGameId()
    return self.gameId + 1
end

function Room:stand(seat, uid, stype)
    log.info(
        "idx(%s,%s) stand uid,sid:%s,%s,%s,%s",
        self.id,
        self.mid,
        uid,
        seat.sid,
        tostring(stype),
        tostring(seat.totalbuyin)
    )
    local user = self.users[uid]
    if seat and user then
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
    log.info("idx(%s,%s) stand uid,sid:%s,%s,%s,%s", self.id, self.mid, uid, seat.sid, tostring(stype), seat.totalbuyin)
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
        log.info("idx(%s,%s) sit uid %s,sid %s %s", self.id, self.mid, uid, seat.sid, seat.totalbuyin)
        seat:sit(uid, user.chips, 0, user.totalbuyin)

        if 0x4 == self.conf.buyin & 0x4 or Utils:isRobot(user.api) then
            buyinmoney = self:getUserMoney(uid)
            if Utils:isRobot(user.api) then
                buyinmoney = math.floor(buyinmoney / self.conf.minchip) * self.conf.minchip
            end
            if not self:userBuyin(uid, user.linkid, {buyinMoney = buyinmoney}, true) then
                seat:stand(uid)
                return
            end
        else
            if seat:totalBuyin() == 0 and seat.chips < (self.conf and self.conf.ante * 80 + self.conf.fee or 0) then
                log.info(
                    "idx(%s,%s) PBTexasPopupBuyin uid %s,sid %s %s",
                    self.id,
                    self.mid,
                    uid,
                    seat.sid,
                    seat.totalbuyin
                )

                seat:setIsBuyining(true)
                timer.tick(
                    self.timer,
                    TimerID.TimerID_Buyin[1] + 100 + uid,
                    self.conf.buyintime * 1000,
                    onBuyin,
                    {self, uid}
                )
            end
        end

        local seatinfo = fillSeatInfo(seat, self)
        local sitcmd = {seatInfo = seatinfo}
        pb.encode(
            "network.cmd.PBDummyPlayerSit",
            sitcmd,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyPlayerSit"),
                    pointer,
                    length
                )
            end
        )
        log.info("idx(%s,%s) player sit in seatinfo:%s", self.id, self.mid, cjson.encode(sitcmd))
        MatchMgr:getMatchById(self.conf.mid):expandRoom()
    end
end

function Room:sendPosInfoToAll(seat, chiptype, exceptme, context)
    local updateseat = {context = context}
    if chiptype then
        seat.chiptype = chiptype
    end

    if seat.uid then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        if exceptme then
            pb.encode(
                "network.cmd.PBDummyUpdateSeat",
                updateseat,
                function(pointer, length)
                    self:sendCmdToPlayingUsersExceptMe(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyUpdateSeat"),
                        pointer,
                        length,
                        exceptme
                    )
                end
            )
        else
            pb.encode(
                "network.cmd.PBDummyUpdateSeat",
                updateseat,
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyUpdateSeat"),
                        pointer,
                        length
                    )
                end
            )
        end
        log.info(
            "idx(%s,%s) updateseat chiptype:%s seatinfo:%s",
            self.id,
            self.mid,
            tostring(chiptype),
            cjson.encode(updateseat.seatInfo)
        )
    end
end

function Room:sendPosInfoToMe(seat, context)
    local user = self.users[seat.uid]
    local updateseat = {context = context}
    if user then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        updateseat.seatInfo.drawcard = seat.drawcard
        updateseat.seatInfo.handcards = seat.handcards
        net.send(
            user.linkid,
            seat.uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyUpdateSeat"),
            pb.encode("network.cmd.PBDummyUpdateSeat", updateseat)
        )
        log.info("idx(%s,%s) checkcard:%s", self.id, self.mid, cjson.encode(updateseat))
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
            "network.cmd.PBDummyGameReady",
            gameready,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyGameReady"),
                    pointer,
                    length
                )
            end
        )
        log.info("idx(%s,%s) gameready:%s,%s", self.id, self.mid, self:getPlayingSize(), cjson.encode(gameready))
    end
    if global.ctsec() - self.ready_start_time >= TimerID.TimerID_Ready[2] then
        timer.cancel(self.timer, TimerID.TimerID_Check[1])
        self.ready_start_time = nil
        self:start()
    end
end

function Room:start()
    self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Start")
    self:reset()
    self.gameId = self:getGameId()
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec()
    self.logid = self.has_started and self.statistic:genLogId(self.starttime) or self.logid
    self.has_started = self.has_started or true
    --self.config_switch = true

    -- 玩家状态，金币数等数据初始化
    self:moveButton()

    self.current_betting_pos = self.buttonpos
    log.info(
        "idx(%s,%s) start ante:%s gameId:%s betpos:%s logid:%s",
        self.id,
        self.mid,
        self.conf.ante,
        self.gameId,
        self.current_betting_pos,
        tostring(self.logid)
    )

    self.poker:start()

    --给机器人两条命
    self.robot_handcards = nil
    local _, r = self:count()
    local pro = rand.rand_between(1, 10000)
    if r > 0 and pro <= (self.conf.pro or 0) then
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
        seats = fillSeats(self)
    }
    pb.encode(
        "network.cmd.PBDummyGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyGameStart"),
                pointer,
                length
            )
        end
    )
    log.info("idx(%s,%s) gamestart:%s,%s", self.id, self.mid, self:getPlayingSize(), cjson.encode(gamestart))

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
            ante = self.conf.ante
        }
    )

    -- 底注
    self:dealPreChips()
end

local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos]
        log.info(
            "idx(%s,%s) onBettingTimer over time bettingpos:%s uid:%s,%s",
            self.id,
            self.mid,
            self.current_betting_pos,
            tostring(self.m_nextfinish_sid),
            current_betting_seat.uid or 0
        )
        local user = self.users[current_betting_seat.uid]
        if current_betting_seat:isChipinTimeout() then
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            current_betting_seat.bet_timeout_count = current_betting_seat.bet_timeout_count + 1
            if (self.m_nextfinish_sid or -1) == self.current_betting_pos then
                self:userchipin(
                    current_betting_seat.uid,
                    pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FINISH"),
                    current_betting_seat.drawcard
                )
            else
                --保留现场
                if
                    current_betting_seat.chiptype ==
                        pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_BETING") and
                        (current_betting_seat.drawcard == 0 and not current_betting_seat.iscreate)
                 then
                    --debug(current_betting_seat.drawcard == 0 or not current_betting_seat.iscreate)
                    self:userchipin(
                        current_betting_seat.uid,
                        pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DRAW"),
                        0
                    )
                else
                    local drawcard =
                        current_betting_seat.drawcard > 0 and current_betting_seat.drawcard or
                        (current_betting_seat.handcards[#current_betting_seat.handcards] or 0)
                    self:userchipin(
                        current_betting_seat.uid,
                        pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DISCARD"),
                        drawcard
                    )
                end
            end
        end
    end
    g.call(doRun)
end

function Room:betting(seat)
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])
    if not seat then
        return false
    end
    seat.bettingtime = global.ctsec()
    self.current_betting_pos = seat.sid
    log.info("idx(%s,%s) it's betting pos:%s uid:%s", self.id, self.mid, self.current_betting_pos, tostring(seat.uid))

    local function notifyBetting()
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_BETING"))
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self)
    end

    notifyBetting()
end

function Room:checkCanChipin(seat, type)
    return seat and seat.uid and seat.isplaying and seat.sid == self.current_betting_pos
end

function Room:checkFinish()
    local isover = self.m_winner_sid > 0
    if isover then
        self.finishstate = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Finish")

        log.info("idx(%s,%s) chipin isover m_winner_sid %s", self.id, self.mid, self.m_winner_sid)

        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        onPotAnimation(self)
        --timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
        return true
    end
    return false
end

function Room:chipin(uid, type, value, extra)
    local seat = self:getSeatByUid(uid)

    log.info(
        "idx(%s,%s) chipin pos:%s uid:%s type:%s value:%s",
        self.id,
        self.mid,
        seat.sid,
        seat.uid and seat.uid or 0,
        type,
        value
    )

    local switch = {}
    local res, needbetting = false, true

    local function draw_func(seat, type, value, extra)
        if seat.drawcard > 0 or seat.handcreate then
            return false
        end
        local cards = self.poker:dealCard(1, seat.sid)
        if cards then
            for _, v in ipairs(cards) do
                table.insert(seat.handcards, v)
                seat.drawcard = v
                break
            end
            seat:chipin(type, 0)
        end
        return true
    end
    local function show2q_func(seat, type, value, extra)
        if seat.show2q then
            return false
        end
        local cnt = 0
        for _, v in ipairs(seat.handcards) do
            cnt = cnt + (self.poker:isSpecialCard(v) and 1 or 0)
        end
        if cnt ~= 2 then
            log.info("idx(%s,%s) show2q %s not match cnt %s", self.id, self.mid, seat.sid, cnt)
            return false
        end
        seat.show2q = true
        seat.canshow2q = false
        seat:chipin(type, 0)
        seat.additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_Show2Q")] = 50
        return true
    end
    local function create_func(seat, type, value, extra)
        local foldcard = extra.foldcards
        local handcard = extra.handcards
        --如果摸过牌或者生过牌就不允许生牌
        if seat.drawcard > 0 or seat.handcreate then
            return false
        end
        --如果生了牌没有手牌也不允许生牌
        if #extra.handcards == #seat.handcards and self.poker:isAllFold(foldcard) then
            return false
        end
        --foldcard&handcard必须要位于对应的牌列表中
        for _, v in ipairs(handcard) do
            if not seat:isInHandCard(v) then
                return false
            end
        end
        for _, v in ipairs(foldcard) do
            if not self.poker:isInFoldCard(v) then
                return false
            end
        end

        if #seat.zone == 0 then
            seat.oneshotflag = 1
        end
        local leftcards = self.poker:create(foldcard)
        for _, v in ipairs(handcard) do
            for kk, vv in ipairs(seat.handcards) do
                if v == vv then
                    table.remove(seat.handcards, kk)
                    break
                end
            end
        end
        if #leftcards > 0 then
            for _, v in ipairs(leftcards) do
                v = self.poker:setOwnerSid(seat.sid, v)
                table.insert(seat.handcards, v)
            end
        end

        local zone = {}
        table.move(foldcard, 1, #foldcard, #zone + 1, zone)
        table.move(handcard, 1, #handcard, #zone + 1, zone)
        table.sort(
            zone,
            function(a, b)
                return (a & 0xFF) < (b & 0xFF)
            end
        )
        table.insert(seat.zone, zone)
        local tosid, additional = table.unpack(self.poker:onCreatePoint(seat.sid, foldcard, handcard, zone))
        for k, v in pairs(additional) do
            if v > 0 then
                seat.additional[k] = (seat.additional[k] or 0) + v
                self:sendPosInfoToAll(seat, k)
            end
        end
        local toseat = self.seats[tosid]
        if toseat then
            for k, v in pairs(additional) do
                if v < 0 then
                    toseat.additional[k] = (seat.additional[k] or 0) + v
                    self:sendPosInfoToAll(toseat, k)
                end
            end
        end
        seat.iscreate = true
        seat.handcreate = true
        seat.lastfoldcard = foldcard[#foldcard]
        seat:chipin(type, 0)
        log.info(
            "idx(%s,%s) uid %s create card %s %s %s",
            self.id,
            self.mid,
            uid,
            cjson.encode(handcard),
            cjson.encode(leftcards),
            cjson.encode(seat.handcards)
        )
        return true
    end
    local function discard_func(seat, type, value, extra)
        if seat.drawcard == 0 and not seat.handcreate then
            log.info("idx(%s,%s) uid no drawcard and create card", self.id, self.mid, uid)
            return false
        end
        if not seat:isInHandCard(value) then
            return false
        end
        for kk, vv in ipairs(seat.handcards) do
            if value == vv then
                self.poker:discard(value)
                table.remove(seat.handcards, kk)
                break
            end
        end
        local zones = {}
        for _, v in ipairs(self.seats) do
            table.move(v.zone, 1, #v.zone, #zones + 1, zones)
        end
        local additional = self.poker:onDropPoint(value, zones)
        for k, v in pairs(additional) do
            seat.additional[k] = (seat.additional[k] or 0) + v
            self:sendPosInfoToAll(seat, k)
        end
        seat.lastfoldcard = 0
        seat.oneshotflag = 0
        seat.drawcard = 0
        seat.handcreate = false
        seat:chipin(type, 0)

        needbetting = false
        res = true
        return true
    end
    local function place_func(seat, type, value, extra)
        if seat.drawcard == 0 and not seat.iscreate then
            return false
        end
        --如果放了牌没有手牌也不允许放牌
        if #extra.handcards == #seat.handcards then
            return false
        end
        for _, v in ipairs(extra.handcards) do
            if not seat:isInHandCard(v) then
                return false
            end
        end
        local cards = g.copy(extra.handcards)
        table.sort(
            cards,
            function(a, b)
                return (a & 0xFF) < (b & 0xFF)
            end
        )
        table.insert(seat.zone, cards)
        for _, v in ipairs(cards) do
            for kk, vv in ipairs(seat.handcards) do
                if v == vv then
                    table.remove(seat.handcards, kk)
                end
            end
        end
        seat:chipin(type, 0)
        return true
    end
    local function save_func(seat, type, value, extra)
        if seat.drawcard == 0 and not seat.iscreate then
            return false
        end
        if not seat:isInHandCard(value) then
            return false
        end
        local tosid = extra.tosid
        local tozoneid = extra.tozoneid
        local toseat = self.seats[tosid]
        if toseat and toseat.zone[tozoneid] then
            table.insert(toseat.zone[tozoneid], self.poker:setToSid(tosid, value))
            table.sort(
                toseat.zone[tozoneid],
                function(a, b)
                    return (a & 0xFF) < (b & 0xFF)
                end
            )
            for k, v in ipairs(seat.handcards) do
                if v == value then
                    table.remove(seat.handcards, k)
                    break
                end
            end
            local tosavesid, additional = table.unpack(self.poker:onSavePoint(value, toseat.zone[tozoneid]))
            local tosaveseat = self.seats[tosavesid]
            if tosaveseat then
                for k, v in pairs(additional) do
                    if v < 0 then
                        tosaveseat.additional[k] = (tosaveseat.additional[k] or 0) + v
                        self:sendPosInfoToAll(tosaveseat, k)
                    end
                end
            end
            self:sendPosInfoToAll(
                toseat,
                pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SAVE"),
                nil,
                extra and extra.context or nil
            )
        end
        seat:chipin(type, 0)
        return true
    end
    local function knock_func(seat, type, value, extra)
        if #seat.handcards ~= 1 then
            return false
        end
        if seat.drawcard == 0 and not seat.iscreate then
            return false
        end

        value = seat.handcards[1]
        local zones = {}
        for k, v in ipairs(self.seats) do
            if #v.zone > 0 then
                for kk, vv in pairs(v.zone) do
                    table.insert(zones, {vv, k, kk})
                end
            else
                --倒霉/无套牌
                v.additional[pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_Unlucky")] = -2
            end
        end
        local tosid, additional, knocktype, savesid, savezoneid =
            table.unpack(self.poker:onKnockPoint(value, seat.zone, zones, seat.lastfoldcard, seat.oneshotflag))
        for k, v in pairs(additional) do
            if v > 0 then
                seat.additional[k] = (seat.additional[k] or 0) + v
                if k == pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SaveLast") then
                    self:sendPosInfoToAll(seat, k)
                    --如果能存牌触发存牌
                    save_func(
                        seat,
                        pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SAVE"),
                        value,
                        {tosid = savesid, tozoneid = savezoneid}
                    )
                    self:sendPosInfoToMe(seat, extra and extra.context or nil)
                    self:sendPosInfoToAll(seat, nil, uid, extra and extra.context or nil)
                end
            end
        end

        --如果不能存牌触发丢牌
        if savesid == 0 then
            for kk, vv in ipairs(seat.handcards) do
                if value == vv then
                    self.poker:discard(value)
                    table.remove(seat.handcards, kk)
                    break
                end
            end
            seat:chipin(pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DISCARD"), 0)
            self:sendPosInfoToMe(seat, extra and extra.context or nil)
            self:sendPosInfoToAll(seat, nil, uid, extra and extra.context or nil)
        end

        local toseat = self.seats[tosid]
        if toseat then
            self.mdir = -self.mdir
            for k, v in pairs(additional) do
                if v < 0 then
                    toseat.additional[k] = (seat.additional[k] or 0) + v
                    self:sendPosInfoToAll(toseat, k)
                end
            end
        end

        seat:chipin(knocktype, 0)
        self.m_winner_sid = seat.sid
        needbetting = false
        res = true
        return true
    end
    local function batchknock_func(seat, type, value, extra)
        self:sendPosInfoToMe(seat, extra and extra.context or nil)
        self:sendPosInfoToAll(seat, nil, uid, extra and extra.context or nil)
        for _, v in ipairs(extra.knock) do
            local chipin_func = switch[v.chipType]
            if
                chipin_func and
                    chipin_func(
                        seat,
                        v.chipType,
                        v.chipValue,
                        {
                            tosid = v.tosid,
                            tozoneid = v.tozoneid,
                            foldcards = v.foldcards,
                            handcards = v.handcards,
                            context = v.context
                        }
                    )
             then
                self:sendPosInfoToMe(seat, v.context)
                self:sendPosInfoToAll(seat, nil, uid, v.context)
            else
                log.info(
                    "idx(%s,%s) batchknock_func invalid bettype uid:%s type:%s",
                    self.id,
                    self.mid,
                    uid,
                    v.chipType
                )
            end
        end
        seat:chipin(type, 0)
        needbetting = false
        res = true
        return false
    end
    local function finish_func(seat, type, value, extra)
        seat:chipin(type, 0)
        self.m_winner_sid = 0xFFFF
        needbetting = false
        res = true
        return true
    end
    switch = {
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DRAW")] = draw_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_CREATE")] = create_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DISCARD")] = discard_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_PLACE")] = place_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_SAVE")] = save_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_KNOCK")] = knock_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_Show2Q")] = show2q_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_BATCHKNOCK")] = batchknock_func,
        [pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FINISH")] = finish_func
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, uid, type)
        return false
    end

    if chipin_func(seat, type, value, extra) then
        self:sendPosInfoToMe(seat, extra and extra.context or nil)
        self:sendPosInfoToAll(seat, nil, uid, extra and extra.context or nil)
    end
    if needbetting then
        self:betting(seat)
    end

    return res
end

function Room:userchipin(uid, type, value, extra, client)
    log.info(
        "idx(%s,%s) userchipin: uid %s, type %s, value %s extra %s",
        self.id,
        self.mid,
        tostring(uid),
        tostring(type),
        tostring(value),
        tostring(cjson.encode(extra))
    )
    uid = uid or 0
    type = type or 0
    value = value or 0
    if
        self.state == pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_None") or
            self.state == pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Finish")
     then
        log.info("idx(%s,%s) uid %s user chipin state invalid:%s", self.id, self.mid, uid, self.state)
        return false
    end
    local chipin_seat = self:getSeatByUid(uid)
    if not chipin_seat then
        log.info("idx(%s,%s) uid %s invalid chipin seat", self.id, self.mid, uid)
        return false
    end
    if chipin_seat.chiptype == pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_KNOCK") then
        log.info(
            "idx(%s,%s) chipin (%s,%s) has folded or finish:%s",
            self.id,
            self.mid,
            uid,
            chipin_seat.sid,
            chipin_seat.chiptype
        )
        return false
    end

    if not self:checkCanChipin(chipin_seat, type) then
        log.info("idx(%s,%s) invalid chipin pos:%s", self.id, self.mid, chipin_seat.sid)
        return false
    end

    if client then
        chipin_seat.bet_timeout_count = 0
    end
    local chipin_result = self:chipin(uid, type, value, extra)
    if not chipin_result then
        --log.info("idx(%s,%s) chipin failed uid:%s",self.id,self.mid,uid)
        return false
    end

    --操作过一轮就不能再显示show2q了
    if chipin_seat.canshow2q then
        chipin_seat.canshow2q = false
    end
    --摸完牌后，下一个玩家丢牌后，牌局结束
    if
        type == pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DISCARD") and
            (self.m_nextfinish_sid or -1) == self.current_betting_pos
     then
        self:chipin(uid, pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_FINISH"), value, extra)
    end

    if self:checkFinish() then
        return true
    end

    local next_seat = self:getNextActionPosition(self.seats[self.current_betting_pos])
    log.info(
        "idx(%s,%s) next_seat uid:%s chipin_pos:%s chipin_uid:%s chiptype:%s chips:%s",
        self.id,
        self.mid,
        next_seat and next_seat.uid or 0,
        tostring(self.current_betting_pos),
        self.seats[self.current_betting_pos].uid,
        self.seats[self.current_betting_pos].chiptype,
        chipin_seat.chips
    )

    if type == pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_DISCARD") and not self.poker:isLeft() then
        self.m_nextfinish_sid = next_seat.sid
    end

    self:betting(next_seat)

    return true
end

function Room:getNextState()
    local oldstate = self.state

    if oldstate == pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_PreChips") then
        self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_HandCard")
        self:dealHandCards()
    elseif oldstate == pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Finish") then
        self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_None")
    end

    log.info("idx(%s,%s) State Change: %s => %s", self.id, self.mid, oldstate, self.state)
end

local function onStartHandCards(self)
    local function doRun()
        log.info("idx(%s,%s) onStartHandCards button_pos:%s", self.id, self.mid, self.buttonpos)

        self:getNextState()
    end
    g.call(doRun)
end

function Room:dealPreChips()
    log.info("idx(%s,%s) dealPreChips ante:%s", self.id, self.mid, self.conf.ante)
    self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_PreChips")
    onStartHandCards(self)
end

function Room:getHandCardNum()
    return 7
end

--deal handcards
function Room:dealHandCards()
    local cfgcardidx = 0
    for k, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user then
            if seat.isplaying then
                cfgcardidx = cfgcardidx + 1
                if self.config_switch then
                    seat.handcards = self.poker:removes(DUMMYCONF.CONFCARDS[cfgcardidx])
                    for kk, vv in ipairs(seat.handcards) do
                        seat.handcards[kk] = self.poker:setOwnerSid(k, vv)
                    end
                else
                    if Utils:isRobot(user.api) and self.robot_handcards then
                        seat.handcards = g.copy(self.robot_handcards)
                        local leftcards = self.poker:dealCard(self:getHandCardNum() - #seat.handcards, k)
                        for _, v in ipairs(leftcards) do
                            table.insert(seat.handcards, v)
                        end
                    else
                        seat.handcards = self.poker:dealCard(self:getHandCardNum(), k)
                    end
                end

                local cards = {
                    cards = {{sid = k, handcards = g.copy(seat.handcards)}},
                    discardCard = self.poker:getFoldCard(),
                    leftcards = self.poker:getLeftCardsCnt()
                }
                net.send(
                    user.linkid,
                    seat.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyDealCard"),
                    pb.encode("network.cmd.PBDummyDealCard", cards)
                )
                self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_HandCard"))

                local cnt = 0
                for _, v in ipairs(seat.handcards) do
                    if self.poker:isSpecialCard(v) then
                        cnt = cnt + 1
                    end
                end
                if cnt == 2 then
                    seat.canshow2q = true
                end
                log.info(
                    "idx(%s,%s) sid:%s,uid:%s deal handcard:%s",
                    self.id,
                    self.mid,
                    k,
                    seat.uid,
                    cjson.encode(cards)
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

    timer.tick(
        self.timer,
        TimerID.TimerID_HandCardsAnimation[1],
        TimerID.TimerID_HandCardsAnimation[2],
        onHandCardsAnimation,
        self
    )
end

function Room:getOnePot()
    local potscore = {}
    for k, v in ipairs(self.seats) do
        if v.isplaying then
            local score = {}
            local totalscore, basescore, zonescore, handscore = calcSeatScore(v, self)
            v.score = totalscore
            local zs = {cards = {}, score = zonescore}
            for _, vv in ipairs(v.zone) do
                local trimzone = self.poker:trimByOwnerSid(vv, k)
                table.move(trimzone, 1, #trimzone, #zs.cards + 1, zs.cards)
            end
            --生牌/放牌/存牌
            table.insert(score, zs)
            --手牌
            table.insert(score, {cards = v.handcards, score = -handscore})
            --数值加分
            for kk, vv in pairs(v.additional) do
                if math.abs(vv) >= 50 then
                    table.insert(score, {cards = {kk}, score = vv})
                end
            end
            --倍数加分
            for kk, vv in pairs(v.additional) do
                if not (math.abs(vv) >= 50) then
                    if vv < 0 then
                        vv = vv + 1
                    else
                        vv = vv - 1
                    end
                    table.insert(score, {cards = {kk}, score = vv * math.abs(basescore)})
                end
            end
            potscore[k] = score
        end
    end

    local totalpot, totalvalue, potrake = 0, 0, 0
    for _, v in ipairs(self.seats) do
        if v.isplaying then
            local totalpoint = 0
            for _, vv in ipairs(self.seats) do
                if vv.isplaying then
                    totalpoint = totalpoint + (v.score - vv.score)
                end
            end
            v.profit = totalpoint * self.conf.ante
            if v.profit < 0 and math.abs(v.profit) > v.chips then
                v.profit = -v.chips
            end
            if v.profit < 0 then
                totalpot = totalpot + math.abs(v.profit)
            else
                totalvalue = totalvalue + v.profit
            end
        end
    end
    totalpot, potrake = self:potRake(totalpot)
    for _, v in ipairs(self.seats) do
        if v.isplaying then
            if v.profit > 0 and totalvalue > 0 then
                v.profit = (v.profit / totalvalue) * totalpot
            end
            v.chips = v.chips + v.profit
        end
    end
    log.info(
        "idx(%s,%s) onepot totalpot %s potrake %s score %s",
        self.id,
        self.mid,
        totalpot,
        potrake,
        cjson.encode(potscore)
    )
    return totalpot, potrake, potscore
end

function Room:finish()
    log.info("idx(%s,%s) finish", self.id, self.mid)

    self.state = pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Finish")
    self.declare_start_time = nil
    self.endtime = global.ctsec()
    self.t_msec = self:getPlayingSize() * 1000 + 5000

    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    local pot, potrake, potscore = self:getOnePot()

    log.info("idx(%s,%s) finish pot:%s", self.id, self.mid, pot)

    local FinalGame = {
        potInfos = {},
        potMoney = pot,
        readyLeftTime = (self.t_msec / 1000 + TimerID.TimerID_Ready[2] + TimerID.TimerID_Check[2] / 1000) -
            (global.ctsec() - self.endtime),
        winerSid = self.m_winner_sid
    }

    local reviewlog = {
        buttonsid = self.buttonpos,
        ante = self.conf.ante,
        items = {}
    }
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            local win = v.profit
            log.info(
                "idx(%s,%s) chips change uid:%s chips:%s last_chips:%s profit:%s",
                self.id,
                self.mid,
                v.uid,
                v.chips,
                v.last_chips,
                win
            )
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].totalpureprofit = self.sdata.users[v.uid].totalpureprofit or win
            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {}
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (win > 0) and 1 or 0
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips
            self.sdata.users[v.uid].totalfee = self.conf.fee + potrake
            self.sdata.users[v.uid].extrainfo =
                cjson.encode(
                {
                    ip = user.ip or "",
                    api = user.api or "",
                    roomtype = self.conf.roomtype,
                    roundid = user.roundId,
                    totalbets = 0,
                    groupcard = g.copy(potscore[v.sid])
                }
            )

            table.insert(
                FinalGame.potInfos,
                {
                    sid = v.sid,
                    winMoney = win,
                    seatMoney = v.chips,
                    score = potscore[v.sid],
                    winType = 0,
                    nickname = user.username,
                    nickurl = user.nickurl
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
                    handcards = g.copy(v.handcards),
                    wintype = 0,
                    win = win,
                    showcard = true
                }
            )
        end
    end
    self.reviewlogs:push(reviewlog)

    -- 广播结算
    log.info("idx(%s,%s) PBDummyFinalGame %s", self.id, self.mid, cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBDummyFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyFinalGame"),
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
    log.info("idx(%s,%s) room:check playing size=%s", self.id, self.mid, cnt)
    if cnt <= 1 then
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
end

function Room:userSit(uid, linkid, rev)
    log.info("idx(%s,%s) req sit down uid:%s", self.id, self.mid, uid)

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid)
    local dsts = self.seats[rev.sid]
    if not user or srcs or not dsts or (dsts and dsts.uid) --[[or not is_buyin_ok ]] then
        log.info(
            "idx(%s,%s) sit failed uid:%s srcuid:%s dstuid:%s",
            self.id,
            self.mid,
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
        log.info("idx(%s,%s) uid %s userBuyin invalid user", self.id, self.mid, uid)
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidUser"))
        return false
    end

    if user.buyin and coroutine.status(user.buyin) ~= "dead" then
        log.info("idx(%s,%s) uid %s userBuyin is buying", self.id, self.mid, uid)
        return false
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s) userBuyin invalid seat", self.id, self.mid)
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
            "idx(%s,%s) userBuyin over limit: minbuyinbb %s, maxbuyinbb %s, chips %s",
            self.id,
            self.mid,
            self.conf.minbuyinbb,
            self.conf.maxbuyinbb,
            seat.chips
        )
        if buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.ante then
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
            seat:buyinToChips()

            pb.encode(
                "network.cmd.PBTexasPlayerBuyin",
                {
                    sid = seat.sid,
                    chips = seat.chips,
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

            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_NotifyGameCoinUpdate"),
                pb.encode("network.cmd.PBNotifyGameCoinUpdate_N", {val = self:getuserMoney(uid)})
            )
            log.info(
                "idx(%s,%s) uid %s userBuyin result buyinmoney %s seatchips %s money %s coin %s",
                self.id,
                self.mid,
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
    if not user then
        log.info("idx(%s,%s) invalid user %s", self.id, self.mid, uid)
        handleFailed()
        return
    end
    if Utils:isRobot(user.api) then
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
    local seat = self.seats[rev.fromsid]
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
    log.info("idx(%s,%s) userReview uid %s", self.id, self.mid, uid)

    local t = {
        reviews = {}
    }
    local function resp()
        log.info("idx(%s,%s) PBDummyReviewResp %s", self.id, self.mid, cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DummyReviewResp"),
            pb.encode("network.cmd.PBDummyReviewResp", t)
        )
    end

    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not user then
        log.info("idx(%s,%s) userReview invalid user", self.id, self.mid)
        resp()
        return
    end

    for _, reviewlog in ipairs(self.reviewlogs:getLogs()) do
        table.insert(t.reviews, reviewlog)
    end
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
            rev.preop >= pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny")
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
                self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_BETING"))
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
    --log.info("idx(%s,%s) resp userTableListInfoReq %s", self.id, self.mid, cjson.encode(t))
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
        self:userLeave(k, v.linkid, 0, true)
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
    return self.state < pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Start") or
        self.state >= pb.enum_id("network.cmd.PBDummyTableState", "PBDummyTableState_Finish")
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
