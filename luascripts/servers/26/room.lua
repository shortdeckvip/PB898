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
require("luascripts/servers/26/seat")
require("luascripts/servers/26/reservation")
require("luascripts/servers/26/blind")

local g_stage_multi = 1000

Room = Room or {}
local default_poker_table = {
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
    0x10E, -- 方块
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
    0x20E, -- 梅花
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
    0x30E, -- 红桃
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
    -- 黑桃
}

local TimerID = {
    TimerID_Check = {1, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, -- id, interval(ms), timestamp(ms)
    TimerID_Betting = {3, 18000}, -- id, interval(ms), timestamp(ms)
    TimerID_AllinAnimation = {4, 200}, -- id, interval(ms), timestamp(ms)
    TimerID_PrechipsRoundOver = {5, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_StartPreflop = {6, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_OnFinish = {7, 1000}, -- id, interval(ms), timestamp(ms)
    TimerID_Timeout = {8, 2000}, -- id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {9, 2000}, -- id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {10, 1000},
    TimerID_Buyin = {11, 1000},
    TimerID_PreflopAnimation = {12, 1000},
    TimerID_FlopTurnRiverAnimation = {13, 1000},
    TimerID_Expense = {14, 5000},
    TimerID_Result = {17, 1200}
}

local EnumUserState = {Playing = 1, Leave = 2, Logout = 3, Intoing = 4}

local function fillSeatInfo(seat, self)
    local seatinfo = {}
    seatinfo.seat = {sid = seat.sid, playerinfo = {}}
    -- seatinfo.sid = seat.sid
    -- seatinfo.player = {}

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
    seatinfo.chipinType = seat.chiptype -- (seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_PRECHIPS")) and pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CLEAR_STATUS") or seat.chiptype
    seatinfo.chipinNum = (seat.roundmoney > seat.chipinnum) and (seat.roundmoney - seat.chipinnum) or 0

    local left_money = seat.chips
    local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0} -- 开局前maxraisepos == 0
    local needcall = maxraise_seat.roundmoney
    if
        self.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop") and
            maxraise_seat.roundmoney <= self.conf.sb * 2
     then
        needcall = self.conf.sb * 2
    else
        if maxraise_seat.roundmoney < self.conf.sb * 2 and maxraise_seat.roundmoney ~= 0 then
            needcall = (left_money > self.conf.sb * 2) and self.conf.sb * 2 or left_money
        else
            needcall = (left_money > maxraise_seat.roundmoney) and maxraise_seat.roundmoney or left_money
        end
    end
    seatinfo.needCall = needcall -- 需要加注金额

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
        seatinfo.chipinType = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BUYING")
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
    end
    if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
        seat.odds = seatinfo.onePot == 0 and 0 or (seatinfo.needCall - seatinfo.chipinMoney) / seatinfo.onePot
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
        local bbseat = self.seats[self.current_betting_pos]
        local nextseat = self:getNextActionPosition(bbseat)
        self:betting(nextseat)
    end
    g.call(doRun)
end

local function onFlopTurnRiverAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onFlopAnimation", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
        local buttonseat = self.seats[self.buttonpos]
        local nextseat = self:getNextActionPosition(buttonseat)
        self:betting(nextseat)
    end
    g.call(doRun)
end

-- allin动画结束
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

-- 定时检测(定时器回调函数)
local function onCheck(self)
    local function doRun()
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
        for k, v in pairs(self.seats) do -- 遍历所有座位
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
                            {
                                sid = v.sid, -- 座位号
                                chips = v.chips, -- 该座位筹码
                                money = self:getUserMoney(v.uid), -- 玩家身上金额
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
                            v:setIsBuyining(true)
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

        if self:getPlayingSize() <= 1 then
            return
        end
        if self:getPlayingSize() > 1 and global.ctsec() > self.endtime then -- + self:nextRoundInterval() then
            timer.cancel(self.timer, TimerID.TimerID_Check[1])
            self:start()
        end
    end
    g.call(doRun)
end

local function onFinish(self)
    self:checkLeave()
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
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 定时检测
    end
    g.call(doRun)
end

-- 开始下盲注(小盲、大盲)
local function onStartPreflop(self)
    local function doRun()
        log.info(
            "idx(%s,%s) onStartPreflop bb:%s sb:%s bb_pos:%s sb_pos:%s button_pos:%s",
            self.id,
            self.mid,
            self.conf.sb * 2,
            self.conf.sb,
            self.bbpos,
            self.sbpos,
            self.buttonpos
        )
        timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])

        self.current_betting_pos = self.sbpos -- 小盲位置玩家下注
        self:chipin(
            self.seats[self.current_betting_pos].uid,
            pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_SMALLBLIND"), -- 下小盲
            self.conf.sb
        )
        self.current_betting_pos = self.bbpos -- 大盲位置玩家下注
        self:chipin(
            self.seats[self.current_betting_pos].uid,
            pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BIGBLIND"), -- 下大盲
            self.conf.sb * 2
        )

        ---- 防逃盲
        -- self:dealAntiEscapeBB()

        self:getNextState()
    end
    g.call(doRun)
end

-- 预操作(交前注)结束
local function onPrechipsRoundOver(self)
    local function doRun()
        log.info("idx(%s,%s) onPrechipsRoundOver", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1]) -- 关闭定时器
        self:roundOver()

        timer.tick(self.timer, TimerID.TimerID_StartPreflop[1], TimerID.TimerID_StartPreflop[2], onStartPreflop, self)
    end
    g.call(doRun)
end

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
    texas.destroy(self.pokerhands)
    for _, v in ipairs(self.seats) do
        v.rv:destroy()
    end
end

-- 获取一张牌
function Room:getOneCard()
    self.pokeridx = self.pokeridx + 1
    return self.cards[self.pokeridx]
end

-- 获取剩余的牌
function Room:getLeftCard()
    local t = {}
    local cfgidx = 1
    for i = self.pokeridx + 1, #self.cards do
        local card = self.cards[i]
        if self.cfgcard_switch and cfgidx <= 5 then
            card = self.cfgcard:getOne(cfgidx)
            cfgidx = cfgidx + 1
        end
        table.insert(t, card)
    end
    return t
end

function Room:init()
    log.info("idx(%s,%s) room init", self.id, self.mid)
    self.conf = MatchMgr:getConfByMid(self.mid)
    self.users = {}
    self.timer = timer.create()
    self.pokeridx = 0
    self.cards = {}
    for _, v in ipairs(default_poker_table) do
        table.insert(self.cards, v)
    end

    self.pokerhands = texas.create()
    self.gameId = 0

    self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None") -- 牌局状态(preflop, flop, turn...)
    self.buttonpos = -1
    self.sbpos = -1
    self.bbpos = -1
    self.straddlepos = -1
    self.ante = 0
    self.minchip = 1
    self.tabletype = self.conf.matchtype
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000
    self.bettingtime = self.conf.bettime
    self.boardcards = {0, 0, 0, 0, 0}
    self.nextboardcards = {0, 0, 0, 0, 0}
    self.roundcount = 0
    self.potidx = 1
    self.current_betting_pos = 0
    self.chipinpos = 0
    self.already_show_card = false
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.card_stage = 0
    self.seats_totalbets = {}
    self.invalid_pot_sid = 0

    self.pots = {} -- 奖池
    self.seats = {} -- 座位
    for sid = 1, self.conf.maxuser do
        local s = Seat:new(self, sid)
        table.insert(self.seats, s)
        table.insert(self.pots, {money = 0, seats = {}})
    end

    self.blind = Blind:new({id = self.mid}) -- 涨盲生成器
    self.smallblind = self.conf and self.conf.sb or 50
    self.bigblind = self.conf and self.conf.sb * 2 or 100
    self.ante = self.conf and self.conf.ante or 0

    -- self.boardlog = BoardLog.new() -- 牌局记录器
    self.statistic = Statistic:new(self.id, self.conf.mid)
    self.sdata = {
        -- moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }

    -- self.round_finish_time = 0      -- 每一轮结束时间  (preflop - flop - ...)
    self.starttime = 0 -- 牌局开始时间
    self.endtime = 0 -- 牌局结束时间

    self.table_match_start_time = 0 -- 开赛时间
    self.table_match_end_time = 0 -- 比赛结束时间

    self.chipinset = {}
    self.last_playing_users = {} -- 上一局参与的玩家列表

    self.finishstate = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None")

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
                0x408,
                0x405,
                0x30b,
                0x30c,
                0x208,
                0x40a,
                0x40d,
                0x302,
                0x109,
                0x402,
                0x20A,
                0x20B,
                0x308,
                0x209,
                0x20C,
                0x20D
            },
            boardcards = {0x30d, 0x30a, 0x30e, 0x109, 0x203}
        }
    )
    -- 主动亮牌
    self.req_show_dealcard = false -- 客户端请求过主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_NULL")
    self.lastchipinpos = 0

    self.tableStartCount = 0
    self.logid = self.statistic:genLogId()
    self.hasFind = false
    self.maxWinnerUID = 0
    self.maxLoserUID = 0

    self.commonCards = {} -- 5张公共牌
    self.seatCards = {} -- 各座位的手牌(每人2张)
    self.seatCardsType = {} -- 各座位最大牌牌型
    self.maxCardsIndex = 0 -- 最大牌所在位置
    self.minCardsIndex = 0 -- 最小牌所在位置
    self.isControl = false
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
    -- log.debug("idx:%s,%s is not cached", self.id,self.mid)
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

function Room:queryUserResult(ok, ud)
    if self.timer then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.debug("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
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
            self.state >= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"), 0)
                self:stand(
                    self.seats[s.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
            else
                if s.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") then
                    s:chipin(pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"), s.roundmoney)
                -- self:sendPosInfoToAll(s, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"))
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
                    self.finishstate = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")
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
                log.info("idx(%s,%s) %s %s %s", self.id, self.mid, j, seat.roundmoney, maxraise_seat.roundmoney)
                if seat and seat.isplaying and seat.roundmoney > maxraise_seat.roundmoney then
                    maxraise_seat = seat
                end
            end
            self.maxraisepos = maxraise_seat.sid
        end
        log.info("idx(%s,%s) maxraisepos %s", self.id, self.mid, self.maxraisepos)
    end

    user.roundmoney = user.roundmoney or 0
    self.pots[self.potidx].money = self.pots[self.potidx].money + user.roundmoney
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
        log.info("idx(%s,%s) money change uid:%s val:%s", self.id, self.mid, uid, val)
    end

    -- 战绩
    if user.gamecount and user.gamecount > 0 then
        Statistic:appendRoomLogs(
            {
                uid = uid,
                time = global.ctsec(),
                roomtype = self.conf.roomtype,
                gameid = global.stype(),
                serverid = global.sid(),
                roomid = self.id,
                smallblind = self.conf.sb,
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

--
local function onResultTimeout(arg)
    arg[1]:queryUserResult(false, nil)
end

-- 扣钱
local function onExpenseTimeout(arg)
    timer.cancel(arg[2].timer, TimerID.TimerID_Expense[1])
    local user = arg[2].users[arg[1]]
    if user and user.expense then
        coroutine.resume(user.expense, false)
    end
    return false
end

function Room:getRecommandBuyin(balance)
    local referrer = self.conf.sb * self.conf.referrerbb
    if referrer > balance then
        referrer = balance
    elseif referrer < self.conf.sb * self.conf.minbuyinbb then
        referrer = self.conf.sb * self.conf.minbuyinbb
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

    -- seat info
    user.chips = user.chips or 0
    user.currentbuyin = user.currentbuyin or 0
    user.roundmoney = user.roundmoney or 0
        
    -- 从坐下到站起期间总买入和总输赢
    user.totalwin = user.totalwin or 0

    -- 座位互斥
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
                -- Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
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

                    log.info(
                        "idx(%s,%s) into room money:%s,%s,%s,%s",
                        self.id,
                        self.mid,
                        uid,
                        self:getUserMoney(uid),
                        self.conf.minbuyinbb,
                        self.conf.sb * 2
                    )

                    -- 防止协程返回时，玩家实质上已离线
                    if ok and user.state ~= EnumUserState.Intoing then
                        ok = false
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                        log.info("idx(%s,%s) user %s logout or leave", self.id, self.mid, uid)
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

                    if not ok then
                        if self.users[uid] ~= nil then
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
                            timer.destroy(user.TimerID_MutexTo)
                            timer.destroy(user.TimerID_Timeout)
                            timer.destroy(user.TimerID_Expense)
                            self.users[uid] = nil
                        end
                        log.info(
                            "idx(%s,%s) not enough money:%s,%s,%s",
                            self.id,
                            self.mid,
                            uid,
                            self:getUserMoney(uid),
                            t.code
                        )
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
    self.boardcards = {0, 0, 0, 0, 0}
    self.nextboardcards = {0, 0, 0, 0, 0}
    self.pokeridx = 0

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
        -- moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}
    -- self.boardlog:reset()
    self.finishstate = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None")

    self.req_show_dealcard = false
    self.lastchipintype = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_NULL")
    self.lastchipinpos = 0
    self.card_stage = 0
    self.has_cheat = false
    self.invalid_pot = 0
    self.potrates = {}
    self.seats_totalbets = {}
    self.invalid_pot_sid = 0
    self.hasFind = false
    self.isControl = false
end

-- 获取无效的下注池?
function Room:getInvalidPot()
    local invalid_pot = 0
    local tmp = {}
    for k, v in ipairs(self.seats) do
        if v.roundmoney > 0 then
            table.insert(tmp, {k, v.roundmoney})
        end
    end
    if #tmp >= 1 then
        table.sort(
            tmp,
            function(a, b)
                return a[2] > b[2]
            end
        )
        self.invalid_pot_sid = tmp[1][1]
        invalid_pot = tmp[1][2] - (tmp[2] and tmp[2][2] or 0)
    end
    log.info("idx(%s,%s) getInvalidPot:%s,%s", self.id, self.mid, cjson.encode(tmp), invalid_pot)

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
                -- self.pots[i].money = self.pots[i].money - potrake
                hand_total_rake = hand_total_rake + potrake
            end
        end
        log.info("idx(%s,%s) after potRake:%s,%s", self.id, self.mid, cjson.encode(self.pots), hand_total_rake)
    end
end

function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s) user table info req uid:%s %s %s", self.id, self.mid, uid, self.conf.sb, self.conf.sb * 2)
    local tableinfo = {
        gameId = self.gameId,
        seatCount = self.conf.maxuser,
        smallBlind = self.conf.sb,
        bigBlind = self.conf.sb * 2,
        tableName = self.conf.name,
        gameState = self.state,
        buttonSid = self.buttonpos,
        smallBlindSid = self.sbpos,
        bigBlindSid = self.bbpos,
        roundNum = self.roundcount,
        ante = self.ante,
        bettingtime = self.bettingtime,
        matchType = self.conf.matchtype,
        roomType = self.conf.roomtype,
        addtimeCost = self.conf.addtimecost,
        peekWinnerCardsCost = self.conf.peekwinnerhandcardcost,
        peekPubCardsCost = self.conf.peekpubcardcost,
        toolCost = self.conf.toolcost,
        jpid = self.conf.jpid or 0,
        jp = JackpotMgr:getJackpotById(self.conf.jpid),
        jp_ratios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or {0, 0, 0}),
        middlebuyin = self.conf.referrerbb * self.conf.sb
    }

    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        tableinfo.minbuyinbb = self.conf.minbuyinbb
        tableinfo.maxbuyinbb = self.conf.maxbuyinbb
    end

    tableinfo.publicCards = {}
    for i = 1, #self.boardcards do
        table.insert(tableinfo.publicCards, self.boardcards[i])
    end

    -- print('userTableInfo', cjson.encode(tableinfo))
    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
end

function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid then
            local seatinfo = fillSeatInfo(seat, self)
            if seat.uid == uid then
                seatinfo.card1 = seat.handcards[1]
                seatinfo.card2 = seat.handcards[2]
            else
                seatinfo.card1 = (seat.handcards[1] ~= 0) and 0 or -1 -- -1 无手手牌，0 牌背
                seatinfo.card2 = (seat.handcards[2] ~= 0) and 0 or -1
            end

            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end

    tableinfo.publicPools = {}
    for i = 1, self.potidx do
        if self.state ~= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None") then
            table.insert(tableinfo.publicPools, self.pots[i].money)
        end
    end

    local resp = pb.encode("network.cmd.PBTexasTableInfoResp", {tableInfo = tableinfo})
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasTableInfoResp"),
        resp
    )
end

-- 判断指定玩家是否坐下
function Room:inTable(uid)
    for i = 1, #self.seats do
        if self.seats[i].uid == uid then
            return true
        end
    end
    return false
end

-- 获取指定玩家所在座位
function Room:getSeatByUid(uid)
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid == uid then
            return seat
        end
    end
    return nil
end

-- 获取一个奖池
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

function Room:distance(seat_a, seat_b)
    local dis = 0
    for i = seat_a.sid, seat_b.sid - 1 + #self.seats do
        dis = dis + 1
    end
    return dis % #self.seats
end

-- 获取坐下的玩家数
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
        if self.seats[i].uid and not self.seats[i].isbuyining and not self.seats[i].rv:isReservation() then
            count = count + 1
        end
    end
    return count
end

function Room:getCurrentBoardSitSize()
    local count = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid and not seat.rv:isReservation() and seat.isplaying then
            count = count + 1
        end
    end

    return count
end

-- 获取参与游戏的玩家数
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

-- 获取下一个未弃牌位置(pos之后的位置)
function Room:getNextNoFlodPosition(pos)
    for i = pos + 1, pos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat.isplaying and seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
            return seat
        end
    end
    return nil
end

function Room:getNextActionPosition(seat)
    log.info("idx(%s,%s) getNextActionPosition sid:%s,%s", self.id, self.mid, seat.sid, tostring(self.maxraisepos))
    local pos = seat.sid
    for i = pos + 1, pos + #self.seats - 1 do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if
            seat and seat.isplaying and
                seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") and
                seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")
         then
            seat.addon_count = 0
            return seat
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
                seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")
         then
            nfold = nfold + 1
        end
    end
    return nfold
end

-- 获取allin玩家数
function Room:getAllinSize()
    local allin = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying and seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") then
            allin = allin + 1
        end
    end
    return allin
end

-- 设置show牌
function Room:setShowCard(pos, riverraise, poss)
    local seat = self.seats[pos]
    if
        seat and seat.isplaying and
            seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
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
    local sitsize = self:getSitSize()
    if sitsize <= 1 then
        log.info("idx(%s,%s) move button failed less than one player", self.id, self.mid)
        return false
    end

    local playersize = 0
    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        playersize = self:getNonRsrvSitSize()
    else
        playersize = self:getSitSize()
    end

    if self.bbpos == -1 then -- 如果大盲还未确定
        -- 如果是刚进来，2人情况下，随机大小盲, 小盲和庄同一人
        if playersize == 2 then
            local pos = {}
            for i = 1, #self.seats do
                local seat = self.seats[i]
                if seat.uid ~= nil then
                    if
                        (self:isRegularMatch() and not seat.isbuyining and not seat.rv:isReservation()) or
                            not self:isRegularMatch()
                     then
                        pos[#pos + 1] = i
                    end
                end
            end
            local rand = rand.rand_between(0, 1)
            if rand == 1 then
                self.bbpos = pos[2] -- 大盲位置
                self.sbpos = pos[1]
                self.buttonpos = pos[1]
                self.chipinpos = pos[2]
            else
                self.bbpos = pos[1]
                self.sbpos = pos[2]
                self.buttonpos = pos[2]
                self.chipinpos = pos[1]
            end
        else
            -- 3人或以上情况下，大盲，小盲，庄，分别为不同人
            local c = 0
            for i = 1, #self.seats do
                local seat = self.seats[i]
                if seat.uid ~= nil then
                    if
                        (self:isRegularMatch() and not seat.isbuyining and not seat.rv:isReservation()) or
                            not self:isRegularMatch()
                     then
                        c = c + 1
                        if c == 1 then
                            self.buttonpos = i
                        elseif c == 2 then
                            self.sbpos = i
                        else
                            self.bbpos = i
                            self.chipinpos = i
                            break
                        end
                    end
                end
            end
        end
    else
        -- 之前已经有牌局了，大小盲，庄，轮着来(大盲先走，小盲和庄跟着大盲走)
        for i = self.bbpos + 1, self.bbpos - 1 + #self.seats do
            local j = i % #self.seats > 0 and i % #self.seats or #self.seats
            if self.seats[j].uid then
                local iscontinue = false
                -- 普通场玩法留座不参与牌局
                if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
                    -- 大盲略过留座
                    if self.seats[j].rv:isReservation() then
                        self.seats[j].rv:chipinTimeoutRound()
                        if self.seats[j].rv:isStandup() then
                            self:stand(self.seats[j], self.seats[j].uid)
                        end
                        iscontinue = true
                        self.seats[j].escape_bb_count = self.seats[j].escape_bb_count + 1
                    end
                    if self.seats[j].isbuyining then
                        iscontinue = true
                    end
                end

                if not iscontinue then
                    local last_bbpos = self.bbpos -- 大盲位置
                    self.bbpos = j
                    self.chipinpos = j
                    self.sbpos = self:getSB(last_bbpos)
                    self.buttonpos = self:getButton()
                    break
                end
            end
        end
    end

    local last_playersize = 0
    for k, v in pairs(self.last_playing_users) do
        last_playersize = last_playersize + 1
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        -- local sit_size = self:getSitSize()
        if seat.uid ~= nil and self.tableStartCount > 1 then
            -- 刚坐下 ，且坐在小盲或庄位，要等下一局才能玩
            if not seat.isplaying and (i == self.sbpos or i == self.buttonpos) and last_playersize > 3 then
                seat.isdelayplay = true
            else
                seat.isdelayplay = false
            end
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

function Room:getSB(last_bbpos)
    -- >2情况， 小盲等于上局大盲
    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        if self:getNonRsrvSitSize() > 2 then
            return last_bbpos
        end
    else
        if self:getSitSize() > 2 then
            return last_bbpos
        end
    end
    -- 这时候bbpos已经是新一局的bbpos，小盲就是新一局大盲后面第一个有人的位置
    local pos
    local i = (self.bbpos - 1 + #self.seats) % #self.seats
    repeat
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]

        -- 普通场/自建普通场留座离桌不交大小盲
        local flag = true
        if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
            if seat.rv:getReservation() == pb.enum_id("network.cmd.PBTexasLeaveToSitResult", "PBLeaveToSitResultSucc") then
                flag = false
            end
            if seat.isbuyining then
                flag = false
            end
        end

        if seat.uid and flag then
            pos = seat.sid
            break
        end
        i = i - 1
    until (i == (self.bbpos % #self.seats))

    return pos == nil and 0 or pos
end

function Room:getButton()
    -- 只有2人，庄和小盲同一人
    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        if self:getNonRsrvSitSize() == 2 then
            return self.sbpos
        end
    else
        if self:getSitSize() == 2 then
            return self.sbpos
        end
    end
    if self.sbpos == 0 then
        return 0
    end
    local pos
    local i = (self.sbpos - 1 + #self.seats) % #self.seats
    repeat
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]

        -- 普通场/自建普通场留座离桌做庄
        local flag = true
        if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
            if seat.rv:getReservation() == pb.enum_id("network.cmd.PBTexasLeaveToSitResult", "PBLeaveToSitResultSucc") then
                flag = false
            end
            if seat.isbuyining then
                flag = false
            end
        end

        -- 有人或者这个人上一局刚站起，这一局空庄
        if (seat.uid ~= nil or (seat.uid == nil and seat.isplaying == true)) and flag then
            pos = seat.sid
            break
        end
        i = i - 1
    until (i == self.sbpos % #self.seats)
    return pos == nil and 0 or pos
end

function Room:getGameId()
    return self.gameId + 1
end

-- 玩家站起
function Room:stand(seat, uid, stype)
    log.info("idx(%s,%s) stand uid,sid:%s,%s,%s", self.id, self.mid, uid, seat.sid, tostring(stype))
    local user = self.users[uid]
    if seat and user then
        if
            self.state >= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") and
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

            -- 输家防倒币行为
            if self.sdata.users[uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
                if
                    not Utils:isRobot(user.api) and extrainfo and
                        self.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop") and -- 翻牌前
                        math.abs(self.sdata.users[uid].totalpureprofit) >= 20 * self.conf.sb * 2 and
                        seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
                        not user.is_bet_timeout and
                        (seat.odds or 1) < 0.25
                 then
                    extrainfo["cheat"] = true
                    extrainfo["totalmoney"] = (self:getUserMoney(uid) or 0) + (seat.chips - seat.roundmoney)  -- 玩家身上总金额
                    self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
                    self.has_cheat = true
                end
            end
            -- 实时牌局
            self.reviewlogitems[seat.uid] =
                self.reviewlogitems[seat.uid] or
                {
                    player = {uid = seat.uid, username = user.username or ""},
                    handcards = {
                        sid = seat.sid,
                        card1 = seat.handcards[1],
                        card2 = seat.handcards[2]
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

-- 玩家坐下
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
                        code = pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney")
                    }
                )
            )
            return
        end
        -- 机器人只有在有空余1个座位以上才能坐下
        local empty = self.conf.maxuser - self:count()
        if Utils:isRobot(user.api) and empty <= 1 then
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
        seat:sit(uid, user.chips, 0, 0, user.totalbuyin)
        local clientBuyin =
            (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante + self.conf.fee or 0))
        if clientBuyin then
            -- 进入房间自动买入流程
            if (0x4 == (self.conf.buyin & 0x4) or Utils:isRobot(user.api)) and user.chips == 0 and user.totalbuyin == 0 then
                clientBuyin = false
                if not self:userBuyin(uid, user.linkid, {buyinMoney = buyinmoney}, true) then
                    seat:stand(uid)
                    return
                end
            else -- 手动点击坐下买入流程
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
            -- 客户端超时站起
            seat.chips = user.chips
            user.chips = 0
        end
        log.info("idx(%s,%s) uid %s sid %s sit clientBuyin %s", self.id, self.mid, uid, seat.sid, tostring(clientBuyin))
        local seatinfo = fillSeatInfo(seat, self)
        pb.encode(
            "network.cmd.PBTexasPlayerSit",
            {
                seatInfo = seatinfo,
                clientBuyin = clientBuyin,
                buyinTime = self.conf.buyintime
            },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerSit"),
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
            "network.cmd.PBTexasUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasUpdateSeat"),
                    pointer,
                    length
                )
            end
        )
    end
end

function Room:start()
    self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Start")
    self:reset()
    self.pokeridx = 0
    for i = 1, #default_poker_table - 1 do -- 洗牌
        local s = rand.rand_between(i, #default_poker_table)
        self.cards[i], self.cards[s] = self.cards[s], self.cards[i]
    end

    self.gameId = self:getGameId()
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec()
    self.logid = self.has_started and self.statistic:genLogId(self.starttime) or self.logid
    self.has_started = self.has_started or true

    self.smallblind = self.conf and self.conf.sb or 50
    self.bigblind = self.conf and self.conf.sb * 2 or 100
    self.ante = self.conf and self.conf.ante or 0
    self.minchip = self.conf and self.conf.minchip or 1
    self.has_player_inplay = false

    -- 玩家状态，金币数等数据初始化
    self:reset()
    self:moveButton()

    self.maxraisepos = self.bbpos -- 大盲位置
    self.maxraisepos_real = self.maxraisepos
    self.current_betting_pos = self.maxraisepos
    log.info(
        "idx(%s,%s) start robotcnt:%s bb:%s ante:%s minchip:%s gameId:%s betpos:%s logid:%s",
        self.id,
        self.mid,
        self:robotCount(),
        self.conf.sb * 2,
        self.ante,
        self.minchip,
        self.gameId,
        self.current_betting_pos,
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
                    roundid = user.roundId,
                    playchips = 20 * (self.conf.fee or 0) -- 2021-12-24
                }
            )
            if k == self.sbpos then
                self.sdata.users[v.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_SB")
            elseif k == self.bbpos then
                self.sdata.users[v.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_BB")
            elseif k == self.buttonpos then
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
        smallBlindSid = self.sbpos,
        bigBlindSid = self.bbpos,
        smallBlind = self.conf.sb,
        bigBlind = self.conf.sb * 2,
        ante = self.ante,
        minChip = self.minchip,
        table_starttime = self.starttime,
        seats = fillSeats(self)
    }
    pb.encode(
        "network.cmd.PBTexasGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasGameStart"),
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
    self.sdata.gameinfo.texas.sb = self.conf.sb
    self.sdata.gameinfo.texas.bb = self.conf.sb * 2
    self.sdata.gameinfo.texas.maxplayers = self.conf.maxuser
    self.sdata.gameinfo.texas.curplayers = curplayers
    self.sdata.gameinfo.texas.ante = self.conf.ante
    self.sdata.jp = {minichips = self.minchip}
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

    -- 前注，大小盲处理
    self:dealPreChips()
end

function Room:checkCanChipin(seat)
    return seat and seat.uid and seat.sid == self.current_betting_pos and seat.isplaying
end

-- 玩家操作
function Room:chipin(uid, type, money)
    local seat = self:getSeatByUid(uid)
    if not self:checkCanChipin(seat) then
        return false
    end

    if not seat then
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

    local old_roundmoney = seat.roundmoney

    local function fold_func(seat, type, money)
        seat:chipin(type, seat.roundmoney)
        seat.rv:checkSitResultSuccInTime()
    end

    local function call_check_raise_allin_func(seat, type, money)
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
        if type == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK") and money == 0 then
            if seat.roundmoney >= maxraise_seat.roundmoney then
                type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK")
                money = seat.roundmoney
            else
                type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")
            end
        elseif type == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") and money < seat.chips then
            money = seat.chips
        elseif type == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_RAISE") and money == seat.chips then
            type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN")
        elseif money < seat.chips and money < maxraise_seat.roundmoney then
            -- money = 0
            type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")
        else
            if money < seat.roundmoney then
                if type == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK") and money == 0 then
                    type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK")
                else
                    type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")
                    money = 0
                end
            elseif money > seat.roundmoney then
                if money == maxraise_seat.roundmoney then
                    type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CALL")
                else
                    type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_RAISE")
                end
            else
                type = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK")
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
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")] = fold_func,
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CALL")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_RAISE")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN")] = call_check_raise_allin_func,
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_SMALLBLIND")] = smallblind_func,
        [pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BIGBLIND")] = bigblind_func
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, uid, type)
        return false
    end

    -- 真正操作chipin
    chipin_func(seat, type, money)

    local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
    if seat.roundmoney > maxraise_seat.roundmoney then
        self.maxraisepos = seat.sid -- 更新最大加注位置
        if (self.seats[seat.sid].roundmoney >= self:minraise()) then
            self.maxraisepos_real = seat.sid
        end
    end

    if
        self.maxraisepos == seat.sid and
            (seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_RAISE") or
                seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN"))
     then
        self.seats[self.maxraisepos].reraise = true
    end

    self.chipinpos = seat.sid
    self:sendPosInfoToAll(seat)

    if
        type ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
            type ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_SMALLBLIND") and
            money > 0
     then
        self.chipinset[#self.chipinset + 1] = money
    end

    -- GameLog
    -- self.boardlog:appendChipin(self, seat)

    return true
end

-- 玩家操作
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
        self.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None") or
            self.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")
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
        self.finishstate = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")
        timer.cancel(self.timer, TimerID.TimerID_Start[1])
        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_AllinAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
        timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])
        timer.cancel(self.timer, TimerID.TimerID_PreflopAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_FlopTurnRiverAnimation[1])
        onPotAnimation(self)
        -- timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
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

    if next_seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BIGBLIND") then
        if next_seat.sid == self.maxraisepos and self:isAllAllin() then
            timer.tick(
                self.timer,
                TimerID.TimerID_AllinAnimation[1],
                TimerID.TimerID_AllinAnimation[2],
                onAllinAnimation,
                self
            )
            return true
        end

        self.seats[self.bbpos].bigblind_betting = true
        self:betting(next_seat)
        self.seats[self.bbpos].bigblind_betting = false
        return true
    end

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
            -- log.debug("maxraise_seat.reraise ... ")
            timer.tick(
                self.timer,
                TimerID.TimerID_AllinAnimation[1],
                TimerID.TimerID_AllinAnimation[2],
                onAllinAnimation,
                self
            )
        else
            -- log.debug("maxraise_seat.reraise betting...")
            self:betting(next_seat)
        end
    else
        log.info("idx(%s,%s) isReraise %s", self.id, self.mid, self.maxraisepos)
        local chipin_seat = self.seats[self.chipinpos]
        local chipin_seat_chiptype = chipin_seat.chiptype
        if
            self:isAllCheck() or self:isAllAllin() or
                (self.maxraisepos == self.chipinpos and
                    (pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK") == chipin_seat_chiptype or
                        pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") == chipin_seat_chiptype))
         then
            -- log.debug("onAllinAnimation")
            -- self.round_finish_time = global.ctms()
            timer.tick(
                self.timer,
                TimerID.TimerID_AllinAnimation[1],
                TimerID.TimerID_AllinAnimation[2],
                onAllinAnimation,
                self
            )
        else
            -- log.debug("onAllinAnimation betting")
            self:betting(next_seat)
        end
    end
    return true
end

-- 进入下一个状态
function Room:getNextState()
    local oldstate = self.state

    if oldstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreChips") then
        self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop")
        -- self:dealPreFlop() -- 发手牌(每人2张)
        self:dealPreFlopNew()
    elseif oldstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop") then
        self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Flop")
        self:dealFlop() -- 发前3张公共牌(发牌)
    elseif oldstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Flop") then
        self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Turn")
        self:dealTurn() -- 发倒数第二张公共牌(发牌)
    elseif oldstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Turn") then
        self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_River")
        self:dealRiver() -- 发最后一张公共牌(发牌)
    elseif oldstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_River") then
        self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")
    elseif oldstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") then
        self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None")
    end

    log.info("idx(%s,%s) State Change: %s => %s", self.id, self.mid, oldstate, self.state)
end

-- 前注，大小盲处理
function Room:dealPreChips()
    log.info("idx(%s,%s) dealPreChips ante:%s", self.id, self.mid, self.ante)
    self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreChips")
    if self.ante > 0 then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            if seat.isplaying then -- 如果该座位玩家参与游戏
                -- seat的chipin, 不是self的chipin
                seat:chipin(pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_PRECHIPS"), self.ante) -- 交前注
                self:sendPosInfoToAll(seat)
            end
        end
        -- GameLog
        -- self.boardlog:appendPreChips(self)

        timer.tick(
            self.timer,
            TimerID.TimerID_PrechipsRoundOver[1],
            TimerID.TimerID_PrechipsRoundOver[2],
            onPrechipsRoundOver,
            self
        )
    else
        onStartPreflop(self)
    end
end

-- 发手牌(每人2张)
function Room:dealPreFlopNew()
    local robotlist = {} -- 机器人列表
    local hasplayer = false -- 是否有真实玩家参与游戏
    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and seat.isplaying then
            if Utils:isRobot(user.api) then
                table.insert(robotlist, seat.uid)
            else
                hasplayer = true
            end
        end
    end
    if self.conf and self.conf.single_profit_switch and self.has_player_inplay then -- 如果单人控制 且 有真实玩家参与游戏
        self.result_co =
            coroutine.create(
            function()
                local msg = {ctx = 0, matchid = self.mid, roomid = self.id, data = {}, ispvp = true}
                for _, seat in ipairs(self.seats) do
                    local v = self.users[seat.uid]
                    if v and not Utils:isRobot(v.api) and seat.isplaying then -- 如果是参与游戏的真实玩家
                        table.insert(msg.data, {uid = seat.uid, chips = 0, betchips = 0})
                    end
                end
                log.info("idx(%s,%s) start result request %s", self.id, self.mid, cjson.encode(msg))
                Utils:queryProfitResult(msg) -- 获取盈利控制结果
                local ok, res = coroutine.yield() -- 等待查询结果
                local winlist, loselist = {}, {} -- 赢家列表，输家列表
                if ok and res then
                    for _, v in ipairs(res) do -- 遍历结果
                        local uid, r, maxwin = v.uid, v.res, v.maxwin
                        if self.sdata.users[uid] and self.sdata.users[uid].extrainfo then
                            local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
                            if extrainfo then
                                extrainfo["maxwin"] = r * maxwin
                                self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
                            end
                        end
                        log.info("idx(%s,%s) finish result %s,%s", self.id, self.mid, uid, r)
                        if r > 0 then -- 玩家赢
                            table.insert(winlist, uid)
                            self.isControl = true
                        elseif r < 0 then -- 玩家输
                            table.insert(loselist, uid)
                            self.isControl = true
                        end
                    end
                end
                log.info(
                    "idx(%s,%s) ok %s winlist=%s,loselist=%s,robotlist=%s,res=%s",
                    self.id,
                    self.mid,
                    tostring(ok),
                    cjson.encode(winlist),
                    cjson.encode(loselist),
                    cjson.encode(robotlist),
                    cjson.encode(res)
                )
                -- local winner, loser
                -- if #winlist > 0 then
                --     winner = self:getSeatByUid(winlist[rand.rand_between(1, #winlist)])
                -- end
                -- if #loselist > 0 then
                --     loser = self:getSeatByUid(loselist[rand.rand_between(1, #loselist)])
                -- end
                -- if not winner and loser and #robotlist > 0 then
                --     winner = self:getSeatByUid(table.remove(robotlist))
                -- elseif winner and not loser and #robotlist > 0 then
                --     loser = self:getSeatByUid(table.remove(robotlist))
                -- end
                local winnerUID, loserUID = 0, 0
                if #winlist > 0 then
                    winnerUID = winlist[rand.rand_between(1, #winlist)]
                end
                if #loselist > 0 then
                    loserUID = loselist[rand.rand_between(1, #loselist)]
                end
                log.debug("dealPreFlopNew(),winnerUID=%s,loserUID=%s", winnerUID, loserUID)
                self:dealCards(winnerUID, loserUID) -- 发牌
                self:dealPreFlop()
            end
        )
        timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, {self})
        coroutine.resume(self.result_co)
    else
        self:dealCards(0, 0) -- 发牌
        self:dealPreFlop()
    end
end

-- 翻牌前?
function Room:dealPreFlop()
    local dealcard = {}
    for _, seat in ipairs(self.seats) do
        table.insert(dealcard, {sid = seat.sid, card1 = 0, card2 = 0})
    end

    -- 旁观广播牌背
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and (not self:getSeatByUid(k) or not self:getSeatByUid(k).isplaying) then
            net.send(
                v.linkid,
                k,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasDealCard"),
                pb.encode("network.cmd.PBTexasDealCard", {cards = dealcard})
            )
        end
    end

    local seatcards = g.copy(dealcard)
    for k, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user then
            if seat.isplaying then
                if self.cfgcard_switch then -- 配牌
                    seat.handcards[1] = self.cfgcard:popHand()
                    seat.handcards[2] = self.cfgcard:popHand()
                else
                    -- seat.handcards[1] = self:getOneCard()
                    -- seat.handcards[2] = self:getOneCard()
                    seat.handcards[1] = self.seatCards[seat.sid][1] -- 发手牌
                    seat.handcards[2] = self.seatCards[seat.sid][2]
                end

                local tmp = g.copy(dealcard)
                for i, dc in ipairs(tmp) do
                    if dc.sid == k then
                        dc.card1 = seat.handcards[1]
                        dc.card2 = seat.handcards[2]
                    end
                end

                for _, dc in ipairs(seatcards) do
                    if dc.sid == k then
                        dc.card1 = seat.handcards[1]
                        dc.card2 = seat.handcards[2]
                        break
                    end
                end

                net.send(
                    user.linkid,
                    seat.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasDealCard"),
                    pb.encode("network.cmd.PBTexasDealCard", {cards = tmp})
                )
                log.info(
                    "idx(%s,%s) deal preflop uid:%s handcard:%s",
                    self.id,
                    self.mid,
                    seat.uid,
                    string.format("0x%x,0x%x", seat.handcards[1], seat.handcards[2])
                )

                -- 统计数据
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].cards =
                    self.sdata.users[seat.uid].cards or {seat.handcards[1], seat.handcards[2]}
                self.sdata.users[seat.uid].sid = k
                self.sdata.users[seat.uid].username = user.username
                if k == self.sbpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_SB")
                elseif k == self.bbpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_BB")
                elseif k == self.buttonpos then
                    self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
                else
                    self.sdata.users[seat.uid].role =
                        pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
                end
            end
        end
    end


    --local leftcards = self:getLeftCard()
    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and Utils:isRobot(user.api) and seat.isplaying then
            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasDealCardOnlyRobot"),
                pb.encode("network.cmd.PBTexasDealCardOnlyRobot", {cards = seatcards, leftcards = self.commonCards, isControl = self.isControl})
            )
        end
    end

    log.debug("idx(%s,%s,%s) dealPreFlop() seatcards=%s,commonCards=%s",self.id, self.mid, self.logid, cjson.encode(seatcards), cjson.encode(self.commonCards))

    -- GameLog
    -- self.boardlog:appendPreFlop(self)

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

-- 发前3张公共牌
function Room:dealFlop()
    if self.cfgcard_switch then -- 配牌
        self.boardcards[1] = self.cfgcard:popBoard() -- 公共牌
        self.boardcards[2] = self.cfgcard:popBoard()
        self.boardcards[3] = self.cfgcard:popBoard()
    else
        -- self.boardcards[1] = self:getOneCard()
        -- self.boardcards[2] = self:getOneCard()
        -- self.boardcards[3] = self:getOneCard()

        self.boardcards[1] = self.commonCards[1]
        self.boardcards[2] = self.commonCards[2]
        self.boardcards[3] = self.commonCards[3]
    end

    -- 记录公共牌
    self.sdata.cards = self.sdata.cards or {}
    table.insert(
        self.sdata.cards,
        {
            cards = {self.boardcards[1], self.boardcards[2], self.boardcards[3]}
        }
    )

    log.info(
        "idx(%s,%s) deal flop card:%s",
        self.id,
        self.mid,
        string.format("0x%x,0x%x,0x%x", self.boardcards[1], self.boardcards[2], self.boardcards[3])
    )

    -- 牌型提示
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and v.isplaying then
            texas.initialize(self.pokerhands)
            texas.sethands(self.pokerhands, v.handcards[1], v.handcards[2], self.boardcards)
            local bestcards = texas.checkhandstype(self.pokerhands)
            local bestcardstype = texas.gethandstype(self.pokerhands)
            log.info(
                "idx(%s,%s):%s %s %s",
                self.id,
                self.mid,
                k,
                string.format("0x%x, 0x%x", v.handcards[1], v.handcards[2]),
                bestcardstype
            )
            net.send(
                user.linkid,
                v.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNotifyBestHand"),
                pb.encode(
                    "network.cmd.PBTexasNotifyBestHand_N",
                    {
                        bestcards = bestcards,
                        bestcardstype = bestcardstype
                    }
                )
            )
        end
    end

    local dealflopcards = {
        cards = {self.boardcards[1], self.boardcards[2], self.boardcards[3]},
        state = 1,
        delay = 0
    }
    if self:isAllAllin() then
        self.card_stage = self.card_stage + 1
        dealflopcards.delay = g_stage_multi * self.card_stage
    end
    pb.encode(
        "network.cmd.PBTexasDealPublicCards",
        dealflopcards,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasDealPublicCards"),
                pointer,
                length
            )
        end
    )

    -- m_seats.dealFlop start
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.chipinset[#self.chipinset + 1] = 0

    -- GameLog
    -- self.boardlog:appendFlop(self)

    if self:isAllAllin() then
        self:getNextState()
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

-- 发第4张公共牌(倒数第2张公共牌)
function Room:dealTurn()
    if self.cfgcard_switch then
        self.boardcards[4] = self.cfgcard:popBoard()
    else
        --self.boardcards[4] = self:getOneCard()
        self.boardcards[4] = self.commonCards[4]
    end

    -- 记录公共牌
    self.sdata.cards = self.sdata.cards or {}
    table.insert(self.sdata.cards, {cards = {self.boardcards[4]}})

    log.info("idx(%s,%s) deal turn card:%s", self.id, self.mid, string.format("0x%x", self.boardcards[4]))

    -- 牌型提示
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and v.isplaying then
            texas.initialize(self.pokerhands)
            texas.sethands(self.pokerhands, v.handcards[1], v.handcards[2], self.boardcards)
            local bestcards = texas.checkhandstype(self.pokerhands)
            local bestcardstype = texas.gethandstype(self.pokerhands)
            log.info(
                "idx(%s,%s):%s %s %s",
                self.id,
                self.mid,
                k,
                string.format("0x%x, 0x%x", v.handcards[1], v.handcards[2]),
                bestcardstype
            )
            net.send(
                user.linkid,
                v.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNotifyBestHand"),
                pb.encode(
                    "network.cmd.PBTexasNotifyBestHand_N",
                    {
                        bestcards = bestcards,
                        bestcardstype = bestcardstype
                    }
                )
            )
        end
    end

    local dealturncard = {cards = {self.boardcards[4]}, state = 2, delay = 0}
    if self:isAllAllin() then
        self.card_stage = self.card_stage + 1
        dealturncard.delay = g_stage_multi * self.card_stage
    end
    pb.encode(
        "network.cmd.PBTexasDealPublicCards",
        dealturncard,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasDealPublicCards"),
                pointer,
                length
            )
        end
    )

    -- m_seats.dealTurn start
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.chipinset[#self.chipinset + 1] = 0

    -- GameLog
    -- self.boardlog:appendTurn(self)

    if self:isAllAllin() then
        self:getNextState()
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

-- 发最后一张公共牌(河牌)
function Room:dealRiver()
    if self.cfgcard_switch then
        self.boardcards[5] = self.cfgcard:popBoard()
    else
        --self.boardcards[5] = self:getOneCard()
        self.boardcards[5] = self.commonCards[5]
    end

    -- 记录公共牌
    self.sdata.cards = self.sdata.cards or {}
    table.insert(self.sdata.cards, {cards = {self.boardcards[5]}})

    log.info("idx(%s,%s) deal river card:%s", self.id, self.mid, string.format("0x%x", self.boardcards[5]))

    local dealrivercard = {cards = {self.boardcards[5]}, state = 3, delay = 0}
    if self:isAllAllin() then
        self.card_stage = self.card_stage + 1
        dealrivercard.delay = g_stage_multi * self.card_stage
    end
    pb.encode(
        "network.cmd.PBTexasDealPublicCards",
        dealrivercard,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasDealPublicCards"),
                pointer,
                length
            )
        end
    )

    -- 牌型提示
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and v.isplaying then
            texas.initialize(self.pokerhands)
            texas.sethands(self.pokerhands, v.handcards[1], v.handcards[2], self.boardcards)
            local bestcards = texas.checkhandstype(self.pokerhands)
            local bestcardstype = texas.gethandstype(self.pokerhands)
            log.info(
                "idx(%s,%s):%s %s %s",
                self.id,
                self.mid,
                k,
                string.format("0x%x, 0x%x", v.handcards[1], v.handcards[2]),
                bestcardstype
            )
            net.send(
                user.linkid,
                v.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNotifyBestHand"),
                pb.encode(
                    "network.cmd.PBTexasNotifyBestHand_N",
                    {
                        bestcards = bestcards,
                        bestcardstype = bestcardstype
                    }
                )
            )
        end
    end

    -- m_seats.dealRiver start
    self.maxraisepos = 0
    self.maxraisepos_real = 0
    self.chipinset[#self.chipinset + 1] = 0

    -- GameLog
    -- self.boardlog:appendRiver(self)

    if self:isAllAllin() then
        self:getNextState()
        self:finish()
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

-- 是否所有玩家都allin
function Room:isAllAllin()
    local allin = 0 -- allin玩家数
    local playing = 0 -- 未弃牌玩家数(包括allin玩家)
    local pos = 0 -- 未弃牌未allin的玩家所在位置
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then -- 如果未弃牌
                playing = playing + 1
                if seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") then -- allin
                    allin = allin + 1
                else
                    pos = i
                end
            end
        end
    end

    -- log.debug("Room:isAllAllin %s,%s playing:%s allin:%s self.maxraisepos:%s pos:%s", self.id,self.mid,playing, allin, self.maxraisepos, pos)

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
    -- log.debug("Room:isAllCall %s,%s ...", self.id,self.mid)
    local maxraise_seat = self.seats[self.maxraisepos]
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            -- log.debug("Room:isAllCall chiptype:%s roundmoney:%s max_roundmoney:%s", seat.chiptype, seat.roundmoney, maxraise_seat.roundmoney)
            if
                seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CALL") and
                    seat.roundmoney < maxraise_seat.roundmoney
             then
                return false
            end

            if
                seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CALL") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN")
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
            if seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
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

function Room:getNonFoldSeats()
    local nonfoldseats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
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
                seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN")
             then
                return false
            end
        end
    end
    return true
end

function Room:minraise()
    local current_betting_seat = self.seats[self.current_betting_pos]
    if self.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop") then
        if #self.chipinset == 1 then
            if current_betting_seat and current_betting_seat.chips < 2 * self.conf.sb * 2 then
                return current_betting_seat.chips
            end
            return 2 * self.conf.sb * 2
        else
            local maxdiff, maxchipin, flag = self:getMaxDiff()
            if not flag and maxdiff < self.conf.sb * 2 then
                maxdiff = self.conf.sb * 2
            end
            if maxdiff + maxchipin < 2 * self.conf.sb * 2 then
                if current_betting_seat and current_betting_seat.chips < 2 * self.conf.sb * 2 then
                    return current_betting_seat.chips
                end
                return 2 * self.conf.sb * 2
            end
            return maxdiff + maxchipin
        end
    elseif
        self.state > pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop") and
            self.state < pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")
     then
        if #self.chipinset == 1 then
            if current_betting_seat and current_betting_seat.chips < self.conf.sb * 2 then
                return current_betting_seat.chips
            end
            return self.conf.sb * 2
        else
            local maxdiff, maxchipin, flag = self:getMaxDiff()
            if not flag and maxdiff < self.conf.sb * 2 then
                maxdiff = self.conf.sb * 2
            end
            if maxdiff + maxchipin < self.conf.sb * 2 then
                if current_betting_seat and current_betting_seat.chips < self.conf.sb * 2 then
                    return current_betting_seat.chips
                end
                return self.conf.sb * 2
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
        if self.chipinset[i - 1] >= self.conf.sb * 2 then
            flag = false
        end
        i = i + 1
    end

    maxchipin = math.max(maxchipin, self.chipinset[#self.chipinset])
    if self.chipinset[#self.chipinset] >= self.conf.sb * 2 then
        flag = false
    end

    -- log.debug("max diff %s, chipin %s, flag %s", maxdiff, maxchipin, flag and 1 or 0)
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
            if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
                playing = playing + 1
                if seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") then
                    allin = allin + 1
                end
            end
        end
    end

    local minraise_ = self:minraise()
    if playing == allin + 1 then
        local maxraise_seat = self.seats[self.maxraise_seat] and self.seats[self.maxraise_seat] or {chips = 0}
        if maxraise_seat.chips < seat.chips then
            -- return self:minraise()
            return minraise_
        end
    end
    -- return seat.chips

    if (self.maxraisepos == self.maxraisepos_real) then
        return seat.chips
    end
    -- 出现无效加注情况
    if self.seats[self.maxraisepos_real] and seat.roundmoney <= self.seats[self.maxraisepos_real].roundmoney then
        -- if (seat.roundmoney < self.seats[self.maxraisepos_real].roundmoney) then
        -- 出现无效加注后没行动过的玩家，可以加注
        return seat.chips
    end
    -- 出现无效加注前行动过的玩家，只能call or fold
    -- 如果出现无效加注后 再有玩家加注， m_maxraisepos_real == m_maxraisepos
    return minraise_
end

-- 下注定时器
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
                user.is_bet_timeout = true
                user.bet_timeout_count = user.bet_timeout_count or 0
                user.bet_timeout_count = user.bet_timeout_count + 1
            end
            -- self:userchipin(current_betting_seat.uid, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"), 0)
            self:userchipin(
                current_betting_seat.uid,
                pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK"),
                current_betting_seat.roundmoney
            )
        end
    end
    g.call(doRun)
end

-- 该座位玩家下注
function Room:betting(seat)
    if not seat then
        return false
    end
    seat.bettingtime = global.ctsec()
    self.current_betting_pos = seat.sid
    log.info("idx(%s,%s) it's betting pos:%s uid:%s", self.id, self.mid, self.current_betting_pos, tostring(seat.uid))

    local function notifyBetting()
        -- print('notifyBetting')
        -- 统计
        -- seat.si.totaljudgecount = seat.si.totaljudgecount + 1
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BETING")) -- 下注中
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self)
    end

    -- 预操作
    local preop = seat:getPreOP()
    -- print('preop', seat.roundmoney)
    if preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None") then
        notifyBetting()
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_CheckOrFold") then
        self:userchipin(
            seat.uid,
            pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK"),
            seat.roundmoney
        )
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_AutoCheck") then
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or {roundmoney = 0}
        if seat.roundmoney < maxraise_seat.roundmoney then
            notifyBetting()
        else
            self:userchipin(seat.uid, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK"), 0)
        end
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny") then
    end
end

-- 一轮结束
function Room:onRoundOver()
    log.info("idx(%s,%s) onRoundOver", self.id, self.mid)
    self:roundOver()
    if 4 == self.roundcount then
        log.info("idx(%s,%s) onRoundOver finish", self.id, self.mid)
        self.finishstate = self.state
        self:finish()
    else
        if self:isAllAllin() then
            self.finishstate = self.state
        end
        self:getNextState()
    end
end

function Room:broadcastShowCardToAll()
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying and seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
            if seat.show then
                local showdealcard = {
                    showType = 1,
                    sid = i,
                    card1 = seat.handcards[1],
                    card2 = seat.handcards[2]
                }
                pb.encode(
                    "network.cmd.PBTexasShowDealCard",
                    showdealcard,
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasShowDealCard"),
                            pointer,
                            length
                        )
                    end
                )
            end
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
        self.lastchipintype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
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
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_REBUYING") and
                    seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD")
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
                pb.encode("network.cmd.PBTexasCanShowDealCard", send)
            )
        end
    end
end

function Room:finish()
    log.info("idx(%s,%s) finish potidx:%s", self.id, self.mid, self.potidx)
    if self.boardcards[1] > 0 then
        log.info(
            "idx(%s,%s) boardcards:%s",
            self.id,
            self.mid,
            string.format(
                "0x%x,0x%x,0x%x,0x%x,0x%x",
                self.boardcards[1],
                self.boardcards[2],
                self.boardcards[3],
                self.boardcards[4],
                self.boardcards[5]
            )
        )
    end

    for _, v in pairs(self.users) do
        if v and not Utils:isRobot(v.api) and not self.has_player_inplay then
            self.has_player_inplay = true
            break
        end
    end

    -- local t_msec = (6 + self:getPotCount() * 3) * 1000

    local laststate = self.state
    self.state = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")

    -- m_seats.finish start
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    --[[ 计算在玩玩家最佳牌形和最佳手牌，用于后续比较 --]]
    self.sdata.jp.uid = nil
    for i = 1, #self.seats do
        local seat = self.seats[i]

        seat.rv:checkSitResultSuccInTime()

        if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and seat.isplaying then
            texas.initialize(self.pokerhands)
            texas.sethands(self.pokerhands, seat.handcards[1], seat.handcards[2], self.boardcards)
            seat.besthand = texas.checkhandstype(self.pokerhands) -- 选出最优的牌
            seat.handtype = texas.gethandstype(self.pokerhands)
            -- seat.si.WTSD = "YES"
            --[[增加JackPot触发判定--]]
            if
                ((seat.handtype == pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_FOURKAND") and
                    ((seat.handcards[1] & 0xFF) == seat.handcards[2] & 0xFF)) or
                    seat.handtype == pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_STRAIGHTFLUSH") or
                    seat.handtype == pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_ROYALFLUS"))
             then
                if
                    JACKPOT_CONF[self.conf.jpid] and g.find(seat.besthand, seat.handcards[1]) ~= -1 and
                        g.find(seat.besthand, seat.handcards[2]) ~= -1
                 then
                    if not self.sdata.jp.uid or self.sdata.winpokertype < seat.handtype then -- 2021-10-29
                        self.sdata.jp.uid = seat.uid
                        self.sdata.jp.username = self.users[seat.uid] and self.users[seat.uid].username or ""
                        local jp_percent_size = #JACKPOT_CONF[self.conf.jpid].percent
                        self.sdata.jp.delta_sub =
                            JACKPOT_CONF[self.conf.jpid].percent[(seat.handtype % jp_percent_size) + 1]
                        self.sdata.winpokertype = seat.handtype
                    end
                end
            end
        end
    end

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
            -- print('i', i, 'pots[i].money', self.pots[i].money)
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
            if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and seat.isplaying then
                -- i号奖池，j号玩家是有份参与的
                if self.pots[i].seats[j] then
                    if #winnerlist == 0 then
                        table.insert(winnerlist, {sid = j, winmoney = 0})
                    end
                    -- 不和自己比较
                    if winnerlist[#winnerlist] and winnerlist[#winnerlist].sid ~= j then
                        local tmp_wi = winnerlist[#winnerlist]
                        local winner_seat = self.seats[tmp_wi.sid]
                        local result =
                            texas.comphandstype(
                            self.pokerhands,
                            seat.handtype, -- 牌型
                            seat.besthand, -- 最好的5张牌
                            winner_seat.handtype,
                            winner_seat.besthand
                        )

                        -- comphandstype(A.handtype, A.besthand, B.handtype, B.besthand)
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
                    for k = 1, #self.seats[wi.sid].besthand do
                        -- potinfo.mark = self.seats[wi.sid].besthand[k]
                        table.insert(potinfo.mark, self.seats[wi.sid].besthand[k])
                    end
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

    -- JackPot抽水
    if JACKPOT_CONF[self.conf.jpid] then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            local win = seat.chips - seat.last_chips
            local delta_add = JACKPOT_CONF[self.conf.jpid].deltabb * self.conf.sb * 2
            if
                seat.isplaying and win > JACKPOT_CONF[self.conf.jpid].profitbb * self.conf.sb * 2 and
                    self.sdata.users[seat.uid].extrainfo
             then
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
        if v.isplaying and v.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
            self:setShowCard(v.sid, 4 == self.roundcount, poss)
        end
        if v.show then
            showcard_players = showcard_players + 1
        end
    end

    self:broadcastShowCardToAll()
    -- self:broadcastCanShowCardToAll(poss)

    local t_msec = showcard_players * 200 + (self:getPotCount() * 200 + 4000) + g_stage_multi * self.card_stage

    -- jackpot 中奖需要额外增加下局开始时间
    if self.sdata.jp.uid and showcard_players > 0 then
        t_msec = t_msec + 5000
        self.jackpot_and_showcard_flags = true
    end

    -- 广播结算
    log.info("idx(%s,%s) PBTexasFinalGame %s", self.id, self.mid, cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBTexasFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasFinalGame"),
                pointer,
                length
            )
        end
    )

    self.endtime = global.ctsec()
    -- self.round_finish_time = 0

    -- 强制亮牌
    local nonfoldseats = self:getNonFoldSeats()
    if #nonfoldseats == 1 and self:isAllFold() then
        for k, v in ipairs(self.seats) do
            if v and nonfoldseats[1] and v.sid ~= nonfoldseats[1].sid and v.isplaying then
                log.info("idx(%s,%s) force show card notify uid %s sid %s", self.id, self.mid, tostring(v.uid), v.sid)
                local user = self.users[v.uid]
                if user then
                    net.send(
                        user.linkid,
                        v.uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNotifyEnforceShowCardBt"),
                        pb.encode("network.cmd.PBTexasNotifyEnforceShowCardBt", {countdown = t_msec / 1000 - 1})
                    )
                end
            end
        end
    end

    -- 下一张牌
    for k, v in ipairs(self.boardcards) do
        if v == 0 then
            if k <= 3 then
                self.nextboardcards[1] = self:getOneCard()
                self.nextboardcards[2] = self:getOneCard()
                self.nextboardcards[3] = self:getOneCard()
                self.nextboardcards[4] = self:getOneCard()
                self.nextboardcards[5] = self:getOneCard()
            elseif k <= 4 then
                self.nextboardcards[4] = self:getOneCard()
                self.nextboardcards[5] = self:getOneCard()
            elseif k <= 5 then
                self.nextboardcards[5] = self:getOneCard()
            end
            for k, v in ipairs(self.seats) do
                if v and v.isplaying then
                    log.info("idx(%s,%s) next card notify uid %s sid %s", self.id, self.mid, tostring(v.uid), v.sid)
                    local user = self.users[v.uid]
                    if user then
                        net.send(
                            user.linkid,
                            v.uid,
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNotifyNextRoundPubCardBt"),
                            pb.encode("network.cmd.PBTexasNotifyNextRoundPubCardBt", {countdown = t_msec / 1000 - 1})
                        )
                    end
                end
            end
            break
        end
    end

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

            local win = v.chips - v.last_chips -- 赢利
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
            self.sdata.users[v.uid].ugameinfo.texas.bestcards = v.besthand
            self.sdata.users[v.uid].ugameinfo.texas.bestcardstype = v.handtype
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips
            -- 输家防倒币行为
            if self:checkWinnerAndLoserAreAllReal() and v.uid == self.maxLoserUID and self.sdata.users[v.uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[v.uid].extrainfo)
                if not Utils:isRobot(user.api) and extrainfo then -- 如果不是机器人
                    local ischeat = false
                    if
                        laststate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop") and -- 翻牌前
                            self.sdata.users[v.uid].totalpureprofit < 0 and -- 该玩家输
                            math.abs(self.sdata.users[v.uid].totalpureprofit) >= 20 * self.conf.sb * 2 and
                            v.lastchiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and -- 主动弃牌
                            not user.is_bet_timeout and
                            (v.odds or 1) < 0.25
                     then -- 需要跟注筹码 < 1/4底池
                        log.debug("cheat first condition,uid=%s", v.uid)
                        ischeat = true
                    elseif
                        laststate >= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Flop") and -- 翻牌后
                            self.sdata.users[v.uid].totalpureprofit < 0 and -- 该玩家输
                            math.abs(self.sdata.users[v.uid].totalpureprofit) >= 20 * self.conf.sb * 2 and -- 玩家输币 >= Poker 20 bb/6+ 50ante
                            v.lastchiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and -- 主动弃牌
                            -- v.handtype >= pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_ONEPAIR") and -- 牌型在对子或对子以上主动弃牌
                            self:checkCheat2(v) and
                            (v.odds or 1) < 0.25
                     then -- 需要跟注筹码 < 1/4底池
                        log.debug("cheat second condition,uid=%s", v.uid)
                        ischeat = true
                    elseif
                        laststate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_River") and -- 河牌
                            self.sdata.users[v.uid].totalpureprofit < 0 and -- 该玩家输
                            math.abs(self.sdata.users[v.uid].totalpureprofit) >= 20 * self.conf.sb * 2 and -- 输最多玩家输币 >= Poker 20 bb/6+ 50ante
                            v.lastchiptype >= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CALL") and
                            self:checkCheat(v)
                     then -- 是否满足规则3条件
                        log.debug("cheat third condition,uid=%s", v.uid)
                        ischeat = true
                    end
                    if ischeat then
                        extrainfo["cheat"] = true
                        self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
                        self.has_cheat = true
                        log.debug("cheat losser uid=%s", v.uid)
                    else
                        log.debug(
                            "not cheat uid=%s,laststate=%s,totalpureprofit=%s,sb=%s,lastchiptype=%s,handtype=%s,odds=%s",
                            v.uid,
                            laststate,
                            tostring(self.sdata.users[v.uid].totalpureprofit),
                            tostring(self.conf.sb),
                            tostring(v.lastchiptype),
                            tostring(v.handtype),
                            tostring(v.odds)
                        )
                    end
                end
            end
        end
    end

    -- 赢家防倒币行为
    for _, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            if
                self.has_cheat and self.maxWinerUID == v.uid and self.sdata.users[v.uid].totalpureprofit > 0 and
                    self.sdata.users[v.uid].extrainfo
             then -- 盈利玩家
                local extrainfo = cjson.decode(self.sdata.users[v.uid].extrainfo)
                if not Utils:isRobot(user.api) and extrainfo then
                    extrainfo["cheat"] = true -- 作弊
                    self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
                    log.debug("cheat winner uid=%s", v.uid)
                end
            end
        end
    end

    self.sdata.etime = self.endtime

    -- 实时牌局
    local reviewlog = {
        buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0,
        sbuid = self.seats[self.sbpos] and self.seats[self.sbpos].uid or 0,
        bbuid = self.seats[self.bbpos] and self.seats[self.bbpos].uid or 0,
        pot = 0,
        pubcards = {
            self.boardcards[1],
            self.boardcards[2],
            self.boardcards[3],
            self.boardcards[4],
            self.boardcards[5]
        },
        items = {}
    }
    for _, pot in ipairs(self.pots) do
        reviewlog.pot = reviewlog.pot + pot.money
    end
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            reviewlog.pot = reviewlog.pot
            table.insert(
                reviewlog.items,
                {
                    player = {uid = v.uid, username = user.username or ""},
                    handcards = {
                        sid = v.sid,
                        card1 = v.handcards[1],
                        card2 = v.handcards[2]
                    },
                    bestcards = v.besthand,
                    bestcardstype = v.handtype,
                    win = v.chips - v.last_chips,
                    showhandcard = v.show,
                    efshowhandcarduid = {},
                    usershowhandcard = {0, 0},
                    roundchipintypes = v.roundchipintypes,
                    roundchipinmoneys = v.roundchipinmoneys
                }
            )
            self.reviewlogitems[v.uid] = nil
        end
    end
    for _, v in pairs(self.reviewlogitems) do
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

    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and seat.isplaying then
            if not Utils:isRobot(user.api) and self.sdata.users[seat.uid].extrainfo then -- 盈利玩家
                local extrainfo = cjson.decode(self.sdata.users[seat.uid].extrainfo)
                if  extrainfo then
                    extrainfo["totalmoney"] = (self:getUserMoney(seat.uid) or 0) + seat.chips -- 总金额                    
                    log.debug("self.sdata.users[uid].extrainfo uid=%s,totalmoney=%s", seat.uid, extrainfo["totalmoney"])
                    self.sdata.users[seat.uid].extrainfo = cjson.encode(extrainfo)
                end
            end
        end
    end


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

-- 一轮结束
function Room:roundOver()
    local isallfold = self:isAllFold()
    local isallallin = self:isAllAllin()
    local allin = {}
    local allinset = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        -- if seat.isplaying and seat.roundmoney > 0 then
        if seat.roundmoney > 0 then
            seat.money = seat.money + seat.roundmoney
            seat.chips = seat.chips > seat.roundmoney and seat.chips - seat.roundmoney or 0

            if seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
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
                seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") and
                    seat.roundmoney == 0
             then
                if self.pots[self.potidx].seats[i] ~= nil then
                    self.potidx = self.potidx + 1
                    break
                end
            end
        end
    end

    if self.conf.matchtype ~= pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        -- 普通场能随便站起，（修复2个人，preflop，大盲站起，导致m_pots少了的bug）
        for i = 1, #allin do
            for j = 1, #self.seats do
                local seat = self.seats[j]
                -- if seat.isplaying then
                if seat.roundmoney > 0 then
                    if i == 1 then
                        if seat.sid == self.bbpos then
                            local money = allin[i] < seat.roundmoney and seat.roundmoney or allin[i]
                            self.pots[self.potidx].money = self.pots[self.potidx].money + money
                        else
                            -- 你的下注大于别人allin， 或者别人allin 大于你的下注
                            local money = allin[i] > seat.roundmoney and seat.roundmoney or allin[i]
                            self.pots[self.potidx].money = self.pots[self.potidx].money + money
                        end
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
                -- end
            end

            -- GameLog
            -- self.boardlog:appendRoundOver(self, self.potidx, self.pots[self.potidx].money)

            self.potidx = self.potidx + 1
        end
    else
        for i = 1, #allin do
            for j = 1, #self.seats do
                local seat = self.seats[j]
                -- if seat.isplaying then
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
                -- end
            end

            -- GameLog
            -- self.boardlog:appendRoundOver(self, self.potidx, self.pots[self.potidx].money)

            self.potidx = self.potidx + 1
        end
    end

    if isallfold or isallallin then
        self.invalid_pot = self:getInvalidPot()
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        -- if seat.isplaying then
        seat.total_bets = (seat.total_bets or 0) + seat.roundmoney
        seat.roundmoney = 0
        seat.chipinnum = 0
        seat.reraise = false
        if
            seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
                seat.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN")
         then
            seat.chiptype = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_NULL")
        end
        seat:setPreOP(pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None"))
        -- end
    end

    if #allin > 0 and self.potidx > 1 then
        self.potidx = self.potidx - 1
    end

    if self.state > pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreChips") then
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

function Room:nextRoundInterval()
    local preflop_time = 1.2
    local flop_time = 1.2
    local turn_time = 0.9
    local river_time = 0.9
    local chips2pots_time = 2.5
    local show_card_time = 1.5

    local tm = 0.0
    local finishstate = self.finishstate
    if
        finishstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None") or
            finishstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Start") or
            finishstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop")
     then
        tm = tm + flop_time + turn_time + river_time
    elseif finishstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Flop") then
        tm = tm + turn_time + river_time
    elseif finishstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Turn") then
        tm = tm + river_time
    -- elseif finishstate == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_River") then
    -- tm = tm + river_time
    end

    tm = tm + self:getPotCount() * chips2pots_time
    tm = tm + show_card_time
    if self.req_show_dealcard then
        tm = tm + show_card_time
    end

    if self:getPotCount() > 1 then
        tm = tm + 1.5
    end
    log.info(
        "idx(%s,%s) nextRoundInterval tm:%s %f, finishstate:%s potCount:%s",
        self.id,
        self.mid,
        math.floor(tm + 0.5),
        tm + 0.5,
        finishstate,
        self:getPotCount()
    )
    return math.floor(tm + 0.5) -- 四舍五入
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
end

function Room:userShowCard(uid, linkid, rev)
    log.info(
        "idx(%s,%s) req show deal card uid:%s sid:%s card1:%s card2:%s",
        self.id,
        self.mid,
        uid,
        tostring(rev.sid),
        tostring(rev.card1),
        tostring(rev.card2)
    )
    -- 下一局开始了，屏蔽主动亮牌
    if self.state ~= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") then
        log.info("idx(%s,%s) user show card: state not valid", self.id, self.mid)
        return
    end
    local seat = self.seats[rev.sid]
    if not seat then
        log.info("idx(%s,%s) user show card: seat not valid", self.id, self.mid)
        return
    end
    if seat.uid ~= uid then
        log.info("idx(%s,%s) user show card: seat uid and req uid not match", self.id, self.mid)
        return
    end
    if seat.show then
        log.info("idx(%s,%s) user show card: system already show", self.id, self.mid)
        return
    end
    if not rev.card1 and not rev.card2 then
        log.info("idx(%s,%s) user show card: no card recevie valid", self.id, self.mid)
        return
    end
    if rev.card1 and rev.card1 ~= 0 and not g.isInTable(seat.handcards, rev.card1) then
        log.info("idx(%s,%s) user show card: client req wrong card", self.id, self.mid)
        return
    end
    if rev.card2 and rev.card2 ~= 0 and not g.isInTable(seat.handcards, rev.card2) then
        log.info("idx(%s,%s) user show card: client req wrong card", self.id, self.mid)
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
        "network.cmd.PBTexasShowDealCard",
        send,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasShowDealCard"),
                pointer,
                length
            )
        end
    )
end

function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s) req stand up uid:%s", self.id, self.mid, uid)

    local s = self:getSeatByUid(uid)
    local user = self.users[uid]
    -- print(s, user)
    if s and user then
        if
            s.isplaying and self.state >= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") and
                self:getPlayingSize() > 1
         then
            if s.sid == self.current_betting_pos then
                self:userchipin(uid, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"), 0)
            else
                if s.chiptype ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") then
                    s:chipin(pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"), s.roundmoney)
                -- self:sendPosInfoToAll(s, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD"))
                end
                local isallfold = self:isAllFold()
                if isallfold or (s.isplaying and self:getPlayingSize() == 2) then
                    log.info("idx(%s,%s) chipin isallfold", self.id, self.mid)
                    self:roundOver()
                    self.finishstate = pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish")
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
                {
                    code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                }
            )
        )
    end
end

function Room:userSit(uid, linkid, rev)
    log.info("idx(%s,%s) req sit down uid:%s", self.id, self.mid, uid)

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid)
    local dsts = self.seats[rev.sid]
    -- local is_buyin_ok = rev.buyinMoney and user.money >= rev.buyinMoney and (rev.buyinMoney >= (self.conf.minbuyinbb*self.conf.sb * 2)) and (rev.buyinMoney <= (self.conf.maxbuyinbb*self.conf.sb * 2))
    -- print(user.money,rev.buyinMoney,self.conf.sb * 2,self.conf.maxbuyinbb,self.conf.minbuyinbb, srcs,dsts)
    if not user or srcs or not dsts or (dsts and dsts.uid) --[[or not is_buyin_ok ]] then
        log.info("idx(%s,%s) sit failed uid:%s blind:%s", self.id, self.mid, uid, self.conf.sb * 2)
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
        self:sit(dsts, uid, self.conf.minbuyinbb * self.conf.sb)
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
    if Utils:isRobot(user.api) and (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.sb) then
        buyinmoney = self.conf.maxbuyinbb * self.conf.sb - (seat.chips - seat.roundmoney)
    end
    if
        (buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.sb) or
            (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.sb) or
            (buyinmoney == 0 and (seat.chips - seat.roundmoney) >= self.conf.maxbuyinbb * self.conf.sb)
     then
        log.info(
            "idx(%s,%s) userBuyin over limit: minbuyinbb %s, maxbuyinbb %s, sb %s",
            self.id,
            self.mid,
            self.conf.minbuyinbb,
            self.conf.maxbuyinbb,
            self.conf.sb
        )
        if (buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.sb) then
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

            -- 当前已弃牌或者牌局未开始，筹码直接到账
            local is_immediately = true
            if
                not seat.isplaying or
                    seat.chiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") or
                    self.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None")
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
            pb.encode("network.cmd.PBGameToolSendResp_S", {code = code or 0, toolID = rev.toolID, leftNum = 0})
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
        log.info("idx(%s,%s) not enough money %s,%s", self.id, self.mid, uid, self:getUserMoney(uid))
        handleFailed(1)
        return
    end
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s) uid %s coroutine is expensing", self.id, self.mid, uid)
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
                    player = {uid = uid, username = user.username or ""},
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

    local t = {reviews = {}}
    local function resp()
        log.info("idx(%s,%s) PBTexasReviewResp %s", self.id, self.mid, cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasReviewResp"),
            pb.encode("network.cmd.PBTexasReviewResp", t)
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
        local tmp = g.copy(reviewlog)
        for _, item in ipairs(tmp.items) do
            if
                item.player and item.player.uid ~= uid and
                    (not item.showhandcard and not g.isInTable(item.efshowhandcarduid, uid))
             then
                item.handcards.card1 = item.usershowhandcard and item.usershowhandcard[1] or 0
                item.handcards.card2 = item.usershowhandcard and item.usershowhandcard[2] or 0
                if not (item.handcards.card1 ~= 0 and item.handcards.card2 ~= 0) then
                    item.bestcards = {0, 0, 0, 0, 0}
                    item.bestcardstype = 0
                end
            end
        end
        table.insert(t.reviews, tmp)
    end
    resp()
end

-- 预操作
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
        log.info("idx(%s,%s) userPreOperate invalid type", self.id, self.mid) -- 预操作类型无效
        return
    end

    seat:setPreOP(rev.preop)

    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPreOperateResp"),
        pb.encode("network.cmd.PBTexasPreOperateResp", {preop = seat:getPreOP()})
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
            pb.encode("network.cmd.PBTexasAddTimeResp", {idx = rev.idx, code = code or 0})
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
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s) uid %s coroutine is expensing", self.id, self.mid, uid)
        return false
    end
    if self.current_betting_pos ~= seat.sid then
        log.info("idx(%s,%s) user add time: user is not betting pos", self.id, self.mid)
        return
    end
    -- print(seat, user, self.current_betting_pos, seat and seat.sid)
    if self.conf and self.conf.addtimecost and seat.addon_count >= #self.conf.addtimecost then
        log.info("idx(%s,%s) user add time: addtime count over limit %s", self.id, self.mid, seat.addon_count)
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.addtimecost[seat.addon_count + 1] or 0) then
        log.info("idx(%s,%ps) user add time: not enough money %s", self.id, self.mid, uid)
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
                self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BETING"))
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

function Room:userEnforceShowCard(uid, linkid, rev)
    log.info("idx(%s,%s) userEnforceShowCard:%s", self.id, self.mid, uid)
    local function handleFailed()
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasEnforceShowCardResp"),
            pb.encode(
                "network.cmd.PBTexasEnforceShowCardResp",
                {
                    code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                }
            )
        )
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        handleFailed()
        return
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s) user:%s is not in seat", self.id, self.mid, uid)
        handleFailed()
        return
    end
    if self.state ~= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") then
        log.info("idx(%s,%s) state:%s not valid", self.id, self.mid, self.state)
        handleFailed()
        return
    end
    local nonfoldseats = self:getNonFoldSeats()
    if #nonfoldseats ~= 1 then
        log.info("idx(%s,%s) nonfoldseats:%s not valid", self.id, self.mid, #nonfoldseats)
        handleFailed()
        return
    end
    if not nonfoldseats[1].uid then
        log.info("idx(%s,%s) nonfoldseats[1].uid is nil: sid %s", self.id, self.mid, nonfoldseats[1].sid)
        handleFailed()
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.peekwinnerhandcardcost or 0) then
        log.info("idx(%s,%s) not enough money %s", self.id, self.mid, uid)
        handleFailed()
        return
    end
    local touser = self.users[nonfoldseats[1].uid]
    if not touser then
        log.info("idx(%s,%s) touser:%s is not in room", self.id, self.mid, nonfoldseats[1].uid)
        handleFailed()
        return
    end

    -- 扣钱加钱
    if self.conf and self.conf.peekwinnerhandcardcost > 0 and self.conf.peekwinnerhandcardearn > 0 then
        Utils:walletRpc(
            uid,
            user.api,
            user.ip,
            -1 * self.conf.peekwinnerhandcardcost,
            pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SHOWCARD"),
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
        Utils:walletRpc(
            nonfoldseats[1].uid,
            touser.api,
            touser.ip,
            self.conf.peekwinnerhandcardcost * self.conf.peekwinnerhandcardearn,
            pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SHOWCARD"),
            touser.linkid,
            self.conf.roomtype,
            self.id,
            self.mid
        )
    end
    -- review log
    local reviewlog = self.reviewlogs:back()
    for k, v in ipairs(reviewlog.items) do
        if v.player.uid == nonfoldseats[1].uid then
            table.insert(v.efshowhandcarduid, uid)
            break
        end
    end
    -- 亮牌
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasEnforceShowCardResp"),
        pb.encode(
            "network.cmd.PBTexasEnforceShowCardResp",
            {
                code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Success"),
                cards = nonfoldseats[1].handcards,
                winnersid = nonfoldseats[1].sid
            }
        )
    )
    -- TOAST
    net.send(
        self.users[nonfoldseats[1].uid] and self.users[nonfoldseats[1].uid].linkid,
        nonfoldseats[1].uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Chat"),
        pb.enum_id("network.cmd.PBChatSubCmdID", "PBChatSubCmdID_NotifySysChatMsg"),
        pb.encode(
            "network.cmd.PBNotifySysChatMsg",
            {
                type = pb.enum_id("network.cmd.PBChatChannelType", "PBChatChannelType_Game"),
                msg = cjson.encode(
                    {
                        type = "EFSHOWCARD",
                        username = user.username,
                        incmoney = self.conf.peekwinnerhandcardcost * self.conf.peekwinnerhandcardearn
                    }
                ),
                gameId = global.stype()
            }
        )
    )
end

function Room:userNextRoundPubCardReq(uid, linkid, rev)
    log.info("idx(%s,%s) userNextRoundPubCardReq:%s", self.id, self.mid, uid)
    local function handleFailed()
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNextRoundPubCardResp"),
            pb.encode(
                "network.cmd.PBTexasNextRoundPubCardResp",
                {
                    code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                }
            )
        )
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        handleFailed()
        return
    end
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s) uid %s coroutine is expensing", self.id, self.mid, uid)
        return false
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s) user:%s is not in seat", self.id, self.mid, uid)
        handleFailed()
        return
    end
    if self.state ~= pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Finish") then
        log.info("idx(%s,%s) state:%s not valid", self.id, self.mid, self.state)
        handleFailed()
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.peekpubcardcost or 0) then
        log.info("idx(%s,%s) not enough money %s", self.id, self.mid, uid)
        handleFailed()
        return
    end

    -- 扣钱加钱
    if self.conf and self.conf.peekpubcardcost > 0 then
        user.expense =
            coroutine.create(
            function(user)
                Utils:walletRpc(
                    uid,
                    user.api,
                    user.ip,
                    -1 * self.conf.peekpubcardcost,
                    pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_NEXTCARD"),
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
                user = self.users[uid]
                -- 亮牌
                net.send(
                    linkid,
                    uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNextRoundPubCardResp"),
                    pb.encode(
                        "network.cmd.PBTexasNextRoundPubCardResp",
                        {
                            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Success"),
                            cards = self.nextboardcards
                        }
                    )
                )
                -- TOAST
                pb.encode(
                    "network.cmd.PBNotifySysChatMsg",
                    {
                        type = pb.enum_id("network.cmd.PBChatChannelType", "PBChatChannelType_Game"),
                        msg = cjson.encode({type = "PUBCARD", username = user and user.username or ""}),
                        gameId = global.stype()
                    },
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Chat"),
                            pb.enum_id("network.cmd.PBChatSubCmdID", "PBChatSubCmdID_NotifySysChatMsg"),
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

function Room:userTableListInfoReq(uid, linkid, rev)
    -- log.info("idx(%s,%s) userTableListInfoReq:%s", self.id, self.mid, uid)
    local t = {
        idx = {
            srvid = rev.serverid or 0,
            roomid = rev.roomid or 0,
            matchid = rev.matchid or 0,
            roomtype = self.conf.roomtype
        },
        ante = self.ante,
        bigBlind = self.conf.sb * 2,
        miniBuyin = self.conf.minbuyinbb * self.conf.sb,
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
    -- log.info("idx(%s,%s) PBTexasTableListInfoResp %s", self.id, self.mid, cjson.encode(t))
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
                sb = self.conf.sb,
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
        log.info("(%s,%s) userWalletResp %s", self.id, self.mid, cjson.encode(rev))
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

-- 检测是否满足cheat条件
function Room:checkCheat(seat)
    -- seat.handcards -- 该玩家手牌(2张)
    -- self.boardcards  -- 公共牌(5张)

    -- (1)公共牌无公对无3条，输最多玩家牌力小于K high ||
    -- (2)公共牌有1个公对，输最多玩家牌力小于两对，手牌无K及K以上(无K无A) ||
    -- (3)公共牌有2个公对或者3条，输最多玩家牌力小于葫芦，手牌无K及K以上(无K无A)
    log.debug(
        "idx(%s,%s)checkCheat(),uid=%s handcard:%s,boardcards=%s",
        self.id,
        self.mid,
        seat.uid,
        string.format("0x%x,0x%x", seat.handcards[1], seat.handcards[2]),
        string.format(
            "0x%x,0x%x,0x%x,0x%x,0x%x",
            self.boardcards[1],
            self.boardcards[2],
            self.boardcards[3],
            self.boardcards[4],
            self.boardcards[5]
        )
    )

    local handHasLargerK = false -- 手中是否有K及K以上的牌
    for i = 1, #seat.handcards do
        if (0xFF & seat.handcards[i]) >= 0xD then
            handHasLargerK = true
            break
        end
    end
    local publicHasLargerK = false -- 公共牌中是否有K及K以上的牌
    for i = 1, #self.boardcards do
        if (0xFF & self.boardcards[i]) >= 0xD then
            publicHasLargerK = true
            break
        end
    end

    local publicPairNum = 0 -- 公共牌对子数
    local publicThreeNum = 0 -- 三张数
    local cardsNum = {}
    for i = 1, #self.boardcards do
        if not cardsNum[self.boardcards[i] & 0xFF] then
            cardsNum[self.boardcards[i] & 0xFF] = 1
        else
            cardsNum[self.boardcards[i] & 0xFF] = cardsNum[self.boardcards[i] & 0xFF] + 1
        end
    end

    for i = 2, 0xE do
        if cardsNum[i] then
            if 2 == cardsNum[i] then
                publicPairNum = publicPairNum + 1
            elseif 3 == cardsNum[i] then
                publicThreeNum = publicThreeNum + 1
            end
        end
    end

    if seat.lastchiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
        seat.handtype = self:getCardsType(self.boardcards, seat.handcards)
    end

    -- (1)公共牌无公对无3条，输最多玩家牌力小于K high
    if
        seat.handtype < pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_ONEPAIR") and
            not handHasLargerK and
            not publicHasLargerK
     then
        return true
    end

    -- (2)公共牌有1个公对，输最多玩家牌力小于两对，手牌无K及K以上(无K无A)
    if
        seat.handtype < pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_TWOPAIRS") and
            not handHasLargerK and
            (1 == publicPairNum)
     then
        return true
    end

    -- (3)公共牌有2个公对或者3条，输最多玩家牌力小于葫芦，手牌无K及K以上(无K无A)
    if
        seat.handtype < pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_FULLHOUSE") and
            not handHasLargerK and
            (2 == publicPairNum or 1 == publicThreeNum)
     then
        return true
    end
    return false
end

-- 判断该局输赢最多的两个玩家是否都是真人
function Room:checkWinnerAndLoserAreAllReal()
    if not self.hasFind then -- 如果还未查找
        self.hasFind = true
        self.maxWinnerLoserAreAllReal = false -- 最大赢家和输家是否都是真人（默认不全是真人）

        self.maxWinnerUID = 0 -- 最大的赢家uid
        self.maxLoserUID = 0 -- 最大输家uid
        local maxWin = 0
        local maxLoss = 0
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if user and v.isplaying then
                local totalwin = v.chips - (v.totalbuyin - v.currentbuyin) -- 该玩家总输赢
                if totalwin > maxWin then
                    maxWin = totalwin
                    self.maxWinnerUID = v.uid
                elseif totalwin < maxLoss then
                    maxLoss = totalwin
                    self.maxLoserUID = v.uid
                end
            end -- ~if
        end -- ~for

        -- 判断最大输家和最大赢家是否都是真人
        if 0 ~= self.maxWinnerUID and 0 ~= self.maxLoserUID then
            local user = self.users[self.maxWinnerUID]
            if user then
                if not Utils:isRobot(user.api) then
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

-- 检测是否满足cheat的第二个条件
function Room:checkCheat2(seat)
    -- 公共牌无公对无3条，输最多玩家牌力大于等于对子
    -- || 公共牌只有1个公对，输最多玩家牌力大于等于两对
    -- || 公共牌有2个公对或者3条，输最多玩家牌力大于等于葫芦

    -- seat.handcards -- 该玩家手牌(2张)
    -- self.boardcards  -- 公共牌(5张)

    local publicPairNum = 0 -- 公共牌对子数
    local publicThreeNum = 0 -- 三张数
    local cardsNum = {}
    for i = 1, #self.boardcards do
        if not cardsNum[self.boardcards[i] & 0xFF] then
            cardsNum[self.boardcards[i] & 0xFF] = 1
        else
            cardsNum[self.boardcards[i] & 0xFF] = cardsNum[self.boardcards[i] & 0xFF] + 1
        end
    end

    for i = 2, 0xE do
        if cardsNum[i] then
            if 2 == cardsNum[i] then
                publicPairNum = publicPairNum + 1
            elseif 3 == cardsNum[i] then
                publicThreeNum = publicThreeNum + 1
            end
        end
    end

    if seat.lastchiptype == pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
        seat.handtype = self:getCardsType(self.boardcards, seat.handcards)
    end

    if
        publicPairNum == 0 and publicThreeNum == 0 and
            seat.handtype >= pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_ONEPAIR")
     then
        return true
    end
    if
        publicPairNum == 1 and publicThreeNum == 0 and
            seat.handtype >= pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_TWOPAIRS")
     then
        return true
    end

    if
        (publicPairNum == 2 or publicThreeNum == 0) and
            seat.handtype >= pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_FULLHOUSE")
     then
        return true
    end
    return false
end

-- 获取最大牌牌型
-- 参数 commonCards： 公共牌(3,4,5张)
-- 参数 handCards: 手牌(2张)
-- 返回值: 返回牌型 最优牌
function Room:getCardsType(commonCards, handCards)
    -- pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_HIGHCARD")
    if type(commonCards) ~= "table" or type(handCards) ~= "table" then
        return pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_HIGHCARD")
    end
    local commonCardsNum = #commonCards -- 公共牌张数
    local handCardsNum = #handCards -- 手牌张数

    if commonCardsNum < 3 or commonCardsNum > 5 then
        return pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_HIGHCARD")
    end
    if handCardsNum ~= 2 then
        return pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_HIGHCARD")
    end

    -- 计算牌型
    if commonCardsNum == 5 then
        texas.initialize(self.pokerhands)
        texas.sethands(self.pokerhands, handCards[1], handCards[2], commonCards)
        local besthand = texas.checkhandstype(self.pokerhands) -- 选出最优的牌
        local handtype = texas.gethandstype(self.pokerhands) -- 获取最优牌牌型
        return handtype
    end
    return pb.enum_id("network.cmd.PBTexasCardWinType", "PBTexasCardWinType_HIGHCARD")
end

-- 获取最大的牌及牌型
-- 参数 commonCards: 公共牌(5张)
-- 参数 handCards: 手牌(2张)
-- 返回值: 返回最大的牌及最大牌牌型
function Room:getMaxCards(commonCards, handCards)
    local maxCards = {} -- 最大的牌
    local maxCardsType = 1

    texas.initialize(self.pokerhands)
    texas.sethands(self.pokerhands, handCards[1], handCards[2], commonCards)
    maxCards = texas.checkhandstype(self.pokerhands) -- 选出最优的牌
    maxCardsType = texas.gethandstype(self.pokerhands) -- 获取最大的牌的牌型

    return maxCards, maxCardsType
end

-- 比较两手牌大小
-- 返回值:  若A>B,则返回1; A==B,返回0; A<B,返回-1
function Room:compare(handtypeA, cardsA, handtypeB, cardsB)
    local result =
        texas.comphandstype(
        self.pokerhands,
        handtypeA, -- 牌型
        cardsA, -- 最好的5张牌
        handtypeB,
        cardsB
    )

    -- 1：A赢牌   0：和牌   -1：A输牌
    return result
end

-- 发牌
-- 参数 winnerUID: 赢家UID   0表示没有确定赢家
-- 参数 loserUID:  输家UID   0表示没有确定输家
function Room:dealCards(winnerUID, loserUID)
    --local playerNum = self.conf and self.conf.maxuser or 10 -- 该局参与者人数
    -- 每个参与者2张牌
    -- 先洗牌，再发牌
    self.cards = {}
    for _, v in ipairs(default_poker_table) do
        table.insert(self.cards, v)
    end

    local beginPos = 0
    for k = 1, #self.seats do
        local seat = self.seats[k]
        if seat and seat.uid and seat.isplaying then
            beginPos = k
            break
        end
    end

    self.pokeridx = 0
    for i = 1, #default_poker_table - 1 do -- 洗牌
        local s = rand.rand_between(i, #default_poker_table) -- 随机一个位置
        self.cards[i], self.cards[s] = self.cards[s], self.cards[i]
    end
    local strongHandcards = {}
    strongHandcards[1] = self:getStrongHandcards()
    strongHandcards[2] = self:getStrongHandcards()
    if strongHandcards[1] then
        log.debug(
            "strongHandcards[1][1]=%s,strongHandcards[1][2]=%s",
            string.format("0x%x", strongHandcards[1][1] or 0),
            string.format("0x%x", strongHandcards[1][2] or 0)
        )
    end
    if strongHandcards[2] then
        log.debug(
            "strongHandcards[2][1]=%s,strongHandcards[2][2]=%s",
            string.format("0x%x", strongHandcards[2][1] or 0),
            string.format("0x%x", strongHandcards[2][2] or 0)
        )
    end

    if (winnerUID and winnerUID > 0) or (loserUID and loserUID > 0) then
        -- 需要发2组大手牌
        self.cards = self:removeCards(self.cards, strongHandcards[1])
        for i = 1, 100 do
            if self:inCards(self.cards, strongHandcards[2]) then
                break
            end
            strongHandcards[2] = self:getStrongHandcards()
        end
        self.cards = self:removeCards(self.cards, strongHandcards[2])
        log.debug("need deal strong cards")
    end

    local hasSendStrongNum = 0 --
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat and seat.uid and seat.isplaying then
            if winnerUID and seat.uid == winnerUID and winnerUID > 0 then
                hasSendStrongNum = hasSendStrongNum + 1
                self.seatCards[i] = {strongHandcards[hasSendStrongNum][1], strongHandcards[hasSendStrongNum][2]}
            elseif loserUID and seat.uid == loserUID and loserUID > 0 then
                hasSendStrongNum = hasSendStrongNum + 1
                self.seatCards[i] = {strongHandcards[hasSendStrongNum][1], strongHandcards[hasSendStrongNum][2]}
            end
        else
            self.seatCards[i] = {}
        end
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat and seat.uid and seat.isplaying then
            if seat.uid ~= winnerUID and seat.uid ~= loserUID then
                if hasSendStrongNum == 1 then
                    hasSendStrongNum = hasSendStrongNum + 1
                    self.seatCards[i] = {strongHandcards[hasSendStrongNum][1], strongHandcards[hasSendStrongNum][2]}
                else
                    self.seatCards[i] = {self:getOneCard(), self:getOneCard()} -- 第i个座位的牌
                end
            end
        else
            self.seatCards[i] = {}
        end
    end

    local leftCards = self:getLeftCard() -- 剩余扑克牌

    for j = 1, 100 do
        -- 洗牌
        for i = 1, 5 do
            local randPos = rand.rand_between(1, #leftCards) -- 随机一个位置
            leftCards[i], leftCards[randPos] = leftCards[randPos], leftCards[i]
        end
        -- 从剩余牌中随机获取5张公共牌

        -- self.commonCards = {self:getOneCard(), self:getOneCard(), self:getOneCard(), self:getOneCard(), self:getOneCard()} -- 公共牌(5张牌)
        self.commonCards = {leftCards[1], leftCards[2], leftCards[3], leftCards[4], leftCards[5]} -- 公共牌(5张牌)

        local maxCardsType = 0
        local maxCardsData = {} -- 最大的5张牌
        local minCardsType = 0
        local minCardsData = {}
        local currentCardsData = {}

        -- 比较获取最大的牌
        maxCardsData, self.seatCardsType[beginPos] = self:getMaxCards(self.commonCards, self.seatCards[beginPos])
        --maxCardsData, self.seatCardsType[1] = self:getMaxCards(self.commonCards, self.seatCards[1])
        --maxCardsType = self.seatCardsType[1]
        --minCardsType = self.seatCardsType[1]
        maxCardsType = self.seatCardsType[beginPos]
        minCardsType = self.seatCardsType[beginPos]
        self.minCardsIndex = beginPos -- 最小牌所在位置
        self.maxCardsIndex = beginPos -- 最大牌所在索引

        minCardsData = g.copy(maxCardsData)
        for i = beginPos + 1, #self.seats do
            if self.seats[i] and self.seats[i].uid and self.seats[i].isplaying then
                currentCardsData, self.seatCardsType[i] = self:getMaxCards(self.commonCards, self.seatCards[i])
                if maxCardsType < self.seatCardsType[i] then
                    self.maxCardsIndex = i
                    maxCardsData = currentCardsData
                    maxCardsType = self.seatCardsType[i]
                elseif maxCardsType == self.seatCardsType[i] then
                    local ret = self:compare(maxCardsType, maxCardsData, self.seatCardsType[i], currentCardsData)
                    if ret == -1 then
                        self.maxCardsIndex = i
                        maxCardsData = currentCardsData
                        maxCardsType = self.seatCardsType[i]
                    elseif self.maxCardsIndex == self.minCardsIndex and ret == 1 then
                        self.minCardsIndex = i
                        minCardsData = currentCardsData
                        minCardsType = self.seatCardsType[i]
                    end
                else
                    if minCardsType > self.seatCardsType[i] then
                        self.minCardsIndex = i
                        minCardsData = currentCardsData
                        minCardsType = self.seatCardsType[i]
                    elseif minCardsType == self.seatCardsType[i] then
                        local ret = self:compare(minCardsType, minCardsData, self.seatCardsType[i], currentCardsData)
                        if ret == 1 then
                            self.minCardsIndex = i
                            minCardsData = currentCardsData
                            minCardsType = self.seatCardsType[i]
                        end
                    end
                end
            end
        end

        -- if ((not winnerUID) or winnerUID == 0) and ((not loserUID) or loserUID == 0) then -- 没有输赢控制者
        --     break
        -- end

        if winnerUID and winnerUID > 0 then
            local seatIndex = 0
            for k, v in ipairs(self.seats) do
                local user = self.users[v.uid]
                if user and v.isplaying and v.uid == winnerUID then
                    seatIndex = k
                    break
                end -- ~if
            end -- ~for
            if seatIndex == self.maxCardsIndex then
                break
            elseif
                self:getHandcardPower(self.seatCards[self.maxCardsIndex][1], self.seatCards[self.maxCardsIndex][2]) >= 7
             then
                self.seatCards[seatIndex][1], self.seatCards[self.maxCardsIndex][1] =
                    self.seatCards[self.maxCardsIndex][1],
                    self.seatCards[seatIndex][1]
                self.seatCards[seatIndex][2], self.seatCards[self.maxCardsIndex][2] =
                    self.seatCards[self.maxCardsIndex][2],
                    self.seatCards[seatIndex][2]
                break
            end
        elseif loserUID and loserUID > 0 then
            local seatIndex = 0
            for k, v in ipairs(self.seats) do
                local user = self.users[v.uid]
                if user and v.isplaying and v.uid == loserUID then
                    seatIndex = k
                    break
                end -- ~if
            end -- ~for
            if seatIndex == self.minCardsIndex then
                break
            elseif
                self:getHandcardPower(self.seatCards[self.minCardsIndex][1], self.seatCards[self.minCardsIndex][2]) >= 7
             then
                self.seatCards[seatIndex][1], self.seatCards[self.minCardsIndex][1] =
                    self.seatCards[self.minCardsIndex][1],
                    self.seatCards[seatIndex][1]
                self.seatCards[seatIndex][2], self.seatCards[self.minCardsIndex][2] =
                    self.seatCards[self.minCardsIndex][2],
                    self.seatCards[seatIndex][2]
                break
            end
            if seatIndex ~= self.maxCardsIndex then
                break
            end
        else
            break
        end

        --[[
        if winnerUID and winnerUID ~= 0 then
            local seatIndex = 0
            for k, v in ipairs(self.seats) do
                local user = self.users[v.uid]
                if user and v.isplaying and v.uid == winnerUID then
                    seatIndex = k
                    break
                end -- ~if
            end -- ~for

            if seatIndex == self.maxCardsIndex then
                break
            end
            if seatIndex ~= 0 and self.maxCardsIndex ~= seatIndex then
                -- -- 牌力判断
                -- if self:getHandcardPower(self.seatCards[self.maxCardsIndex][1], self.seatCards[self.maxCardsIndex][2]) >= 7 then
                -- end

                -- 换牌
                local card1 = self.seatCards[seatIndex][1]
                local card2 = self.seatCards[seatIndex][2]
                self.seatCards[seatIndex][1] = self.seatCards[self.maxCardsIndex][1]
                self.seatCards[seatIndex][2] = self.seatCards[self.maxCardsIndex][2]
                self.seatCards[self.maxCardsIndex][1] = card1
                self.seatCards[self.maxCardsIndex][2] = card2
                if seatIndex == self.minCardsIndex then
                    self.minCardsIndex = self.maxCardsIndex
                end
                self.maxCardsIndex = seatIndex
            end

            -- 判断牌力值
        end

        if loserUID and loserUID ~= 0 then
            local seatIndex = 0
            for k, v in ipairs(self.seats) do
                local user = self.users[v.uid]
                if user and v.isplaying and v.uid == loserUID then
                    seatIndex = k
                    break
                end -- ~if
            end -- ~for
            if seatIndex ~= 0 and self.minCardsIndex ~= seatIndex then
                -- 换牌
                local card1 = self.seatCards[seatIndex][1]
                local card2 = self.seatCards[seatIndex][2]
                self.seatCards[seatIndex][1] = self.seatCards[self.minCardsIndex][1]
                self.seatCards[seatIndex][2] = self.seatCards[self.minCardsIndex][2]
                self.seatCards[self.minCardsIndex][1] = card1
                self.seatCards[self.minCardsIndex][2] = card2
                if seatIndex == self.maxCardsIndex then
                    self.maxCardsIndex = self.minCardsIndex
                end
                self.minCardsIndex = seatIndex
            end
        end

        -- 检测最大玩家的手牌牌力是否>=6
        if
            winnerUID and winnerUID > 0 and
                self:getHandcardPower(self.seatCards[self.maxCardsIndex][1], self.seatCards[self.maxCardsIndex][2]) >= 6
         then
            log.warn("find out maxCard winnerUID=%s", winnerUID)
            break
        end

        if self:getHandcardPower(self.seatCards[self.minCardsIndex][1], self.seatCards[self.minCardsIndex][2]) >= 6 then
            log.warn("find out minCard")
            break
        end

        --]]
    end -- ~for

    -- 打印牌数据
    log.debug(
        "maxCardsIndex=%s,minCardsIndex=%s,commonCards=%s,beginPos=%s",
        self.maxCardsIndex,
        self.minCardsIndex,
        string.format(
            "0x%x,0x%x,0x%x,0x%x,0x%x",
            self.commonCards[1],
            self.commonCards[2],
            self.commonCards[3],
            self.commonCards[4],
            self.commonCards[5]
        ),
        beginPos
    )
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat and seat.uid and seat.isplaying then
            log.debug(
                "sid=%s, handcards=%s,cardsType=%s",
                i,
                string.format("0x%x,0x%x", self.seatCards[i][1], self.seatCards[i][2]),
                self.seatCardsType[i] or 0
            )
        end
    end
end

-- 根据手牌计算牌力 [0,9]
function Room:getHandcardPower(card1, card2)
    local MAX_HANDCARD_POWER = 9 -- 手牌最大牌力

    local TexasHandCardPower = {
        -- --2, 3, 4, 5, 6, 7, 8, 9, T, J, Q, K, A
        -- {4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3}, --2
        -- {0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3}, --3
        -- {0, 0, 4, 2, 1, 0, 0, 0, 0, 0, 0, 0, 3}, --4
        -- {0, 0, 2, 5, 2, 1, 0, 0, 0, 0, 0, 0, 3}, --5
        -- {0, 0, 1, 2, 5, 2, 1, 0, 0, 0, 0, 0, 3}, --6
        -- {0, 0, 0, 1, 2, 6, 2, 1, 1, 0, 0, 0, 3}, --7
        -- {0, 0, 0, 1, 1, 2, 6, 2, 2, 0, 0, 1, 3}, --8
        -- {0, 0, 0, 0, 0, 1, 2, 7, 3, 1, 1, 2, 3}, --9
        -- {0, 0, 0, 0, 0, 1, 2, 3, 7, 3, 3, 4, 4}, --T
        -- {0, 0, 0, 0, 0, 0, 0, 1, 3, 8, 3, 4, 5}, --J
        -- {0, 0, 0, 0, 0, 0, 0, 1, 3, 3, 8, 5, 7}, --Q
        -- {0, 0, 0, 0, 0, 0, 1, 2, 4, 4, 5, 9, 8}, --K
        -- {3, 3, 3, 3, 3, 3, 3, 3, 4, 5, 7, 8, 9} --A

        --2, 3, 4, 5, 6, 7, 8, 9, T, J, Q, K, A
        {6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5}, --2
        {0, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5}, --3
        {0, 0, 6, 5, 5, 0, 0, 0, 0, 0, 0, 0, 5}, --4
        {0, 5, 5, 6, 5, 5, 0, 0, 0, 0, 0, 0, 5}, --5
        {0, 0, 5, 5, 6, 5, 5, 0, 0, 0, 0, 0, 5}, --6
        {0, 0, 0, 5, 5, 7, 5, 5, 5, 0, 0, 0, 5}, --7
        {0, 0, 0, 0, 5, 5, 7, 5, 5, 5, 0, 0, 5}, --8
        {0, 0, 0, 0, 0, 5, 5, 7, 5, 5, 5, 0, 5}, --9
        {0, 0, 0, 0, 0, 5, 5, 5, 7, 5, 5, 5, 7}, --T
        {0, 0, 0, 0, 0, 0, 5, 5, 5, 8, 6, 6, 7}, --J
        {0, 0, 0, 0, 0, 0, 0, 5, 5, 6, 8, 7, 8}, --Q
        {0, 0, 0, 0, 0, 0, 0, 0, 5, 6, 7, 8, 8}, --K
        {5, 5, 5, 5, 5, 5, 5, 5, 7, 7, 8, 8, 8} --A
    }

    local hand_power = TexasHandCardPower[(card1 & 0xF) - 1][(card2 & 0xF) - 1] or 0
    if hand_power < MAX_HANDCARD_POWER and (card1 & 0xF00) == (card2 & 0xF00) then
        hand_power = hand_power + 1
    end
    return hand_power
end

-- 获取强力手牌
function Room:getStrongHandcards()
    local strongHandcards = {
        -- 牌力为8的牌
        -- 对A
        {0x10E, 0x20E},
        {0x10E, 0x30E},
        {0x10E, 0x40E},
        {0x20E, 0x30E},
        {0x20E, 0x40E},
        {0x30E, 0x40E},
        -- 对K
        {0x10D, 0x20D},
        {0x10D, 0x30D},
        {0x10D, 0x40D},
        {0x20D, 0x30D},
        {0x20D, 0x40D},
        {0x30D, 0x40D},
        -- 对Q
        {0x10C, 0x20C},
        {0x10C, 0x30C},
        {0x10C, 0x40C},
        {0x20C, 0x30C},
        {0x20C, 0x40C},
        {0x30C, 0x40C},
        -- 对J
        {0x10B, 0x20B},
        {0x10B, 0x30B},
        {0x10B, 0x40B},
        {0x20B, 0x30B},
        {0x20B, 0x40B},
        {0x30B, 0x40B},
        --AK
        {0x10E, 0x10D},
        {0x10E, 0x20D},
        {0x10E, 0x30D},
        {0x10E, 0x40D},
        {0x20E, 0x10D},
        {0x20E, 0x20D},
        {0x20E, 0x30D},
        {0x20E, 0x40D},
        {0x30E, 0x10D},
        {0x30E, 0x20D},
        {0x30E, 0x30D},
        {0x30E, 0x40D},
        {0x40E, 0x10D},
        {0x40E, 0x20D},
        {0x40E, 0x30D},
        {0x40E, 0x40D},
        --AQ
        {0x10E, 0x10C},
        {0x10E, 0x20C},
        {0x10E, 0x30C},
        {0x10E, 0x40C},
        {0x20E, 0x10C},
        {0x20E, 0x20C},
        {0x20E, 0x30C},
        {0x20E, 0x40C},
        {0x30E, 0x10C},
        {0x30E, 0x20C},
        {0x30E, 0x30C},
        {0x30E, 0x40C},
        {0x40E, 0x10C},
        {0x40E, 0x20C},
        {0x40E, 0x30C},
        {0x40E, 0x40C},
        -- 牌力为7的牌
        -- AJ
        {0x10E, 0x10B},
        {0x10E, 0x20B},
        {0x10E, 0x30B},
        {0x10E, 0x40B},
        {0x20E, 0x10B},
        {0x20E, 0x20B},
        {0x20E, 0x30B},
        {0x20E, 0x40B},
        {0x30E, 0x10B},
        {0x30E, 0x20B},
        {0x30E, 0x30B},
        {0x30E, 0x40B},
        {0x40E, 0x10B},
        {0x40E, 0x20B},
        {0x40E, 0x30B},
        {0x40E, 0x40B},
        --A10
        {0x10E, 0x10A},
        {0x10E, 0x20A},
        {0x10E, 0x30A},
        {0x10E, 0x40A},
        {0x20E, 0x10A},
        {0x20E, 0x20A},
        {0x20E, 0x30A},
        {0x20E, 0x40A},
        {0x30E, 0x10A},
        {0x30E, 0x20A},
        {0x30E, 0x30A},
        {0x30E, 0x40A},
        {0x40E, 0x10A},
        {0x40E, 0x20A},
        {0x40E, 0x30A},
        {0x40E, 0x40A},
        --KQ
        {0x10D, 0x10C},
        {0x10D, 0x20C},
        {0x10D, 0x30C},
        {0x10D, 0x40C},
        {0x20D, 0x10C},
        {0x20D, 0x20C},
        {0x20D, 0x30C},
        {0x20D, 0x40C},
        {0x30D, 0x10C},
        {0x30D, 0x20C},
        {0x30D, 0x30C},
        {0x30D, 0x40C},
        {0x40D, 0x10C},
        {0x40D, 0x20C},
        {0x40D, 0x30C},
        {0x40D, 0x40C},
        --KJ
        {0x10D, 0x10B},
        {0x20D, 0x20B},
        {0x30D, 0x30B},
        {0x40D, 0x40B},
        --对10
        {0x10A, 0x20A},
        {0x10A, 0x30A},
        {0x10A, 0x40A},
        {0x20A, 0x30A},
        {0x20A, 0x40A},
        {0x30B, 0x40A},
        --对9
        {0x109, 0x209},
        {0x109, 0x309},
        {0x109, 0x409},
        {0x209, 0x309},
        {0x209, 0x409},
        {0x309, 0x409},
        --对8
        {0x108, 0x208},
        {0x108, 0x308},
        {0x108, 0x408},
        {0x208, 0x308},
        {0x208, 0x408},
        {0x308, 0x408},
        --对7
        {0x107, 0x207},
        {0x107, 0x307},
        {0x107, 0x407},
        {0x207, 0x307},
        {0x207, 0x407},
        {0x307, 0x407}
    }

    local ret = {}
    local index = rand.rand_between(1, #strongHandcards)
    ret[1] = strongHandcards[index][1]
    ret[2] = strongHandcards[index][2]
    return ret
end

-- 移除指定牌
-- 参数 cards: 从这些牌中移除
-- 参数 removedCards: 待移除的牌
function Room:removeCards(cards, removedCards)
    local cardsNum = #cards -- 牌总张数
    local removedCardsNum = #removedCards -- 要移除的牌张数

    for i = 1, removedCardsNum, 1 do
        local card = removedCards[i] -- 第i张要移除的牌
        for j = 1, cardsNum, 1 do
            if (cards[j] & 0xFFFF) == (card & 0xFFFF) then
                cards[j] = cards[cardsNum]
                cards[cardsNum] = nil
                cardsNum = cardsNum - 1
                break
            end
        end
    end
    return cards
end

-- 判断一组牌是否在另一组牌中
function Room:inCards(cards, subcards)
    local cardsNum = #cards -- 牌总张数
    local subcardsNum = #subcards -- 少的牌张数
    for i = 1, subcardsNum, 1 do
        local card = subcards[i] -- 第i张要移除的牌
        local hasFind = false
        for j = 1, cardsNum, 1 do
            if (cards[j] & 0xFFFF) == (card & 0xFFFF) then
                hasFind = true
                break
            end
        end
        if not hasFind then
            return false
        end
    end
    return true
end

-- 若需要某玩家赢，先发手牌(牌力>=7的牌)
