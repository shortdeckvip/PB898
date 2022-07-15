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
require("luascripts/servers/33/seat")
require("luascripts/servers/33/teempatti")

Room = Room or {}
TeenPattiSpecialTime = TeenPattiSpecialTime or {}

local TimerID = {
    TimerID_Check = {1, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, -- id, interval(ms), timestamp(ms)
    TimerID_PrechipsOver = {3, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_StartHandCards = {4, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_HandCardsAnimation = {5, 1000},
    TimerID_Betting = {6, 12000}, -- id, interval(ms), timestamp(ms)
    TimerID_Dueling = {7, 4000}, -- 比牌定时器？
    TimerID_OnFinish = {8, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_Timeout = {9, 2000}, -- id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {10, 2000}, -- id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {11, 1000},
    TimerID_Buyin = {12, 1000},
    TimerID_Expense = {14, 5000},
    TimerID_RobotLeave = {15, 1000},
    TimerID_CheckRobot = {16, 5000}, -- 定时检测机器人
    TimerID_Result = {17, 1200},
    TimerID_WaitBetting = {18, 800}
}

local EnumUserState = {
    Playing = 1,
    Leave = 2,
    Logout = 3,
    Intoing = 4
}

-- 填充座位信息
-- 参数 seat: 座位
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
    seatinfo.seatMoney = (seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0 -- 身上金额

    if seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING_LACK") then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING") -- 操作状态
    else
        seatinfo.chipinType = seat.chiptype -- 操作状态
    end
    seatinfo.totalChipin = seat.totalChipin
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
        seatinfo.ischall = true -- 已看牌跟注 或 加注
    end

    return seatinfo
end

-- 填充所有座位信息
local function fillSeats(self)
    local seats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        local seatinfo = fillSeatInfo(seat, self)
        table.insert(seats, seatinfo)
    end
    return seats
end

-- 发牌动画播放完毕(发牌完毕)
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
        local bbseat = self.seats[self.buttonpos] -- 庄家座位
        local nextseat = self:getNextActionPosition(bbseat) -- 下一个待操作位置
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting") -- 该桌下注状态
        self:betting(nextseat) -- 下一个玩家下注
    end
    g.call(doRun)
end

--
local function onPotAnimation(self)
    local function doRun()
        log.debug("idx(%s,%s,%s) onPotAnimation", self.id, self.mid, tostring(self.logid))
        timer.cancel(self.timer, TimerID.TimerID_PotAnimation[1])
        self:finish()
    end
    g.call(doRun)
end

-- 买入超时
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

local function onBeting(arg)
    local function doRun()
        local self = arg[1]
        timer.cancel(self.timer, TimerID.TimerID_WaitBetting[1])
        self:betting(arg[2])
    end
    g.call(doRun)
end

-- 未调用该函数
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

-- 定时检测
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
                if user.is_bet_timeout and user.bet_timeout_count >= 2 then -- 超过两轮下注超时
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
                            {
                                sid = v.sid,
                                chips = v.chips,
                                money = self:getUserMoney(v.uid),
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
                    end
                    if v.chips > (self.conf and self.conf.ante + self.conf.fee or 0) then
                        v.isplaying = true
                    elseif v.chips <= (self.conf and self.conf.ante + self.conf.fee or 0) then
                        v.isplaying = false
                        if v:getIsBuyining() then -- 正在买入
                        elseif v:totalBuyin() > 0 then -- 非第一次坐下待买入，弹窗补币
                            v:setIsBuyining(true) -- 设置该玩家正在买入
                            pb.encode(
                                "network.cmd.PBTexasPopupBuyin",
                                {
                                    clientBuyin = true,
                                    buyinTime = self.conf.buyintime,
                                    sid = k
                                },
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
                        -- 客户端超时站起
                        end
                    end
                end
            end
        end

        -- log.info("idx(%s,%s) onCheck playing size=%s", self.id, self.mid, self:getPlayingSize())

        if self:getPlayingSize() < 2 then
            return
        end
        if self:getPlayingSize() >= 2 and global.ctsec() > self.endtime then
            timer.cancel(self.timer, TimerID.TimerID_Check[1]) -- 关闭检测定时器
            self:start() -- 开始游戏
        end
    end
    g.call(doRun)
end

-- 定时检测机器人
local function onCheckRobot(self)
    local function doRun()
        local all, r = self:count()
        if self.conf and self.conf.special and self.conf.special == 1 then -- 如果是新手专场
            if r < 4 then -- 确保有4个机器人
                Utils:notifyCreateRobot(self.conf.roomtype, self.mid, self.id, 3 - r)
            end
            if all == r and self.conf.maxuser == all then -- 如果全是机器人
                -- 随机一个机器人，让其离开
                for k, v in ipairs(self.seats) do
                    local user = self.users[v.uid]
                    if user and Utils:isRobot(user.api) then
                        user.state = EnumUserState.Logout
                        user.logoutts = global.ctsec() - 60
                        log.debug(
                            "idx(%s,%s,%s) onCheckRobot() robot leave, uid=%s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            tostring(v.uid)
                        )
                        break
                    end
                end
            end
        else -- 非新手专场
            if all == self.conf.maxuser and r > 1 then -- 如果座位已坐满且不止1个机器人坐下
                -- 随机一个机器人，让其离开
                for k, v in ipairs(self.seats) do
                    local user = self.users[v.uid]
                    if user and Utils:isRobot(user.api) then
                        user.state = EnumUserState.Logout
                        user.logoutts = global.ctsec() - 60
                        log.debug(
                            "idx(%s,%s,%s) onCheckRobot() robot leave, uid=%s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            tostring(v.uid)
                        )
                        break
                    end
                end
            end
            if r == 0 then -- 如果没有机器人
                log.debug("idx(%s,%s,%s) notify create robot", self.id, self.mid, tostring(self.logid))
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
    end
    g.call(doRun)
end

-- 定时结算清桌
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
        -- if self.needCancelTimer then
        --     onRobotLeave(self)
        -- end
        self:getNextState() -- 进入下一个状态
        self:reset()
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 定时检测
    end
    g.call(doRun)
end

-- 获取玩家身上金额
function Room:getUserMoney(uid)
    local user = self.users[uid]
    -- print('getUserMoney roomtype', self.conf.roomtype, 'money', user.money, 'coin', user.coin)
    if self.conf and user then
        if not self.conf.roomtype or self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
            return user.money
        elseif self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
            return user.coin
        end
    end
    return 0
end

-- 新建房间
-- room start
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
    self.conf = MatchMgr:getConfByMid(self.mid) -- 获取房间配置
    self.users = {}
    self.timer = timer.create()
    self.poker = TeemPatti:new()
    self.gameId = 0

    self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_None") -- 牌局状态(preflop, flop, turn...)
    self.buttonpos = 0 -- 庄家位置
    self.tabletype = self.conf.matchtype
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000
    self.bettingtime = self.conf.bettime -- 正常下注时长
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

    -- self.boardlog = BoardLog.new() -- 牌局记录器
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
    -- 实时牌局
    self.reviewlogitems = {} -- 暂存站起玩家牌局
    -- self.recentboardlog = RecentBoardlog.new() -- 最近牌局

    -- 配牌
    self.cfgcard_switch = false
    self.cfgcard =
        cfgcard:new(
        {
            handcards = {
                0x20E,
                0x10E,
                0x40E,
                0x30D,
                0x10D,
                0x40D,
                0x304,
                0x20d,
                0x10d,
                0x402,
                0x30b,
                0x102,
                0x105,
                0x203,
                0x30E
            }
        }
    )
    -- 主动亮牌
    self.req_show_dealcard = false -- 客户端请求过主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_NULL")
    self.lastchipinpos = 0

    self.tableStartCount = 0
    self.logid = self.statistic:genLogId()

    self.lastDealSpecialCardsTime = 0 -- 上次发特殊牌时刻(未充值玩家并且，玩牌局数>5,80%触发特殊牌局（5分钟内只能触发一次)
end

-- 重新加载配置
function Room:reload()
    self.conf = MatchMgr:getConfByMid(self.mid)
end

-- 给该桌所有玩家广播消息
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
    -- log.debug("idx:%s,%s is not cached", self.id,self.mid)
    end

    net.send_users(cjson.encode(self.links), maincmd, subcmd, msg, msglen)
end

-- 获取玩家数目
function Room:getUserNum()
    return self:count()
end

function Room:getApiUserNum()
    local t = {}
    for k, v in pairs(self.users) do
        if v.api and self.conf and self.conf.roomtype then
            t[v.api] = t[v.api] or {}
            t[v.api][self.conf.roomtype] = t[v.api][self.conf.roomtype] or {}
            if v.state == EnumUserState.Playing then -- 如果该玩家参与游戏
                if self:getSeatByUid(k) then
                    -- 参与游戏的人数
                    t[v.api][self.conf.roomtype].players = (t[v.api][self.conf.roomtype].players or 0) + 1
                else
                    -- 旁观者数目
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

-- 获取机器人人数
function Room:robotCount()
    local c = 0
    for k, v in pairs(self.users) do
        if Utils:isRobot(v.api) then
            c = c + 1
        end
    end
    return c
end

-- 返回坐下的人数 及 坐下的机器人人数
function Room:count()
    local c, r = 0, 0
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user then -- 如果该位置有玩家坐下
            c = c + 1
            if Utils:isRobot(user.api) then
                r = r + 1
            end
        end
    end
    return c, r
end

-- 未调用该函数
function Room:checkLeave()
    local c = self:count()
    if c == self.conf.maxuser then
        self.max_leave_count = (self.max_leave_count or 0) + 1
        self.rand_leave_count = self.rand_leave_count or rand.rand_between(0, 3)
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if user then
                if Utils:isRobot(user.api) and self.rand_leave_count <= self.max_leave_count then
                    self:userLeave(v.uid, user.linkid)
                    break
                end
            end
        end
    end
    c = self:count()
    if c < self.conf.maxuser then
        self.max_leave_count = nil
        self.rand_leave_count = nil
    end
end

-- 玩家退出
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

-- 清空指定服务器的玩家
function Room:clearUsersBySrvId(srvid)
    for k, v in pairs(self.users) do
        if v.linkid == srvid then
            self:logout(k)
        end
    end
end

-- 查询用户信息
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

-- 查询玩家已玩局数
function Room:userQueryPlayHand(uid, playHand)
    local user = self.users[uid]
    if user then
        user.playHand = playHand -- 已玩总局数
        log.info("DQW userQueryPlayHand() uid=%s, playHand=%s", uid, playHand)
    end
end

-- 查询充值信息
function Room:userQueryChargeInfo(uid, chargeMoney)
    local user = self.users[uid]
    if user then
        log.info("DQW userQueryChargeInfo() uid=%s, chargeMoney=%s", uid, chargeMoney)
        user.chargeMoney = chargeMoney -- 充值金额
    end
end

-- 玩家互斥检测
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

-- 查询用户结果
function Room:queryUserResult(ok, ud)
    if self.timer then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.debug("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

-- 玩家离开
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
                -- 增加条件，判断是否已经弃牌 2022-4-18
                if s.lastchiptype ~= pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") then
                    s:chipin(pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
                end
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
    -- local val = s.chips - s.last_chips
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
    if c == 1 and r == 1 then -- 如果只剩1个机器人
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

-- 获取推荐买入金额
function Room:getRecommandBuyin(balance, isRobot)
    local referrer = self.conf.ante * self.conf.referrerbb -- 推荐买入
    if referrer > balance then
        referrer = balance
        if isRobot then
            if referrer > self.conf.ante * self.conf.minbuyinbb * 200 then
                referrer = self.conf.ante * self.conf.minbuyinbb * rand.rand_between(5, 30)
            elseif referrer > self.conf.ante * self.conf.minbuyinbb * 100 then
                referrer = self.conf.ante * self.conf.minbuyinbb * rand.rand_between(5, 25)
            elseif referrer > self.conf.ante * self.conf.minbuyinbb * 20 then
                referrer = self.conf.ante * self.conf.minbuyinbb * rand.rand_between(5, 20)
            end
        end
    elseif referrer < self.conf.ante * self.conf.minbuyinbb then
        referrer = self.conf.ante * self.conf.minbuyinbb
    end
    if referrer > self.conf.ante * self.conf.maxbuyinbb then
        referrer = self.conf.ante * self.conf.maxbuyinbb
    end
    return referrer
end

-- 玩家进入
function Room:userInto(uid, linkid, mid, quick, ip, api)
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"), -- 返回码
        gameid = global.stype(), -- 游戏ID
        idx = {
            srvid = global.sid(), -- 服务器ID
            roomid = self.id, -- 房间ID
            matchid = self.mid, -- match ID
            roomtype = self.conf.roomtype or 0 -- 房间类型
        },
        maxuser = self.conf and self.conf.maxuser -- 最大玩家数
    }

    local function handleFail(code) -- 进入失败处理
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
    if Utils:hasIP(self, uid, ip, api) then -- 如果有相同IP的玩家存在
        handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_SameIp"))
        return
    end

    -- 新增条件
    if not Utils:isRobot(api) then -- 如果不是机器人
        -- self.conf = self.conf or MatchMgr:getConfByMid(self.mid)
        if self.conf.special and self.conf.special == 1 then -- 如果是新手专场
            local seat, inseat = nil, false
            for k, v in ipairs(self.seats) do
                if v.uid and v.uid == uid then
                    inseat = true -- 如果该玩家已经在该桌
                    seat = v
                    break
                end
            end
            if not inseat then
                local playerNum, robotNum = self:count() -- 获取所有玩家数及机器人人数
                if playerNum > robotNum then -- 如果已有真实玩家存在
                    handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_OverMaxInto"))
                    return
                end
            end
        end
    end

    self.users[uid] =
        self.users[uid] or
        {
            TimerID_MutexTo = timer.create(),
            TimerID_Timeout = timer.create(),
            TimerID_Expense = timer.create()
        }
    local user = self.users[uid]
    user.money = 0
    user.diamond = 0
    user.linkid = linkid
    user.ip = ip
    user.totalbuyin = user.totalbuyin or 0
    user.state = EnumUserState.Intoing
    -- 座位互斥
    local seat, inseat = nil, false
    for k, v in ipairs(self.seats) do
        if v.uid then
            if v.uid == uid then
                inseat = true -- 已经坐下
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
                -- Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
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
                    -- print("start coroutine", self, user, uid)
                    local ok, ud = coroutine.yield()
                    -- print('ok', ok, 'ud', ud)
                    if ud then
                        -- userinfo
                        user.uid = uid
                        user.money = ud.money or 0
                        user.coin = ud.coin or 0
                        user.diamond = ud.diamond or 0
                        user.nickurl = ud.nickurl or ""
                        user.username = ud.name or ""
                        user.viplv = ud.viplv or 0
                        -- user.tomato = 0
                        -- user.kiss = 0
                        user.sex = ud.sex or 0
                        user.api = ud.api or ""
                        user.ip = ip or ""
                        -- print('ud.money', ud.money, 'ud.coin', ud.coin, 'ud.diamond', ud.diamond, 'ud.nickurl', ud.nickurl, 'ud.name', ud.name, 'ud.viplv', ud.viplv)
                        -- user.addon_timestamp = ud.addon_timestamp

                        -- seat info
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
                    if ok and not inseat and self:getUserMoney(uid) + user.chips > self.conf.maxinto then
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
                                    {
                                        uid = uid,
                                        srvid = global.sid(),
                                        roomid = self.id
                                    }
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
                        self:sit(seat, uid, self:getRecommandBuyin(self:getUserMoney(uid), Utils:isRobot(user.api)))
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
    -- 奖池中包含哪些人共享
    self.maxraisepos = 0
    self.m_needcall = self.conf.ante
    self.roundcount = 0
    self.current_betting_pos = 0
    self.already_show_card = false
    self.sdata = {
        -- moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag -- 房间等级
    }
    self.reviewlogitems = {}
    -- self.boardlog:reset()
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
        bettingtime = self.bettingtime, --正常下注阶段时长
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

-- 发送所有座位信息给uid玩家
function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {} -- 该桌所有座位信息
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid then -- 如果该座位有人
            local seatinfo = fillSeatInfo(seat, self) -- 填充座位信息
            if seat.uid == uid and seat.ischeck then
                seatinfo.handcards = g.copy(seat.handcards)
                seatinfo.cardsType = seat.handtype
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
    -- print("PBTeemPattiTableInfoResp=", cjson.encode(tableinfo))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiTableInfoResp"),
        resp
    )
end

-- 检测指定玩家是否坐下
function Room:inTable(uid)
    for i = 1, #self.seats do
        if self.seats[i].uid == uid then
            return true
        end
    end
    return false
end

-- 根据玩家ID获取对应座位
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

-- 获取还在玩的玩家数 及 看了牌的玩家数
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

-- 获取seat的下一个要操作的座位
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

-- 获取下一个比牌位置
-- 参数 seat: 发起比牌者座位
function Room:getNextDuelPosition(seat)
    -- 两人明牌
    local nonfolds = self:getNonFoldSeats()
    if #nonfolds == 2 then -- 只有2个未弃牌玩家
        for _, v in ipairs(nonfolds) do
            if v.sid ~= seat.sid then
                return v
            end
        end
    end

    -- 两人以上比牌
    local j = (seat.sid - 1) % #self.seats > 0 and (seat.sid - 1) % #self.seats or #self.seats -- 查找一个座位号
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

-- 玩家站起
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
            self.sdata.users[uid].ugameinfo.texas.inctotalhands = 1 -- 增加的局数
            self.sdata.users[uid].ugameinfo.texas.inctotalwinhands =
                self.sdata.users[uid].ugameinfo.texas.inctotalwinhands or 0
            -- 第一次下注是盲注的手数
            self.sdata.users[uid].ugameinfo.texas.incpreflopfoldhands =
                self.sdata.users[uid].ugameinfo.texas.incpreflopfoldhands or 0
            -- 看牌加注的手数
            self.sdata.users[uid].ugameinfo.texas.incpreflopraisehands =
                self.sdata.users[uid].ugameinfo.texas.incpreflopraisehands or 0
            self.sdata.users[uid].ugameinfo.texas.leftchips = seat.chips - seat.roundmoney

            -- -- 输家防倒币行为
            -- if self.sdata.users[uid].extrainfo then
            --     local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
            --     if
            --         not Utils:isRobot(user.api) and extrainfo and self.sdata.users[uid].totalpureprofit < 0 and
            --             math.abs(self.sdata.users[uid].totalpureprofit) >= 100 * self.conf.ante and
            --             seat.last_active_chipintype ==
            --                 pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
            --             not user.is_bet_timeout and
            --             (user.check_call_num or 0) >= 3 and
            --             (self.round_player_num or 0) >= 2 and
            --             self.is_trigger_fold
            --      then
            --         extrainfo["cheat"] = true
            --         self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
            --         self.has_cheat = true
            --     end
            -- end

            self.reviewlogitems[seat.uid] =
                self.reviewlogitems[seat.uid] or
                {
                    player = {uid = seat.uid, username = user.username or ""},
                    sid = seat.sid,
                    handcards = g.copy(seat.handcards),
                    cardtype = self.poker:getPokerTypebyCards(seat.handcards),
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
        user.roundmoney = seat.roundmoney -- 该局总下注
        -- log.debug("idx(%s,%s,%s), uid=%s, roundmoney=%s", self.id, self.mid, tostring(self.logid), uid, seat.roundmoney)

        user.totalbuyin = seat.totalbuyin
        user.is_bet_timeout = nil
        user.bet_timeout_count = 0
        user.active_stand = true

        seat:stand(uid)
        pb.encode(
            "network.cmd.PBTexasPlayerStand",
            {sid = seat.sid, type = stype},
            function(pointer, length)
                self:sendCmdToPlayingUsers( -- 广播给该桌所有玩家某玩家站起
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

-- 玩家坐下
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
        -- 机器人只有在有空余1个座位以上才能坐下
        local allNum, robotNum = self:count()
        local empty = self.conf.maxuser - allNum -- 空座位数
        if Utils:isRobot(user.api) and (empty < 1 or (self.conf.maxuser - robotNum == 1)) then
            net.send(
                user.linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitFailed"),
                pb.encode(
                    "network.cmd.PBTexasSitFailed",
                    {
                        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                    }
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

        log.debug("queryPlayHand() 2, uid=%s, special=%s", uid, self.conf.special or 0)
        if self.conf and self.conf.special and self.conf.special == 1 then
            if not Utils:isRobot(user.api) then
                log.info("queryPlayHand(), uid=%s", uid)
                Utils:queryPlayHand(uid, global.stype(), self.mid, self.id, self.conf.roomtype) -- 查询真实玩家已玩局数
            end
        end
        seat:sit(uid, user.chips, 0, user.totalbuyin)
        local clientBuyin =
            (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante + self.conf.fee or 0))
        -- print('clientBuyin', clientBuyin)
        if clientBuyin then
            if (0x4 == (self.conf.buyin & 0x4) or Utils:isRobot(user.api)) and user.chips == 0 and user.totalbuyin == 0 then
                clientBuyin = false
                if not self:userBuyin(uid, user.linkid, {buyinMoney = buyinmoney}, true) then -- 玩家买入
                    seat:stand(uid)
                    return
                end
            else
                seat:setIsBuyining(true) -- 设置正在买入
                timer.tick(
                    self.timer,
                    TimerID.TimerID_Buyin[1] + 100 + uid,
                    self.conf.buyintime * 1000,
                    onBuyin, -- 等待买入
                    {self, uid},
                    1
                )
            end
        else
            -- 客户端超时站起
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
        local sitcmd = {
            seatInfo = seatinfo,
            clientBuyin = clientBuyin,
            buyinTime = self.conf.buyintime
        }
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

-- 发送操作位置  广播给所有人轮到某人操作
-- 参数 seat: 要操作者所在座位
-- 参数 chiptype: 操作方式(下注...)  非空则表示需要更新操作状态
function Room:sendPosInfoToAll(seat, chiptype)
    local updateseat = {}
    if chiptype then
        seat.chiptype = chiptype -- 该座位玩家正要做什么操作
        if chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING") then
            self:checkCharge(seat.uid) -- 检测某玩家是否需要充值
        elseif chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHARGING") then
            seat.addon_time = 300 - self.bettingtime -- 增加充值时间(300s)
            seat.total_time = seat:getChipinLeftTime()
        end
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
                self:sendCmdToPlayingUsers( -- 广播给该桌所有玩家
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
            updateseat.seatInfo.cardsType = seat.handtype  -- 牌型
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
    self.hasDuel = false -- 是否有比牌
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

    -- self.maxraisepos = self.buttonpos
    -- self.current_betting_pos = self.buttonpos
    log.info(
        "idx(%s,%s,%s) start ante:%s gameId:%s betpos:%s,%s robotcnt:%s logid:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self.conf.ante,
        self.gameId,
        self.current_betting_pos,
        self.buttonpos,
        self:robotCount(),
        tostring(self.logid)
    )
    -- 配牌处理
    if self.cfgcard_switch then
        self:setcard()
    end

    -- GameLog
    -- self.boardlog:appendStart(self)
    -- 服务费
    for k, v in ipairs(self.seats) do
        if v.uid and v.isplaying then
            local user = self.users[v.uid]
            if user and not Utils:isRobot(user.api) and not self.has_player_inplay then
                self.has_player_inplay = true
                -- 查询玩家充值金额
                if self.conf and self.conf.special and self.conf.special == 1 then
                    Utils:queryChargeInfo(v.uid, 33, self.mid, self.id)
                end
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
                    playchips = 20 * (self.conf.fee or 0)
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
            -- self:sendPosInfoToAll(v)
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
        cjson.encode(
        {
            buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0
        }
    )

    if self:getPlayingSize() == 1 then
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
        return
    end

    -- 底注
    self:dealPreChips()

    -- 防逃盲
    -- self:dealAntiEscapeBB()

    -- if self.conf.ante <= 0 then
    --   onStartPreflop(self)
    -- end
end

-- 判断该玩家是否可操作
function Room:checkCanChipin(seat)
    return seat and seat.uid and seat.sid == self.current_betting_pos and seat.isplaying and --        self.state == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_BETTING") and
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
        -- timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
        return true
    end
    return false
end

-- 比牌超时？
-- 参数 nofold: 没有弃牌者?
local function onDuelCard(arg)
    local function doRun()
        local self = arg[1]
        local nofold = arg[2]
        timer.cancel(self.timer, TimerID.TimerID_Dueling[1])
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting") -- 比牌结束，进入下注状态
        local dueler = self.seats[self.m_dueler_pos] -- 发起比牌者
        local loser = self.seats[self.m_duel_loser_pos]
        log.debug(
            "idx(%s,%s,%s) onDuelCard() self.m_dueler_pos=%s, self.m_duel_loser_pos",
            self.id,
            self.mid,
            tostring(self.logid),
            self.m_dueler_pos,
            self.m_duel_loser_pos
        )

        if loser then -- 失败者座位
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
            local next = self:getNextActionPosition(dueler) -- 下一个操作者座位
            self:betting(next)
        end
    end
    g.call(doRun)
end

-- 玩家操作
-- 参数 uid: 操作者uid
-- 参数 type: 操作方式
-- 参数 money: 操作所需金额
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

    -- 弃牌
    local function fold_func(seat, type, money)
        if self.state == pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Dueling") then -- 如果是比牌状态
            if seat.sid ~= self.m_dueled_pos then
                log.error(
                    "idx(%s,%s,%s) fold_func() sid=%s,m_dueled_pos=%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    seat.sid,
                    self.m_dueled_pos
                )
            end
            self.m_duel_loser_pos = self.m_dueled_pos -- 被比牌者输?
            timer.tick(self.timer, TimerID.TimerID_Dueling[1], 800, onDuelCard, {self, false})
            --onDuelCard({self})
            return false
        end

        seat:chipin(type, 0)
        res = true
        return true
    end

    -- 交前注
    local function prechips_func(seat, type, money)
        seat:chipin(type, money)
        return true
    end

    -- 看牌
    local function check_func(seat, type, money)
        if not seat.ischeck then -- 如果还未看牌
            seat.ischeck = true
            seat:chipin(type, 0)
            self:sendPosInfoToMe(seat)
            seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
        end
        return true
    end

    -- 跟注或加注
    local function call_raise_func(seat, type, money)
        if seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING_LACK") then
            self:sendPosInfoToAll(
                seat,
                pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHARGING")
            )
            log.info("send PBTeemPattiChipinType_CHARGING uid=%s", seat.uid)
            return false
        end

        if not is_enough_money then
            if self.conf and self.conf.special and self.conf.special == 1 then -- 如果是新手专场
                local user = self.users[uid]
                if not Utils:isRobot(user.api) then
                    self:sendPosInfoToAll(
                        seat,
                        pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHARGING")
                    )
                    log.info("send PBTeemPattiChipinType_CHARGING 2 uid=%s", seat.uid)
                end
            end
            return false
        end

        -- 玩家看牌后跟注次数
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

        log.debug(
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
            -- if not is_enough_money or needcall ~= money then
            if needcall ~= money then
                type = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
                money = 0
            end
        elseif type == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_RAISE") then
            -- if not is_enough_money or needraise ~= money then
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

    -- 确认比牌
    -- 参数 type:
    -- 参数 noduel: 是否明牌
    local function duel_yes_func(seat, type, money, noduel)
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting")
        if (self.m_dueled_pos or 0) == seat.sid then
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            seat:chipin(type, 0)

            local duelCardCmd = {type = 0, winnerSid = 0, loserSid = 0}
            local dueler = self.seats[self.m_dueler_pos] -- 发起比牌者座位
            local dueled = self.seats[self.m_dueled_pos] -- 被比牌者座位
            if dueler and dueler.isplaying and dueled and dueled.isplaying then
                if self.poker:isBankerWin(dueler.handcards, dueled.handcards) > 0 then -- 如果发起比牌者赢
                    duelCardCmd.winnerSid = self.m_dueler_pos
                    duelCardCmd.loserSid = self.m_dueled_pos
                else
                    duelCardCmd.winnerSid = self.m_dueled_pos
                    duelCardCmd.loserSid = self.m_dueler_pos
                end
                self.m_duel_loser_pos = duelCardCmd.loserSid
            end

            if not noduel then -- 如果不明牌
                duelCardCmd.type = 1 -- 1：比牌，2：明牌
                timer.tick(self.timer, TimerID.TimerID_Dueling[1], TimerID.TimerID_Dueling[2], onDuelCard, {self}) -- 

                for k, user in pairs(self.users) do
                    if user.state == EnumUserState.Playing then
                        duelCardCmd.cards = nil
                        if dueler and dueler.uid == k and dueled then
                            duelCardCmd.cards = {}
                            duelCardCmd.cards.showType = 1
                            duelCardCmd.cards.sid = self.m_dueled_pos
                            duelCardCmd.cards.handcards = g.copy(dueled.handcards)
                            duelCardCmd.cards.cardsType = dueled.handtype
                        end
                        if dueled and dueled.uid == k and dueler then
                            duelCardCmd.cards = {}
                            duelCardCmd.cards.showType = 1
                            duelCardCmd.cards.sid = self.m_dueler_pos
                            duelCardCmd.cards.handcards = g.copy(dueler.handcards)
                            duelCardCmd.cards.cardsType = dueler.handtype
                        end
                        local resp = pb.encode("network.cmd.PBTeemPattiNotifyDuelCard_N", duelCardCmd)
                        net.send(
                            user.linkid,
                            k,
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiNotifyDuelCard"),
                            resp
                        )
                    end
                end
                log.debug(
                    "idx(%s,%s,%s) duel_yes_func()  m_dueler_pos=%s,m_dueled_pos=%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    self.m_dueler_pos,
                    self.m_dueled_pos
                )
            else
                -- 明牌需要show牌
                dueler.show, dueled.show = true, true
                -- timer.tick(self.timer, TimerID.TimerID_Dueling[1], TimerID.TimerID_Dueling[2], onDuelCard, self)
                duelCardCmd.type = 2 -- 1：比牌，2：明牌

                for k, user in pairs(self.users) do
                    if user.state == EnumUserState.Playing then
                        duelCardCmd.cards = nil
                        if dueler and dueler.uid == k and dueled then
                            duelCardCmd.cards = {}
                            duelCardCmd.cards.showType = 1
                            duelCardCmd.cards.sid = self.m_dueled_pos
                            duelCardCmd.cards.handcards = g.copy(dueled.handcards)
                            duelCardCmd.cards.cardsType = dueled.handtype
                        end
                        if dueled and dueled.uid == k and dueler then
                            duelCardCmd.cards = {}
                            duelCardCmd.cards.showType = 1
                            duelCardCmd.cards.sid = self.m_dueler_pos
                            duelCardCmd.cards.handcards = g.copy(dueler.handcards)
                            duelCardCmd.cards.cardsType = dueler.handtype
                        end
                        local resp = pb.encode("network.cmd.PBTeemPattiNotifyDuelCard_N", duelCardCmd)
                        net.send(
                            user.linkid,
                            k,
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiNotifyDuelCard"),
                            resp
                        )
                    end
                end

                self:sendPosInfoToAll(seat)
                log.debug(
                    "idx(%s,%s,%s) duel_yes_func() 2 m_dueler_pos=%s,m_dueled_pos=%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    self.m_dueler_pos,
                    self.m_dueled_pos
                )
                timer.tick(self.timer, TimerID.TimerID_Dueling[1], 800, onDuelCard, {self, true})
                -- onDuelCard(self, true)
                return false --??
            end
        end
        return true
    end

    -- 拒绝比牌
    local function duel_no_func(seat, type, money)
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Betting") -- 比完牌进入下注状态
        local dueler = self.seats[self.m_dueler_pos] -- 发起比牌者座位
        if (self.m_dueled_pos or 0) == seat.sid and dueler then
            log.debug(
                "idx(%s,%s,%s) duel_no_func() m_dueler_pos=%s,m_dueled_pos=%s",
                self.id,
                self.mid,
                tostring(self.logid),
                self.m_dueler_pos,
                self.m_dueled_pos
            )
            timer.cancel(self.timer, TimerID.TimerID_Betting[1])
            seat:chipin(type, 0)
            self:sendPosInfoToAll(seat)
            self.m_dueled_pos, self.m_dueler_pos = 0, 0
            local next = self:getNextActionPosition(dueler)
            self:betting(next)
        end
        return true
    end

    -- 发起比牌
    local function duel_func(seat, type, money)
        if seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING_LACK") then
            self:sendPosInfoToAll(
                seat,
                pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHARGING")
            )
            log.info("send PBTeemPattiChipinType_CHARGING uid=%s", seat.uid)
            return false
        end

        local playingnum, checknum = self:getPlayingAndCheckNum() -- 获取还在玩的玩家数 及 看了牌的玩家数
        if is_enough_money then
            local next = self:getNextDuelPosition(seat) -- 获取被比牌者
            if next then
                self.m_dueler_pos = seat.sid -- 发起比牌者座位号
                self.m_dueled_pos = next.sid -- 被比牌者座位号
                self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_Dueling") -- 比牌中
                self.hasDuel = true -- 有比牌
                if playingnum == 2 then -- 如果只剩2个玩家在玩
                    seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
                    next.handtype = self.poker:getPokerTypebyCards(g.copy(next.handcards))
                    seat:chipin(type, money)
                    self:sendPosInfoToAll(seat)
                    log.debug(
                        "idx(%s,%s,%s) duel_func() m_dueler_pos=%s,m_dueled_pos=%s playingnum == 2 ",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        self.m_dueler_pos,
                        self.m_dueled_pos
                    )
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
                        log.debug(
                            "idx(%s,%s,%s) duel_func() m_dueler_pos=%s,m_dueled_pos=%s ",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            self.m_dueler_pos,
                            self.m_dueled_pos
                        )
                        -- 增加时间 DQW 2022-4-19
                        timer.tick( self.timer, TimerID.TimerID_WaitBetting[1],
                            TimerID.TimerID_WaitBetting[2],
                            onBeting,
                            {self,next}
                         )
                        -- self:betting(next)
                    end
                end
            end
        end
        return false
    end

    local switch = {
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")] = fold_func, -- 弃牌
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CALL")] = call_raise_func, -- 跟注
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CHECK")] = check_func, -- 看牌
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_RAISE")] = call_raise_func, -- 加注
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL")] = duel_func, -- 比牌
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL_YES")] = duel_yes_func, -- 确认比牌
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_DUEL_NO")] = duel_no_func, -- 拒绝比牌
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_WAIT")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_CLEAR_STATUS")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_REBUYING")] = nil,
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_PRECHIPS")] = prechips_func, -- 交前注
        [pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BUYING")] = nil -- 正在买入
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, tostring(self.logid), uid, type)
        return false
    end

    -- 真正操作chipin
    if chipin_func(seat, type, money) then
        log.debug("idx(%s,%s,%s) chipin_func chipintype:%s", self.id, self.mid, tostring(self.logid), type)
        self:sendPosInfoToAll(seat)
    end

    -- GameLog
    -- self.boardlog:appendChipin(self, seat)
    return res
end

-- 参数 type: 操作方式
-- 参数 money: 操作所需金额
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
    if money < self.conf.minchip then
        money = self.conf.minchip
    end
    if self.conf.minchip == 0 or (money > 0 and money < self.conf.minchip) then
        log.info("idx(%s,%s,%S) chipin minchip invalid uid:%s", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    if
        not chipin_seat.isplaying or
            chipin_seat.chiptype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
     then -- 如果不参与游戏 或 已经弃牌
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
    if not chipin_result then -- 如果操作失败
        -- log.info("idx(%s,%s) chipin failed uid:%s",self.id,self.mid,uid)
        return false
    end
    -- if type == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") then -- 如果当前是弃牌操作
    --     -- 判断该玩家是否是机器人
    --     if self.users[uid] and Utils:isRobot(self.users[uid].api) then -- 如果是机器人
    --         if not self.willLeaveRobot then -- 如果还没有机器人要离开
    --             self.willLeaveRobot = uid
    --             timer.tick(
    --                 self.timer,
    --                 TimerID.TimerID_RobotLeave[1],
    --                 TimerID.TimerID_RobotLeave[2] + rand.rand_between(0, 20000),
    --                 onRobotLeave, -- 定时离开
    --                 self
    --             )
    --             self.needCancelTimer = true
    --         else -- 如果已有机器人要离开
    --             if rand.rand_between(1, 10000) < 5000 then
    --                 self.willLeaveRobot = uid -- 随机更改要离开的机器人
    --             end
    --         end
    --     end
    -- end

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

    self:betting(next_seat) -- 广播轮到下一个玩家操作

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
        self.state = pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_HandCard") -- 进入发牌状态
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
        -- self.boardlog:appendPreChips(self)

        timer.tick(self.timer, TimerID.TimerID_PrechipsOver[1], TimerID.TimerID_PrechipsOver[2], onPrechipsOver, self)
    else
        onStartHandCards(self)
    end
end

-- 通用发牌
-- 参数 seatcards:
-- 参数 needDealBigCards: 是否需要发大牌
-- 参数 bigcardcheck: 是否需要给所有人发大牌
-- 参数 robotfire: 是否通知机器人
function Room:dealHandCardsCommon(seatcards, needDealBigCards, bigcardcheck, robotfire)
    -- 给该座位所有玩家发牌
    local needRedeal = false -- 是否需要重新发牌
    local createJoker = false
    local times = 0 -- 重发次数
    local allSendCards = {} -- 所有已发出的牌

    if needDealBigCards and bigcardcheck then
        while (times < 5) do
            allSendCards = {} -- 所有已发出的牌
            needRedeal = false -- 是否需要重新发牌
            for k, seat in ipairs(self.seats) do
                local user = self.users[seat.uid]
                if user and seat.isplaying then
                    seat.handcards = self.poker:getNCard(2)

                    if
                        self.poker:hasSend(allSendCards, seat.handcards[1]) or
                            self.poker:hasSend(allSendCards, seat.handcards[2])
                     then
                        needRedeal = true -- 需要重新发牌
                        self.poker:reset()
                        times = times + 1
                        break
                    end
                    table.insert(allSendCards, seat.handcards[1])
                    table.insert(allSendCards, seat.handcards[2])

                    seat.handcards[3] = self.poker:getJokerCard(seat.handcards)
                    if self.poker:hasSend(allSendCards, seat.handcards[3]) then
                        needRedeal = true -- 需要重新发牌
                        self.poker:reset()
                        times = times + 1
                        break
                    end

                    table.insert(allSendCards, seat.handcards[3])
                    seat.handtype = self.poker:getPokerTypebyCards(seat.handcards)
                end
            end
            if not needRedeal then
                log.debug("send big cards")
                createJoker = true
                break
            end
        end
    end
    if not needDealBigCards or needRedeal then -- 如果不需要发大牌
        for k, seat in ipairs(self.seats) do
            local user = self.users[seat.uid]
            if user and seat.isplaying then
                if self.cfgcard_switch then
                    seat.handcards[1] = self.cfgcard:popHand()
                    seat.handcards[2] = self.cfgcard:popHand()
                    seat.handcards[3] = self.cfgcard:popHand()
                else
                    seat.handcards = self.poker:getNCard(3)
                end
                seat.handtype = self.poker:getPokerTypebyCards(seat.handcards)
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

                log.debug(
                    "idx(%s,%s,%s) sid:%s,uid:%s deal handcard:%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    k,
                    seat.uid,
                    string.format("0x%x,0x%x,0x%x", seat.handcards[1], seat.handcards[2], seat.handcards[3])
                    --cjson.encode(seat.handcards)
                )

                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].cards =
                    self.sdata.users[seat.uid].cards or
                    {
                        seat.handcards[1],
                        seat.handcards[2],
                        seat.handcards[3]
                    }
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
                    pb.encode(
                        "network.cmd.PBTeemPattiDealCardOnlyRobot",
                        {cards = seatcards, isJoker = createJoker, isSpecial = false}
                    )
                )
            end
        end
    end
end

-- 发牌
-- deal handcards
function Room:dealHandCards()
    local dealcard = {}
    local robotlist = {} -- 机器人ID 列表
    local hasplayer = false
    local realPlayerUID = 0 -- 真实玩家UID

    for _, seat in ipairs(self.seats) do
        table.insert(dealcard, {sid = seat.sid, handcards = {0, 0, 0}})
        local user = self.users[seat.uid]
        if user and seat.isplaying then
            if Utils:isRobot(user.api) then
                table.insert(robotlist, seat.uid)
            else
                realPlayerUID = seat.uid
                hasplayer = true -- 有真人参与游戏
            end
        end
    end

    -- 广播牌背给所有在玩玩家
    for k, v in pairs(self.users) do
        -- if v.state == EnumUserState.Playing and (not self:getSeatByUid(k) or not self:getSeatByUid(k).isplaying) then
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

    -- 判断是否要真实玩家赢
    local winnerUID = 0 -- 赢家UID
    local loserUID = 0
    local sendSpecialCards = false -- 是否发特殊牌
    if self.conf and self.conf.special and self.conf.special == 1 and hasplayer then -- 如果是新手专场
        log.debug("hasplayer=%s, self.conf.special=%s", tostring(hasplayer), tostring(self.conf.special))
        -- 查找参与游戏的真实玩家
        local user = self.users[realPlayerUID] -- 真实玩家
        if user and user.chargeMoney and user.chargeMoney == 0 then -- 如果玩家未充值
            if user.playHand then -- 如果该玩家还未玩tp游戏
                log.debug("DQW realPlayerUID=%s, user.chargeMoney=%s", realPlayerUID, user.chargeMoney)
                if user.playHand == 0 then -- 如果该玩家还未玩tp游戏
                    winnerUID = realPlayerUID
                elseif user.playHand <= 5 then
                    -- 60%的概率玩家赢
                    -- if rand.rand_between(1, 10000) < 1000 then -- 10% + 45%的概率玩家赢
                    --     winnerUID = realPlayerUID
                    -- end
                    if rand.rand_between(1, 100) < 60 then -- 60%的概率玩家赢
                        winnerUID = realPlayerUID
                    else
                        loserUID = realPlayerUID
                        log.debug("playHand=%s,loserUID=%s", user.playHand, loserUID)
                    end
                else -- 超过5局
                    local seat = self:getSeatByUid(realPlayerUID)
                    local money = self:getUserMoney(realPlayerUID) or 0
                    --60%触发特殊牌局（5分钟内只能触发一次）
                    --user.lastSendSpecialCardsTime = user.lastSendSpecialCardsTime or 0 --上次发特殊牌时刻
                    TeenPattiSpecialTime = TeenPattiSpecialTime or {}
                    TeenPattiSpecialTime[realPlayerUID] = TeenPattiSpecialTime[realPlayerUID] or 0  --上次发特殊牌时刻
                    local currentTime = global.ctsec() -- 当前时刻(秒)
                    if currentTime - (TeenPattiSpecialTime[realPlayerUID] or 0) > 600 and seat then
                        --  剩余筹码小于340*ante                        
                        if seat and self.conf and self.conf.ante and seat.chips + money < 340 * self.conf.ante then
                            log.debug("uid=%s, ante=%s, chips=%s", realPlayerUID, self.conf.ante, seat.chips)
                            -- 60%的概率发特殊牌
                            if rand.rand_between(1, 100) < 60 then
                                --user.lastSendSpecialCardsTime = currentTime --
                                TeenPattiSpecialTime[realPlayerUID] = currentTime
                                winnerUID = realPlayerUID
                                sendSpecialCards = true -- 准备发特殊牌
                            end

                            -- 移除未使用的玩家信息
                            for i, v in pairs(TeenPattiSpecialTime) do
                                if i and v and currentTime - v > 600 then
                                    TeenPattiSpecialTime[i] = nil
                                    log.debug("DQW TeenPattiSpecialTime[%s] = nil", i)
                                end
                            end

                        else
                            log.debug(
                                "DQW realPlayerUID=%s, user.chargeMoney=%s, ante=%s, chips=%s",
                                realPlayerUID,
                                user.chargeMoney,
                                self.conf.ante,
                                seat.chips
                            )
                        end
                    end

                    if not sendSpecialCards and user.playHand <= 30 and seat then                        
                        if seat and self.conf and self.conf.ante and (seat.chips + money < 340 * self.conf.ante) then
                            -- 未充值玩家，6-30局未触发特殊牌局，筹码+余额<30*ante，30%赢
                            if rand.rand_between(1, 100) < 30 then
                                winnerUID = realPlayerUID
                            else
                                loserUID = realPlayerUID
                            end

                        end
                    end
                end                

                user.playHand = user.playHand + 1 -- 已玩局数增1
            end
        end
    else
        log.debug("hasplayer=%s, self.conf.special=%s", tostring(hasplayer), tostring(self.conf.special))
    end

    local seatcards = g.copy(dealcard)
    if sendSpecialCards then  -- 如果 发特殊牌
        -- elseif winnerUID > 0 then
        --     self:dealSpecialCards2(seatcards, winnerUID) -- 发牌,控制玩家输赢
        -- elseif loserUID > 0 then
        --     self:dealSpecialCards2(seatcards, nil, loserUID) -- 发牌,控制玩家输赢
        --self:dealSpecialCards(seatcards) -- 发特殊牌
        if rand.rand_between(1, 100) < 50 then
            self:dealSpecialCards2(seatcards, nil, winnerUID) -- 发牌,控制玩家输赢
        else
            self:dealSpecialCards2(seatcards, winnerUID, nil) -- 发牌,控制玩家输赢
        end
    elseif (self.conf.single_profit_switch and hasplayer) or winnerUID > 0 or loserUID > 0 then -- 单个人控制 且 有真实玩家下注了
        self.result_co =
            coroutine.create(
            function()
                local msg = {
                    ctx = 0,
                    matchid = self.mid,
                    roomid = self.id,
                    data = {},
                    ispvp = true
                }
                for _, seat in ipairs(self.seats) do
                    local v = self.users[seat.uid]
                    if v and not Utils:isRobot(v.api) and seat.isplaying then -- 真实玩家
                        table.insert(
                            msg.data,
                            {
                                uid = seat.uid,
                                chips = 0, --20 * (self.conf.fee or 0),   -- 2022-4-16 
                                betchips = 0
                            }
                        )
                    end
                end
                log.info(
                    "idx(%s,%s) start result request %s winnerUID=%s,loserUID=%s",
                    self.id,
                    self.mid,
                    cjson.encode(msg),
                    winnerUID,
                    loserUID
                )
                Utils:queryProfitResult(msg)
                local ok, res = coroutine.yield() -- 等待查询结果
                local winlist, loselist = {}, {}
                if ok and res then
                    for _, v in ipairs(res) do
                        local uid, r, maxwin = v.uid, v.res, v.maxwin
                        if winnerUID > 0 then
                            r = 1
                        elseif loserUID > 0 then
                            r = -1
                        end

                        if self.sdata.users[uid] and self.sdata.users[uid].extrainfo then
                            local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
                            if extrainfo then
                                extrainfo["maxwin"] = r * maxwin
                                self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
                            end
                        end
                        log.info(
                            "idx(%s,%s,%s) finish result uid=%s,r=%s, winnerUID=%s,loserUID=%s,v.res=%s,v.maxwin=%s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            uid,
                            r,
                            winnerUID,
                            loserUID,
                            tostring(v.res),
                            tostring(v.maxwin)
                        )
                        if r > 0 then
                            table.insert(winlist, uid)
                        elseif r < 0 then
                            table.insert(loselist, uid)
                        end
                    end
                end
                log.info(
                    "idx(%s,%s,%s) ok %s winlist loselist robotlist %s,%s,%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
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
                if not winner and loser and #robotlist > 0 then -- 如果没有确定赢家只确定输家
                    -- winner = self:getSeatByUid(table.remove(robotlist))
                    winner = self:getSeatByUid(table.remove(robotlist, rand.rand_between(1, #robotlist)))
                elseif winner and not loser and #robotlist > 0 then
                    loser = self:getSeatByUid(table.remove(robotlist, rand.rand_between(1, #robotlist)))
                end
                if winner and loser then
                    local dealBigCardsTimes = 0
                    for retrytime = 1, 1000 do
                        local leftCards = {
                            --方块
                            0x102,
                            0x103,
                            0x104,
                            0x105,
                            0x106,
                            0x107,
                            0x108,
                            0x109,
                            0x10A,
                            0x10B,
                            0x10C,
                            0x10D,
                            0x10E,
                            --梅花
                            0x202,
                            0x203,
                            0x204,
                            0x205,
                            0x206,
                            0x207,
                            0x208,
                            0x209,
                            0x20A,
                            0x20B,
                            0x20C,
                            0x20D,
                            0x20E,
                            --红桃
                            0x302,
                            0x303,
                            0x304,
                            0x305,
                            0x306,
                            0x307,
                            0x308,
                            0x309,
                            0x30A,
                            0x30B,
                            0x30C,
                            0x30D,
                            0x30E,
                            --黑桃
                            0x402,
                            0x403,
                            0x404,
                            0x405,
                            0x406,
                            0x407,
                            0x408,
                            0x409,
                            0x40A,
                            0x40B,
                            0x40C,
                            0x40D,
                            0x40E
                        } -- 剩余的牌
                        local handcards_rank = {}
                        --local pairnum = 0
                        local max_cardtype = 0
                        self.poker:reset()
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying then
                                local hcards = {0, 0, 0}
                                if self.cfgcard_switch then
                                    hcards[1] = self.cfgcard:popHand()
                                    hcards[2] = self.cfgcard:popHand()
                                    hcards[3] = self.cfgcard:popHand()
                                else
                                    -- hcards = self.poker:getNCard(3)
                                    if dealBigCardsTimes < 2 then
                                        dealBigCardsTimes = dealBigCardsTimes + 1
                                        hcards = self:dealBigCards2(leftCards)
                                    else
                                        hcards = self:randNormalCards(leftCards)
                                    end
                                    leftCards = self:removeCards(leftCards, hcards) -- 更新剩余的牌
                                end
                                local htype = self.poker:getPokerTypebyCards(hcards)
                                -- if
                                --     htype >=
                                --         pb.enum_id(
                                --             "network.cmd.PBTeemPattiCardWinType",
                                --             "PBTeemPattiCardWinType_ONEPAIR"
                                --         ) and (hcards[2] & 0xF) >= 0x8
                                --  then -- 待修改
                                --     pairnum = pairnum + 1
                                -- end
                                -- if htype > max_cardtype then
                                --     max_cardtype = htype
                                -- end

                                table.insert(handcards_rank, {htype, hcards})
                            end
                        end
                        table.sort(
                            handcards_rank,
                            function(a, b)
                                return self.poker:isBankerWin(a[2], b[2]) < 0
                            end
                        )
                        log.debug(
                            "idx(%s,%s,%s) find the result=%s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            cjson.encode(handcards_rank)
                        )
                        -- 分配最大牌赢家
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying then
                                if winner == seat then
                                    seat.handcards = handcards_rank[#handcards_rank][2]
                                    seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
                                    table.remove(handcards_rank)
                                    log.debug(
                                        "idx(%s,%s,%s) winner cards=%s,uid=%s,sid=%s",
                                        self.id,
                                        self.mid,
                                        tostring(self.logid),
                                        string.format(
                                            "0x%x,0x%x,0x%x",
                                            seat.handcards[1],
                                            seat.handcards[2],
                                            seat.handcards[3]
                                        ),
                                        seat.uid,
                                        seat.sid
                                    )
                                    break
                                end
                            end
                        end
                        -- 分配第二大牌输家
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying then
                                if loser == seat then
                                    seat.handcards = handcards_rank[#handcards_rank][2]
                                    seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
                                    table.remove(handcards_rank)
                                    log.debug(
                                        "idx(%s,%s,%s) loser cards=%s,uid=%s,sid=%s",
                                        self.id,
                                        self.mid,
                                        tostring(self.logid),
                                        string.format(
                                            "0x%x,0x%x,0x%x",
                                            seat.handcards[1],
                                            seat.handcards[2],
                                            seat.handcards[3]
                                        ),
                                        seat.uid,
                                        seat.sid
                                    )
                                    break
                                end
                            end
                        end
                        -- 剩余分配给其他玩家
                        for _, seat in ipairs(self.seats) do
                            if seat.isplaying and seat ~= winner and seat ~= loser then
                                seat.handcards = handcards_rank[#handcards_rank][2]
                                seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
                                table.remove(handcards_rank)
                                log.debug(
                                    "idx(%s,%s,%s) other cards=%s,uid=%s,sid=%s",
                                    self.id,
                                    self.mid,
                                    tostring(self.logid),
                                    string.format(
                                        "0x%x,0x%x,0x%x",
                                        seat.handcards[1],
                                        seat.handcards[2],
                                        seat.handcards[3]
                                    ),
                                    seat.uid,
                                    seat.sid
                                )
                            end
                        end
                        -- if
                        --     pairnum >= 2 and
                        --         max_cardtype <
                        --             pb.enum_id(
                        --                 "network.cmd.PBTeemPattiCardWinType",
                        --                 "PBTeemPattiCardWinType_STRAIGHTFLUSH"
                        --             )
                        --  then
                        --     log.info("idx(%s,%s) result success %s", self.id, self.mid, pairnum)
                        --     break
                        -- end
                        break
                    end
                    self:dealHandCardsCommon(seatcards, true, false, false)
                else
                    log.debug(
                        "idx(%s,%s,%s) dealHandCardsCommon(seatcards, false, false, true)",
                        self.id,
                        self.mid,
                        tostring(self.logid)
                    )
                    self:dealHandCardsCommon(seatcards, false, false, true)
                end
            end
        )
        timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, {self})
        coroutine.resume(self.result_co)
    else
        local needDealBigCards = rand.rand_between(1, 10000) <= (self.conf.bigcardsrate or 0)
        log.debug(
            "idx(%s,%s,%s) dealHandCardsCommon(seatcards, ?, true, true)",
            self.id,
            self.mid,
            tostring(self.logid)
        )
        self:dealHandCardsCommon(seatcards, needDealBigCards, true, true) -- 发手牌
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

-- 检测是否超出底池限制
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

-- 获取所有非弃牌玩家座位
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

-- 下注超时处理
local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos] -- 当前下注座位

        local user = self.users[current_betting_seat.uid] --
        if current_betting_seat:isChipinTimeout() then -- 是否操作超时
            log.info(
                "idx(%s,%s,%s) onBettingTimer over time bettingpos:%s uid:%s",
                self.id,
                self.mid,
                tostring(self.logid),
                self.current_betting_pos,
                current_betting_seat.uid or 0
            )
            timer.cancel(self.timer, TimerID.TimerID_Betting[1]) -- 关闭定时器

            if user and self.m_dueled_pos ~= self.current_betting_pos then -- 如果是被比牌者
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
    g.call(doRun)
end

-- 轮到指定座位操作(下注、加注、弃牌等)
function Room:betting(seat)
    if not seat then
        return false
    end

    seat.bettingtime = global.ctsec() -- 开始下注时刻(秒)
    self.current_betting_pos = seat.sid -- 更新当前操作座位号
    log.debug(
        "idx(%s,%s,%s) it's betting pos:%s uid:%s",
        self.id,
        self.mid,
        tostring(self.logid),
        self.current_betting_pos,
        tostring(seat.uid)
    )

    local function notifyBetting() -- 通知所有玩家轮到某人下注
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING"))
        --self:checkCharge(seat.uid) -- 检测某玩家是否需要充值
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self)
    end

    -- 预操作
    local preop = seat:getPreOP() --
    if preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_CheckOrFold") then -- 过牌或弃牌
        -- 玩家弃牌
        self:userchipin(seat.uid, pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD"), 0)
        seat:setPreOP(pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None"))
    else
        notifyBetting() -- 通知所有玩家轮到某人下注
    end
end

-- 广播show牌
function Room:broadcastShowCardToAll()
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying and seat.show then
            local showdealcard = {
                showType = 1,
                sid = i,
                handcards = g.copy(seat.handcards),
                cardsType = seat.handtype  -- 牌型
            }
            if self.isOverPot then
                showdealcard.showType = 3
            end
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

    -- 摊牌前最后一个弃牌的玩家可以主动亮牌
    if
        self.lastchipintype == pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD") and
            self.lastchipinpos ~= 0 and
            self.lastchipinpos <= #self.seats and
            not self.seats[self.lastchipinpos].show
     then
        showpos[self.lastchipinpos] = true
    end

    -- 获取底池的玩家可以主动亮牌
    for pos, _ in pairs(poss) do
        if not self.seats[pos].show then
            showpos[pos] = true
        end
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        local user = self.users[seat.uid]
        if seat.isplaying and seat.uid and user then
            -- 系统盖牌的玩家有权主动亮牌
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

    -- 获取或者玩家座位列表
    local winners = {}
    local nonfolds = self:getNonFoldSeats()
    local isoverpot = self:isOverPotLimit()
    self.isOverPot = isoverpot
    for i = 1, #nonfolds do
        local seat = nonfolds[i]
        seat.show = isoverpot and true or seat.show
        for j = 1, #nonfolds do
            local other = nonfolds[j]
            if other then
                if self.poker:isBankerWin(seat.handcards, other.handcards) < 0 then
                    break
                end
            end
            -- 全赢或者平手
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
        log.debug(
            "idx(%s,%s,%s) user finish %s %s %s",
            self.id,
            self.mid,
            tostring(self.logid),
            v.roundmoney,
            v.chips,
            v.last_chips
        )
        v.last_chips = v.chips + self.conf.fee
        if g.isInTable(winners, v) then -- 盈利玩家
            -- 奖池抽水服务费
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

            -- JackPot中奖
            if
                JACKPOT_CONF[self.conf.jpid] and #winners == 1 and
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
        else -- 亏损玩家
            v.chips = (v.chips > v.roundmoney) and (v.chips - v.roundmoney) or 0
        end
    end

    -- JackPot抽水
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
    if not self.hasDuel and not isoverpot then
        t_msec = t_msec - 3000
    end
    -- jackpot 中奖需要额外增加下局开始时间
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
    self:checkCheat() -- 防倒币检测  2022-3-1

    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            local win = v.chips - v.last_chips -- 赢利
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

            -- 盈利扣水
            if win > 0 and (self.conf.rebate or 0) > 0 then
                local rebate = math.floor(win * self.conf.rebate)
                win = win - rebate
                v.chips = v.chips - rebate
            end
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].totalpureprofit = win
            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {} --
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1 -- 增加已玩局数
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (win > 0) and 1 or 0
            self.sdata.users[v.uid].ugameinfo.texas.bestcards = v.handcards
            self.sdata.users[v.uid].ugameinfo.texas.bestcardstype = v.handtype
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips

            --[[
            -- 输家防倒币行为
            -- 1.输最多玩家输币 >= 100底注
            -- 2.输最多玩家看牌后跟注次数大于3次
            -- 3.输最多玩家主动弃牌
            -- 4.弃牌时仅两个玩家
            -- 5.有两个或两个以上真人
            if self.sdata.users[v.uid].extrainfo then
                local extrainfo =
                    cjson.decode(self.sdata.users[v.uid].extrainfo)
                if not Utils:isRobot(user.api) and extrainfo and
                    self.sdata.users[v.uid].totalpureprofit < 0 and
                    math.abs(self.sdata.users[v.uid].totalpureprofit) >= 100 *
                    self.conf.ante and v.last_active_chipintype ==
                    pb.enum_id("network.cmd.PBTeemPattiChipinType",
                               "PBTeemPattiChipinType_FOLD") and
                    not user.is_bet_timeout and (user.check_call_num or 0) >= 3 and
                    (self.round_player_num or 0) >= 2 and self.is_trigger_fold then
                    extrainfo["cheat"] = true
                    self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
                    self.has_cheat = true
                end
            end
            --]]
            table.insert(
                reviewlog.items,
                {
                    player = {uid = v.uid, username = user.username or ""},
                    sid = k,
                    handcards = g.copy(v.handcards),
                    cardtype = self.poker:getPokerTypebyCards(v.handcards),
                    win = win,
                    showcard = v.show
                }
            )
            self.reviewlogitems[v.uid] = nil
        end
    end
    log.debug(
        "idx(%s,%s,%s) review %s %s",
        self.id,
        self.mid,
        tostring(self.logid),
        cjson.encode(reviewlog),
        cjson.encode(self.reviewlogitems)
    )

    self:updatePlayChips() -- 2022-1-6 12:48:19

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

    -- 设置剩余筹码是否有效
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

    -- 赢家防倒币行为
    for _, v in ipairs(self.seats) do
        -- local user = self.users[v.uid]
        -- if user and v.isplaying then
        --     if self.has_cheat and self.sdata.users[v.uid].extrainfo and
        --         self.sdata.users[v.uid].totalpureprofit > 0 then -- 盈利玩家
        --         local extrainfo =
        --             cjson.decode(self.sdata.users[v.uid].extrainfo)
        --         if not Utils:isRobot(user.api) and extrainfo then
        --             extrainfo["cheat"] = true
        --             self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
        --         end
        --     end
        -- end
        -- 解决结算后马上离开，计算战绩多扣导致显示不正确的问题
        v.roundmoney = 0
    end

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
    self.sdata.etime = self.endtime
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
    log.debug("idx(%s,%s,%s) room:check playing size=%s", self.id, self.mid, tostring(self.logid), cnt)
    if cnt <= 1 then
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_PrechipsOver[1])
        timer.cancel(self.timer, TimerID.TimerID_StartHandCards[1])
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
    end
    timer.tick(self.timer, TimerID.TimerID_CheckRobot[1], TimerID.TimerID_CheckRobot[2], onCheckRobot, self)
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
    local send = {showType = 2, sid = rev.sid, card1 = 0, card2 = 0}
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
    log.debug("idx(%s,%s,%s) req stand up uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local s = self:getSeatByUid(uid)
    local user = self.users[uid]
    -- print(s, user)
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
                {
                    code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                }
            )
        )
    end
end

function Room:userSit(uid, linkid, rev)
    log.debug("idx(%s,%s,%s) req sit down uid:%s", self.id, self.mid, tostring(self.logid), uid)

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
                {
                    code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                }
            )
        )
    else
        -- 判断该玩家是否是机器人
        self:sit(dsts, uid, self:getRecommandBuyin(self:getUserMoney(uid), Utils:isRobot(user.api)))
    end
end

-- 参数 system: 是否是系统自动买入
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

    --if self.conf and self.conf.special and self.conf.special ~= 1 then
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
    --end

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
    log.debug("idx(%s,%s,%s) userChat:%s", self.id, self.mid, tostring(self.logid), uid)
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

    local t = {reviews = {}}
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

    -- 如果是机器人预操作
    if Utils:isRobot(user.api) then
        log.error("idx(%s,%s,%s) robot preOperate uid=%s", self.id, self.mid, tostring(self.logid), uid)
    end

    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPreOperateResp"),
        pb.encode("network.cmd.PBTexasPreOperateResp", {preop = seat:getPreOP()})
    )
end

-- 请求增加思考时间
function Room:userAddTime(uid, linkid, rev)
    log.debug("idx(%s,%s,%s) req addtime uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local function handleFailed(code)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasAddTimeResp"),
            pb.encode("network.cmd.PBTexasAddTimeResp", {idx = rev.idx, code = code or 0})
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
    -- print(seat, user, self.current_betting_pos, seat and seat.sid)
    if self.conf and self.conf.addtimecost and seat.addon_count >= #self.conf.addtimecost then
        -- 超出增加思考时间次数限制
        log.info(
            "idx(%s,%s,%s) user add time: addtime count over limit %s",
            self.id,
            self.mid,
            tostring(self.logid),
            seat.addon_count
        )
        return
    end
    -- 检测玩家身上金额是否足够
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
    -- log.info("idx(%s,%s) userTableListInfoReq:%s", self.id, self.mid, uid)
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
    -- log.info("idx(%s,%s) resp userTableListInfoReq %s", self.id, self.mid, cjson.encode(t))
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
    if rev.wintype > pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_THRREKAND") then
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
    end
    if value ~= 0 then -- 2021-9-17
        local reviewlog = self.reviewlogs:back()
        for k, v in ipairs(reviewlog.items) do
            if v.player and v.player.username == rev.nickname then
                v.win = v.win + value
            end
        end
    end
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
    -- self:sendPosInfoToAll(seat)

    if self.sdata.jp and self.sdata.jp.uid and self.sdata.jp.uid == uid and self.jackpot_and_showcard_flags then
        self.jackpot_and_showcard_flags = false
        pb.encode(
            "network.cmd.PBGameJackpotAnimation_N",
            {
                data = {
                    sid = seat.sid,
                    uid = uid,
                    delta = value,
                    wintype = seat.handtype
                }
            },
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

-- 踢出所有玩家
function Room:kickout()
    for k, v in pairs(self.users) do
        self:userLeave(k, v.linkid)
    end
end

-- 金额更新
function Room:phpMoneyUpdate(uid, rev)
    log.debug("(%s,%s,%s)phpMoneyUpdate %s", self.id, self.mid, tostring(self.logid), uid)
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

        -- 如果玩家身上金额 > 0, 且 玩家坐下，则自动买入筹码
        if self.conf and self.conf.special and self.conf.special == 1 and not Utils:isRobot(user.api) and self.conf then
            local userMoney = self:getUserMoney(uid)
            if userMoney > 0 then
                local seat = self:getSeatByUid(uid)
                if seat and (userMoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.ante) then
                    userMoney =  self.conf.maxbuyinbb * self.conf.ante - (seat.chips - seat.roundmoney)
                end

                self:userBuyin(uid, user.linkid, {buyinMoney = userMoney}, true) -- 自动买入
            end
            if
                not self.conf.roomtype or
                    self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and rev.money > 0
             then
                self:sendChargeNotifyToAll(uid, rev.money) -- 通知所有人某玩家充值了
            else
                self:sendChargeNotifyToAll(uid, rev.coin) -- 通知所有人某玩家充值了
            end
        end
    end
end

function Room:needLog()
    return self.has_player_inplay or (self.sdata and self.sdata.jp and self.sdata.jp.id)
end

-- 获取指定玩家IP
function Room:getUserIp(uid)
    local user = self.users[uid]
    if user then
        return user.ip
    end
    return ""
end

--
function Room:tools(jdata)
    log.debug("(%s,%s,%s) tools>>>>>>>> %s", self.id, self.mid, tostring(self.logid), jdata)
    local data = cjson.decode(jdata)
    if data then
        log.debug("(%s,%s,%s) handle tools %s", self.id, self.mid, tostring(self.logid), cjson.encode(data))
        if data["api"] == "kickout" then
            self.isStopping = true
        end
    end
end

--
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

-- 更新所有玩家打码量   playchips
function Room:updatePlayChips()
    local feerate = self.conf.feerate or 0
    for k, seat in ipairs(self.seats) do
        if seat and seat.uid and seat.isplaying then
            local user = self.users[seat.uid]
            if user and not Utils:isRobot(user.api) then
                local extrainfo = cjson.decode(self.sdata.users[user.uid].extrainfo)
                if feerate > 0 then
                    log.debug("updatePlayChips() uid=%s, seat.roundmoney=%s,feerate=%s",seat.uid, seat.roundmoney,feerate)
                    -- 服务费*20 + (开启底池抽水 ? 下注总量 : 0)
                    extrainfo["playchips"] = 20 * (self.conf.fee or 0) + (seat.roundmoney or 0)
                else
                    log.debug("updatePlayChips() uid=%s, feerate=%s",seat.uid, feerate)
                    extrainfo["playchips"] = 20 * (self.conf.fee or 0)
                end
                self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)
                log.debug("extrainfo=%s", self.sdata.users[user.uid].extrainfo)
            end
        end
    end
end

-- 防倒币行为  2022-3-1
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

            -- 判断输最多玩家的牌是否小于 KJ10
            local cards = {0x10D, 0x20B, 0x30A}
            if self.poker:isBankerWin(seat.handcards, cards) < 0 then
                -- 输最多玩家看牌后下注/加注总额度 >= 50底注
                if --self.sdata.users[self.maxLoserUID].totalpureprofit < 0 and
                    --math.abs(self.sdata.users[self.maxLoserUID].totalpureprofit) >= 50 * self.conf.ante
                    (seat.chips - seat.last_chips) < 0 and math.abs(seat.chips - seat.last_chips) >= 50 * self.conf.ante then
                    -- 输最多玩家看牌后下注/加注次数 >= 2
                    if (user.check_call_num or 0) >= 2 then
                        log.debug("DQW hasCheat 1")
                        hasCheat = true
                    else
                        log.debug("DQW user.check_call_num = %s", user.check_call_num or 0)
                    end
                else
                    log.debug(
                        "DQW seat.chips=%s,seat.last_chips=%s,ante=%s",
                        seat.chips,
                        seat.last_chips,
                        self.conf.ante
                    )
                end
            else
                -- 规则3:
                -- 1.输赢最多玩家均非AI
                -- 2.输最多玩家看牌后下注/盲加注总额度 >= 50底注
                -- 3.输最多玩家大于对子8
                -- 4.输最多玩家主动弃牌
                log.debug("DQW card larger KJ10")
                local cards = {0x108, 0x208, 0x10E} -- 最大的对8
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
                log.debug("DQW hasCheat 2")
            else
                if
                    seat and
                        seat.last_active_chipintype ==
                            pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_FOLD")
                 then
                    log.debug("DQW seat.last_active_chipintype = PBTeemPattiChipinType_FOLD")
                end
                log.debug("DQW seat.chips=%s,seat.last_chips=%s, ante=%s", seat.chips, seat.last_chips, self.conf.ante)
            end
        end

        if hasCheat then
            log.debug("DQW has player cheat, maxWinnerUID=%s,maxLoserUID=%s", self.maxWinnerUID, self.maxLoserUID)
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
        else
            log.debug("DQW no player cheat, maxWinnerUID=%s,maxLoserUID=%s", self.maxWinnerUID, self.maxLoserUID)
        end
    else
        log.debug(
            "DQW self.maxWinnerLoserAreAllReal = false, self.maxWinnerUID=%s,self.maxLoserUID=%s",
            self.maxWinnerUID,
            self.maxLoserUID
        )
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
            log.warn("checkWinnerAndLoserAreAllReal(),uid=%s", seat and seat.uid or 0)
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

-- 获取指定玩家已玩teenpatti局数
function Room:getPlayCount(uid)
    local user = self.users[uid]
    if user and not user.totalhands then
        if Utils:isrobot(user.api) then
            return 0
        end
    end
    return 0
end

-- 判断指定玩家是否已充值
function Room:hasDeposit(uid)
    local user = self.users[uid]
    if user then
        if user.viplv and user.viplv > 0 then
            return true
        end
    end
    return false
end

-- 随机同花顺（随机910J - QKA）
function Room:randLargeCards(leftCards)
    local cards = {}
    local randValue = rand.rand_between(1,100)
    if randValue < 1 then  -- 发豹子(3张牌值相同的牌)
        for i=1, 100 do
            local color = rand.rand_between(1, 4)
            local firstCardValue = rand.rand_between(2, 14)
            cards[1] = (color << 8) + firstCardValue  -- 第一张牌
            color = (color % 4) + 1
            cards[2] = (color << 8) + firstCardValue
            color = (color % 4) + 1
            cards[3] = (color << 8) + firstCardValue
            if self:isAllInTable(leftCards, cards) then
                return cards
            end
        end
    else
        for i = 1, 100 do
            local color = rand.rand_between(1, 4)
            local firstCardValue = rand.rand_between(9, 12)

            cards[1] = (color << 8) + firstCardValue -- color * 0x100 + firstCardValue
            cards[2] = cards[1] + 1
            cards[3] = cards[1] + 2
            if self:isAllInTable(leftCards, cards) then
                return cards
            end
        end
    end
    cards[1] = leftCards[1]
    cards[2] = leftCards[2]
    cards[3] = leftCards[3]
    return cards
end

-- 随机同花顺(随机234-8910)或者顺子
-- 参数 leftCars: 剩余的牌(确保至少有3张牌)
function Room:randSmallCards(leftCards)
    local cards = {}
    for i = 1, 100 do
        local value = rand.rand_between(1, 100)
        if value < 50 then
            -- 随机小的同花顺
            local color = rand.rand_between(1, 4) -- 第一张牌花色
            local firstCardValue = rand.rand_between(2, 8) -- 第一张牌牌值
            cards[1] = (color << 8) + firstCardValue
            cards[2] = cards[1] + 1
            cards[3] = cards[1] + 2
            log.debug(
                "randSmallCards() rand straight flush cards[1]=%s,cards[2]=%s,cards[3]=%s",
                cards[1],
                cards[2],
                cards[3]
            )
        else
            -- 随机顺子
            local color = rand.rand_between(1, 4)
            local color2 = rand.rand_between(1, 4)
            local color3 = rand.rand_between(1, 4)
            if color == color2 and color2 == color3 then
                color2 = (color + rand.rand_between(1, 3)) % 4 + 1
            end

            local firstCardValue = rand.rand_between(2, 0xC) -- 第一张牌牌值
            cards[1] = (color << 8) + firstCardValue -- 第1张牌
            cards[2] = (color2 << 8) + firstCardValue + 1 -- 第2张牌
            cards[3] = (color3 << 8) + firstCardValue + 2 -- 第3张牌
            log.debug(
                "randSmallCards() rand straight cards[1]=%s,cards[2]=%s,cards[3]=%s",
                cards[1],
                cards[2],
                cards[3]
            )
        end
        if self:isAllInTable(leftCards, cards) then
            return cards
        end
    end
    cards[1] = leftCards[1]
    cards[2] = leftCards[2]
    cards[3] = leftCards[3]
    return cards
end

-- 随机普通牌(小牌)
function Room:randNormalCards(leftCards)
    local cardsNum = #leftCards
    local cards = {}
    local times = 0
    while times < 100 do
        times = times + 1
        for i = 1, 3 do
            local randPos = rand.rand_between(1, cardsNum)
            cards[i] = leftCards[randPos]
            leftCards[randPos] = leftCards[cardsNum]
            leftCards[cardsNum] = cards[i]
            cardsNum = cardsNum - 1
        end
        -- 获取牌型
        local handtype = self.poker:getPokerTypebyCards(cards)
        if handtype <= pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_ONEPAIR") then
            break
        end
        cardsNum = #leftCards
    end
    return cards
end

-- 从指定牌堆中移除某些牌
-- 参数 cards: 从这些牌中移除指定的牌
-- 参数 removedCards: 待移除的牌
function Room:removeCards(cards, removedCards)
    local cardsNum = #cards
    local removedCardsNum = #removedCards -- 待移除的牌张数
    for i = 1, removedCardsNum do
        for j = 1, cardsNum do
            if removedCards[i] == cards[j] then
                cards[j] = cards[cardsNum]
                cards[cardsNum] = nil
                cardsNum = cardsNum - 1
                break
            end
        end
    end
    return cards -- 返回剩余的牌
end

-- 判断subt中所有元素是否都在t中
function Room:isAllInTable(t, subt)
    local tNum = #t
    local subtNum = #subt
    local inTable = false

    for i = 1, subtNum do
        inTable = false
        for j = 1, tNum do
            if subt[i] == t[j] then
                inTable = true
                break
            end
        end
        if not inTable then
            return false
        end
    end
    return true
end

-- 通知所有玩家，某玩家已充值
function Room:sendChargeNotifyToAll(uid, currentChargeMoney)
    local chargeNotify = {uid = uid, chargeMoney = currentChargeMoney}
    log.debug(
        "idx(%s,%s,%s) uid:%s,msg=%s",
        self.id,
        self.mid,
        tostring(self.logid),
        tostring(uid),
        cjson.encode(chargeNotify)
    )

    -- pb.encode(
    --     "network.cmd.PBTeemPattiNotifyCharge", -- 充值通知
    --     chargeNotify,
    --     function(pointer, length)
    --         self:sendCmdToPlayingUsers(
    --             pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    --             pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiNotifyCharge"),
    --             pointer,
    --             length
    --         )
    --     end
    -- )
    for sid, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and Utils:isRobot(user.api) and seat.isplaying then
            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiNotifyCharge"),
                pb.encode("network.cmd.PBTeemPattiNotifyCharge", {uid = uid, chargeMoney = currentChargeMoney})
            )
        end
    end
end

-- 检测当前操作者是否有足够金额跟注
function Room:checkCharge(uid)
    if self.conf and (not self.conf.special or self.conf.special ~= 1) then
        return
    end

    local seat = self:getSeatByUid(uid)
    local user = self.users[uid]
    if seat then
        if user and not Utils:isRobot(user.api) then
            log.debug("checkCharge(),uid=%s", uid)
            --seat.addon_time = 0
            --seat.total_time = self.bettingtime
            -- 需要增加条件 判断玩家身上筹码是否足够下注或跟注
            local seatMoney = (seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0 -- 身上金额
            local needcall = seat.ischeck and self.m_needcall * 2 or self.m_needcall -- 下注或跟注所需金额
            log.debug("checkCharge(),uid=%s,seatMoney=%s,needcall=%s", uid, seatMoney, needcall)
            if seatMoney < needcall then
                --seat.addon_time = 300 - self.bettingtime -- 增加充值时间(300s)
                --seat.total_time = seat:getChipinLeftTime()
                -- 检测该真实玩家的金额是否足够
                --self:sendChargeNotifyToAll(uid)

                --更新该座位的状态(下注中但缺筹码)
                seat.chiptype = pb.enum_id("network.cmd.PBTeemPattiChipinType", "PBTeemPattiChipinType_BETING_LACK")
                log.info("checkCharge(),uid=%s, PBTeemPattiChipinType_BETING_LACK", uid)
            end
        end
    end
end

-- 发特殊牌
function Room:dealSpecialCards(seatcards)
    local leftCards = {
        0x102,
        0x103,
        0x104,
        0x105,
        0x106,
        0x107,
        0x108,
        0x109,
        0x10A,
        0x10B,
        0x10C,
        0x10D,
        0x10E,
        --方块
        0x202,
        0x203,
        0x204,
        0x205,
        0x206,
        0x207,
        0x208,
        0x209,
        0x20A,
        0x20B,
        0x20C,
        0x20D,
        0x20E,
        --梅花
        0x302,
        0x303,
        0x304,
        0x305,
        0x306,
        0x307,
        0x308,
        0x309,
        0x30A,
        0x30B,
        0x30C,
        0x30D,
        0x30E,
        --红桃
        0x402,
        0x403,
        0x404,
        0x405,
        0x406,
        0x407,
        0x408,
        0x409,
        0x40A,
        0x40B,
        0x40C,
        0x40D,
        0x40E
    }

    log.info("(%s,%s,%s) dealSpecialCards()", self.id, self.mid, tostring(self.logid))

    local hasSendSmallCardsNum = 0
    local seatnum = #self.seats
    local randvalue = rand.rand_between(1, seatnum)
    for i = 1, seatnum do
        local seat = self.seats[(i + randvalue) % seatnum + 1]
        if seat and seat.uid and seat.uid > 0 and seat.isplaying then
            local sid = seat.sid
            local user = self.users[seat.uid]
            if user then -- 如果该玩家参与游戏
                local sendCards = {}
                if Utils:isRobot(user.api) then -- 如果是机器人
                    if hasSendSmallCardsNum < 2 then
                        sendCards = self:randSmallCards(leftCards) -- 发第2大牌
                        leftCards = self:removeCards(leftCards, sendCards)
                        hasSendSmallCardsNum = hasSendSmallCardsNum + 1
                    else
                        sendCards = self:randNormalCards(leftCards) --发最小的牌
                        leftCards = self:removeCards(leftCards, sendCards)
                    end
                else -- 真人
                    sendCards = self:randLargeCards(leftCards)
                    leftCards = self:removeCards(leftCards, sendCards)
                end
                seat.handcards[1] = sendCards[1]
                seat.handcards[2] = sendCards[2]
                seat.handcards[3] = sendCards[3]
                seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
                for _, dc in ipairs(seatcards) do
                    if dc.sid == sid then
                        dc.handcards[1] = seat.handcards[1]
                        dc.handcards[2] = seat.handcards[2]
                        dc.handcards[3] = seat.handcards[3]
                        break
                    end
                end
                log.debug(
                    "idx(%s,%s,%s) sid:%s,uid:%s deal handcard:%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    sid,
                    seat.uid,
                    cjson.encode(seat.handcards)
                )
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].cards =
                    self.sdata.users[seat.uid].cards or
                    {
                        seat.handcards[1],
                        seat.handcards[2],
                        seat.handcards[3]
                    }
                self.sdata.users[seat.uid].sid = sid
                self.sdata.users[seat.uid].username = user.username
                if sid == self.buttonpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
                else
                    self.sdata.users[seat.uid].role =
                        pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
                end
            end
        end
    end

    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and Utils:isRobot(user.api) and seat.isplaying then -- 给所有参与的机器人发该消息
            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiDealCardOnlyRobot"),
                pb.encode(
                    "network.cmd.PBTeemPattiDealCardOnlyRobot",
                    {cards = seatcards, isJoker = false, isSpecial = true}
                )
            )
        end
    end
end

-- 发特控制玩家输赢
-- 参数 winnerUID: 赢家UID
function Room:dealSpecialCards2(seatcards, winnerUID, loserUID)
    local leftCards = {
        0x102,
        0x103,
        0x104,
        0x105,
        0x106,
        0x107,
        0x108,
        0x109,
        0x10A,
        0x10B,
        0x10C,
        0x10D,
        0x10E,
        --方块
        0x202,
        0x203,
        0x204,
        0x205,
        0x206,
        0x207,
        0x208,
        0x209,
        0x20A,
        0x20B,
        0x20C,
        0x20D,
        0x20E,
        --梅花
        0x302,
        0x303,
        0x304,
        0x305,
        0x306,
        0x307,
        0x308,
        0x309,
        0x30A,
        0x30B,
        0x30C,
        0x30D,
        0x30E,
        --红桃
        0x402,
        0x403,
        0x404,
        0x405,
        0x406,
        0x407,
        0x408,
        0x409,
        0x40A,
        0x40B,
        0x40C,
        0x40D,
        0x40E
    }

    log.info("(%s,%s,%s) dealSpecialCards2()", self.id, self.mid, tostring(self.logid))
    local winnerSID = 0
    if winnerUID and winnerUID > 0 then
        local seat = self:getSeatByUid(winnerUID)
        if seat and seat.isplaying then
            winnerSID = seat.sid
        end
    end
    local loserSID = 0
    if loserUID and loserUID > 0 then
        local seat = self:getSeatByUid(loserUID)
        if seat and seat.isplaying then
            loserSID = seat.sid
        end
    end

    local seatnum = #self.seats
    local sendCards = {}
    local maxCardsSID = 0 -- 最大牌所在座位号
    local secondCardsSID = 0 -- 第二大牌所在座位号
    local dealBigCardsTimes = 0 -- 发大牌次数
    local randValue = rand.rand_between(0, seatnum)
    if winnerSID > 0 or loserSID > 0 then
        -- dealBigCardsTimes = 2
        dealBigCardsTimes = 3
    end
    -- 给每个玩家发牌
    for j = 1, seatnum do
        local i = (j + randValue) % seatnum + 1
        local seat = self.seats[i]
        if seat and seat.uid and seat.uid > 0 and seat.isplaying then
            if dealBigCardsTimes > 0 then
                -- sendCards = self:dealBigCards(leftCards)
                sendCards = self:randLargeCards(leftCards)  -- 发（910J - QKA 同花顺）
                dealBigCardsTimes = dealBigCardsTimes - 1
            else
                sendCards = self:randNormalCards(leftCards)
            end
            leftCards = self:removeCards(leftCards, sendCards)
            seat.handcards[1] = sendCards[1]
            seat.handcards[2] = sendCards[2]
            seat.handcards[3] = sendCards[3]
            seat.handtype = self.poker:getPokerTypebyCards(g.copy(seat.handcards))
            if maxCardsSID == 0 then
                maxCardsSID = i
            else
                if self.seats[maxCardsSID].handtype < seat.handtype then
                    secondCardsSID = maxCardsSID -- 第二大牌座位号
                    maxCardsSID = i
                elseif self.seats[maxCardsSID].handtype == seat.handtype then -- 如果牌型相同
                    if self.poker:isBankerWin(seat.handcards, self.seats[maxCardsSID].handcards) > 0 then -- 如果
                        secondCardsSID = maxCardsSID -- 第二大牌座位号
                        maxCardsSID = i
                    elseif secondCardsSID == 0 then
                        secondCardsSID = i
                    elseif self.poker:isBankerWin(seat.handcards, self.seats[secondCardsSID].handcards) > 0 then
                        secondCardsSID = i
                    end
                else
                    if secondCardsSID == 0 then
                        secondCardsSID = i
                    elseif self.poker:isBankerWin(seat.handcards, self.seats[secondCardsSID].handcards) > 0 then
                        secondCardsSID = i
                    end
                end
            end
        end
    end

    -- 判断是否需要换牌
    if winnerSID > 0 and winnerSID ~= maxCardsSID then
        self.seats[maxCardsSID].handtype, self.seats[winnerSID].handtype =
            self.seats[winnerSID].handtype,
            self.seats[maxCardsSID].handtype
        self.seats[maxCardsSID].handcards[1], self.seats[winnerSID].handcards[1] =
            self.seats[winnerSID].handcards[1],
            self.seats[maxCardsSID].handcards[1]
        self.seats[maxCardsSID].handcards[2], self.seats[winnerSID].handcards[2] =
            self.seats[winnerSID].handcards[2],
            self.seats[maxCardsSID].handcards[2]
        self.seats[maxCardsSID].handcards[3], self.seats[winnerSID].handcards[3] =
            self.seats[winnerSID].handcards[3],
            self.seats[maxCardsSID].handcards[3]
        if secondCardsSID == winnerSID then
            secondCardsSID = maxCardsSID
        end
        maxCardsSID = winnerSID
    end

    -- 换牌判断
    if loserSID > 0 and loserSID ~= secondCardsSID then -- 如果输家获取到的牌不是第二大的牌
        local sid = 0
        local randvalue = rand.rand_between(1, seatnum)
        for i = 1, seatnum do
            local seat = self.seats[(i + randvalue) % seatnum + 1]
            if seat and seat.uid and seat.uid > 0 and seat.isplaying and loserSID ~= seat.sid then
                sid = seat.sid
                break
            end
        end
        self.seats[loserSID].handtype, self.seats[secondCardsSID].handtype =
            self.seats[secondCardsSID].handtype,
            self.seats[loserSID].handtype
        self.seats[loserSID].handcards[1], self.seats[secondCardsSID].handcards[1] =
            self.seats[secondCardsSID].handcards[1],
            self.seats[loserSID].handcards[1]
        self.seats[loserSID].handcards[2], self.seats[secondCardsSID].handcards[2] =
            self.seats[secondCardsSID].handcards[2],
            self.seats[loserSID].handcards[2]
        self.seats[loserSID].handcards[3], self.seats[secondCardsSID].handcards[3] =
            self.seats[secondCardsSID].handcards[3],
            self.seats[loserSID].handcards[3]
        if maxCardsSID == loserSID then
            maxCardsSID = secondCardsSID
        end
        secondCardsSID = loserSID
    end

    for i = 1, seatnum do
        local seat = self.seats[i]
        if seat and seat.uid and seat.uid > 0 and seat.isplaying then
            local sid = seat.sid
            local user = self.users[seat.uid]
            if user then -- 如果该玩家参与游戏
                for _, dc in ipairs(seatcards) do
                    if dc.sid == sid then
                        dc.handcards[1] = seat.handcards[1]
                        dc.handcards[2] = seat.handcards[2]
                        dc.handcards[3] = seat.handcards[3]
                        break
                    end
                end
                log.debug(
                    "idx(%s,%s,%s) sid:%s,uid:%s deal handcard:%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    sid,
                    seat.uid,
                    cjson.encode(seat.handcards)
                )
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].cards =
                    self.sdata.users[seat.uid].cards or
                    {
                        seat.handcards[1],
                        seat.handcards[2],
                        seat.handcards[3]
                    }
                self.sdata.users[seat.uid].sid = sid
                self.sdata.users[seat.uid].username = user.username
                if sid == self.buttonpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
                else
                    self.sdata.users[seat.uid].role =
                        pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
                end
            end
        end
    end

    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and Utils:isRobot(user.api) and seat.isplaying then -- 给所有参与的机器人发该消息
            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TeemPattiDealCardOnlyRobot"),
                pb.encode(
                    "network.cmd.PBTeemPattiDealCardOnlyRobot",
                    {cards = seatcards, isJoker = false, isSpecial = true}
                )
            )
        end
    end
end

-- 发大牌 >=jj2   (对子<同花<顺子<同花顺)
function Room:dealBigCards(leftCards)
    local cards = {}
    local randTimes = 0 -- 已随机次数
    while (randTimes < 100) do
        randTimes = randTimes + 1
        local cardsNum = #leftCards -- 剩余牌张数

        local randPos = rand.rand_between(1, cardsNum) -- 随机第1张牌
        cards[1] = leftCards[randPos]
        leftCards[cardsNum], leftCards[randPos] = leftCards[randPos], leftCards[cardsNum]
        cardsNum = cardsNum - 1
        randPos = rand.rand_between(1, cardsNum) -- 随机第2张牌
        cards[2] = leftCards[randPos]
        leftCards[cardsNum], leftCards[randPos] = leftCards[randPos], leftCards[cardsNum]
        cardsNum = cardsNum - 1
        randPos = rand.rand_between(1, cardsNum) -- 随机第3张牌
        cards[3] = leftCards[randPos]

        -- 获取牌型
        local cardsType = self.poker:getPokerTypebyCards(cards) -- 获取牌型
        if
            cardsType > pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_ONEPAIR") and
                cardsType < pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_STRAIGHTFLUSH")
         then
            break
        end
        if
            cardsType == pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_ONEPAIR") and
                (cards[2] & 0xF) >= 0xB
         then -- 如果是对J及其之上的对子
            break
        end
    end
    log.debug(
        "idx(%s,%s,%s) dealBigCards() randTimes=%s,cards=%s",
        self.id,
        self.mid,
        tostring(self.logid),
        randTimes,
        string.format("0x%x,0x%x,0x%x", cards[1], cards[2], cards[3])
    )
    return cards
end

-- 发大牌 >=882   (对子<同花<顺子<同花顺)
function Room:dealBigCards2(leftCards)
    -- 对子85%  同花10%  顺子5%
    local needCardsType = pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_ONEPAIR") -- 对子
    local randValue = rand.rand_between(1, 100)
    local cards = {}
    local randTimes = 0 -- 已随机次数

    if randValue <= 10 then -- 10%的概率是同花
        needCardsType = pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_FLUSH") --- 同花
    elseif randValue <= 15 then -- 5%的概率是顺子
        needCardsType = pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_STRAIGHT") -- 顺子
    else -- 85%是对子
        needCardsType = pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_ONEPAIR") -- 对子
    end

    while (randTimes < 500) do
        randTimes = randTimes + 1
        local cardsNum = #leftCards -- 剩余牌张数

        local randPos = rand.rand_between(1, cardsNum) -- 随机第1张牌
        cards[1] = leftCards[randPos]
        leftCards[cardsNum], leftCards[randPos] = leftCards[randPos], leftCards[cardsNum]
        cardsNum = cardsNum - 1
        randPos = rand.rand_between(1, cardsNum) -- 随机第2张牌
        cards[2] = leftCards[randPos]
        leftCards[cardsNum], leftCards[randPos] = leftCards[randPos], leftCards[cardsNum]
        cardsNum = cardsNum - 1
        randPos = rand.rand_between(1, cardsNum) -- 随机第3张牌
        cards[3] = leftCards[randPos]

        -- 获取牌型
        local cardsType = self.poker:getPokerTypebyCards(cards) -- 获取牌型
        if cardsType == needCardsType then
            if needCardsType == pb.enum_id("network.cmd.PBTeemPattiCardWinType", "PBTeemPattiCardWinType_ONEPAIR") then
                if (cards[2] & 0xF) >= 0x8 then -- >=对8的对子
                    break
                end
            else
                break
            end
        end
    end -- while
    log.debug(
        "idx(%s,%s,%s) dealBigCards2() randTimes=%s,cards=%s",
        self.id,
        self.mid,
        tostring(self.logid),
        randTimes,
        string.format("0x%x,0x%x,0x%x", cards[1], cards[2], cards[3])
    )
    return cards
end

--[[
--------------------------
Teenpatti逻辑调整：
1.下注三轮以后才可以show/sideshow  
2.坐下后自动买入筹码为全部余额(需要确认tablelist配置recommendbuyin设置到无穷大就会自动带入全部余额)

1.桌子增加配置属性：新用户专场
2.有此配置的牌桌，每桌保持至少3个机器人
3.每桌只能进入一个真实玩家  

5.未充值玩家并且，teenpatti玩牌局数==0，控制赢的概率为100%

6.未充值玩家并且，teenpatti玩牌局数大于0小于等于5，控制赢的概率为80%

7.未充值玩家并且，玩牌局数>5, 剩余筹码小于340*ante, 80%触发特殊牌局（5分钟内只能触发一次）
 
	特殊牌局逻辑：
	1.真实玩家手牌为同花顺（随机910J - QKA）      
	2.其他两个AI随机为同花顺（随机234-8910）或者顺子  
	
	3.AI在真实玩家剩余筹码>跟注所需筹码时都进行加注
	4.轮到真实玩家操作，但是筹码不足跟注时,标记玩家为补码状态
	6.server将该玩家操作计时增加至300s
	
	5.牌桌中间显示“请等待XX补充筹码”（sideshow请求界面） 服务器通知该桌所有玩家
	6.操作按钮上方气泡提示“你的筹码不足，你有xx:xx来购买补充筹码”   服务器通知玩家 (5.6.可合成一条消息)
	
	7.玩家购买成功后（玩家为补码状态时，金币余额增加），自动将所有余额补充买入，5、6显示的界面消失

其他客户端修改 ：
1.未充值用户提现申请提交按钮点击后，所有客户端输入检查通过后判断，未充值用户弹窗提示：vip用户才可以使用该功能。弹窗点击确认后，界面自动切换到充值界面。

--]]

--[[
*. 增加桌子属性：新用户专场(>=3个机器人，<=1个真实玩家)  确保该房间有3个机器人，且不能超过1个真实玩家  
*. 根据玩家赢的概率随机玩家输赢，根据该玩家输赢情况发牌(可能需要换牌)  
*. 随机特殊牌(同花顺、顺子)  
*. 判断玩家是否已充值  
*. 判断玩家已玩teenpatti游戏局数  

*. 增加字段，通知AI真实玩家当前剩余筹码 
*. 增加机器人加注条件(真实玩家剩余筹码>跟注所需筹码时都进行加注)，计算真实玩家根据所需筹码   
*. 增加补码状态(条件判断：真实玩家+筹码不足跟注)  
*. 延长玩家操作时长(300s)，操作超时当弃牌处理  
*. 增加消息，通知所有玩家某玩家补码，延长操作时长300s(需客户端配合)  
*. 购买成功后，刷新玩家金额(若为补码状态，则直接买入)    
*. 判断玩家是否是新用户，是否进入新用户专场  ?
--]]

-- Game2UserInfoSubCmd_QueryChargeInfo
