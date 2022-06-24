-- serverdev\luascripts\servers\36\room.lua

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
require("luascripts/servers/36/seat")
require("luascripts/servers/36/domino")

Room = Room or {}

-- 定时器
local TimerID = {
    TimerID_Check = {1, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, --id, interval(ms), timestamp(ms)
    TimerID_PrechipsOver = {3, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_StartHandCards = {4, 1000}, --id, interval(ms), timestamp(ms)
    TimerID_HandCardsAnimation = {5, 3000}, -- 发牌动画
    TimerID_Betting = {6, 11000}, --id, interval(ms), timestamp(ms)  下注时长(出牌时长)
    TimerID_Settlement = {7, 30000},
    TimerID_OnFinish = {8, 8500}, --id, interval(ms), timestamp(ms)
    TimerID_Timeout = {9, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {10, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_PotAnimation = {11, 2000},
    TimerID_Buyin = {12, 1000}, -- 买筹码定时器
    TimerID_Ready = {13, 5}, -- 准备剩余时长(秒)
    TimerID_Next = {14, 1000}, -- 下一个玩家出牌
    TimerID_Expense = {15, 5000},
    TimerID_CheckRobot = {16, 5000}
}

-- 玩家状态
local EnumUserState = {
    Playing = 1, -- 在房间中，且坐下
    Leave = 2, --
    Logout = 3, -- 退出
    Intoing = 4
}

-- 填充座位信息
local function fillSeatInfo(seat, self)
    local seatinfo = {}
    seatinfo.seat = {
        sid = seat.sid,
        tid = 0,
        playerinfo = {} -- 该座位上的玩家信息
    }

    local user = self.users[seat.uid]
    seatinfo.seat.playerinfo = {
        uid = seat.uid or 0,
        nickname = "",
        username = user and user.username or "",
        viplv = 0,
        gender = user and user.sex or 0,
        nickurl = user and user.nickurl or "",
        balance = seat.chips or 0,
        currency = "",
        extra = {api = "", ip = "", platuid = ""}
    }

    seatinfo.isPlaying = seat.isplaying and 1 or 0
    seatinfo.seatMoney = seat.chips or 0
    seatinfo.chipinType = seat.chiptype or 0
    if seatinfo.chipinType == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_BETING") then
        seatinfo.chipinValue = self.lastOutCard or 0
    else
        seatinfo.chipinValue = seat.chipinnum
    end

    seatinfo.chipinTime = seat:getChipinLeftTime()
    seatinfo.totalTime = seat:getChipinTotalTime()

    -- 拷贝手牌 因为是广播消息，所以不能包含手牌数据
    -- seatinfo.handcards = g.copy(seat.handcards)

    seatinfo.pot = self:getOnePot()
    seatinfo.currentBetPos = self.current_betting_pos
    seatinfo.addtimeCost = self.conf.addtimecost
    seatinfo.addtimeCount = seat.addon_count

    if seat:getIsBuyining() then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_BUYING")
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
    end

    if seat.chiptype and seat.chiptype == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS") then -- 如果是过牌
        seatinfo.lastOutCardSid = self.maxraisepos -- 最近一个出牌者座位ID
        local maxseat = self.seats[self.maxraisepos] -- 最近一个出牌者座位
        if maxseat then
            seatinfo.lastOutCardMoney = maxseat.chips -- 最后一个出牌者身上金额
            if seat.sid == self.maxraisepos then
                seatinfo.passCardPay = 0 -- 过牌者需要支付的金额
            else
                local fine = math.floor(self.conf.ante * 1)
                seatinfo.passCardPay = fine -- 过牌者需要支付的金额
            end
        end
    end

    return seatinfo
end

local function fillSeats(self)
    local seats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            local seatinfo = fillSeatInfo(seat, self)

            seatinfo.handcards = {}
            if seat.isplaying then
                for k, v in ipairs(seat.handcards) do
                    if v == 0 then
                        table.insert(seatinfo.handcards, v)
                    end
                end
            end

            table.insert(seats, seatinfo)
        end
    end
    return seats
end

-- 发牌动画结束
local function onHandCardsAnimation(self)
    local function doRun()
        log.info("idx(%s,%s) onHandCardsAnimation:%s", self.id, self.mid, self.current_betting_pos)
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1]) -- 关闭定时器
        if self.bbpos <= 0 then
            self.bbpos = rand.rand_between(1, #self.seats)
            log.info("idx(%s,%s) [error] bbpos <= 0", self.id, self.mid)
        end
        local bbseat = self.seats[self.bbpos]
        local nextseat = self:getNextActionPosition(bbseat)
        self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Betting") -- 进入下注阶段(出牌阶段)
        log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state))
        self:betting(nextseat) --从庄家开始出牌
    end
    g.call(doRun)
end

-- 下一个玩家出牌
local function onNextPlayerBet(self)
    timer.cancel(self.timer, TimerID.TimerID_Next[1])
    local next_seat = self:getNextActionPosition(self.seats[self.current_betting_pos]) --
    log.info(
        "idx(%s,%s) next_seat uid:%s chipin_pos:%s chipin_uid:%s chiptype:%s,sid:%s",
        self.id,
        self.mid,
        next_seat and next_seat.uid or 0,
        tostring(self.current_betting_pos),
        self.seats[self.current_betting_pos].uid,
        self.seats[self.current_betting_pos].chiptype,
        next_seat.sid
    )

    self:betting(next_seat) -- 下一个玩家出牌
end

local function onPotAnimation(self)
    local function doRun()
        self.finishstate = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish")
        log.info("idx(%s,%s) onPotAnimation", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_PotAnimation[1])
        self:finish()
    end
    g.call(doRun)
end

-- 买入定时器响应函数
local function onBuyin(t)
    local function doRun()
        local self = t[1]
        local uid = t[2] -- 买入者UID

        timer.cancel(self.timer, TimerID.TimerID_Buyin[1] + 100 + uid) -- 关闭买入定时器
        local seat = self:getSeatByUid(uid)
        if seat then -- 如果该买入者已坐下
            local user = self.users[uid]
            if user and user.buyin and coroutine.status(user.buyin) == "suspended" then
                log.debug("onBuyin(.), uid=%s, resume coroutine", uid)
                coroutine.resume(user.buyin, false) -- 唤醒协程，买入失败
            else
                self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_BuyinFailed")) -- 买入失败，玩家站起
                log.info("idx(%s,%s) onBuyin(.) BuyinFailed. uid=%s", self.id, self.mid, uid)
            end
        else
            log.debug("onBuyin() error, seat is nil,uid=%s", uid)
        end
    end
    g.call(doRun)
end

-- 准备阶段  定时检测
local function onCheck(self)
    local function doRun()
        if self.isStopping then
            Utils:onStopServer(self)
            return
        end

        -- check all users issuses
        for uid, user in pairs(self.users) do -- 遍历该桌所有玩家，让多次超时玩家离开
            -- clear logout users after 10 mins
            if user.state == EnumUserState.Logout and global.ctsec() >= user.logoutts + MYCONF.logout_to_kickout_secs then -- 如果该玩家超出离线时长
                log.debug(
                    "idx(%s,%s) onCheck(.) uid=%s,user logoutts=%s,current=%s",
                    self.id,
                    self.mid,
                    uid,
                    user.logoutts,
                    global.ctsec()
                )
                self:userLeave(uid, user.linkid) -- 玩家离开
            elseif user.toleave then --游戏过程中，在玩玩家点击了离开
                log.debug("idx(%s,%s) onCheck(.) uid=%s", self.id, self.mid, uid)
                self:userLeave(uid, user.linkid) -- 玩家离开
            end
        end

        -- check all seat users issuses
        for k, v in ipairs(self.seats) do -- 遍历所有座位
            local user = v.uid and self.users[v.uid] -- 获取该座位上的玩家
            if user then -- 如果该座位有玩家坐下
                local uid = v.uid or 0
                -- 超时两轮自动站起
                if v.bet_timeout_count >= 2 or user.toStand then
                    log.info(
                        "idx(%s,%s) onCheck user(%s,%s) betting timeout %s",
                        self.id,
                        self.mid,
                        uid,
                        k,
                        tostring(user.toStand)
                    )
                    user.toStand = false
                    --self:userLeave(v.uid, user.linkid) -- 玩家离开
                    self:stand(
                        v,
                        v.uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_ReservationTimesLimit")
                    )
                else
                    v:reset()
                    if v:hasBuyin() then -- 上局正在玩牌（非 fold）且已买入成功则下局生效
                        v:buyinToChips() -- 将买入金额转换为筹码
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

                    if v.chips > (self.conf and 9 * self.conf.ante + self.conf.fee or 0) then -- 如果该座位上金额足够
                        v.isplaying = true
                    elseif v.chips <= (self.conf and 9 * self.conf.ante + self.conf.fee or 0) then -- 下面是该座位筹码不够的情况
                        v.isplaying = false
                        if v:getIsBuyining() then --正在买入
                        elseif v:totalBuyin() > 0 then --非第一次坐下待买入，弹窗补币
                            v:setIsBuyining(true)
                            pb.encode(
                                "network.cmd.PBTexasPopupBuyin",
                                {clientBuyin = true, buyinTime = self.conf.buyintime, sid = k},
                                function(pointer, length)
                                    self:sendCmdToPlayingUsers( -- 这是要发给该桌所有在玩玩家? 通知该桌所有玩家某座位正在买入
                                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPopupBuyin"),
                                        pointer,
                                        length
                                    )
                                end
                            )

                            log.debug(
                                "set buyin timer,uid=%s, seat.totalbuyin=%s,seat.chips=%s, fee=%s, ante=%s",
                                uid,
                                v:totalBuyin(),
                                v.chips,
                                self.conf and self.conf.fee or 0,
                                self.conf and self.conf.ante or 0
                            )
                            timer.tick( -- 启动买入定时器
                                self.timer,
                                TimerID.TimerID_Buyin[1] + 100 + uid, --某玩家买入定时器
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
        --log.info("idx(%s,%s) onCheck playing size=%s", self.id, self.mid, self:getPlayingSize())

        local playingcount = self:getPlayingSize() -- 准备玩的玩家数目

        if playingcount < 2 then -- 如果准备好的玩家人数未满足开始条件，则需要继续等待玩家
            self.ready_start_time = nil
            self.wait_start_time = 0
            return
        else
            self:ready()
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

        -- 检测创建机器人
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

-- dqw 结算  结束定时器
local function onFinish(self)
    local function doRun()
        log.info("idx(%s,%s) onFinish", self.id, self.mid)
        timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])

        Utils:broadcastSysChatMsgToAllUsers(self.notify_jackpot_msg) -- 广播消息(头奖)
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
        self:reset() -- 重置房间
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 定时检测
    end
    g.call(doRun)
end

-- 获取玩家身上金额
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
-- 新建一个房间
function Room:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init() -- 房间初始化
    o:check() --
    return o
end

--
function Room:destroy()
    timer.destroy(self.timer) -- 销毁定时器管理器
end

-- dqw 房间初始化
function Room:init()
    self.conf = MatchMgr:getConfByMid(self.mid) -- 根据房间类型ID获取配置信息
    if not self.conf then
        log.info("Room:init() idx(%s,%s), self.conf=nil", self.id, self.mid)
    else
        --log.info("self.conf.minplayercount=%s", self.conf.minplayercount)
        log.info("Room:init() idx(%s,%s), self.conf=%s", self.id, self.mid, cjson.encode(self.conf)) -- 打印配置信息
    end

    self.users = {} -- 存放该房间的所有玩家
    self.timer = timer.create() -- 创建定时器管理器
    self.poker = Domino:new() -- 新建一副牌
    self.gameId = 0 -- 标识是哪一局

    self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_None") -- 当前房间状态(准备状态)
    log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态
    self.buttonpos = 1 -- 庄家位置(庄家是每局第一个出牌的人，一局结束后按照顺时针方向旋转换庄家)

    -- self.tabletype = self.conf.matchtype  -- 房间类型 ？
    self.tabletype = self.conf.roomtype -- 房间类型

    self.seats = {} -- 所有座位
    for sid = 1, self.conf.maxuser do -- 根据每桌玩家最大数目创建座位
        local s = Seat:new(self, sid) -- 新建座位
        table.insert(self.seats, s)
    end
    -- log.info("self.seats=%s", cjson.encode(self.seats))   -- 打印座位信息

    self.sdata = {
        -- 游戏数据
        roomtype = self.conf.roomtype, -- 房间类型
        tag = self.conf.tag -- ?
    }

    self.starttime = 0 -- 牌局开始时刻
    self.endtime = 0 -- 牌局结束时刻

    self.ready_start_time = nil -- 准备阶段开始时刻

    ---------------------------------------
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000 -- 下注时长(秒)
    self.bettingtime = self.conf.bettime -- 下注时长(秒)
    self.current_betting_pos = 0 -- 当前下注的位置

    self.maxraisepos = 0

    self.pot = 0 -- 奖池

    self.config_switch = false
    self.statistic = Statistic:new(self.id, self.conf.mid)

    self.table_match_start_time = 0 -- 开赛时间
    self.table_match_end_time = 0 -- 比赛结束时间

    self.last_playing_users = {} -- 上一局参与的玩家列表

    self.finishstate = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_None")

    self.reviewlogs = LogMgr:new(1)
    --实时牌局
    self.reviewlogitems = {} --暂存站起玩家牌局
    --self.recentboardlog = RecentBoardlog.new() -- 最近牌局

    -- 主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_NULL")
    self.lastchipinpos = 0

    self.tableStartCount = 0
    self.m_winner_sid = 0
    self.bbpos = -1
    self.wait_start_time = 0

    self.m_multiple = 1 -- 输赢倍数
    self.finish_type = 1 -- 结束方式 1：普通结束  2:死亡结束
    self.lastOutCard = 0 -- 最近出的牌
    self.logid = self.statistic:genLogId()
end

function Room:reload()
    self.conf = MatchMgr:getConfByMid(self.mid)
end

-- 发送消息给在玩玩家
function Room:sendCmdToPlayingUsers(maincmd, subcmd, msg, msglen)
    self.links = self.links or {}
    if not self.user_cached then -- 如果玩家缓存无效
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

-- 获取该桌坐下的玩家总数及坐下的机器人总数
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

-- 获取房间类型
function Room:roomtype()
    return self.conf.roomtype
end

-- 该桌机器人数目
function Room:robotCount()
    local c = 0
    for k, v in pairs(self.users) do
        if Utils:isRobot(v.api) then
            c = c + 1
        end
    end
    return c
end

-- 获取该桌坐下的玩家总数及坐下的机器人总数
function Room:count()
    local c, r = 0, 0
    for k, v in ipairs(self.seats) do -- 遍历该桌所有座位
        local user = self.users[v.uid]
        if user then -- 如果玩家对象有效
            c = c + 1
            if Utils:isRobot(user.api) then
                r = r + 1
            end
        end
    end
    return c, r
end


-- 玩家退出
function Room:logout(uid)
    local user = self.users[uid]
    if user then
        user.state = EnumUserState.Logout
        user.logoutts = global.ctsec()
        log.info("idx(%s,%s) room logout uid:%s %s", self.id, self.mid, uid, user and user.logoutts or 0)
    end
end

--
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

-- 指定玩家离开房间
-- 参数 client: 是否是客户端主动离开
function Room:userLeave(uid, linkid, client)
    log.info("Room:userLeave(...) idx(%s,%s) userLeave:%s,%s", self.id, self.mid, uid, tostring(client))

    local function handleFailed() -- 处理离开失败的情况
        local resp =
            pb.encode(
            "network.cmd.PBLeaveGameRoomResp_S",
            {
                code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed")
            }
        )
        net.send( -- 发送离开失败消息
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
        log.info("handleFailed() send LeaveGameFailed message")
    end

    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        handleFailed()
        return
    end

    local seat  -- 要离开的玩家所在座位
    for k, v in ipairs(self.seats) do -- 遍历所有座位
        if v.uid == uid then -- 如果要离开的玩家在座位中
            seat = v
            break
        end
    end

    if seat and seat.isplaying then -- 如果该离开的玩家坐下且正在玩，不能立即离开
        if
            self.state >= pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish") and
                seat.isplaying
         then
            user.toleave = true -- 将要离开
            log.info("idx(%s,%s) user:%s isplaying", self.id, self.mid, uid)
            handleFailed()
            return
        elseif
            self.state == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish") and
                not self.hasCalcResult and
                seat.isplaying
         then
            user.toleave = true -- 将要离开
            log.info("idx(%s,%s) user:%s isplaying", self.id, self.mid, uid)
            handleFailed()
            return
        end
    end

    -- 下面是玩家可以直接离开的情况
    local changed = 0
    local sid = 0
    local totalProfit = self:getTotalProfit(uid)
    if seat then -- 如果坐下了 (可能在玩，可能不参与游戏)
        changed = seat.chips - seat.totalbuyin
        sid = seat.sid
        log.debug("Room:userLeave(...) stand uid=%s, sid=%s", uid, seat.sid)
        -- s = self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")) -- 玩家起立
        self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")) -- 玩家起立
    end

    user.state = EnumUserState.Leave -- 玩家状态变成离开状态

    -- 结算
    -- local val = s and s.room_delta or 0 -- 身上金额
    -- local val  -- = s and s.chips or 0 -- 身上金额
    local val = user.chips or 0 -- 玩家身上筹码
    if user.chips and user.totalbuyin then
        changed = user.chips - user.totalbuyin
    end
    log.debug(
        "idx(%s,%s) Room:userLeave() uid:%s val:%s, userMoney=%s ",
        self.id,
        self.mid,
        uid,
        val,
        self:getUserMoney(uid)
    )
    if val ~= 0 then -- 如果身上有筹码，则需要将筹码转换为金币
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
        user.chips = 0 -- 默认已全部转换为金币
        log.debug(
            "idx(%s,%s) money change uid:%s val:%s, userMoney=%s ",
            self.id,
            self.mid,
            uid,
            val,
            self:getUserMoney(uid)
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
            smallblind = self.conf.ante, -- 底注
            seconds = global.ctsec() - (user.intots or 0), -- 时间长度有问题 2021-10-15
            changed = changed, -- s and s.room_delta or 0,   -- 当前身上筹码 - 总买入筹码
            roomname = self.conf.name,
            gamecount = user.gamecount,
            matchid = self.mid,
            api = tonumber(user.api) or 0
        }

        Statistic:appendRoomLogs(logdata)
        log.info("idx(%s,%s) uid=%s,sid=%s upload roomlogs %s", self.id, self.mid, uid, sid, cjson.encode(logdata))
    end

    mutex.request( -- 请求离开房间
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
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess"), -- 成功离开
            roomtype = self.conf.roomtype,
            hands = user.gamecount or 0,
            profits = changed -- totalProfit   -- 从进入房间到离开房间这段时间的总收益
        }
    )
    self.users[uid] = nil -- 成功离开房间后，将玩家置空
    self.user_cached = false -- 玩家缓存变更(无效)

    net.send( --发送离开成功消息
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
        resp
    )
    log.info("idx(%s,%s) userLeave:%s,%s", self.id, self.mid, uid, user.gamecount or 0)

    if not next(self.users) then -- 如果该房间没有玩家
        MatchMgr:getMatchById(self.conf.mid):shrinkRoom() -- 移除空房间
    end
end

local function onMutexTo(arg)
    arg[2]:userMutexCheck(arg[1], -1)
end

-- 查询用户信息超时处理
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

-- 获取推荐买入金额
function Room:getRecommandBuyin(balance)
    local referrer = self.conf.ante * self.conf.referrerbb
    if referrer > balance then
        referrer = balance
    elseif referrer < self.conf.ante * self.conf.minbuyinbb then
        referrer = self.conf.ante * self.conf.minbuyinbb
    end
    return referrer
end

-- 玩家进入房间
function Room:userInto(uid, linkid, mid, quick, ip, api)
    log.info("idx(%s,%s) Room:userInto(...), uid=%s", self.id, self.mid, uid)
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"), -- 默认进入成功
        gameid = global.stype(),
        idx = {
            srvid = global.sid(),
            roomid = self.id,
            matchid = self.mid,
            roomtype = self.conf.roomtype or 0
        },
        maxuser = self.conf and self.conf.maxuser -- 每桌最大玩家数
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
        log.info("idx(%s,%s) uid=%s,ip=%s,code=%s into room failed", self.id, self.mid, uid, tostring(ip), code)
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
    user.state = EnumUserState.Intoing

    --座位互斥
    local seat, inseat = nil, false -- 可坐下的座位信息 , 玩家是否已经坐下
    for k, v in ipairs(self.seats) do -- 遍历该桌所有座位
        if v.uid then -- 如果该座位上有人
            -- 其他人在该座位上
            if v.uid == uid then -- 如果该玩家已经在该座位
                inseat = true
                seat = v
                break
            end
        else
            seat = v -- 空闲的座位
        end
    end

    if not seat then -- 如果没有空闲的座位可坐下
        log.info("idx(%s,%s) the room has been full uid=%s fail to sit", self.id, self.mid, uid)
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
            if not ok then -- 如果进入房间失败
                if self.users[uid] ~= nil then
                    timer.destroy(user.TimerID_MutexTo)
                    timer.destroy(user.TimerID_Timeout)
                    timer.destroy(user.TimerID_Expense)
                    self.users[uid] = nil
                    t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入房间失败
                    net.send( -- 发送进入房间失败消息
                        linkid,
                        uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                        pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                    )
                end
                log.info("idx(%s,%s) uid=%s has been in another room", self.id, self.mid, uid) -- 该玩家已经在其他房间中
                return
            end

            user.co =
                coroutine.create(
                function(user)
                    Utils:queryUserInfo( -- 查询玩家信息
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
                    local ok, ud = coroutine.yield() -- 等待查询结果

                    if ud then -- 如果查询到玩家信息
                        -- userinfo
                        user.uid = uid --玩家ID
                        user.money = ud.money or 0
                        user.coin = ud.coin or 0
                        user.diamond = ud.diamond or 0
                        user.nickurl = ud.nickurl or ""
                        user.username = ud.name or ""
                        user.viplv = ud.viplv or 0
                        user.sex = ud.sex or 0
                        user.api = ud.api or ""
                        user.ip = ip or ""
                        --print('ud.money', ud.money, 'ud.coin', ud.coin, 'ud.diamond', ud.diamond, 'ud.nickurl', ud.nickurl, 'ud.name', ud.name, 'ud.viplv', ud.viplv)
                        --user.addon_timestamp = ud.addon_timestamp

                        --seat info
                        if user.chips then
                            log.debug("idx(%s,%s) uid=%s,user.chips=%s", self.id, self.mid, uid, user.chips)
                        else
                            log.debug("idx(%s,%s) uid=%s,user.chips=0.", self.id, self.mid, uid)
                        end
                        user.chips = user.chips or 0
                        user.currentbuyin = user.currentbuyin or 0
                        user.roundmoney = user.roundmoney or 0

                        -- 从坐下到站起期间总买入和总输赢
                        user.totalbuyin = user.totalbuyin or 0
                        user.totalwin = user.totalwin or 0

                        -- 携带数据
                        user.linkid = linkid
                        user.intots = user.intots or global.ctsec() -- 玩家首次进入房间时刻
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
                    if ok and not inseat and self:getUserMoney(uid) > self.conf.maxinto then
                        ok = false
                        log.info(
                            "idx(%s,%s) uid=%s userMoney=%s more than maxinto=%s",
                            self.id,
                            self.mid,
                            uid,
                            self:getUserMoney(uid),
                            tostring(self.conf.maxinto)
                        )
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_OverMaxInto")
                    end

                    -- 金额不足也能进入房间  2021-10-25
                    -- if ok and not inseat and self.conf.minbuyinbb * self.conf.ante > self:getUserMoney(uid) then -- 身上金额不足
                    --     log.info(
                    --         "idx(%s,%s) userBuyin not enough money: buyinmoney %s, user money %s, minbuyinbb=%s,ante=%s",
                    --         self.id,
                    --         self.mid,
                    --         self.conf.minbuyinbb * self.conf.ante,
                    --         self:getUserMoney(uid),
                    --         self.conf.minbuyinbb,
                    --         self.conf.ante
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
                            "idx(%s,%s) not enough money:uid=%s,money=%s,code=%s",
                            self.id,
                            self.mid,
                            uid,
                            ud.money,
                            t.code
                        )
                        return
                    end

                    self.user_cached = false
                    user.state = EnumUserState.Playing

                    local resp, e = pb.encode("network.cmd.PBIntoGameRoomResp_S", t) --进入房间返回
                    local to = {
                        uid = uid,
                        srvid = global.sid(),
                        roomid = self.id,
                        matchid = self.mid,
                        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"), -- 进入房间响应消息
                        data = resp
                    }

                    local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)

                    net.shared(
                        linkid,
                        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                        pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                        synto
                    )

                    quick = (0x2 == (self.conf.buyin & 0x2)) and true or false -- 是否支持自动坐下买入

                    if not inseat and self:count() < self.conf.maxuser and quick and not user.active_stand then
                        if self.conf.minbuyinbb * self.conf.ante <= self:getUserMoney(uid) then -- 身上金额必须足够才能坐下 2021-10-25
                            self:sit(seat, uid, self:getRecommandBuyin(self:getUserMoney(uid)))
                        end
                    end

                    log.info(
                        "idx(%s,%s) into room: uid=%s,linkid=%s,seat.chips=%s,userMoney=%s,sitSize=%s",
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

-- dqw 房间重置
function Room:reset()
    self.pots = {money = 0, seats = {}}
    --奖池中包含哪些人共享
    self.maxraisepos = 0
    self.roundcount = 0 -- ??
    self.current_betting_pos = 0

    self.sdata = {
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}
    --self.boardlog:reset()
    self.finishstate = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_None")

    self.lastchipintype = pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_NULL")
    self.lastchipinpos = 0
    self.poker:resetAll()
    self.pot = 0
    self.winner_seats = nil
    self.m_winner_sid = 0
    self.m_join_type = 0
    self.buttonpos = 0

    self.m_multiple = 1
    self.lastOutCard = 0
end

--获取桌子信息
function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s) user table info req uid:%s ante:%s", self.id, self.mid, uid, self.conf.ante)
    local tableinfo = {
        gameId = self.gameId,
        seatCount = self.conf.maxuser,
        tableName = self.conf.name,
        gameState = self.state or 1,
        buttonSid = self.buttonpos,
        pot = self:getOnePot(),
        ante = self.conf.ante, -- 底注
        minbuyin = self.conf.minbuyinbb,
        middlebuyin = self.conf.referrerbb * self.conf.ante,
        maxbuyin = self.conf.maxbuyinbb,
        bettingtime = self.bettingtime,
        matchType = self.conf.matchtype,
        matchState = self.conf.matchState or 0,
        --matchType = self.conf.roomtype,
        roomType = self.conf.roomtype,
        addtimeCost = self.conf.addtimecost,
        toolCost = self.conf.toolcost,
        jpid = self.conf.jpid or 0,
        jp = JackpotMgr:getJackpotById(self.conf.jpid),
        jpRatios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or {0, 0, 0}),
        discardCard = g.copy(self.poker:getDiscardCards() or {}), -- 已发的牌 ，该游戏改成已出的牌
        readyLeftTime = ((self.t_msec or 0) / 1000 + TimerID.TimerID_Check[2] / 1000) - (global.ctsec() - self.endtime)
    }
    -- tableinfo.readyLeftTime =
    --     self.ready_start_time and TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time) or
    --     tableinfo.readyLeftTime
    if self.state == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_None") then --
        if self.ready_start_time and TimerID.TimerID_Ready[2] > (global.ctsec() - self.ready_start_time) then
            tableinfo.readyLeftTime = TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time)
            log.info("idx(%s,%s) tableinfo.readyLeftTime=%s", self.id, self.mid, tableinfo.readyLeftTime)
        else
            tableinfo.readyLeftTime = 0
            log.info("idx(%s,%s) tableinfo.readyLeftTime=  0", self.id, self.mid)
        end
    end

    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    log.info(
        "idx(%s,%s) uid:%s discardCard:%s, minbuyin=%s,maxbuyin=%s,ante=%s",
        self.id,
        self.mid,
        uid,
        cjson.encode(tableinfo.discardCard),
        tableinfo.minbuyin,
        tableinfo.maxbuyin,
        tableinfo.ante
    )
    --log.info("idx(%s,%s) uid:%s userTableInfo:%s", self.id, self.mid, uid, cjson.encode(tableinfo))
end

-- 发送所有座位信息
function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {}
    for i = 1, #self.seats do
        local seat = self.seats[i] -- 第i个座位
        if seat.uid then
            local seatinfo = fillSeatInfo(seat, self)
            seatinfo.handcards = {}
            if seat.uid == uid then
                seatinfo.handcards = g.copy(seat.handcards)
            else
                if seat.isplaying then
                    for k, v in ipairs(seat.handcards) do
                        if v == 0 then
                            table.insert(seatinfo.handcards, v)
                        end
                    end
                end
            end
            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end
    -- log.info("tableinfo=%s", cjson.encode(tableinfo))

    local resp = pb.encode("network.cmd.PBDominoTableInfoResp", {tableInfo = tableinfo})
    --log.info("2 tableinfo=%s", cjson.encode(tableinfo))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoTableInfoResp"),
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

-- 获取该桌正在玩的玩家数
function Room:getPlayingSize()
    local count = 0
    for i = 1, #self.seats do -- 遍历所有座位
        if self.seats[i].isplaying then -- 如果该座位上的玩家正在玩
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

-- 获取下一个正在玩的玩家座位
-- 参数 seat: 当前已出牌或已过牌的玩家座位
function Room:getNextActionPosition(seat)
    local pos = seat and seat.sid or 0
    log.info("idx(%s,%s) getNextActionPosition sid:%s,%s", self.id, self.mid, pos, tostring(self.maxraisepos))
    for i = pos + 1, pos + #self.seats - 1 do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seati = self.seats[j]
        if seati and seati.isplaying then
            seati.addon_count = 0
            return seati
        end
    end
    return nil
end

-- 移动庄家位置按钮(更新庄家位置)
function Room:moveButton()
    log.info("idx(%s,%s) move button", self.id, self.mid)

    if self.bbpos == -1 then
        self.bbpos = rand.rand_between(1, #self.seats)
    end
    for i = self.bbpos + 1, self.bbpos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat.isplaying then
            self.bbpos = j
            break
        end
    end
    for i = self.bbpos + 1, self.bbpos - 1 + #self.seats do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats
        local seat = self.seats[j]
        if seat.isplaying then
            self.buttonpos = j -- 庄家座位号
            self.current_betting_pos = j -- 当前要出牌的玩家位置
            break
        end
    end

    log.info("idx(%s,%s) movebutton:%s,%s,%s", self.id, self.mid, self.bbpos, self.buttonpos, self.current_betting_pos)
end

-- 获取该局游戏ID
function Room:getGameId()
    return self.gameId + 1 -- 游戏局号增1
end

-- 玩家站起
-- 参数 seat: 座位对象
-- 参数 uid: 要站起的玩家ID
-- 参数 stype: 玩家站起原因(方式)，如：PBTexasStandType_PlayerStand、PBTexasStandType_BuyinFailed
-- 返回值: 成功站起则返回true,否则返回false
function Room:stand(seat, uid, stype)
    log.info(
        "idx(%s,%s) stand(..) uid=%s,sid=%s,stype=%s,seat.totalbuyin=%s",
        self.id,
        self.mid,
        uid,
        seat.sid,
        tostring(stype),
        seat.totalbuyin
    )

    local user = self.users[uid]
    if seat and user then
        if seat.uid == uid and self:canStand(uid) then
            user.chips = seat.chips -- 玩家身上筹码?
            user.totalbuyin = seat.totalbuyin -- 玩家总买入筹码
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
            -- MatchMgr:getMatchById(self.conf.mid):shrinkRoom()
            return true
        end
    end
    return false
end

-- 玩家坐下到指定位置
-- 参数 buyinmoney: 买入金额
-- 参数 ischangetable: 是否换桌?
function Room:sit(seat, uid, buyinmoney, ischangetable)
    log.info(
        "idx(%s,%s,%s) sit uid=%s,sid=%s buyin=%s  userMoney=%s, ischangetable=%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        seat.sid,
        buyinmoney,
        self:getUserMoney(uid),
        ischangetable and 1 or 0
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
                    "network.cmd.PBTexasBuyinFailed", -- 买入失败
                    {
                        code = pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney"),
                        context = 0
                    }
                )
            )
            log.debug("idx(%s,%s) sit(.) uid=%s,user.chips=%s", self.id, self.mid, uid, user.chips)
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
            log.debug("idx(%s,%s) sit(.) robot uid=%s, empty seat num=%s", self.id, self.mid, uid, empty)
            return
        end

        log.debug(
            "idx(%s,%s,%s) sit(.) uid=%s,sid=%s,seat.totalbuyin=%s,user.totalbuyin=%s，user.chips=%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            seat.sid,
            seat.totalbuyin,
            user.totalbuyin,
            user.chips
        )
        seat:sit(uid, user.chips, 0, user.totalbuyin)

        -- 是否由客户端弹出操作买入
        local clientBuyin =
            (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante + self.conf.fee or 0)) -- 身上筹码不够下底注

        if clientBuyin then
            if (0x4 == (self.conf.buyin & 0x4) or Utils:isRobot(user.api)) and user.chips == 0 and user.totalbuyin == 0 then
                clientBuyin = false
                log.debug("idx(%s,%s) sit(.) uid=%s qw", self.id, self.mid, uid)
                if not self:userBuyin(uid, user.linkid, {buyinMoney = buyinmoney}, true) then -- 模拟客户端消息自动买入
                    seat:stand(uid) -- 买入失败，玩家起立
                    return
                end
            else
                log.debug("sit(),set timer for buyin, uid=%s", uid)
                seat:setIsBuyining(true)
                timer.tick( -- 设置买入定时器
                    self.timer,
                    TimerID.TimerID_Buyin[1] + 100 + uid,
                    self.conf.buyintime * 1000,
                    onBuyin,
                    {self, uid},
                    1
                )
            end
        else
            --客户端超时站起?
            seat.chips = user.chips
            user.chips = 0
            log.debug("idx(%s,%s) sit(.) uid=%s, seat.chips=%s", self.id, self.mid, uid, seat.chips)
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
        local seatinfo = fillSeatInfo(seat, self) -- 座位信息
        seatinfo.handcards = {}
        if seat.isplaying then
            for k, v in ipairs(seat.handcards) do
                if v == 0 then
                    table.insert(seatinfo.handcards, v)
                end
            end
        end

        local sitcmd = {seatInfo = seatinfo, clientBuyin = clientBuyin, buyinTime = self.conf.buyintime}
        pb.encode(
            "network.cmd.PBDominoPlayerSit",
            sitcmd,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoPlayerSit"),
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

--通知该桌所有玩家轮到某人出牌了
function Room:sendPosInfoToAll(seat, chiptype)
    local updateseat = {}
    if chiptype then
        seat.chiptype = chiptype -- 操作方式()
    end

    if seat.uid then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        updateseat.seatInfo.handcards = {}
        if seat.isplaying then
            for k, v in ipairs(seat.handcards) do
                if v == 0 then
                    table.insert(updateseat.seatInfo.handcards, v)
                end
            end
        end

        pb.encode(
            "network.cmd.PBDominoUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers( -- 将消息广播给该桌所有玩家
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoUpdateSeat"),
                    pointer,
                    length
                )
            end
        )
        log.info(
            "idx(%s,%s) updateseat chiptype:%s seatinfo:%s",
            self.id,
            self.mid,
            tostring(chiptype),
            cjson.encode(updateseat.seatInfo)
        )
    end
end

-- 给指定座位玩家发送他的座位信息
function Room:sendPosInfoToMe(seat)
    local user = self.users[seat.uid]
    local updateseat = {}
    if user then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        updateseat.seatInfo.handcards = {}
        if seat.isplaying then
            for k, v in ipairs(seat.handcards) do
                if v == 0 then
                    table.insert(updateseat.seatInfo.handcards, v)
                end
            end
        end
        updateseat.seatInfo.drawcard = seat.drawcard
        net.send(
            user.linkid,
            seat.uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoUpdateSeat"),
            pb.encode("network.cmd.PBDominoUpdateSeat", updateseat)
        )
        log.info("idx(%s,%s) checkcard:%s", self.id, self.mid, cjson.encode(updateseat))
    end
end

-- dqw 准备
function Room:ready()
    if not self.ready_start_time then -- 如果还未准备
        self.ready_start_time = global.ctsec() -- 准备阶段开始时刻(秒)

        -- 广播准备
        local gameready = {
            readyLeftTime = TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time)
        }
        pb.encode(
            "network.cmd.PBDominoGameReady",
            gameready,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoGameReady"),
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

-- dqw 游戏开始 所有人准备好后就开始游戏
function Room:start()
    self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Start") -- 更新桌子状态为开始状态

    log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态
    self:reset()
    self.gameId = self:getGameId() -- 更新游戏ID
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec() -- 开始时刻(秒)
    self.logid = self.has_started and self.statistic:genLogId(self.starttime) or self.logid
    self.has_started = self.has_started or true

    self.wait_start_time = 0
    self.finish_type = 1 -- 默认为1：普通结束  2：死亡结束

    -- 更新庄家位置
    self:moveButton()

    self.current_betting_pos = self.buttonpos -- 当前出牌位置(从庄家开始出牌)
    log.info(
        "idx(%s,%s) start ante:%s gameId:%s betpos:%s logid:%s fee=%s",
        self.id,
        self.mid,
        self.conf.ante,
        self.gameId,
        self.current_betting_pos,
        tostring(self.logid),
        self.conf.fee
    )

    self.poker:start() -- 开始洗牌

    -- 扣底注

    -- 服务费
    for k, v in ipairs(self.seats) do
        if v.uid and v.isplaying then -- 如果该座位玩家正在玩
            if self.conf and self.conf.fee and v.chips > self.conf.fee then
                v.chips = v.chips - self.conf.fee --扣除服务费
                v.last_chips = v.chips -- 最后输赢金额不考虑服务费情况 2021-10-18
                v.room_delta = v.room_delta - self.conf.fee
                v.profit = v.profit - self.conf.fee
                -- self.pot = self.pot + self.conf.fee  -- 服务费不计入奖池 2021-10-14
                -- 统计
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
                self.sdata.users[v.uid].totalfee = self.conf.fee
            end

            -- 注释掉  一开始不扣底注
            -- if self.conf and self.conf.ante and v.chips > self.conf.ante then -- 如果身上有足够金额扣除底注
            --     v.chips = v.chips - self.conf.ante -- 扣除底注
            --     v.room_delta = v.room_delta - self.conf.ante -- 扣除底注
            --     v.profit = v.profit - self.conf.ante
            --     self.pot = self.pot + self.conf.ante -- 将底注加到奖池中
            -- end
            local user = self.users[v.uid]
            if user then
                user.gamecount = (user.gamecount or 0) + 1 -- 统计数据
            end

            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            self.sdata.users[v.uid].sid = k
            self.sdata.users[v.uid].username = user and user.username or ""
            self.sdata.users[v.uid].cards = g.copy(v.handcards) -- 初始手牌
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
        ante = self.conf.ante, -- 前注
        minChip = self.conf.minchip,
        tableStarttime = self.starttime,
        seats = fillSeats(self)
    }
    pb.encode(
        "network.cmd.PBDominoGameStart", -- 游戏开始消息
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoGameStart"),
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
            buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0, -- 庄家ID
            ante = self.conf.ante
        }
    )

    -- 底注
    self:dealPreChips()
end

-- 检测是否轮到该玩家出牌
function Room:checkCanChipin(seat, type)
    return seat and seat.uid and seat.isplaying and seat.sid == self.current_betting_pos and
        (type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD") or
            type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS"))
end

-- 检测是否结束
function Room:checkFinish(chipin_seat, jointype, value)
    local isallfold = false -- 是否结束本局游戏

    if chipin_seat.sid == self.maxraisepos and jointype == 0 then
        self.finish_type = pb.enum_id("network.cmd.PBDominoFinishType", "PBDominoFinishType_Death") -- 死亡结束
        isallfold = true

        -- 在死亡结束中，剩余点数最小者为赢家
        local minpoint = 256 --点数和最小者
        local maxpoint = -1
        local winners = {} -- 各赢家座位号
        for k, v in ipairs(self.seats) do
            if v.uid and v.isplaying then -- 只考虑参与游戏的玩家
                table.sort(
                    v.handcards, -- 排序手中的牌?
                    function(a, b)
                        return self.poker:getPointSum(a) < self.poker:getPointSum(b)
                    end
                )
                local leftpoint = v:getLeftPoint() -- 手上牌点数和

                if leftpoint < minpoint then
                    minpoint = leftpoint
                    winners = {k}
                elseif leftpoint == minpoint then
                    table.insert(winners, k)
                end
            end
        end

        if minpoint == 256 then
            log.info("idx(%s,%s) [error] do not find minpoint", self.id, self.mid)
        end
        if #winners == 1 then -- 如果只有一个赢家
            self.m_winner_sid = winners[1]
        else
            -- 下面是不止一个最小点数玩家的情况
            local minpoint = 256
            local super_winners = {}
            for _, v in ipairs(winners) do
                --local point = self.poker:getPointSum(self.seats[v].handcards[1])
                local point = self.poker:getMinPointOneCard(self.seats[v].handcards)
                if point < minpoint then
                    minpoint = point
                    super_winners = {v}
                elseif point == minpoint then
                    table.insert(super_winners, v)
                end
            end

            if #super_winners == 1 then
                self.m_winner_sid = super_winners[1] -- 赢方座位号
            else
                local minpoint = 256
                winners = {}
                for _, v in ipairs(super_winners) do
                    local point = self.poker:getMinPointSelfCard(self.seats[v].handcards)
                    if point < minpoint then
                        minpoint = point
                        winners = {v}
                    elseif point == minpoint then
                        table.insert(winners, v)
                    end
                end
                if #winners == 1 then
                    self.m_winner_sid = winners[1]
                else
                    log.info(
                        "idx(%s,%s) [error] do not find minpoint from self card, winner num=%s",
                        self.id,
                        self.mid,
                        tostring(#winners)
                    )
                end
            end
        end
        log.info("idx(%s,%s) death finished,winner_sid=%s", self.id, self.mid, tostring(self.m_winner_sid))
        self.m_multiple = 1
    end

    if chipin_seat:isEmptyCard() and jointype > 0 then
        self.finish_type = pb.enum_id("network.cmd.PBDominoFinishType", "PBDominoFinishType_Normal") -- 普通结束
        self.m_winner_sid = chipin_seat.sid -- 赢方座位号
        self.m_winer_card = value
        isallfold = true

        if self.poker:isMagic(value) then -- 特殊牌
            if (jointype & 1) > 0 and (jointype & 2) > 0 then
                self.m_multiple = 4
            else
                self.m_multiple = 2
            end
        else
            if (jointype & 1) > 0 and (jointype & 2) > 0 then
                self.m_multiple = 3
            else
                self.m_multiple = 1
            end
        end
        log.info(
            "idx(%s,%s) normal finished,winner_sid=%s,multiple=%s",
            self.id,
            self.mid,
            tostring(self.m_winner_sid),
            tostring(self.m_multiple)
        )
    end

    if isallfold then
        -- 正常情况下是下面这个值，但若有玩家破产，则可能比该值小
        self.pot = self.pot + self.conf.ante * self.m_multiple * (self:getPlayingSize() - 1)

        log.info(
            "idx(%s,%s) chipin isallfold:%s,%s,%s,%s,%s",
            self.id,
            self.mid,
            tostring(self.m_winner_sid),
            tostring(self.jointype),
            tostring(self.finish_type),
            self.m_multiple,
            value
        )

        timer.cancel(self.timer, TimerID.TimerID_Betting[1])
        timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])
        timer.cancel(self.timer, TimerID.TimerID_Settlement[1])
        -- onPotAnimation(self)
        timer.tick(self.timer, TimerID.TimerID_PotAnimation[1], TimerID.TimerID_PotAnimation[2], onPotAnimation, self)
        return true
    end
    return false
end

-- 参数 type: 2:出牌或3:过牌
-- 参数 value: 要出的牌(可以为负数)
function Room:chipin(uid, type, value)
    local seat = self:getSeatByUid(uid)
    if
        type ~= pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD") and
            type ~= pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS")
     then
        log.info("idx(%s,%s) [error] type is invalid.", self.id, self.mid)
    end

    log.info(
        "idx(%s,%s) chipin pos:%s uid:%s type:%s value:%s",
        self.id,
        self.mid,
        seat.sid,
        seat.uid and seat.uid or 0,
        type,
        value
    )

    -- 出牌函数
    -- 参数 type： 2:出牌或3:过牌
    -- 参数 value: 待出的牌
    local function discard_func(seat, type, value)
        local jointype = self.poker:checkJoinable(value)
        if jointype == 0 then -- 不可加入
            log.info("idx(%s,%s) [error] discard value not joinable %s,%s", self.id, self.mid, uid, tostring(value))
            return false
        end
        if value < 0 and (jointype & 0x1) ~= 1 then
            log.info(
                "idx(%s,%s) [error] discard value left but join invalid %s,%s",
                self.id,
                self.mid,
                uid,
                tostring(value)
            )
            return false
        end
        if value > 0 and (jointype & 0x2) ~= 2 then
            log.info(
                "idx(%s,%s) [error] discard value right but join invalid %s,%s",
                self.id,
                self.mid,
                uid,
                tostring(value)
            )
            return false
        end

        local idx = seat:getIdxByCardValue(math.abs(value)) -- 根据牌值获取在手牌中的位置
        if idx == 0 then -- 未找出这张牌
            log.info("idx(%s,%s) [error] card value not exists %s,%s", self.id, self.mid, uid, tostring(value))
            return false
        end
        seat.handcards[idx] = 0 -- 将这张打出的牌置为0
        seat:chipin(type, value)
        self.poker:discard(value) -- 出一张牌

        local strDiscardCards = ""
        local index = 1
        local discardcards = self.poker:getDiscardCards()
        while index <= #discardcards do
            if discardcards[index] > 0 then
                strDiscardCards = strDiscardCards .. string.format("0x%04x,", discardcards[index] & 0xFFFF)
            else
                strDiscardCards = strDiscardCards .. string.format("-0x%04x,", math.abs(discardcards[index]) & 0xFFFF)
            end
            index = index + 1
        end

        log.info("idx(%s,%s) discard list [%s]", self.id, self.mid, strDiscardCards)
        --log.info("idx(%s,%s) discard list %s", self.id, self.mid, cjson.encode(self.poker:getDiscardCards()))
        log.info("idx(%s,%s) discard card %s,%s", self.id, self.mid, value, cjson.encode(seat.handcards))
        return true
    end

    -- 过牌函数
    local function pass_func(seat, type, value)
        local maxseat = self.seats[self.maxraisepos] -- 最近一个出牌者座位
        if maxseat then
            -- local fine = math.floor(self.conf.ante * self:getPlayingSize() * 0.1)
            local fine = math.floor(self.conf.ante * 1) -- Domino Pass惩罚金额改为1倍Ante
            maxseat.chips = maxseat.chips + fine -- 增加身上金额
            seat.chips = seat.chips - fine
            maxseat.room_delta = maxseat.room_delta + fine
            maxseat.profit = maxseat.profit + fine
            seat.room_delta = seat.room_delta - fine
            seat.profit = seat.profit - fine
        end
        seat:chipin(type, value)
        log.info("idx(%s,%s) pass card %s,%s", self.id, self.mid, value, cjson.encode(seat.handcards))
        return true
    end

    local switch = {
        [pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD")] = discard_func, -- 出牌函数
        [pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS")] = pass_func -- 过牌函数
    }

    local chipin_func = switch[type]
    if not chipin_func then -- 如果对应的函数不存在
        log.info("idx(%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, uid, type)
        return false
    end

    -- 真正操作chipin
    if chipin_func(seat, type, value) then -- 如果成功执行出牌或过牌函数
        if type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS") then
            seat.passcnt = seat.passcnt + 1
            self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS")) -- 过牌支付
        else
            self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD")) -- 出牌
        end
        return true
    end
    return false
end

-- 玩家出牌
-- 参数 uid: 出牌者玩家ID
-- 参数 type: 2:出牌(PBDominoChipinType_DISCARD)，3：过牌
-- 参数 values: 要出的牌数据(可以为负数) 负数在左
-- 参数 client： 是否是客户端自己出牌  true表示是玩家自己出的牌
function Room:userchipin(uid, type, values, client)
    uid = uid or 0
    type = type or 0
    values = values or 0
    if -- self.state == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_None") or
        --     self.state == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish")
        self.state ~= pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Betting") then -- 只有出牌阶段才可以出牌
        log.info("idx(%s,%s) [error] user chipin state invalid:%s", self.id, self.mid, self.state)
        return false
    end

    local chipin_seat = self:getSeatByUid(uid) -- 出牌者所在座位
    if not chipin_seat then
        log.info("idx(%s,%s) [error] invalid chipin seat, uid=%s", self.id, self.mid, uid)
        return false
    end

    if not self:checkCanChipin(chipin_seat, type) then -- 检测是否轮到该玩家出牌
        log.info(
            "[error] idx(%s,%s) invalid chipin pos,uid=%s,sid=%s,current_pos=%s",
            self.id,
            self.mid,
            uid,
            chipin_seat.sid,
            self.current_betting_pos
        )
        return false
    end
    -- 防止多次出牌
    if chipin_seat.bettingtime > global.ctsec() then -- 开始时刻
        log.info("[error]idx(%s,%s) uid=%s has chipin,type=%s,values=%s", self.id, self.mid, uid, type, values)
        return false
    end
    if self.conf.minchip == 0 then -- ??
        log.info("idx(%s,%s) [error] chipin minchip invalid uid:%s", self.id, self.mid, uid)
        return false
    end

    if client then -- 如果是玩家自己出牌
        chipin_seat.bet_timeout_count = 0
    end

    local jointype = 0 -- 默认为过牌，不可以出这张牌

    if type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD") then -- 如果是出牌
        jointype = self.poker:checkJoinable(values) -- 判断是否可以出这张牌
        if jointype == 0 then
            log.info(
                "idx(%s,%s) [error] uid=%s,type=%s,jointype=0, values=%s, isclient=%s",
                self.id,
                self.mid,
                uid,
                type,
                tostring(values),
                (client and 1 or 0)
            )
            return false
        else
            if values < 0 and (jointype & 1 ~= 1) then
                if (jointype & 2) == 2 then
                    values = -values
                end
            elseif values > 0 and (jointype & 2 ~= 2) then
                if (jointype & 1) == 1 then
                    values = -values
                end
            end
        end
    end

    -- 下面是有玩家出牌或过牌的情况
    -- timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    log.info(
        "idx(%s,%s) userchipin(...): uid=%s, sid=%s type=%s, value=%s, isclient=%s",
        self.id,
        self.mid,
        tostring(uid),
        tostring(chipin_seat.sid),
        tostring(type), -- 2:出牌  3:过牌
        tostring(values),
        (client and 1 or 0)
    )

    local ret = self:chipin(uid, type, values) -- 真正出牌或过牌
    if not ret then
        log.info("idx(%s,%s) [error] client=%s,values=%s", self.id, self.mid, (client and 1 or 0), tostring(values))
        return false
    end

    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    -- 添加操作记录
    self.sdata.users = self.sdata.users or {}
    self.sdata.users[uid] = self.sdata.users[uid] or {}
    self.sdata.users[uid].ugameinfo = self.sdata.users[uid].ugameinfo or {}
    self.sdata.users[uid].ugameinfo.texas = self.sdata.users[uid].ugameinfo.texas or {}
    self.sdata.users[uid].ugameinfo.texas.pre_bets = self.sdata.users[uid].ugameinfo.texas.pre_bets or {}
    if type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD") then
        self.lastOutCard = values
        table.insert(self.sdata.users[uid].ugameinfo.texas.pre_bets, {uid = uid, bt = tostring(type), bv = values})
    else
        local fine = math.floor(self.conf.ante * 1)
        if
            chipin_seat.sid == self.maxraisepos and
                type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS")
         then
            fine = 0
        end
        table.insert(self.sdata.users[uid].ugameinfo.texas.pre_bets, {uid = uid, bt = tostring(type), bv = fine})
    end
    chipin_seat.bettingtime = global.ctsec() + 40000 -- 防止重复操作 2021-10-21

    -- 检测是否死亡结束
    if
        chipin_seat.sid == self.maxraisepos and
            type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS")
     then -- 3
        -- 死亡结束了
        log.info("idx(%s,%s) death finished", self.id, self.mid)
        if self:checkFinish(chipin_seat, 0, 0) then
            return true
        end
    end

    if self:checkFinish(chipin_seat, jointype, values) then -- 检测是否为普通结束(有人出完了手中牌)
        log.info("idx(%s,%s) normal finished", self.id, self.mid)
        return true
    end

    if jointype > 0 then
        self.maxraisepos = chipin_seat.sid
    end

    -- 定时通知下一个玩家出牌TimerID_Next
    if type == pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD") then
        timer.tick(self.timer, TimerID.TimerID_Next[1], TimerID.TimerID_Next[2], onNextPlayerBet, self)
    else
        timer.tick(self.timer, TimerID.TimerID_Next[1], 4000, onNextPlayerBet, self) --之前是2000
    end

    -- self:betting(next_seat) -- 下一个玩家出牌

    return true
end

-- 进入下一个状态
function Room:getNextState()
    local oldstate = self.state -- 当前状态

    if oldstate == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_PreChips") then
        self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_HandCard") -- 进入发牌阶段
        log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态
        self:dealHandCards()
    elseif oldstate == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish") then
        self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_None")
        log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态
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
    self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_PreChips")
    log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态
    onStartHandCards(self)
end

--deal handcards
-- dqw 发牌
function Room:dealHandCards()
    local cfgcardidx = 0

    for k, seat in ipairs(self.seats) do
        local user = nil
        if seat.uid then
            user = self.users[seat.uid]
        end
        if user and seat.isplaying then
            cfgcardidx = cfgcardidx + 1
            if self.config_switch then
            else
                seat.handcards = self.poker:getNCard(7) -- 获取7张牌
            end

            local cards = {
                cards = {{sid = k, handcards = g.copy(seat.handcards)}}
            }
            net.send(
                user.linkid,
                seat.uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoDealCard"),
                pb.encode("network.cmd.PBDominoDealCard", cards)
            )
            log.info(
                "idx(%s,%s) sid:%s,uid:%s deal handcard:%s",
                self.id,
                self.mid,
                k,
                seat.uid,
                string.format(
                    "0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x,0x%04x",
                    seat.handcards[1] & 0xFFFF,
                    seat.handcards[2] & 0xFFFF,
                    seat.handcards[3] & 0xFFFF,
                    seat.handcards[4] & 0xFFFF,
                    seat.handcards[5] & 0xFFFF,
                    seat.handcards[6] & 0xFFFF,
                    seat.handcards[7] & 0xFFFF
                )
            )

            -- log.info("idx(%s,%s) sid:%s,uid:%s deal handcard:%s", self.id, self.mid, k, seat.uid, cjson.encode(cards))

            self.sdata.users = self.sdata.users or {}
            self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
            self.sdata.users[seat.uid].sid = k
            self.sdata.users[seat.uid].username = user.username
            self.sdata.users[seat.uid].cards = g.copy(seat.handcards) -- 初始手牌
            if k == self.buttonpos then
                self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
            else
                self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
            end
        end
    end

    -- 通知该桌不参与游戏的玩家
    for k, v in pairs(self.users) do
        --self:userLeave(k, v.linkid)
        local isPlaying = false
        if v and v.linkid then
            -- 查看该玩家是否参与游戏
            for k2, seat in ipairs(self.seats) do
                if k == seat.uid then
                    if seat.isplaying then
                        isPlaying = true
                        break
                    end
                end
            end
            if not isPlaying then
                local cards = {
                    cards = {}
                }
                net.send(
                    v.linkid,
                    k,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoDealCard"),
                    pb.encode("network.cmd.PBDominoDealCard", cards)
                )
            end
        end
    end

    log.info("idx(%s,%s) playercount=%s", self.id, self.mid, self:getPlayingSize())
    timer.tick(
        self.timer,
        TimerID.TimerID_HandCardsAnimation[1],
        1400 + 700 * self:getPlayingSize() + 500,
        onHandCardsAnimation,
        self
    )
    log.info("idx(%s,%s) timer end", self.id, self.mid)
end

function Room:isAllFold()
    return false
end

-- 当前底池
function Room:getOnePot()
    return self.pot
end

-- 出牌超时
local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos] -- 当前出牌的座位
        log.info(
            "idx(%s,%s) onBettingTimer over time bettingpos:%s uid:%s",
            self.id,
            self.mid,
            self.current_betting_pos,
            current_betting_seat.uid or 0
        )
        --local user = self.users[current_betting_seat.uid]
        if current_betting_seat then
            local discard = current_betting_seat:findDiscardCard() -- 查找可出的牌
            if discard == 0 or current_betting_seat:isChipinTimeout() then
                timer.cancel(self.timer, TimerID.TimerID_Betting[1]) -- 关闭定时器

                if discard ~= 0 then -- 找到可出的牌
                    current_betting_seat.bet_timeout_count = current_betting_seat.bet_timeout_count + 1
                    self:userchipin(
                        current_betting_seat.uid, -- 出牌者玩家ID
                        pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_DISCARD"), -- 出牌 2
                        discard -- 要出的牌
                    )
                else -- 没有可出的牌
                    self:userchipin(
                        current_betting_seat.uid, -- 过牌者玩家ID
                        pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_PASS"), -- 过牌 3
                        discard
                    )
                end
            end
        else
            -- 还未超时(等待下一次)
            log.info("idx(%s,%s) onBettingTimer(.) not timeout", self.id, self.mid)
        end
    end
    g.call(doRun)
end

-- 指定座位玩家出牌()
function Room:betting(seat)
    if not seat then
        return false
    end
    seat.bettingtime = global.ctsec() -- 开始时刻
    self.current_betting_pos = seat.sid --座位号
    log.info("idx(%s,%s) it's betting pos:%s uid:%s", self.id, self.mid, self.current_betting_pos, tostring(seat.uid))

    -- 通知所有玩家轮到该玩家出牌了
    local function notifyBetting()
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_BETING")) -- 正要出牌

        -- 判断当前玩家是否可以出牌
        local current_betting_seat = self.seats[self.current_betting_pos] -- 当前出牌的座位
        local timerLength = TimerID.TimerID_Betting[2] -- 定时时长
        if current_betting_seat then -- 判断是否超时
            local discard = current_betting_seat:findDiscardCard() -- 查找可出的牌
            if discard == 0 then -- 如果没有可出的牌
                timerLength = 1000
                onBettingTimer(self) -- 直接通知玩家过牌
                return true
            end
        end
        timer.tick(self.timer, TimerID.TimerID_Betting[1], timerLength, onBettingTimer, self) -- 启动出牌超时定时器(超时后系统提醒或帮你出牌)
    end

    notifyBetting()
end

-- 本局游戏结束
function Room:finish()
    log.info("idx(%s,%s) finish", self.id, self.mid)

    self.hasCalcResult = false
    self.state = pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish") -- 进入结算状态
    log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态

    self.endtime = global.ctsec() -- 结束时刻
    self.t_msec = self:getPlayingSize() * 1000 + 5000

    -- m_seats.finish start
    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    local pot = self:getOnePot() -- 当前底池
    --self.winner_seats = self.winner_seats or self.seats[self.m_winner_sid] -- 赢家所在座位
    self.winner_seats = self.seats[self.m_winner_sid] -- 赢家所在座位
    -- self.winner_seats.chips = (self.winner_seats.chips or 0) + (pot * 0.85) -- 增加金额

    local FinalGame = {
        potInfos = {},
        potMoney = pot, -- 奖池中金额
        --readyLeftTime = (self.t_msec / 1000 + TimerID.TimerID_Check[2] / 1000) - (global.ctsec() - self.endtime),
        readyLeftTime = TimerID.TimerID_OnFinish[2] / 1000,
        finishType = self.finish_type,
        winTimes = self.m_multiple
    }

    local reviewlog = {
        buttonsid = self.buttonpos,
        ante = self.conf.ante,
        pot = self:getOnePot(),
        items = {}
    }
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            local win = -self.conf.ante * self.m_multiple -- 输家需要再输掉的金额(包括底注)
            --赢利
            if k == self.m_winner_sid then -- 如果该玩家是赢家
                -- win = pot * 0.85
                win = pot -- 赢家赢走整个奖池 2021-10-14
            end
            v.room_delta = v.room_delta + win --
            v.profit = v.profit + win
            v.last_chips = v.chips
            v.chips = v.chips + win -- 身上筹码
            log.info(
                "idx(%s,%s) chips change uid:%s chips:%s last_chips:%s totalwin:%s, roomdelta:%s, profit=%s",
                self.id,
                self.mid,
                v.uid, -- 玩家ID
                v.chips, -- 当前身上筹码
                v.last_chips,
                v.chips - v.last_chips, -- 输赢情况
                v.room_delta, --
                v.profit
            )

            --盈利扣水
            if v.profit > 0 and (self.conf.rebate or 0) > 0 then
                local rebate = math.floor(v.profit * self.conf.rebate)
                v.profit = v.profit - rebate
                v.chips = v.chips - rebate
            end

            self.sdata.users = self.sdata.users or {}
            self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
            --self.sdata.users[v.uid].totalpureprofit = v.room_delta -- 纯盈利?
            self.sdata.users[v.uid].totalpureprofit = v.profit -- 当前局纯盈利

            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {}
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1 -- 该玩家玩的局数相对之前增加的局数
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (win > 0) and 1 or 0 -- 该玩家赢的局数
            if self.finish_type == pb.enum_id("network.cmd.PBDominoFinishType", "PBDominoFinishType_Death") then
                self.sdata.users[v.uid].ugameinfo.texas.incpreflopraisehands = 1
            else
                self.sdata.users[v.uid].ugameinfo.texas.incpreflopraisehands = 0
            end
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips
            self.sdata.users[v.uid].extrainfo =
                cjson.encode(
                {
                    ip = user.ip or "",
                    api = user.api or "",
                    roomtype = self.conf.roomtype,
                    groupcard = "", -- cjson.encode(v:formatGroupCards())
                    finishType = self.finish_type, -- 结束方式:2：死亡结束 和 1：普通结束
                    winTimes = self.m_multiple, -- 输赢倍数：1,2,3,4
                    playchips = 20 * (self.conf and self.conf.fee or 0) -- 2021-12-24
                }
            )

            table.insert(
                FinalGame.potInfos,
                {
                    sid = v.sid,
                    winMoney = v.chips - v.last_chips, -- 玩家赢的金额，不考虑服务费及pass的情况
                    seatMoney = v.chips,
                    nickname = user.username,
                    nickurl = user.nickurl,
                    handcards = g.copy(v.handcards), -- 手牌
                    passcnt = v.passcnt,
                    point = self.poker:getTotalPoint(v.handcards),
                    profit = v.profit
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
                    wintype = self.finish_type,
                    win = v.profit,
                    showcard = true,
                    point = self.poker:getTotalPoint(v.handcards),
                    passcnt = v.passcnt,
                    profit = v.profit
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
                nickname = v.player.username,
                nickurl = v.player.nickurl,
                handcards = g.copy(v.handcards),
                passcnt = v.passcnt,
                point = self.poker:getTotalPoint(v.handcards),
                profit = v.profit
            }
        )
    end
    self.reviewlogs:push(reviewlog)
    self.reviewlogitems = {}
    self.winner_seats = nil

    -- 广播结算
    log.info("idx(%s,%s) PBDominoFinalGame %s", self.id, self.mid, cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBDominoFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoFinalGame"),
                pointer,
                length
            )
        end
    )

    self.m_winner_sid = 0
    self.sdata.etime = self.endtime

    -- -- 已出牌数据(公共牌数据)
    self.sdata.cards = {}
    self.sdata.cards[1] = {}
    self.sdata.cards[1].cards = g.copy(self.poker.discardCards)

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
    --log.info("idx(%s,%s) appendLogs(),self.sdata=%s", self.id, self.mid, cjson.encode(self.sdata))
    self.statistic:appendLogs(self.sdata, self.logid)
    self.hasCalcResult = true
    --log.info("idx(%s,%s) appendLogs() end", self.id, self.mid)
    timer.tick(self.timer, TimerID.TimerID_OnFinish[1], TimerID.TimerID_OnFinish[2], onFinish, self)
end

-- dqw 准备阶段
function Room:check()
    if global.stopping() then
        return
    end

    -- 准备好的玩家数(本桌正在玩的玩家数目)
    local cnt = self:getPlayingSize()

    log.info("idx(%s,%s) room:check playing size=%s", self.id, self.mid, cnt)

    --if cnt < 4 then
    timer.cancel(self.timer, TimerID.TimerID_Betting[1]) -- 取消下注定时器
    timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])
    timer.cancel(self.timer, TimerID.TimerID_HandCardsAnimation[1])

    timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 启动检测定时器
    timer.tick(self.timer, TimerID.TimerID_CheckRobot[1], TimerID.TimerID_CheckRobot[2], onCheckRobot, self) -- 启动检测定时器
    -- else
    --     -- 立即开始游戏
    --     self:start()
    -- end
end

-- 玩家站起
function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req stand up uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local s = self:getSeatByUid(uid)
    local user = self.users[uid]
    if s and user and self:canStand(uid) then
        -- TODO:站起
        self:stand(s, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))

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
        if user then
            user.toStand = true -- 将要自动站起
        end
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasStandFailed"), -- 站起失败消息ID
            pb.encode(
                "network.cmd.PBTexasStandFailed",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")}
            )
        )
        log.debug("userStand() stand failed")
    end
end

-- 玩家坐下
function Room:userSit(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req sit down uid:%s", self.id, self.mid, tostring(self.logid), uid)

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid) -- 原座位
    local dsts = self.seats[rev.sid] -- 目的座位

    -- 如果玩家不存在(不在该房间) 或 已经在某座位坐下了 或者 目的座位不存在 或 目的座位上已有其它玩家，则坐下失败
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
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitFailed"), -- 坐下失败消息
            pb.encode(
                "network.cmd.PBTexasSitFailed",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")}
            )
        )
    else
        self:sit(dsts, uid, self:getRecommandBuyin(self:getUserMoney(uid)))
    end
end

-- 玩家买入筹码
-- 参数 system: 是否由系统自动买入
-- 返回值: 成功买入则返回true,失败则返回false.
function Room:userBuyin(uid, linkid, rev, system)
    log.info(
        "idx(%s,%s,%s) userBuyin uid %s buyinmoney %s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        tostring(rev.buyinMoney) -- 要买入的筹码量
    )

    local buyinmoney = rev.buyinMoney or 0

    local function handleFailed(code)
        net.send( -- 发送买入失败消息
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

    if user.buyin and coroutine.status(user.buyin) ~= "dead" then -- 如果正在买入(尚未结束)
        log.info("idx(%s,%s,%s) uid %s userBuyin is buying", self.id, self.mid, tostring(self.logid), uid)
        return false
    end

    local seat = self:getSeatByUid(uid)
    if not seat then -- 如果还未坐下
        log.info("idx(%s,%s,%s) Room:userBuyin() invalid seat", self.id, self.mid, tostring(self.logid))
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidSeat"))
        return false
    end

    if Utils:isRobot(user.api) and (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.ante) then
        buyinmoney = self.conf.maxbuyinbb * self.conf.ante - (seat.chips - seat.roundmoney)
    end

    if
        (buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.ante) or
            (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.ante)
     then
        log.info(
            "idx(%s,%s,%s) Room:userBuyin(), over limit: minbuyinbb %s, maxbuyinbb %s, ante %s",
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

    -- 开始准备买入
    user.buyin =
        coroutine.create(
        function(user)
            log.info(
                "idx(%s,%s,%s) uid=%s userBuyin start buyinmoney=%s, seatchips %s money %s coin %s",
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
            local ok = coroutine.yield() -- 等待结果
            timer.cancel(self.timer, TimerID.TimerID_Buyin[1] + 100 + uid)
            if not ok then -- 如果买入失败
                log.info(
                    "idx(%s,%s,%s) userBuyin not enough money: buyinmoney %s, user money %s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    buyinmoney,
                    self:getUserMoney(uid)
                )
                handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_NotEnoughMoney")) -- 发送买入失败消息
                return false
            end

            -- 下面是成功买入的情况
            seat:buyin(buyinmoney) --
            seat:setIsBuyining(false) -- 买入完成
            user.totalbuyin = seat.totalbuyin -- 玩家总买入

            seat:buyinToChips() -- 将买入金额转换为筹码

            pb.encode(
                "network.cmd.PBTexasPlayerBuyin",
                {
                    sid = seat.sid,
                    chips = seat.chips > seat.roundmoney and seat.chips - seat.roundmoney or 0, -- 身上剩余筹码
                    money = self:getUserMoney(uid), -- 身上金额
                    context = rev.context,
                    immediately = true
                },
                function(pointer, length)
                    self:sendCmdToPlayingUsers( -- 发送给该桌正在玩的玩家
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerBuyin"),
                        pointer,
                        length
                    )
                end
            )
            log.info(
                "idx(%s,%s,%s) uid %s userBuyin result buyinmoney=%s, seat.chips=%s, money=%s, coin=%s",
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
        if seat.chips < (self.conf and self.conf.toolcost or 0) then
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
    log.info("idx(%s,%s) userReview uid %s", self.id, self.mid, uid)

    local t = {
        reviews = {}
    }
    local function resp()
        log.info("idx(%s,%s) PBDominoReviewResp %s", self.id, self.mid, cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DominoReviewResp"),
            pb.encode("network.cmd.PBDominoReviewResp", t)
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
                self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_BETING"))
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

-- 踢出该桌所有玩家
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

-- 判断是否可以更新房间
function Room:canChangeRoom(uid)
    if
        self.state < pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Start") or
            self.state == pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish")
     then
        return true
    end

    for k, v in ipairs(self.seats) do -- 遍历所有座位
        if v and v.uid == uid and not v.isplaying then
            return true
        end
    end

    return false
end

function Room:userWalletResp(rev)
    if not rev.data or #rev.data == 0 then
        return
    end
    for _, v in ipairs(rev.data) do
        local seat = self:getSeatByUid(v.uid)
        local user = self.users[v.uid]
        if user and seat then
            log.info("(%s,%s) userWalletResp %s", self.id, self.mid, cjson.encode(rev))
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

-- 获取这一局的输赢情况
function Room:getCurrentProfit(uid)
    local currentProfit = 0
    local seat = self:getSeatByUid(uid)
    if seat then
        currentProfit = seat.profit or 0 -- 本局纯收益
    end
    return currentProfit
end

-- 获取从坐下到现在总的收益
function Room:getTotalProfit(uid)
    local totalProfit = 0
    local seat = self:getSeatByUid(uid)
    if seat then
        totalProfit = seat.room_delta or 0 -- 总收益
    end
    return totalProfit
end

-- 检测指定玩家是否可以站起
-- 参数 uid: 待查看的玩家
-- 返回值: 若可以站起则返回true，否则返回false
function Room:canStand(uid)
    -- 若该玩家参与了游戏，且游戏开始了还未结束
    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if seat and user then
        if not seat.isplaying then -- 如果该玩家还未参与游戏
            return true
        end

        if self.state < pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Start") then
            return true
        elseif
            self.state >= pb.enum_id("network.cmd.PBDominoTableState", "PBDominoTableState_Finish") and
                self.hasCalcResult
         then
            return true
        end
        return false
    end
    return true
end

-- 检测指定玩家是否有足够筹码继续游戏，若筹码不足则提示买入筹码或让玩家站起
-- 返回值: 若有足够多筹码则返回true
function Room:hasEnoughChips(uid)
    return true
end
