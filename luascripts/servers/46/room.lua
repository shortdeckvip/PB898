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
require(string.format("luascripts/servers/%d/seat", global.stype()))
require(string.format("luascripts/servers/%d/reservation", global.stype()))
require(string.format("luascripts/servers/%d/seotda", global.stype()))


Room = Room or {}

-- 默认牌数据(共20张)
local default_poker_table = {
    0x11,
    0x12,
    0x21,
    0x22,
    0x31,
    0x32,
    0x41,
    0x42,
    0x51,
    0x52,
    0x61,
    0x62,
    0x71,
    0x72,
    0x81,
    0x82,
    0x91,
    0x92,
    0xA1,
    0xA2
}

local TimerID = {
    TimerID_Check = { 1, 1000 }, -- id, interval(ms), timestamp(ms)  check定时器
    TimerID_Start = { 2, 4000 }, -- id, interval(ms), timestamp(ms)
    TimerID_Betting = { 3, 18000 }, -- id, interval(ms), timestamp(ms)  下注定时器(下注超时使用)
    TimerID_PrechipsRoundOver = { 5, 1000 }, -- id, interval(ms), timestamp(ms)  交前注定时器
    TimerID_StartPreflop = { 6, 1000 }, -- id, interval(ms), timestamp(ms)
    TimerID_OnFinish = { 7, 1000 }, -- id, interval(ms), timestamp(ms)
    TimerID_Timeout = { 8, 2000 }, -- id, interval(ms), timestamp(ms)
    TimerID_MutexTo = { 9, 2000 }, -- id, interval(ms), timestamp(ms)
    TimerID_Buyin = { 11, 1000 },
    TimerID_Expense = { 14, 5000 },
    TimerID_ShowOneCard = { 15, 10000 }, -- 等待显示牌
    TimerID_SelectCompareCards = { 16, 10000 }, -- 选择要比较的牌
    TimerID_Result = { 17, 1200 },
    TimerID_ReplayChips = { 18, 10000 }, -- 等待补足筹码重赛
    TimerID_WaitBet = { 19, 3000 }, -- 等待进入下注阶段

}

-- 玩家状态
local EnumUserState = { Playing = 1, Leave = 2, Logout = 3, Intoing = 4 }


-- 参数 seat: 座位对象
-- 返回值: 返回座位信息
local function fillSeatInfo(seat, self)
    local seatinfo = {}
    seatinfo.seat = { sid = seat.sid, playerinfo = {} }

    local user = self.users[seat.uid]
    seatinfo.seat.playerinfo = { -- 该座位玩家信息
        uid = seat.uid or 0,
        username = user and user.username or "",
        gender = user and user.sex or 0,
        nickurl = user and user.nickurl or ""
    }

    --seatinfo.isPlaying = seat.isplaying and 1 or 0 -- 该座位玩家是否参与游戏
    seatinfo.isPlaying = 0 -- 该座位玩家是否参与游戏
    -- if seat.isplaying and ((seat.state & 2) ~= 0) then  -- 如果该玩家参与游戏 且 坐下
    --     seatinfo.isPlaying = 1
    -- end
    if not seat.hasLeave then -- 如果该玩家还未离开
        seatinfo.isPlaying = 1
    end


    seatinfo.seatMoney = (seat.chips > seat.roundmoney) and (seat.chips - seat.roundmoney) or 0 -- 剩余筹码
    seatinfo.chipinMoney = seat.roundmoney -- 当前下注额
    seatinfo.chipinType = seat.chiptype -- 操作类型

    -- seatinfo.chipinNum = (seat.roundmoney > seat.chipinnum) and (seat.roundmoney - seat.chipinnum) or 0 --??

    local left_money = seat.chips -- 剩余金额
    local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or { roundmoney = 0 } -- 开局前maxraisepos == 0

    local needcall = self:getRoundMaxBet()
    needcall = math.ceil(needcall / self.minchip) * self.minchip
    if left_money < needcall then
        needcall = left_money
    end

    seatinfo.needCall = needcall -- 跟注所需金额
    seatinfo.chipinTime = seat:getChipinLeftTime() -- 下注剩余时长
    seatinfo.onePot = self:getOnePot() -- 该局总下注金额
    --seatinfo.reserveSeat = seat.rv:getReservation()
    seatinfo.totalTime = seat:getChipinTotalTime()
    seatinfo.addtimeCost = self.conf.addtimecost
    seatinfo.addtimeCount = seat.addon_count
    seatinfo.totalChipin = seat.total_bets or 0
    if seat:getIsBuyining() then
        seatinfo.chipinType = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_BUYING") -- 正在买入
        seatinfo.chipinTime = self.conf.buyintime - (global.ctsec() - (seat.buyin_start_time or 0))
        seatinfo.totalTime = self.conf.buyintime
    end
    if seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then
        seat.odds = seatinfo.onePot == 0 and 0 or (seatinfo.needCall - seatinfo.chipinMoney) / seatinfo.onePot
    end
    seatinfo.raiseHalf = (seatinfo.onePot + seatinfo.needCall) / 2 + seatinfo.needCall -- 1/2底池加注 =(当前底池总量  + needcall) * 1/2 + needcall
    seatinfo.raiseHalf = math.floor(seatinfo.raiseHalf / self.minchip) * self.minchip
    seatinfo.raiseQuarter = (seatinfo.onePot + seatinfo.needCall) / 4 + seatinfo.needCall -- 1/4底池加注 =(当前底池总量  + needcall) * 1/4 + needcall
    seatinfo.raiseQuarter = math.floor(seatinfo.raiseQuarter / self.minchip) * self.minchip
    seatinfo.raise = seatinfo.needCall * 2
    if (seat.operateTypes & (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK"))) > 0 then -- 是否过牌了
        seatinfo.hasCheck = true
    else
        seatinfo.hasCheck = false
    end
    seatinfo.playerState = seat.playerState or 0
    if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips") then
        if seat.playerState == 1 then
            seatinfo.replayChips = self.seats[self.maxraisepos].total_bets - seat.total_bets
        else
            seatinfo.replayChips = 0
        end
        seatinfo.replayLeftTime = math.abs(TimerID.TimerID_ReplayChips[2] - (global.ctms() - self.stateBeginTime)) -- 剩余时长(毫秒)
    end
    seatinfo.cardsNum = seat.cardsNum -- 手牌张数
    seatinfo.roundMaxBet = self:getRoundMaxBet()
    seatinfo.operateTypes = seat.operateTypes
    seatinfo.operateTypesRound = seat.operateTypesRound
    seatinfo.showCard = seat.firstShowCard or 0

    seatinfo.canFold = true
    if self.current_betting_pos == seat.sid then -- 如果轮到该玩家操作
        seatinfo.canCheck = false
        seatinfo.canCall = false
        seatinfo.canMinBet = false
        seatinfo.canRaise = false
        seatinfo.canRaiseHalf = false
        seatinfo.canRaiseQuarter = false
        seatinfo.canAllIn = false

        -- 第一轮操作规则：
        -- (1)前面没有玩家下注情况下（第一个操作玩家同理），只可以 다이（弃牌）或者하프（1/2底池）
        -- (2) 第一轮操作每个玩家只可以加注一次
        -- (3) 第一轮加注选项只有1/2底池
        if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then
            if seatinfo.roundMaxBet == 0 then -- 如果还没有玩家操作过
                if seatinfo.seatMoney >= seatinfo.raiseHalf then
                    seatinfo.canRaiseHalf = true
                elseif seatinfo.seatMoney > 0 then
                    seatinfo.canAllIn = true
                end
            else
                if seatinfo.chipinMoney == 0 then -- 如果该玩家还未加注过
                    if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.raiseHalf then
                        seatinfo.canRaiseHalf = true
                    elseif seatinfo.seatMoney > 0 then
                        seatinfo.canAllIn = true
                    end
                    if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.roundMaxBet then
                        seatinfo.canCall = true
                    elseif seatinfo.seatMoney > 0 then
                        seatinfo.canAllIn = true
                    end
                else
                    if seatinfo.chipinMoney >= seatinfo.roundMaxBet then
                        seatinfo.canCheck = true
                    end
                    if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.roundMaxBet then
                        seatinfo.canCall = true
                    elseif seatinfo.seatMoney > 0 then
                        seatinfo.canAllIn = true
                    end
                    -- 判断是否已经加注过
                    if (
                        seat.operateTypes &
                            (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2"))) == 0 then -- 如果还未加注过
                        if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.raiseHalf then
                            seatinfo.canRaiseHalf = true
                        elseif seatinfo.seatMoney > 0 then
                            seatinfo.canAllIn = true
                        end
                    end
                end
            end
        else -- 第二轮及之后下注
            -- 第二轮操作规则:
            -- (1) 玩家加注选项固定，即没有自由加注额度
            -- (2) check过的玩家不可以再加注
            if seatinfo.roundMaxBet == 0 and seatinfo.seatMoney >= self.minchip then -- 如果这一轮还没有玩家下注
                seatinfo.canMinBet = true
            end
            if seatinfo.chipinMoney >= seatinfo.roundMaxBet then
                seatinfo.canCheck = true
            end
            if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.roundMaxBet then
                seatinfo.canCall = true
            elseif seatinfo.seatMoney > 0 then
                seatinfo.canAllIn = true
            end

            if not seatinfo.hasCheck then -- 如果还未check过
                -- 判断是否可以加注
                if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.raise then
                    seatinfo.canRaise = true
                elseif seatinfo.seatMoney > 0 then
                    seatinfo.canAllIn = true
                end
                if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.raiseHalf then
                    seatinfo.canRaiseHalf = true
                elseif seatinfo.seatMoney > 0 then
                    seatinfo.canAllIn = true
                end
                if seatinfo.chipinMoney + seatinfo.seatMoney >= seatinfo.raiseQuarter then
                    seatinfo.canRaiseQuarter = true
                elseif seatinfo.seatMoney > 0 then
                    seatinfo.canAllIn = true
                end
            end
        end
        log.debug("idx(%s,%s,%s) fillSeatInfo(),uid=%s,state=%s,seatinfo=%s", self.id,
            self.mid, self.logid, seat.uid, self.state, cjson.encode(seatinfo))
    end

    return seatinfo
end

-- 填充该桌所有座位信息
local function fillSeats(self)
    local seats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        local seatinfo = fillSeatInfo(seat, self)
        table.insert(seats, seatinfo)
    end
    return seats
end

local function onBet1(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_WaitBet[1])
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1")) -- 第一轮下注状态
    end

    g.call(doRun)
end

-- 买入超时处理
local function onBuyin(t)
    local function doRun()
        local self = t[1]
        local uid = t[2]
        timer.cancel(self.timer, TimerID.TimerID_Buyin[1] + 100 + uid) -- 关闭买入定时器
        local seat = self:getSeatByUid(uid)
        if seat then
            local user = self.users[uid]
            if user and user.buyin and coroutine.status(user.buyin) == "suspended" then
                coroutine.resume(user.buyin, false)
            else
                self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_BuyinFailed")) -- 买入失败站起
            end
        end
    end

    g.call(doRun)
end

-- 显示一张牌
local function onShowOneCard(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_ShowOneCard[1])

        -- 通知所有玩家哪些玩家显示了牌
        local allSeatsShow = {}
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying then
                if not seat.firstShowCard or seat.firstShowCard == 0 then
                    seat.firstShowCard = seat.handcards[1]
                    seat.secondCard = seat.handcards[2]
                end
                table.insert(allSeatsShow, { sid = seat.sid, card = seat.firstShowCard })
            end
        end

        pb.encode(
            "network.cmd.PBSeotdaShowOneCardResp",
            { allSeats = allSeatsShow },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaShowOneCardResp"),
                    pointer,
                    length
                )
            end
        )
        log.debug("idx(%s,%s,%s) userShowOneCardReq(),PBSeotdaShowOneCardResp=%s", self.id, self.mid, self.logid,
            cjson.encode(allSeatsShow))

        timer.tick(self.timer, TimerID.TimerID_WaitBet[1], TimerID.TimerID_WaitBet[2], onBet1, self) -- 定时
    end

    g.call(doRun)
end

-- 选择要比较的牌
local function onSelectCompareCards(self)
    local function doRun()
        log.debug("idx(%s,%s,%s) onSelectCompareCards()", self.id, self.mid, self.logid)
        timer.cancel(self.timer, TimerID.TimerID_SelectCompareCards[1])

        -- 进入比牌阶段
        self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Dueling"))
        self:compareCards() -- 比牌
    end

    g.call(doRun)
end

-- 等待补足筹码重赛
local function onReplayChips(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_ReplayChips[1])

        self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReDealCards")) -- 重新发牌

        local allSeatsState = {}
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying then
                if seat.playerState == 1 then
                    seat.playerState = 3 -- 默认不重赛
                end
                table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
            end
        end
        -- 通知所有玩家哪些玩家需要重赛
        pb.encode(
            "network.cmd.PBSeotdaReplayState",
            { allSeats = allSeatsState, replayType = self.replayType },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReplayState"),
                    pointer,
                    length
                )
            end
        )
        log.debug("idx(%s,%s,%s) onReplayChips(),PBSeotdaReplayState=%s", self.id, self.mid, self.logid,
            cjson.encode(allSeatsState))

        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReDealCards")) -- 重赛发牌
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3")) -- 进入下注状态
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
                log.info("idx(%s,%s,%s) onCheck(),user logout.uid=%s,logoutts=%s,currentts=%s", self.id, self.mid,
                    self.logid, user.uid or 0, user.logoutts, global.ctsec())
                self:userLeave(uid, linkid)
            end
        end
        -- check all seat users issuses
        for k, seat in pairs(self.seats) do -- 遍历所有座位
            seat:reset() -- 重置座位
            local user = self.users[seat.uid]
            if user then -- 如果该座位的玩家存在
                local linkid = user.linkid
                local uid = seat.uid
                -- 超时两轮自动站起
                if user.is_bet_timeout and user.bet_timeout_count >= 2 then
                    log.debug("idx(%s,%s,%s) onCheck(),uid=%s,bet_timeout_count=%s", self.id, self.mid, self.logid,
                        user.uid, user.bet_timeout_count)
                    -- 处理筹码为 0 的情况
                    self:stand(
                        seat,
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_ReservationTimesLimit")
                    )
                    user.is_bet_timeout = nil
                    user.bet_timeout_count = 0
                else -- 该座位玩家有效
                    -- seat:reset() -- 重置座位
                    if seat:hasBuyin() then -- 上局正在玩牌（非 fold）且已买入成功则下局生效
                        seat:buyinToChips()
                        if not Utils:isRobot(user.api) then
                            Utils:updateChipsNum(global.sid(), uid, seat.chips)
                        end
                        pb.encode(
                            "network.cmd.PBTexasPlayerBuyin", --
                            {
                                sid = seat.sid, -- 座位号
                                chips = seat.chips, -- 该座位筹码
                                money = self:getUserMoney(seat.uid), -- 玩家身上金额
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
                    if seat.chips > (self.conf and self.conf.ante + self.conf.fee or 0) then -- 如果筹码足够
                        seat.isplaying = true -- 本局参与游戏
                        seat.hasLeave = false
                        --seat.state = seat.state | 1
                    elseif seat.chips <= (self.conf and self.conf.ante + self.conf.fee or 0) then -- 如果筹码不够
                        seat.isplaying = false
                        seat.hasLeave = true
                        --seat.state = seat.state & 2
                        if seat:getIsBuyining() then -- 正在买入
                        elseif seat:totalBuyin() > 0 then -- 非第一次坐下待买入，弹窗补币
                            seat:setIsBuyining(true)
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
                                self.conf.buyintime * 1000, -- 设置买入定时器
                                onBuyin,
                                { self, uid }
                            )
                            -- 客户端超时站起
                        end
                    end
                end
            else -- 该座位玩家不存在
                seat.uid = nil
                seat.hasLeave = true
                -- seat.state = 0 -- 不参与游戏，也没玩家坐下
            end
        end

        if self:getPlayingSize() <= 1 then
            --log.debug("onCheck() getPlayingSize()=%s", self:getPlayingSize())
            return -- 继续检测
        end
        -- 至少有2人才开始游戏
        if self:getPlayingSize() > 1 and global.ctsec() > self.endtime then
            timer.cancel(self.timer, TimerID.TimerID_Check[1]) -- 关闭check定时器
            self:start()
        end
    end

    g.call(doRun)
end

-- 定时结算(清空桌子)
local function onFinish(self)
    self:checkLeave()
    local function doRun()
        log.info("idx(%s,%s,%s) onFinish()", self.id, self.mid, self.logid)
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

        self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None")) -- 进入check阶段
        self:reset()
        for sid, seat in ipairs(self.seats) do -- 遍历每个座位
            if seat then
                seat:flush()
            end
        end

        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 定时检测
    end

    g.call(doRun)
end

-- 下盲注结束
local function onStartPreflop(self)
    local function doRun()
        log.info(
            "idx(%s,%s,%s) onStartPreflop(),buttonpos=%s",
            self.id,
            self.mid,
            self.logid,
            self.buttonpos
        )
        timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])

        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCards1")) -- 第一轮发牌
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ShowOneCard")) -- 进入show牌状态(展示第一张牌)
    end

    g.call(doRun)
end

-- 预操作(交前注)结束
local function onPrechipsRoundOver(self)
    local function doRun()
        log.info("idx(%s,%s,%s) onPrechipsRoundOver()", self.id, self.mid, self.logid)
        timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1]) -- 关闭定时器
        self:roundOver() -- 一轮结束

        --检测是否游戏结束
        if self:checkGameOver() then
            self:finish() -- 立马结束游戏
        else
            timer.tick(self.timer, TimerID.TimerID_StartPreflop[1], TimerID.TimerID_StartPreflop[2], onStartPreflop, self)
        end
    end

    g.call(doRun)
end

-- 获取玩家身上金额
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
    timer.destroy(self.timer) -- 销毁定时器
    -- for _, seat in ipairs(self.seats) do
    --     seat.rv:destroy()
    -- end
end

-- 获取一张牌
function Room:getOneCard()
    self.pokeridx = self.pokeridx + 1
    return self.cards[self.pokeridx]
end

-- 获取剩余的牌(未调用)
function Room:getLeftCard()
    log.debug("idx(%s,%s,%s) getLeftCard()", self.id, self.mid, self.logid)
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

-- 房间初始化
function Room:init()
    self.conf = MatchMgr:getConfByMid(self.mid) or {} -- 获取配置信息

    log.info("idx(%s,%s,%s) init(),conf=%s", self.id, self.mid, self.logid, cjson.encode(self.conf))

    self.users = {}

    self.timer = timer.create()
    self.pokeridx = 0 -- 已使用的牌张数(seotda只有20张牌)
    self.cards = {} -- 一副牌数据
    for _, v in ipairs(default_poker_table) do
        table.insert(self.cards, v)
    end

    self.gameId = 0 -- 该房间已开始的游戏局数

    self.state = pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None") -- 牌局状态(check状态、开始状态、第一轮下注状态、)
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.buttonpos = 0 -- 庄家所在位置(上一局赢家坐庄，若没有赢家，则随机一个玩家坐庄)
    self.minchip = self.conf and self.conf.minchip or 1 -- 最小筹码值(确保每次赢的金额是该筹码的整数倍)
    self.tabletype = self.conf.matchtype --比赛类型(1-常规场 2-SNG  3-MTT)
    self.conf.bettime = TimerID.TimerID_Betting[2] / 1000 -- 下注时长
    self.bettingtime = self.conf.bettime -- 总下注时间

    self.roundcount = 0 -- 已经过的轮数

    self.current_betting_pos = 0 -- 当前下注位置
    self.chipinpos = 0
    self.already_show_card = false
    self.maxraisepos = 0 -- 最大加注位置
    self.seats_totalbets = {} -- 各座位的总下注金额
    self.invalid_pot_sid = 0

    self.potidx = 1 -- 奖池数
    self.pots = { { money = 0, seats = {} } } -- 奖池(存放各奖池金额及各奖池参与者座位号)

    self.seats = {} -- 座位
    for sid = 1, self.conf.maxuser do
        local seat = Seat:new(self, sid)
        table.insert(self.seats, seat)
        table.insert(self.pots, { money = 0, seats = {} }) --
    end

    self.smallblind = self.conf and self.conf.sb or 50 -- 小盲
    self.bigblind = self.conf and self.conf.sb * 2 or 100 -- 大盲
    self.ante = self.conf and self.conf.ante or 0 -- 底注

    self.statistic = Statistic:new(self.id, self.conf.mid) -- 统计信息
    self.sdata = {
        -- moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }

    -- self.round_finish_time = 0      -- 每一轮结束时间  (preflop - flop - ...)
    self.starttime = 0 -- 牌局开始时间(秒)
    self.endtime = 0 -- 牌局结束时间(秒)

    self.table_match_start_time = 0 -- 开赛时间
    self.table_match_end_time = 0 -- 比赛结束时间

    self.chipinset = {}
    self.last_playing_users = {} -- 上一局参与的玩家列表

    self.finishstate = pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None")

    self.reviewlogs = LogMgr:new(5)

    -- 实时牌局
    self.reviewlogitems = {} -- 暂存站起玩家牌局
    -- self.recentboardlog = RecentBoardlog.new() -- 最近牌局

    -- 配牌
    self.cfgcard_switch = false
    self.cfgcard = cfgcard:new(
        {
            handcards = { -- 手牌数据
                0x91, 0x41, -- 멍텅구리구사 牌型
                0x92, 0x42, -- 구사 (9·4)) 牌型
                0x12,
                0x71,
                0x22,
                0x61,
                0x32,
                0x41,
                0x42,
                0x51,
                0x52,
                0x31,
                0x42,
                0x21,
                0x12,
                0x81,
                0x82
            }
        }
    )
    -- 主动亮牌
    self.lastchipintype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_NULL") -- 最近一次操作类型
    self.lastchipinpos = 0

    self.tableStartCount = 0
    self.logid = self.statistic:genLogId() or 0
    self.hasFind = false
    self.maxWinnerUID = 0 -- 最大赢家UID
    self.maxLoserUID = 0 -- 最大输家UID

    self.commonCards = {} -- 5张公共牌
    self.seatCards = {} -- 各座位的手牌(每人2张)
    self.seatCardsType = {} -- 各座位最大牌牌型
    self.maxCardsIndex = 0 -- 最大牌所在位置
    self.minCardsIndex = 0 -- 最小牌所在位置

    self.lastWinnerUID = 0 -- 上一局赢家UID(每局游戏结束时更新)
    self.has_player_inplay = false
    self.replayType = 0
    self.calcChipsTime = 0           -- 计算筹码时刻(秒)
     
end

-- 重新加载配置信息
function Room:reload()
    self.conf = MatchMgr:getConfByMid(self.mid)
end

--
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

-- 获取玩家数
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

-- 获取机器人数目
function Room:robotCount()
    local c = 0
    for k, v in pairs(self.users) do
        if Utils:isRobot(v.api) then
            c = c + 1
        end
    end
    return c
end

-- 该桌玩家数及机器人人数
function Room:count()
    local c, r = 0, 0
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user then
            c = c + 1 -- 所有坐下的玩家数(包括机器人)
            if Utils:isRobot(user.api) then
                r = r + 1 -- 所有坐下的机器人人数
            end
        end
    end
    return c, r
end

-- 检测
function Room:checkLeave()
    log.debug("idx(%s,%s,%s) checkLeave()", self.id, self.mid, self.logid)
    local c = self:count()
    if c == self.conf.maxuser then -- 如果已经坐满，则随机0-3个机器人离开
        self.max_leave_count = (self.max_leave_count or 0) + 1
        self.rand_leave_count = self.rand_leave_count or rand.rand_between(0, 3)
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if user then
                if Utils:isRobot(user.api) and self.rand_leave_count <= self.max_leave_count then
                    self:userLeave(v.uid, user.linkid) -- 让机器人离开
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
        log.info("idx(%s,%s,%s) logout(),uid=%s,logoutts=%s", self.id, self.mid, self.logid, uid,
            user and user.logoutts or 0)
    end
end

-- 清理某服玩家
function Room:clearUsersBySrvId(srvid)
    log.debug("idx(%s,%s,%s) clearUsersBySrvId(),srvid=%s", self.id, self.mid, self.logid, tostring(srvid))
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
        log.info("idx(%s,%s,%s) userQueryUserInfo(),uid=%s,ok=%s", self.id, self.mid, self.logid, tostring(uid)
            , tostring(ok))
        coroutine.resume(user.co, ok, ud)
    end
end

-- 玩家互斥检测
function Room:userMutexCheck(uid, code)
    local user = self.users[uid]
    if user then
        timer.cancel(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1])
        log.info("idx(%s,%s,%s) userMutexCheck(),uid=%s,code=%s", self.id, self.mid, self.logid, tostring(uid),
            tostring(code))
        coroutine.resume(user.mutex, code > 0)
    end
end

--
function Room:queryUserResult(ok, ud)
    if self.timer then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.debug("idx(%s,%s,%s) queryUserResult(),ok:%s", self.id, self.mid, self.logid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

-- 玩家离开
function Room:userLeave(uid, linkid)
    log.info("idx(%s,%s,%s) userLeave(),uid=%s", self.id, self.mid, self.logid, uid)

    local function handleFailed() -- 离开失败处理
        log.debug("idx(%s,%s,%s) userLeave(),leave failed.", self.id, self.mid, self.logid)
        local resp = pb.encode(
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
        log.info("idx(%s,%s,%s) userLeave(),user(uid=%s) is not in room", self.id, self.mid, self.logid, uid)
        handleFailed()
        return
    end

    local s -- 座位对象
    for k, seat in ipairs(self.seats) do
        if seat.uid == uid then
            s = seat
            break
        end
    end
    user.state = EnumUserState.Leave -- 离开状态
    if s then -- 如果该玩家已坐下
        if self.state >= pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Start") and
            self.state < pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Finish") and
            self:getPlayingSize() > 1
        then
            if s.sid == self.current_betting_pos then -- 如果刚轮到该玩家操作
                self:userchipin(uid, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"), 0) -- 弃牌
                self:stand(
                    self.seats[s.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
                log.debug("idx(%s,%s,%s) userLeave(),uid=%s,s.sid == self.current_betting_pos", self.id, self.mid,
                    self.logid, uid)

                -- 检测是否游戏结束，若未结束，则通知下一个玩家操作


            else -- 尚未轮到该玩家操作
                -- if s.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN") then
                --     s:chipin(pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"), s.roundmoney)
                -- end

                if not s.isplaying then -- 如果该玩家未参与游戏
                    self:stand(
                        self.seats[s.sid],
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                    )
                    log.debug("idx(%s,%s,%s) userLeave(),uid=%s,s.isplaying == false", self.id, self.mid, self.logid, uid)
                elseif not s.hasLeave and
                    s.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then -- 如果该玩家参与游戏且还未弃牌
                    s:chipin(pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"), s.roundmoney) -- 弃牌操作
                    self:stand(
                        self.seats[s.sid],
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                    )
                    log.debug("idx(%s,%s,%s) userLeave(),uid=%s,FOLD", self.id, self.mid, self.logid, uid) -- 弃牌操作
                elseif not s.hasLeave and
                    s.chiptype == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then -- 如果该玩家参与游戏且已经弃牌
                    self:stand(
                        self.seats[s.sid],
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                    )
                    log.debug("idx(%s,%s,%s) userLeave(),uid=%s,has FOLD", self.id, self.mid, self.logid, uid) -- 弃牌操作
                end

                -- 检测是否游戏结束
                if self:checkGameOver() then
                    self:finish() -- 立马结束游戏
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
        log.info("idx(%s,%s,%s) userLeave(), s.sid=%s,maxraisepos=%s", self.id, self.mid, self.logid, s.sid,
            self.maxraisepos)
        if s.sid == self.maxraisepos or self.maxraisepos == 0 then
            local maxraise_seat = { roundmoney = -1, sid = s.sid }
            for i = s.sid + 1, s.sid + #self.seats - 1 do
                local j = i % #self.seats > 0 and i % #self.seats or #self.seats
                local seat = self.seats[j]
                log.info("idx(%s,%s,%s) userLeave(), j=%s, roundmoney=%s, maxraise.roundmoney=%s", self.id, self.mid,
                    self.logid, j, seat.roundmoney, maxraise_seat.roundmoney)
                if seat and seat.isplaying and seat.roundmoney > maxraise_seat.roundmoney then
                    maxraise_seat = seat
                end
            end
            self.maxraisepos = maxraise_seat.sid
        end
        log.info("idx(%s,%s,%s) userLeave(), maxraisepos=%s", self.id, self.mid, self.logid, self.maxraisepos)
    end

    user.roundmoney = user.roundmoney or 0

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
                roundId = user.roundId or ""
            }
        )
        log.info("idx(%s,%s,%s) userLeave(), money change uid=%s,val=%s", self.id, self.mid, self.logid, uid, val)
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
    log.info("idx(%s,%s,%s) userLeave(),uid=%s", self.id, self.mid, self.logid, uid)

    mutex.request(
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
        pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
        pb.encode("network.cmd.PBMutexRemove", { uid = uid, srvid = global.sid(), roomid = self.id })
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

    if not Utils:isRobot(user.api) then
        Utils:updateChipsNum(global.sid(), uid, 0)
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
    log.info("idx(%s,%s,%s) userLeave(),uid=%s,gamecount=%s,profits=%s", self.id, self.mid, self.logid, uid
        , user.gamecount or 0,
        val - user.totalbuyin)

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

-- 玩家进入房间
-- 参数 uid:
-- 参数 mid: matchid
-- 参数 quick:
function Room:userInto(uid, linkid, mid, quick, ip, api)
    log.debug("idx(%s,%s,%s) userInto(),uid=%s", self.id, self.mid, self.logid, uid)
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
        log.info("idx(%s,%s,%s) userInto(),uid=%s,ip=%s,code=%s into room failed", self.id, self.mid, self.logid, uid,
            tostring(ip), code)
    end

    if self.isStopping then
        handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail"))
        return
    end

    if Utils:hasIP(self, uid, ip, api) then
        handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_SameIp"))
        return
    end

    self.users[uid] = self.users[uid] or
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
                inseat = true -- 已经坐在该桌
                seat = v
                break
            end
        else
            seat = v
        end
    end

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
                        roomtype = self.conf and self.conf.roomtype
                    }
                )
            )
            local ok = coroutine.yield()
            if not ok then -- 互斥检测失败(说明已经在其它房间中)
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
                log.info("idx(%s,%s,%s) userInto(),player(uid=%s) has been in another room", self.id, self.mid,
                    self.logid, uid)
                return
            end

            user.co = coroutine.create(
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
                        "idx(%s,%s,%s) userInto(), into room money: uid=%s,userMoney=%s,minbuyinbb=%s,sb=%s",
                        self.id,
                        self.mid,
                        self.logid,
                        uid,
                        self:getUserMoney(uid),
                        self.conf.minbuyinbb,
                        self.conf.sb
                    )

                    -- 防止协程返回时，玩家实质上已离线
                    if ok and user.state ~= EnumUserState.Intoing then
                        ok = false
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                        log.info("idx(%s,%s,%s) userInto(), user(uid=%s) logout or leave", self.id, self.mid, self.logid
                            , uid)
                    end
                    if ok and not inseat and self:getUserMoney(uid) + user.chips > self.conf.maxinto then
                        ok = false
                        log.info(
                            "idx(%s,%s,%s) userInto(), user(uid=%s) more than maxinto=%s",
                            self.id,
                            self.mid,
                            self.logid,
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
                            if not Utils:isRobot(self.users[uid].api) then
                                Utils:updateChipsNum(global.sid(), uid, 0)
                            end
                            self.users[uid] = nil
                        end
                        log.info(
                            "idx(%s,%s,%s) userInto(),not enough money: uid=%s,userMoney=%s,t.code=%s",
                            self.id,
                            self.mid,
                            self.logid,
                            uid,
                            self:getUserMoney(uid),
                            t.code
                        )
                        return
                    end

                    self.user_cached = false
                    user.state = EnumUserState.Playing

                    log.info(
                        "idx(%s,%s,%s) userInto(), into room() uid=%s,linkid=%s,state=%s,userMoney=%s,%s",
                        self.id,
                        self.mid,
                        self.logid,
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
                { uid, self }
            )
            coroutine.resume(user.co, user)
        end
    )
    timer.tick(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1], TimerID.TimerID_MutexTo[2], onMutexTo, { uid, self })
    coroutine.resume(user.mutex, user)
end

-- 重置房间(每局开始时才重置)
function Room:reset()
    log.debug("idx(%s,%s,%s) reset()", self.id, self.mid, self.logid)
    self.pokeridx = 0 -- 已使用牌张数

    -- 各边池
    self.pots = {
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} },
        { money = 0, seats = {} }
    }
    self.maxraisepos = 0
    self.chipinpos = 0
    self.potidx = 1
    self.roundcount = 0 -- 该局轮数
    self.current_betting_pos = 0 -- 当前操作位置
    self.already_show_card = false
    self.chipinset = {}
    self.sdata = {
        -- moneytype = self.conf.moneytype,
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}

    self.finishstate = pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None")

    self.lastchipintype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_NULL")
    self.lastchipinpos = 0
    self.has_cheat = false
    self.invalid_pot = 0
    self.potrates = {}
    self.seats_totalbets = {}
    self.invalid_pot_sid = 0
    self.hasFind = false
    self.replayType = 0 -- 重赛类型(0-不需要重赛  1-有相同牌型赢家重赛  2-特殊牌重赛(询问补码重赛) 3-特殊牌重赛(询问补码重赛))
end

-- 获取无效的下注池?
function Room:getInvalidPot()
    local invalid_pot = 0
    local tmp = {}
    for sid, seat in ipairs(self.seats) do -- 遍历每个座位
        if seat.roundmoney > 0 then -- 如果该轮下注了
            table.insert(tmp, { sid, seat.roundmoney }) -- {{座位ID,该轮下注金额}}
        end
    end
    if #tmp >= 1 then
        table.sort(
            tmp,
            function(a, b)
                return a[2] > b[2] -- 根据下注金额从大到小排序?
            end
        )
        self.invalid_pot_sid = tmp[1][1]
        invalid_pot = tmp[1][2] - (tmp[2] and tmp[2][2] or 0)
    end
    log.info("idx(%s,%s,%s) getInvalidPot() tmp=%s,invalid_pot=%s", self.id, self.mid, self.logid, cjson.encode(tmp),
        invalid_pot)

    return invalid_pot
end

-- uid玩家获取桌子信息
function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userTableInfo(), uid=%s sb=%s", self.id, self.mid, self.logid, uid, self.conf.sb)

    local tableinfo = {
        gameId = self.gameId, -- 牌局id(每局开始时累加)
        seatCount = self.conf.maxuser, -- 每桌最大玩家数
        smallBlind = self.conf.sb,
        bigBlind = self.conf.sb * 2,
        tableName = self.conf.name, -- 桌子名称
        gameState = self.state, -- 桌子状态
        buttonSid = self.buttonpos, -- 庄家所在位置
        pot = self:getTotalBet(), -- 下注池总金额(底池)
        roundNum = self.roundcount or 0, -- 轮数
        ante = self.ante, -- 底注
        minbuyinbb = self.minbuyinbb or 10, -- 最小买入
        maxbuyinbb = self.maxbuyinbb or 100000, -- 最大买入
        middlebuyin = self.conf.referrerbb * self.conf.sb, -- 推荐买入

        bettingtime = self.bettingtime, -- 总下注时间
        matchType = self.conf.matchtype, -- 比赛类型
        matchState = self.conf.matchState or 0,
        roomType = self.conf.roomtype, -- PBRoomType
        addtimeCost = self.conf.addtimecost, -- 加时花费
        toolCost = self.conf.toolcost, -- 互动道具花费
        jpid = self.conf.jpid or 0, -- jackpot id, >0表示房间配置jackpot
        jp = JackpotMgr:getJackpotById(self.conf.jpid), -- jackpot value
        jpRatios = g.copy(JACKPOT_CONF[self.conf.jpid] and JACKPOT_CONF[self.conf.jpid].percent or { 0, 0, 0 }), -- jackpot 牌型奖励配置，从低到高(fourkind straightflush royalflush)
        betLimit = self.conf.ante or 0,
        potLimit = self.conf.ante or 0,

        operatePos = self.current_betting_pos or 0,
        leftTime = 10000, -- 该状态剩余时长(毫秒)
        replayType = self.replayType or 0, -- 重赛类型
        roundMaxBet = self:getRoundMaxBet(), -- 本轮最大下注金额
        maxinto = (self.conf.maxinto or 0) * (self.conf.ante or 0) / (self.conf.sb or 1)
    }

    if self.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") then
        tableinfo.minbuyinbb = self.conf.minbuyinbb
        tableinfo.maxbuyinbb = self.conf.maxbuyinbb
    end

    if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ShowOneCard") then -- 公开显示一张牌
        local passTime = global.ctms() - self.stateBeginTime -- 当前状态经过时长(毫秒)
        if passTime < TimerID.TimerID_ShowOneCard[2] then
            tableinfo.leftTime = TimerID.TimerID_ShowOneCard[2] - passTime
        else
            tableinfo.leftTime = 0
        end
    elseif self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards") then -- 选择要比较的牌
        local passTime = global.ctms() - self.stateBeginTime -- 当前状态经过时长(毫秒)
        if passTime < TimerID.TimerID_SelectCompareCards[2] then
            tableinfo.leftTime = TimerID.TimerID_SelectCompareCards[2] - passTime
        else
            tableinfo.leftTime = 0
        end
    end

    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
end

-- 发送桌子信息给uid玩家
function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {} -- 所有座位信息

    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.uid then -- 如果该座位有人
            local seatinfo = fillSeatInfo(seat, self) -- 填充座位信息
            if seat.uid == uid then
                seatinfo.handcards = g.copy(seat.handcards) -- 手牌数据
                seatinfo.cardsType = seat.cardsType -- 手牌牌型
                seatinfo.card1 = seat.handcards[1]
                seatinfo.card2 = seat.handcards[2]
                if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards") and
                    seatinfo.cardsNum == 3 then
                    seatinfo.groups = {}
                    local group = { card1 = seat.handcards[1], card2 = seat.handcards[2],
                        cardsType = Seotda:GetCardsType({ seat.handcards[1], seat.handcards[2] }) }
                    table.insert(seatinfo.groups, group)
                    group = { card1 = seat.handcards[1], card2 = seat.handcards[3],
                        cardsType = Seotda:GetCardsType({ seat.handcards[1], seat.handcards[3] }) }
                    table.insert(seatinfo.groups, group)
                    group = { card1 = seat.handcards[2], card2 = seat.handcards[3],
                        cardsType = Seotda:GetCardsType({ seat.handcards[2], seat.handcards[3] }) }
                    table.insert(seatinfo.groups, group)
                end
            else
                seatinfo.handcards = {}
                for _, v in ipairs(seat.handcards) do
                    table.insert(seatinfo.handcards, v ~= 0 and 0 or -1) -- -1 无手手牌，0 牌背
                end
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

    local resp = pb.encode("network.cmd.PBSeotdaTableInfoResp", { tableInfo = tableinfo })
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaTableInfoResp"),
        resp
    )
    log.debug("idx(%s,%s,%s) sendAllSeatsInfoToMe(),tableinfo=%s", self.id, self.mid, self.logid,
        cjson.encode(tableinfo))
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

-- 获取一个奖池(该局所有玩家总的下注额)
function Room:getOnePot()
    local money = 0 --
    for i = 1, #self.seats do
        if self.seats[i].isplaying then -- 如果该座位玩家参与游戏
            money = money + self.seats[i].money + self.seats[i].roundmoney
        end
    end
    return money
end

-- 获取奖池个数
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
        if seat.isplaying and seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then
            return seat
        end
    end
    return nil
end

-- 获取本轮最大下注金额
function Room:getRoundBetMax()
    local roundBetMax = 0
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and not seat.hasLeave and
            seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then

            if seat.roundmoney > roundBetMax then -- 如果该玩家下注了
                roundBetMax = seat.roundmoney
            end
        end
    end
    return roundBetMax
end

-- 从sid位置开始寻找一个可操作的座位
-- 参数 sid: 座位ID
-- 返回值: 返回找到的座位对象
function Room:getNextActionPosition(sid)
    sid = sid or 1
    log.debug("idx(%s,%s,%s) getNextActionPosition() sid=%s,", self.id, self.mid, self.logid, sid)

    -- 查找本轮最大下注金额
    local maxBet = self:getRoundBetMax()

    for i = sid, sid + #self.seats - 1 do
        local j = i % #self.seats > 0 and i % #self.seats or #self.seats -- 实际座位号
        local seati = self.seats[j]

        if seati and seati.isplaying and not seati.hasLeave and
            not self:checkOperate(seati, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")) and
            not self:checkOperate(seati, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) -- 如果该座位参与游戏且未弃牌
        then
            if seati.roundmoney < maxBet or maxBet == 0 then
                seati.addon_count = 0 -- 本轮已增加思考时间次数
                return seati
            end
        end
    end
    log.error("idx(%s,%s,%s) getNextActionPosition() not find seat, err ", self.id, self.mid, self.logid)
    return nil
end

-- 获取未弃牌玩家数
function Room:getNoFoldCnt()
    local nfold = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat and seat.isplaying and not seat.hasLeave and
            seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")
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
        if seat.isplaying and not seat.hasLeave and
            seat.chiptype == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN") then
            allin = allin + 1
        end
    end
    return allin
end

-- 游戏局数
function Room:getGameId()
    return self.gameId + 1
end

-- 玩家站起
-- 参数 seat: 座位对象
-- 参数 uid: 玩家UID
-- 参数 stype: 站起方式(PBTexasStandType_PlayerStand:正常站起)
function Room:stand(seat, uid, stype)
    log.info("idx(%s,%s,%s) stand(),uid=%s,sid=%s,stype=%s", self.id, self.mid, self.logid, uid, seat.sid,
        tostring(stype))
    local user = self.users[uid]
    if seat and user then
        if self.state >= pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Start") and
            self.state < pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Finish") and -- 在游戏过程中
            seat.isplaying and
            not seat.hasLeave
        then
            log.info("idx(%s,%s,%s) stand(),uid=%s", self.id, self.mid, self.logid, uid)
            -- 判断该玩家是否弃牌
            local hasFold = 0 ~=
                (seat.operateTypes & (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")))
            if hasFold then -- 如果该玩家已弃牌
                log.info("idx(%s,%s,%s) stand(),uid=%s,hasFold==true", self.id, self.mid, self.logid, uid)
            else
                log.info("idx(%s,%s,%s) stand(),uid=%s,hasFold==false", self.id, self.mid, self.logid, uid)
                -- 弃牌操作
                seat.operateTypes = seat.operateTypes |
                    (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"))
            end

            -- 统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[uid] = self.sdata.users[uid] or {}
            self.sdata.users[uid].totalpureprofit = self.sdata.users[uid].totalpureprofit or
                seat.chips - seat.last_chips - seat.roundmoney
            self.sdata.users[uid].ugameinfo = self.sdata.users[uid].ugameinfo or {}
            self.sdata.users[uid].ugameinfo.texas = self.sdata.users[uid].ugameinfo.texas or {}
            self.sdata.users[uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[uid].ugameinfo.texas.inctotalwinhands = self.sdata.users[uid].ugameinfo.texas.inctotalwinhands
                or 0
            self.sdata.users[uid].ugameinfo.texas.leftchips = seat.chips - seat.roundmoney -- 剩余筹码

            -- 输家防倒币行为
            if self.sdata.users[uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[uid].extrainfo)
                if not Utils:isRobot(user.api) and extrainfo and
                    self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_PreChips") and -- 交前注
                    math.abs(self.sdata.users[uid].totalpureprofit) >= 20 * self.conf.sb * 2 and
                    seat.chiptype == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") and -- 弃牌
                    not user.is_bet_timeout and
                    (seat.odds or 1) < 0.25
                then
                    extrainfo["cheat"] = true
                    extrainfo["totalmoney"] = (self:getUserMoney(uid) or 0) + (seat.chips - seat.roundmoney) -- 玩家身上总金额
                    self.sdata.users[uid].extrainfo = cjson.encode(extrainfo)
                    self.has_cheat = true
                end
            end
            -- 实时牌局
            self.reviewlogitems[seat.uid] = self.reviewlogitems[seat.uid] or
                {
                    player = { uid = seat.uid, username = user.username or "" },
                    handcards = {
                        sid = seat.sid,
                        card1 = seat.handcards[1],
                        card2 = seat.handcards[2]
                    },
                    --bestcards = seat.besthand,
                    bestcardstype = seat.cardsType,
                    win = self.sdata.users[uid].totalpureprofit or seat.chips - seat.last_chips - seat.roundmoney,
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

        seat:stand(uid) -- 玩家站起
        if not Utils:isRobot(user.api) then
            Utils:updateChipsNum(global.sid(), uid, user.chips)
        end
        pb.encode(
            "network.cmd.PBTexasPlayerStand",
            { sid = seat.sid, type = stype },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerStand"),
                    pointer,
                    length
                )
            end
        )
        log.info("idx(%s,%s,%s) stand(),uid=%s,sid=%s", self.id, self.mid, self.logid, uid, seat.sid)
        --MatchMgr:getMatchById(self.conf.mid):shrinkRoom()
    end
end

-- 玩家坐下
function Room:sit(seat, uid, buyinmoney, ischangetable)
    log.info(
        "idx(%s,%s,%s) sit(),uid=%s,sid=%s buyinmoney=%s,userMoney=%s",
        self.id,
        self.mid,
        self.logid,
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
            log.debug("idx(%s,%s,%s) sit() user.chips=%s", self.id, self.mid, self.logid, user.chips)
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
            log.debug("idx(%s,%s,%s) sit() empty=%s", self.id, self.mid, self.logid, empty)
            return
        end
        local ret = seat:sit(uid, user.chips, 0, 0, user.totalbuyin)
        if not ret then
            log.debug("idx(%s,%s,%s) sit(), ret=%s", self.id, self.mid, self.logid, ret)
            return
        end

        local clientBuyin =
        (not ischangetable and 0x1 == (self.conf.buyin & 0x1) and
            user.chips <= (self.conf and self.conf.ante + self.conf.fee or 0))
        if clientBuyin then
            -- 进入房间自动买入流程
            if (0x4 == (self.conf.buyin & 0x4) or Utils:isRobot(user.api)) and user.chips == 0 and user.totalbuyin == 0 then
                clientBuyin = false
                if not self:userBuyin(uid, user.linkid, { buyinMoney = buyinmoney }, true) then
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
                    { self, uid },
                    1
                )
            end
        else
            -- 客户端超时站起
            seat.chips = user.chips
            user.chips = 0
        end
        log.info("idx(%s,%s,%s) sit(), uid=%s, sid=%s sit clientBuyin %s", self.id, self.mid, self.logid, uid, seat.sid,
            tostring(clientBuyin))
        local seatinfo = fillSeatInfo(seat, self)
        local playerSit = { seatInfo = seatinfo, clientBuyin = clientBuyin, buyinTime = self.conf.buyintime }
        pb.encode(
            "network.cmd.PBSeotdaPlayerSit",
            playerSit,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaPlayerSit"),
                    pointer,
                    length
                )
            end
        )
        log.debug("idx(%s,%s,%s) sit() PBSeotdaPlayerSit=%s", self.id, self.mid, self.logid, cjson.encode(playerSit))

        MatchMgr:getMatchById(self.conf.mid):expandRoom()
    end
end

-- 发送某座位信息给该桌所有玩家
function Room:sendPosInfoToAll(seat, chiptype)
    local updateseat = { state = self.state }
    if chiptype then
        seat.chiptype = chiptype -- 更新该座位的操作类型
    end

    if seat.uid then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        pb.encode(
            "network.cmd.PBSeotdaUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaUpdateSeat"),
                    pointer,
                    length
                )
            end
        )
    end
end

-- 游戏开始
function Room:start()
    self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Start")) -- 开始状态
    self.starttime = global.ctsec() -- 游戏开始时刻(秒)
    self.logid = self.statistic:genLogId(self.starttime) or 0 -- 日志ID

    log.debug("idx(%s,%s,%s) start()", self.id, self.mid, self.logid)

    self:shuffleCards() -- 洗牌

    self.gameId = self:getGameId() -- 局数编号(每局游戏开始时累加)
    self.tableStartCount = self.tableStartCount + 1 -- 游戏开始局数

    self.has_started = self.has_started or true

    self.smallblind = self.conf and self.conf.sb or 50
    self.bigblind = self.conf and self.conf.sb * 2 or 100

    self.ante = self.conf and self.conf.ante or 0 -- 底注(前注)
    self.minchip = self.conf and self.conf.minchip or 1 -- 最小筹码
    self.has_player_inplay = false

    -- 玩家状态，金币数等数据初始化
    self:reset() -- 重置房间信息(每局开始时才重置房间)
    self:updateBankerPos() -- 更新庄家位置


    log.info(
        "idx(%s,%s,%s) start(),robotcnt:%s ante:%s minchip:%s gameId:%s betpos:%s logid:%s",
        self.id,
        self.mid,
        self.logid,
        self:robotCount(),
        self.ante,
        self.minchip,
        self.gameId,
        self.current_betting_pos,
        self.logid
    )
    -- 配牌处理
    if self.cfgcard_switch then
        self:setcard()
    end

    -- 服务费
    for k, seat in ipairs(self.seats) do
        if seat.uid and seat.isplaying and not seat.hasLeave then
            local user = self.users[seat.uid]
            if user and not self.has_player_inplay and not Utils:isRobot(user.api) then
                self.has_player_inplay = true -- 有真实玩家参与游戏
            end

            if self.conf and self.conf.fee and seat.chips > self.conf.fee then
                seat.last_chips = seat.chips
                seat.chips = seat.chips - self.conf.fee
                -- 统计
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                self.sdata.users[seat.uid].totalfee = self.conf.fee
            end
            if user then
                user.gamecount = (user.gamecount or 0) + 1 -- 统计数据(已玩游戏局数)
            end
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
            self.sdata.users[seat.uid].sid = k
            self.sdata.users[seat.uid].username = user and user.username or ""
            self.sdata.users[seat.uid].extrainfo = cjson.encode(
                {
                    ip = user and user.ip or "",
                    api = user and user.api or "",
                    roomtype = self.conf.roomtype,
                    roundid = user and user.roundId or "",
                    playchips = 20 * (self.conf.fee or 0) -- 2021-12-24
                }
            )
            if k == self.buttonpos then -- 庄家所在位置
                self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
            else
                self.sdata.users[seat.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
            end
        end
    end

    -- 广播开赛
    local gamestart = {
        gameId = self.gameId, -- 牌局id
        gameState = self.state, -- 桌子状态
        buttonSid = self.buttonpos, -- 庄家所在位置
        smallBlindSid = 0,
        bigBlindSid = 0,
        smallBlind = self.conf.sb,
        bigBlind = self.conf.sb * 2,
        ante = self.ante, -- 底注
        minChip = self.minchip, -- 最小筹码
        tableStarttime = self.starttime, -- 牌局开始时刻(秒)
        seats = fillSeats(self) -- 座位信息
    }
    pb.encode(
        "network.cmd.PBSeotdaGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaGameStart"),
                pointer,
                length
            )
        end
    )
    log.debug("idx(%s,%s,%s) start(),PBSeotdaGameStart=%s", self.id, self.mid, self.logid, cjson.encode(gamestart))

    local curplayers = 0 -- 当前坐下的玩家数
    -- 同步当前状态给客户端
    for k, seat in ipairs(self.seats) do
        if seat.uid then -- 如果该座位有玩家坐下
            self:sendPosInfoToAll(seat)
            curplayers = curplayers + 1
        end
    end

    -- 数据统计
    self.sdata.stime = self.starttime -- 牌局开始时间(秒)
    self.sdata.gameinfo = self.sdata.gameinfo or {}
    self.sdata.gameinfo.texas = self.sdata.gameinfo.texas or {}
    -- self.sdata.gameinfo.texas.sb = self.conf.sb      -- 小盲
    -- self.sdata.gameinfo.texas.bb = self.conf.sb * 2  -- 大盲
    self.sdata.gameinfo.texas.maxplayers = self.conf.maxuser -- 每桌最大玩家数
    self.sdata.gameinfo.texas.curplayers = curplayers -- 当前坐下的玩家数
    self.sdata.gameinfo.texas.ante = self.conf.ante
    self.sdata.jp = { minichips = self.minchip }
    self.sdata.extrainfo = cjson.encode(
        {
            buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0
        }
    )

    if self:getPlayingSize() == 1 then -- 如果只有一个玩家参与游戏
        log.debug("idx(%s,%s,%s) start(),PlayingSize==1", self.id, self.mid, self.logid)
        timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
        return
    end

    self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_PreChips")) -- 交前注
end

-- 检测该位置是否可操作
function Room:checkCanChipin(seat, type)
    if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then -- 如果是弃牌操作
        return seat and seat.uid and seat.isplaying
    end

    return seat and seat.uid and seat.sid == self.current_betting_pos and seat.isplaying
end

-- 检测是否可操作
-- 参数 seat: 当前要操作的座位
-- 参数 type: 操作类型
function Room:checkCanChipin2(seat, type, chips)
    log.debug("idx(%s,%s,%s) checkCanChipin2() roundcount=%s", self.id, self.mid, self.logid, self.roundcount)
    if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then
        return true
    end

    if self.roundcount < 1 then -- 如果是第一轮
        -- 第一个操作者只可以 다이（弃牌）或者하프（1/2底池）
        local roundMaxBet = self:getRoundMaxBet()

        if roundMaxBet == 0 then -- 如果之前还没玩家操作过(即当前玩家是第一个操作者)
            -- 第一个操作者只可以 다이（弃牌）或者하프（1/2底池）
            if type ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") and
                type ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2") then
                log.debug("idx(%s,%s,%s) checkCanChipin2() hasBet==false", self.id, self.mid, self.logid)
                return false
            end
        end

        -- 第一轮加注选项只有1/2底池
        if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE") or
            type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE3") then
            return false
        end

        -- 第一轮操作每个玩家只可以加注一次
        if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2") then
            -- 判断该玩家是否已经加注过
            if 0 ~=
                (
                seat.operateTypes &
                    (
                    (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE")) |
                        (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2")) |
                        (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE3")))) then
                log.debug("idx(%s,%s,%s) checkCanChipin2() DQW", self.id, self.mid, self.logid)
                return false
            end
        end
        return true
    else -- 第二轮及之后操作
        -- check过的玩家不可以再加注
        if 0 ~= (seat.operateTypes & (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK"))) then -- 如果该玩家已经check过
            if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE") or
                type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2") or
                type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE3") then
                log.debug("idx(%s,%s,%s) checkCanChipin2() roundcount=%s 2", self.id, self.mid, self.logid,
                    self.roundcount)
                return false
            end
        end
    end
    return true
end

-- 玩家操作
-- 参数 uid: 玩家UID
-- 参数 type: 操作类型   PBSeotdaChipinType_FOLD、PBSeotdaChipinType_CALL
-- 参数 money: 操作涉及到的金额(筹码)
-- 返回值：成功则返回true，否则返回false
function Room:chipin(uid, type, money)
    money = money or 0
    log.debug("idx(%s,%s,%s) chipin(),uid=%s,type=%s,money=%s", self.id, self.mid, self.logid, uid, tostring(type),
        tostring(money))
    local seat = self:getSeatByUid(uid) -- 获取指定玩家对应的座位
    if not seat then
        return false
    end
    if not self:checkCanChipin(seat, type) then -- 检测某玩家是否可以操作
        return false -- 该玩家不可操作
    end

    if not self:checkCanChipin2(seat, type, money) then
        return false
    end

    if seat.chips < money then -- 如果身上筹码不够
        money = seat.chips -- 操作筹码不能超过身上筹码
    end


    log.info(
        "idx(%s,%s,%s) chipin(),pos=%s,uid=%s,type=%s,money=%s",
        self.id,
        self.mid,
        self.logid,
        seat.sid,
        seat.uid and seat.uid or 0,
        type,
        money
    )

    local old_roundmoney = seat.roundmoney -- 本局已下注金额

    -- 弃牌操作
    local function fold_func(seat, type, money)
        log.debug("fold_func(),sid=%s,uid=%s,type=%s", seat.sid, tostring(seat.uid), type)
        seat:chipin(type, seat.roundmoney)
        --seat.rv:checkSitResultSuccInTime() -- 检查是否立刻留座生效
    end

    -- 跟注加注操作
    local function call_check_raise_allin_func(seat, type, money)
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or { roundmoney = 0 } -- 最大加注座位信息

        if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_BET") and money == self.ante then
            -- 确保是第二轮的第一个下注者
            if self:getRoundMaxBet() > money and
                self.state ~= pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then
                type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") -- 默认弃牌
            end
        end
        if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK") and money == 0 then -- 过牌操作(必须是第二轮及之后才可过牌)
            if seat.roundmoney >= maxraise_seat.roundmoney then -- 如果满足过牌条件
                type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK") -- 过牌操作
                money = seat.roundmoney -- 本轮已押注金额
                -- 必须超过1轮下注才可以过牌check
                if self.roundcount < 1 then
                    type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") -- 操作失败，则默认是弃牌
                end
            else
                type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") -- 操作失败，则默认是弃牌
            end
        elseif type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN") and money < seat.chips then -- 全押
            money = seat.chips -- 押注金额为身上剩余筹码
        elseif type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE") and money == seat.chips then -- 加注
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")
        elseif type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2") and money == seat.chips then -- 加注
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")
        elseif type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE3") and money == seat.chips then -- 加注
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")
        elseif money < seat.chips and money < maxraise_seat.roundmoney then -- 这个money是本轮总下注金额?
            -- money = 0
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")
        else
            if money < seat.roundmoney then
                if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK") and money == 0 then -- 过牌操作是money必须为0!!!
                    type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK") -- 过牌
                else
                    type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") -- 弃牌
                    money = 0
                end
            elseif money > seat.roundmoney then
                if money == maxraise_seat.roundmoney then
                    type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CALL") -- 跟注
                else
                    type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE")
                end
            else -- money == seat.roundmoney
                type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK") -- 过牌操作
            end
        end

        if type == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK")
            and self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then
            -- 第二轮开始才可以check
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") -- 弃牌
            money = 0
        end

        seat:chipin(type, money)
    end

    -- 加注2 (하프 -- 1/2底池)  = (当前底池总量  + needcall) * 1/2 + needcall)
    local function raise2(seat, type, money)
        if money == seat.chips then -- 加注
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")
        elseif money < seat.roundmoney then
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")
        end

        seat:chipin(type, money)
    end

    -- 加注3(쿼터 -- 1/4底池)  = (当前底池总量  + needcall) * 1/4 + needcall
    local function raise3(seat, type, money)
        if money == seat.chips then -- 加注
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")
        elseif money < seat.roundmoney then
            type = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")
        end
        seat:chipin(type, money)
    end

    local switch = {
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")] = fold_func, -- 弃牌
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CALL")] = call_check_raise_allin_func, -- 跟注
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK")] = call_check_raise_allin_func, -- 过牌
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE")] = call_check_raise_allin_func, -- 加注
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")] = call_check_raise_allin_func, -- 全下
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_BET")] = call_check_raise_allin_func, -- 下注
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE2")] = raise2, -- 加注2 (하프 -- 1/2底池)
        [pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_RAISE3")] = raise3 -- 加注3(쿼터 -- 1/4底池)
    }

    local chipin_func = switch[type]
    if not chipin_func then
        log.info("idx(%s,%s,%s) invalid bettype uid:%s type:%s", self.id, self.mid, self.logid, uid, type)
        return false
    end

    -- 真正操作chipin
    chipin_func(seat, type, money)

    local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or { roundmoney = 0 }
    if seat.roundmoney > maxraise_seat.roundmoney then
        self.maxraisepos = seat.sid -- 更新最大加注位置
    end

    self.chipinpos = seat.sid
    self:sendPosInfoToAll(seat)

    if type ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") and
        type ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_SMALLBLIND") and
        money > 0
    then
        self.chipinset[#self.chipinset + 1] = money -- 各操作涉及的金额集合
    end

    return true
end

-- 弃牌玩家重赛回应
function Room:userReplayResp(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userReplayResp() uid=%s,rev=%s", self.id, self.mid, self.logid, uid, cjson.encode(rev))

    if rev and self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips") then
        local seat = self:getSeatByUid(uid)
        if rev.replay == 1 then
            --local user = self.users[uid]
            if seat and
                (seat.operateTypes & (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_COMPARE")))
                == 0 then -- 该玩家还未比过牌
                -- 跟注所需筹码
                local needChips = self.seats[self.maxraisepos].total_bets - seat.total_bets
                if needChips <= seat.chips then
                    seat.total_bets = self.seats[self.maxraisepos].total_bets
                    seat.money = seat.money + needChips -- 一局总消耗筹码数
                    seat.betmoney = seat.total_bets
                    seat.chips = seat.chips - needChips
                    seat.operateTypes = seat.operateTypes |
                        (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CALL")) -- 补齐筹码相当于跟注了
                    -- 将弃牌操作位去掉
                    seat.operateTypes = seat.operateTypes &
                        (~(1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")))
                    seat.chiptype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CALL")
                    seat.playerState = 2 -- 确认补码重赛
                else
                    seat.playerState = 3 -- 确认不重赛
                end
            end
        else
            if seat then
                seat.playerState = 3 -- 确认不重赛
            end
        end
        local allSeatsState = {}
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying and not seat.hasLeave then
                table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
            end
        end
        -- 通知所有玩家哪些玩家需要重赛
        pb.encode(
            "network.cmd.PBSeotdaReplayState",
            { allSeats = allSeatsState, replayType = self.replayType },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReplayState"),
                    pointer,
                    length
                )
            end
        )
        log.debug("idx(%s,%s,%s) userReplayResp(),PBSeotdaReplayState=%s", self.id, self.mid, self.logid,
            cjson.encode(allSeatsState))

    end
end

-- 公开显示某一张牌
function Room:userShowOneCardReq(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userShowOneCardReq() uid=%s,rev=%s", self.id, self.mid, self.logid, uid, cjson.encode(rev))

    if rev and self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ShowOneCard") then
        local seat = self:getSeatByUid(uid)
        if seat and seat.firstShowCard == 0 and rev and rev.card then
            for i = 1, seat.cardsNum do
                if rev.card == seat.handcards[i] then
                    seat.firstShowCard = rev.card
                    -- 判断是否所有玩家都公开显示了一张牌 DQW
                    if self:isAllShowOneCard() then
                        onShowOneCard(self)
                    end
                    if i == 1 then
                        seat.secondCard = seat.handcards[2]
                    else
                        seat.secondCard = seat.handcards[1]
                    end

                    break
                end
            end
        end
    end
end

-- 选择要比较的牌
function Room:userCompareCardsReq(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userCompareCardsReq() uid=%s,rev=%s", self.id, self.mid, self.logid, uid, cjson.encode(rev))

    if rev and self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards") then
        local seat = self:getSeatByUid(uid)
        if seat and seat.isplaying and rev and rev.card1 and rev.card2 then
            for i = 1, seat.cardsNum do
                -- 将要比较的牌放在最前面
                if rev.card1 == seat.handcards[i] and i ~= 1 then
                    seat.handcards[1], seat.handcards[i] = seat.handcards[i], seat.handcards[1]
                elseif rev.card2 == seat.handcards[i] and i ~= 2 then -- 找出第2张牌
                    seat.handcards[2], seat.handcards[i] = seat.handcards[i], seat.handcards[2]
                    if rev.card1 == seat.handcards[i] and 1 ~= i then
                        seat.handcards[1], seat.handcards[i] = seat.handcards[i], seat.handcards[1]
                    end
                end
            end
        end
    end
end

-- 玩家操作
-- 参数 uid：操作者UID
-- 参数 type: 操作类型，见 PBSeotdaChipinType
-- 参数 money: 操作金额
-- 参数 client: 是否是客户端主动操作
function Room:userchipin(uid, type, money, client)
    log.info(
        "idx(%s,%s,%s) userchipin() uid=%s, type=%s, money=%s, client=%s",
        self.id,
        self.mid,
        self.logid,
        tostring(uid),
        tostring(type),
        tostring(money),
        tostring(client)
    )
    uid = uid or 0
    type = type or 0
    money = money or 0
    if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None") or
        self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Finish")
    then
        log.error("idx(%s,%s,%s) user chipin state invalid. state=%s", self.id, self.mid, self.logid, self.state)
        return false
    end
    local chipin_seat = self:getSeatByUid(uid) -- 正要操作的座位
    if not chipin_seat then
        log.error("idx(%s,%s,%s) invalid chipin seat,uid=%s", self.id, self.mid, self.logid, uid)
        return false
    end

    if self.current_betting_pos ~= chipin_seat.sid or not chipin_seat.isplaying then -- 如果还未轮到该玩家操作 或 该座位未参与游戏
        log.error(
            "idx(%s,%s,%s) invalid chipin pos, sid=%s,current_betting_pos=%s,isplaying=%s",
            self.id,
            self.mid,
            self.logid,
            chipin_seat.sid,
            self.current_betting_pos or 0,
            tostring(chipin_seat.isplaying)
        )
        return false
    end
    if self.minchip == 0 then -- 最小筹码不能为0
        log.error("idx(%s,%s,%s) chipin minchip invalid. uid=%s", self.id, self.mid, self.logid, uid)
        return false
    end

    if money % self.minchip ~= 0 then
        if money < self.minchip then
            money = self.minchip
        else
            money = math.floor(money / self.minchip) * self.minchip -- 确保操作金额是最小金额的整数倍
        end
    end

    local user = self.users[uid]
    if client and user then
        user.is_bet_timeout = false
        user.bet_timeout_count = 0 -- 操作超时次数置零
    end

    local chipin_result = self:chipin(uid, type, money)
    if not chipin_result then -- 如果操作失败
        log.error("idx(%s,%s,%s) chipin() failed, chipin_result=false,uid=%s", self.id, self.mid, self.logid,
            uid)
        return false
    end
    if chipin_seat.sid == self.current_betting_pos then
        timer.cancel(self.timer, TimerID.TimerID_Betting[1]) -- 关闭下注定时器
    end

    if self:checkGameOver() then
        self:finish() -- 立马结束游戏
        return true
    end

    -- 检测是否一轮结束
    if self:checkRoundOver() then
        self:roundOver() -- 一轮结束处理(暂时不可操作)

        -- 进入下一阶段
        if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then
            self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCard2"))
        elseif self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting2") then
            self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards")) -- 进入选择2张要比较的牌阶段
        elseif self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3") then
            self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips")) -- 重赛前等待弃牌玩家补齐筹码重赛状态
        end
        return true
    end

    -- 游戏尚未结束
    if chipin_seat.sid == self.current_betting_pos then -- 如果当前玩家操作了，则需要轮到下一个玩家操作
        local next_seat = self:getNextActionPosition((self.current_betting_pos % #self.seats) + 1) -- 下一个待操作的座位
        if not next_seat then
            if self:checkGameOver() then -- 检测游戏是否结束
                self:finish() -- 立马结束游戏
                return true
            else
                log.error("idx(%s,%s,%s) userchipin(),uid=%s,next_seat==nil", self.id, self.mid, self.logid, uid)
            end
        end
        if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") or
            self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting2") or
            self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3") then
            self:betting(next_seat) -- 通知下一个玩家下注
        end
    end

    return true
end

-- 前注，大小盲处理
function Room:dealPreChips()
    log.info("idx(%s,%s,%s) dealPreChips(),ante=%s", self.id, self.mid, self.logid, self.ante)

    if self.ante > 0 then
        for i = 1, #self.seats do
            local seat = self.seats[i]
            if seat.isplaying then -- 如果该座位玩家参与游戏
                -- seat的chipin, 不是self的chipin
                seat:chipin(pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_PRECHIPS"), self.ante) -- 交前注
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
    else
        onStartPreflop(self)
    end
end

-- 判断是否所有玩家弃牌
function Room:isAllFold()
    local fold_count = 0 -- 弃牌玩家数
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then
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

-- 判断是否所有未弃牌玩家AllIn或跟注了
function Room:isAllAllinOrCall()
    local callMoney = 0
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")) then
                if callMoney == 0 then
                    callMoney = seat.roundmoney
                elseif callMoney ~= seat.roundmoney then
                    return false
                end
            end
        end
    end
    return true
end

-- 获取所有未弃牌位置
function Room:getNonFoldSeats()
    local nonfoldseats = {}
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then
                table.insert(nonfoldseats, seat)
            end
        end
    end
    return nonfoldseats
end

-- 下注定时器
local function onBettingTimer(self)
    local function doRun()
        local current_betting_seat = self.seats[self.current_betting_pos]
        log.info(
            "idx(%s,%s,%s) onBettingTimer() over time bettingpos:%s uid:%s",
            self.id,
            self.mid,
            self.logid,
            self.current_betting_pos,
            current_betting_seat and current_betting_seat.uid or 0
        )
        if not current_betting_seat then
            log.error("idx(%s,%s,%s) onBettingTimer(),current_betting_pos=%s", self.current_betting_pos)
            return
        end

        local user = self.users[current_betting_seat.uid]
        if current_betting_seat:isChipinTimeout() then -- 判断是否操作超时
            timer.cancel(self.timer, TimerID.TimerID_Betting[1]) -- 关闭下注超时定时器
            if user then
                user.is_bet_timeout = true
                user.bet_timeout_count = user.bet_timeout_count or 0
                user.bet_timeout_count = user.bet_timeout_count + 1 -- 增加操作超时次数
                log.debug("idx(%s,%s,%s) onBettingTimer(),uid=%s, bet_timeout_count=%s", self.id, self.mid, self.logid,
                    current_betting_seat.uid,
                    user.bet_timeout_count)
            end
            if self.state >= pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCards1") then
                self:userchipin(
                    current_betting_seat.uid,
                    pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK"), -- 默认是过牌操作
                    current_betting_seat.roundmoney
                )
            else
                self:userchipin(current_betting_seat.uid,
                    pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"), 0) -- 弃牌操作
            end
        end
    end

    g.call(doRun)
end

-- 广播轮到该座位玩家下注
function Room:betting(seat)
    if not seat then
        log.error("idx(%s,%s,%s) betting(),seat==nil", self.id, self.mid, self.logid)
        return false
    end

    seat.bettingtime = global.ctsec() -- 该座位玩家开始下注时刻(秒)
    self.current_betting_pos = seat.sid -- 当前下注位置
    log.info("idx(%s,%s,%s) betting(),current_betting_pos=%s,uid=%s", self.id, self.mid, self.logid,
        self.current_betting_pos, tostring(seat.uid))

    local function notifyBetting() -- 通知下注
        self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_BETING")) -- 下注中
        timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBettingTimer, self) -- 设置下注超时定时器
    end

    -- 预操作
    local preop = seat:getPreOP()
    log.debug("idx(%s,%s,%s) betting(),preop=%s", self.id, self.mid, self.logid, preop)
    if preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None") then
        notifyBetting()
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_CheckOrFold") then -- 过牌或弃牌
        self:userchipin(
            seat.uid,
            pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK"),
            seat.roundmoney
        )
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_AutoCheck") then
        local maxraise_seat = self.seats[self.maxraisepos] and self.seats[self.maxraisepos] or { roundmoney = 0 }
        if seat.roundmoney < maxraise_seat.roundmoney then
            notifyBetting()
        else
            self:userchipin(seat.uid, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_CHECK"), 0)
        end
    elseif preop == pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny") then
        log.error("idx(%s,%s,%s) betting(),preop=PBTexasPreOPType_RaiseAny", self.id, self.mid, self.logid)
        return false
    else
        log.error("idx(%s,%s,%s) betting(),preop=%s", self.id, self.mid, self.logid, tostring(preop))
        return false
    end
    return true
end

-- 广播亮牌
function Room:broadcastShowCardToAll()
    log.debug("idx(%s,%s,%s) broadcastShowCardToAll()", self.id, self.mid, self.logid)
    -- 获取未弃牌玩家数
    local notFoldPlayerNum = self:getNotFoldPlayerNum()
    if notFoldPlayerNum < 2 then
        return
    end

    for i = 1, #self.seats do
        local seat = self.seats[i]
        if not seat.hasLeave and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"))
            and seat.cardsNum >= 2 then -- 如果参与游戏且未弃牌

            local showdealcard = {
                showType = seat.cardsType, -- 牌型
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

--
function Room:broadcastCanShowCardToAll(poss)
    log.debug("idx(%s,%s,%s) broadcastCanShowCardToAll()", self.id, self.mid, self.logid)
    local showpos = {}
    for i = 1, #self.seats do
        showpos[i] = false
    end

    -- 摊牌前最后一个弃牌的玩家可以主动亮牌
    if self.lastchipintype == pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") and
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
            if not showpos[i] and not seat.show and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_REBUYING"))
                and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"))
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

-- 结算
function Room:finish()
    log.info("idx(%s,%s,%s) finish(),potidx:%s", self.id, self.mid, self.logid, self.potidx)

    for _, user in pairs(self.users) do -- 遍历每个玩家
        if user and not self.has_player_inplay and not Utils:isRobot(user.api) then
            local seat = self:getSeatByUid(user.uid)
            if seat and seat.isplaying then
                self.has_player_inplay = true -- 判断是否有真实玩家参与游戏
                break
            end
        end
    end

    self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Finish")) -- 结算状态

    timer.cancel(self.timer, TimerID.TimerID_Betting[1])

    -- 计算在玩玩家最佳牌形和最佳手牌，用于后续比较
    self.sdata.jp = self.sdata.jp or { minichips = self.minchip }
    self.sdata.jp.uid = nil
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if not seat.hasLeave and seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")
            and seat.isplaying then -- 如果该座位玩家参与游戏且未弃牌
            seat.besthand = self:getMaxCards(seat.handcards, seat.cardsNum) -- 最大手牌
            seat.cardsType = Seotda:GetCardsType(seat.besthand) -- 牌型
        end
    end

    self:broadcastShowCardToAll()

    self:calcResult() --计算本局游戏结果

    --local total_winner_info = {} -- 总的奖池分池信息，哪些人在哪些奖池上赢取多少钱都在里面
    local FinalGame = { potInfos = {}, profits = {}, seatMoney = {} }

    for sid, seat in ipairs(self.seats) do
        if seat then
            table.insert(FinalGame.seatMoney, seat.chips) -- 各座位的当前筹码
            if seat.isplaying and not seat.hasLeave then
                -- local pot = { sid = seat.sid, winMoney = seat.winmoney - seat.total_bets, seatMoney = seat.chips }
                -- if pot.winMoney > 0 then
                --     table.insert(FinalGame.potInfos, pot)
                -- end

                -- for i = 1, self.potidx do
                --     if self.pots[i] and self.pots[i].seats and self.pots[i].seats[seat.sid] then
                --         -- 计算表中有效元素个数
                --         local num = 0
                --         for k, v in ipairs(self.seats) do
                --             if self.pots[i].seats[k] then
                --                 num = num + 1
                --             end
                --         end
                --         local pot = { sid = seat.sid, winMoney = math.floor(self.pots[i].money / num), seatMoney = seat.chips, potID=i }
                --         table.insert(FinalGame.potInfos, pot)
                --     end
                -- end

                --table.insert(FinalGame.profits, seat.winmoney - seat.total_bets)
                table.insert(FinalGame.profits, seat.chips - seat.last_chips) -- 各座位的盈利额
                log.debug("idx(%s,%s,%s) finish(),sid=%s, chips=%s,last_chips=%s,winmoney=%s,total_bets=%s",
                    self.id, self.mid, self.logid, seat.sid, seat.chips, seat.last_chips, seat.winmoney, seat.total_bets)
            else
                table.insert(FinalGame.profits, 0)
            end
        end
    end

    for i = 1, self.potidx do
        if self.pots[i] and self.pots[i].seats then
            local seats = {}
            for k, v in ipairs(self.seats) do
                if self.pots[i].seats[k] then
                    table.insert(seats, k)
                end
            end

            -- 获取未弃牌的玩家列表
            seats = self:getNotFoldSidList(seats)
            if #seats > 1 then
                seats = self:getMaxCardsSid(seats) -- 获取赢家SID列表
            end
            for j = 1, #seats do
                local pot = { sid = seats[j], winMoney = math.floor(self.pots[i].money / #seats),
                    seatMoney = self.seats[seats[j]].chips, potID = i }
                table.insert(FinalGame.potInfos, pot)
            end
        end
    end


    -- 广播结算
    log.info("idx(%s,%s,%s) finish(),PBSeotdaFinalGame=%s", self.id, self.mid, self.logid, cjson.encode(FinalGame))
    pb.encode(
        "network.cmd.PBSeotdaFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaFinalGame"),
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
                "idx(%s,%s,%s) finish(),chips change uid:%s chips:%s last_chips:%s totalbuyin:%s totalwin:%s",
                self.id,
                self.mid,
                self.logid,
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
            self.sdata.users[v.uid].totalfee = self.conf.fee
            self.sdata.users[v.uid].ugameinfo = self.sdata.users[v.uid].ugameinfo or {}
            self.sdata.users[v.uid].ugameinfo.texas = self.sdata.users[v.uid].ugameinfo.texas or {}
            self.sdata.users[v.uid].ugameinfo.texas.inctotalhands = 1
            self.sdata.users[v.uid].ugameinfo.texas.inctotalwinhands = (win > 0) and 1 or 0
            self.sdata.users[v.uid].ugameinfo.texas.bestcards = v.besthand
            self.sdata.users[v.uid].ugameinfo.texas.bestcardstype = v.cardsType
            self.sdata.users[v.uid].ugameinfo.texas.leftchips = v.chips
            -- 输家防倒币行为
            if self:checkWinnerAndLoserAreAllReal() and v.uid == self.maxLoserUID and self.sdata.users[v.uid].extrainfo then
                local extrainfo = cjson.decode(self.sdata.users[v.uid].extrainfo)
                if not Utils:isRobot(user.api) and extrainfo then -- 如果不是机器人
                    local ischeat = false
                end
            end
        end
    end

    -- 赢家防倒币行为
    for _, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying then
            if self.has_cheat and self.maxWinerUID == v.uid and self.sdata.users[v.uid].totalpureprofit > 0 and
                self.sdata.users[v.uid].extrainfo
            then -- 盈利玩家
                local extrainfo = cjson.decode(self.sdata.users[v.uid].extrainfo)
                if not Utils:isRobot(user.api) and extrainfo then
                    extrainfo["cheat"] = true -- 作弊
                    self.sdata.users[v.uid].extrainfo = cjson.encode(extrainfo)
                    log.debug("idx(%s,%s,%s) finish(),cheat winner uid=%s", self.id, self.mid, self.logid, v.uid)
                end
            end
        end
    end

    self.sdata.etime = self.endtime

    -- 实时牌局(牌局记录)
    local reviewlog = {
        buttonuid = self.seats[self.buttonpos] and self.seats[self.buttonpos].uid or 0, -- 庄家UID
        pot = 0, -- 公共池
        items = {}
    }
    reviewlog.pot = self:getTotalBet() -- 下注池总金额
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if user and v.isplaying and not v.hasLeave then -- 如果该玩家存在 且 该座位参与游戏
            local logItem = {
                player = { uid = v.uid, username = user.username or "" },
                handcards = { -- 手牌信息
                    sid = v.sid,
                    card1 = v.handcards[1], -- 待比较的牌数据(前2张牌是待比较的牌)
                    card2 = v.handcards[2], -- 待比较的牌数据
                    cardsNum = v.cardsNum, -- 手牌张数
                    cardsType = v.cardsType, -- 手牌牌型
                    handcards = g.copy(v.handcards),
                    firstCard = v.firstShowCard, -- 三张中第一张要显示的牌
                    roundNum = v.roundNum,
                    secondCard = v.secondCard -- 第二张手牌
                },

                bestcardstype = v.cardsType, -- 最大牌牌型
                win = v.chips - v.last_chips, -- 输赢情况
                roundchipintypes = v.roundchipintypes,
                roundchipinmoneys = v.roundchipinmoneys
            }
            if v.roundNum >= 3 then
                logItem.handcards.replayCards = g.copy(v.replayCards)
            end
            if v.cardsNum == 1 then
                logItem.handcards.card1 = 0
                logItem.handcards.card2 = 0
                logItem.handcards.handcards[2] = 0
            end
            if 0 ~= (v.operateTypes & (1 << 20)) then
                logItem.showhandcards = true
            else
                logItem.showhandcards = false
            end

            table.insert(reviewlog.items, logItem)
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
    log.info("idx(%s,%s,%s) finish(),reviewlog %s", self.id, self.mid, self.logid, cjson.encode(reviewlog))

    for _, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and seat.isplaying and not seat.hasLeave then
            if not Utils:isRobot(user.api) and self.sdata.users[seat.uid].extrainfo then -- 盈利玩家
                local extrainfo = cjson.decode(self.sdata.users[seat.uid].extrainfo)
                if extrainfo then
                    extrainfo["totalmoney"] = (self:getUserMoney(seat.uid) or 0) + seat.chips -- 总金额
                    log.debug("self.sdata.users[uid].extrainfo uid=%s,totalmoney=%s", seat.uid, extrainfo["totalmoney"])
                    self.sdata.users[seat.uid].extrainfo = cjson.encode(extrainfo)
                end
            end
            if not Utils:isRobot(user.api) then
                Utils:updateChipsNum(global.sid(), user.uid, seat.chips)
            end
        end
    end

    if self:needLog() then
        self.statistic:appendLogs(self.sdata, self.logid)
    end

    for sid, seat in ipairs(self.seats) do -- 遍历每个座位
        if seat then
            seat:flush()
        end
    end

    local t_msec = 4000
    if self.potidx > 2 then
        t_msec = t_msec + 500 * (self.potidx - 2)
    end
    timer.tick(self.timer, TimerID.TimerID_OnFinish[1], t_msec, onFinish, self)

end

-- 更新边池
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
    log.debug("idx(%s,%s,%s) sendUpdatePotsToAll(),PBTexasUpdatePots=%s", self.id, self.mid, self.logid,
        cjson.encode(updatepots))
    return true
end

-- 一轮结束(下注结束) 更新玩家身上金额
-- 返回值:如果真正结束则返回false,需要通知玩家操作则返回true
function Room:roundOver()
    log.debug("idx(%s,%s,%s) roundOver()", self.id, self.mid, self.logid)

    -- local isallfold = self:isAllFold() -- 是否所有玩家都弃牌
    -- local isallallin = self:isAllAllin() -- 是否所有玩家都AllIn
    -- local allin = {} -- 存放本轮各种下注额(相同下注额只会存放一次)

    -- 一轮结束后，更新各玩家身上筹码
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying then
            seat.operateTypesRound = 0
            if seat.roundmoney > 0 then -- 如果本轮下注了
                seat.money = seat.money + seat.roundmoney -- 一局总消耗筹码数
                seat.total_bets = seat.total_bets + seat.roundmoney
                seat.betmoney = seat.total_bets
                seat.chips = seat.chips > seat.roundmoney and seat.chips - seat.roundmoney or 0 -- 身上剩余筹码
                seat.roundmoney = 0
                local user = self.users[seat.uid]
                if user and not Utils:isRobot(user.api) then
                    Utils:updateChipsNum(global.sid(), seat.uid, seat.chips or 0)
                end
            end
        end
    end

    self:getPotsByBets()

    self:sendUpdatePotsToAll()
end

--
function Room:setcard()
    log.info("idx(%s,%s,%s) setcard()", self.id, self.mid, self.logid)
    self.cfgcard:init()
end

--
function Room:check()
    log.debug("idx(%s,%s,%s) check()", self.id, self.mid, self.logid)
    if global.stopping() then
        log.debug("idx(%s,%s,%s) check(),stopping", self.id, self.mid, self.logid)
        return
    end

    -- local cnt = 0 -- 参与游戏的座位数
    -- for k, v in ipairs(self.seats) do
    --     if v.isplaying then
    --         cnt = cnt + 1
    --     end
    -- end

    --if cnt <= 1 then
    --timer.cancel(self.timer, TimerID.TimerID_Start[1])
    -- timer.cancel(self.timer, TimerID.TimerID_Betting[1])
    -- timer.cancel(self.timer, TimerID.TimerID_PrechipsRoundOver[1])
    -- timer.cancel(self.timer, TimerID.TimerID_StartPreflop[1])
    -- timer.cancel(self.timer, TimerID.TimerID_OnFinish[1])

    timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 定时检测
    --end
end

function Room:userShowCard(uid, linkid, rev)

end

-- 玩家站起
function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userStand(),uid:%s", self.id, self.mid, self.logid, uid)

    local seat = self:getSeatByUid(uid)
    local user = self.users[uid]
    if seat and user then
        if not seat.hasLeave and seat.isplaying and
            self.state >= pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Start") and
            self.state < pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Finish") and
            self:getPlayingSize() > 1 -- 如果还在游戏过程中
        then
            if seat.sid == self.current_betting_pos then -- 如果刚轮到该玩家操作
                self:userchipin(uid, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"), 0) -- 弃牌
                self:stand(
                    self.seats[seat.sid],
                    uid,
                    pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                )
                log.debug("idx(%s,%s,%s) userStand(),uid=%s,seat.sid == self.current_betting_pos", self.id, self.mid,
                    self.logid, uid)
            else -- 尚未轮到该玩家操作
                if not seat.isplaying then -- 如果该玩家未参与游戏
                    self:stand(self.seats[seat.sid], uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
                    log.debug("idx(%s,%s,%s) userStand(),uid=%s,seat.isplaying == false", self.id, self.mid, self.logid,
                        uid)
                elseif not
                    self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏且还未弃牌
                    seat:chipin(pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"), seat.roundmoney) -- 弃牌操作
                    self:stand(
                        self.seats[seat.sid],
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                    )
                    log.debug("idx(%s,%s,%s) userStand(),uid=%s,FOLD", self.id, self.mid, self.logid, uid) -- 弃牌操作
                elseif self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏但已弃牌
                    self:stand(
                        self.seats[seat.sid],
                        uid,
                        pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
                    )
                    log.debug("idx(%s,%s,%s) userStand(),uid=%s,has FOLD", self.id, self.mid, self.logid, uid) -- 弃牌操作
                end

                -- 检测是否游戏结束
                if self:checkGameOver() then
                    self:finish() -- 立马结束游戏
                end
            end

            log.info("idx(%s,%s,%s) userStand(),uid:%s,state=%s", self.id, self.mid, self.logid, uid, self.state)
            return true
            -- end
        end

        -- 站起
        self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")) -- 普通类型站起
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
        if not user then
            log.debug("idx(%s,%s,%s) userStand(),uid:%s,user==nil", self.id, self.mid, self.logid, uid)
        else
            log.debug("idx(%s,%s,%s) userStand(),uid:%s,seat==nil", self.id, self.mid, self.logid, uid)
        end
    end
end

-- 玩家坐下
function Room:userSit(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userSit() req sit down,uid=%s,sid=%s", self.id, self.mid, self.logid, uid, tostring(rev.sid))

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid)
    local dsts = self.seats[rev.sid]

    if not user or (srcs and not srcs.hasLeave) or not dsts or (not dsts.hasLeave or dsts.uid) --[[or not is_buyin_ok ]] then
        log.info("idx(%s,%s,%s) userSit(),sit failed,uid=%s", self.id, self.mid, self.logid, uid)
        if not user then
            log.info("idx(%s,%s,%s) userSit(),uid=%s not user", self.id, self.mid, self.logid, uid)
        elseif srcs and not srcs.hasLeave then
            log.info("idx(%s,%s,%s) userSit(),uid=%s srcs.hasLeave=false", self.id, self.mid, self.logid, uid)
        elseif not dsts then
            log.info("idx(%s,%s,%s) userSit(),uid=%s not dsts", self.id, self.mid, self.logid, uid)
        elseif not dsts.hasLeave then
            log.info("idx(%s,%s,%s) userSit(),uid=%s,dsts.hasLeave=false", self.id, self.mid, self.logid, uid)
        elseif dsts.uid then
            log.info("idx(%s,%s,%s) userSit(),uid=%s,dsts.hasLeave=false", self.id, self.mid, self.logid, uid)
        end

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

-- 买入筹码
-- 参数 uid: 买入者UID
-- 参数 system: 是否是系统自动买入
function Room:userBuyin(uid, linkid, rev, system)
    log.info("idx(%s,%s,%s) userBuyin(), uid=%s, buyinmoney=%s", self.id, self.mid, self.logid, uid,
        tostring(rev.buyinMoney))

    local buyinmoney = rev.buyinMoney or 0 -- 要买入的筹码量
    local function handleFailed(code) -- 买入失败处理
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasBuyinFailed"), -- 买入失败
            pb.encode("network.cmd.PBTexasBuyinFailed", { code = code, context = rev.context })
        )
    end

    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) userBuyin(), uid=%s userBuyin invalid user", self.id, self.mid, self.logid, uid)
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidUser"))
        return false
    end
    if user.buyin and coroutine.status(user.buyin) ~= "dead" then -- 如果已经在买入
        log.info("idx(%s,%s,%s) userBuyin(), uid %s userBuyin is buying", self.id, self.mid, self.logid, uid)
        return false
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) userBuyin invalid seat", self.id, self.mid, self.logid)
        handleFailed(pb.enum_id("network.cmd.PBTexasBuyinResultType", "PBTexasBuyinResultType_InvalidSeat"))
        return false
    end
    if Utils:isRobot(user.api) and (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.sb) then
        buyinmoney = self.conf.maxbuyinbb * self.conf.sb - (seat.chips - seat.roundmoney)
    end
    if (buyinmoney + (seat.chips - seat.roundmoney) < self.conf.minbuyinbb * self.conf.sb) or
        (buyinmoney + (seat.chips - seat.roundmoney) > self.conf.maxbuyinbb * self.conf.sb) or
        (buyinmoney == 0 and (seat.chips - seat.roundmoney) >= self.conf.maxbuyinbb * self.conf.sb)
    then
        log.info(
            "idx(%s,%s,%s) userBuyin over limit: minbuyinbb %s, maxbuyinbb %s, sb %s",
            self.id,
            self.mid,
            self.logid,
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

    user.buyin = coroutine.create(
        function(user)
            log.info(
                "idx(%s,%s,%s) uid %s userBuyin start buyinmoney %s seatchips %s money %s coin %s",
                self.id,
                self.mid,
                self.logid,
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
                    roundId = user.roundId or ""
                }
            )
            local ok = coroutine.yield()
            timer.cancel(self.timer, TimerID.TimerID_Buyin[1] + 100 + uid)
            if not ok then
                log.info(
                    "idx(%s,%s,%s) userBuyin not enough money: buyinmoney %s, user money %s",
                    self.id,
                    self.mid,
                    self.logid,
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
            if not seat.isplaying or
                self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) or
                self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None")
            then
                seat:buyinToChips()
                if not Utils:isRobot(user.api) then
                    Utils:updateChipsNum(global.sid(), uid, seat.chips)
                end
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
                "idx(%s,%s,%s) uid %s userBuyin result buyinmoney %s seatchips %s money %s coin %s",
                self.id,
                self.mid,
                self.logid,
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

--
function Room:userChat(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userChat() uid=%s", self.id, self.mid, self.logid, uid)
    if not rev.type or not rev.content then
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) user:%s is not in room", self.id, self.mid, self.logid, uid)
        return
    end
    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) user:%s is not in seat", self.id, self.mid, self.logid, uid)
        return
    end
    if #rev.content > 200 then
        log.info("idx(%s,%s,%s) content over length limit", self.id, self.mid, self.logid)
        return
    end
    pb.encode(
        "network.cmd.PBGameNotifyChat_N",
        { sid = seat.sid, type = rev.type, content = rev.content },
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

--
function Room:userTool(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userTool() uid=%s,fromsid=%s,tosid=%s", self.id, self.mid, self.logid, uid,
        tostring(rev.fromsid), tostring(rev.tosid))
    local function handleFailed(code)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameToolSendResp"),
            pb.encode("network.cmd.PBGameToolSendResp_S", { code = code or 0, toolID = rev.toolID, leftNum = 0 })
        )
    end

    if not self.seats[rev.fromsid] or self.seats[rev.fromsid].uid ~= uid then
        log.info("idx(%s,%s,%s) invalid fromsid %s", self.id, self.mid, self.logid, rev.fromsid)
        handleFailed()
        return
    end
    if not self.seats[rev.tosid] or self.seats[rev.tosid].uid == 0 then
        log.info("idx(%s,%s,%s) invalid tosid %s", self.id, self.mid, self.logid, rev.tosid)
        handleFailed()
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) invalid user %s", self.id, self.mid, self.logid, uid)
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
        log.info("idx(%s,%s,%s) not enough money %s,%s", self.id, self.mid, self.logid, uid, self:getUserMoney(uid))
        handleFailed(1)
        return
    end
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s,%s) uid %s coroutine is expensing", self.id, self.mid, self.logid, uid)
        return false
    end

    -- 扣钱
    if self.conf and self.conf.toolcost > 0 then
        user.expense = coroutine.create(
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
                    log.info("idx(%s,%s,%s) expense uid %s not enough money", self.id, self.mid, self.logid, uid)
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
            { uid, self }
        )
        coroutine.resume(user.expense, user)
    end
end

--
function Room:userSituation(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userSituation() uid=%s", self.id, self.mid, self.logid, uid)

    local t = { situations = {} }

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
        log.info("idx(%s,%s,%s) userSituation invalid user", self.id, self.mid, self.logid)
        resp()
        return
    end

    for uid, user in pairs(self.users) do
        if user.totalbuyin and user.totalbuyin > 0 then
            table.insert(
                t.situations,
                {
                    player = { uid = uid, username = user.username or "" },
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

--
function Room:userReview(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userReview() uid %s", self.id, self.mid, self.logid, uid)

    local t = { reviews = {} }
    local function resp()
        log.info("idx(%s,%s,%s) userReview(),PBSeotdaReviewResp=%s", self.id, self.mid, self.logid, cjson.encode(t))
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReviewResp"),
            pb.encode("network.cmd.PBSeotdaReviewResp", t)
        )
    end

    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not user then
        log.info("idx(%s,%s,%s) userReview invalid user", self.id, self.mid, self.logid)
        resp()
        return
    end

    for _, reviewlog in ipairs(self.reviewlogs:getLogs()) do
        local tmp = g.copy(reviewlog)
        for _, item in ipairs(tmp.items) do
            if item.player and item.player.uid ~= uid and not item.showhandcards then
                if item.handcards then
                    item.handcards.handcards[1] = 0
                    item.handcards.handcards[2] = 0
                    item.handcards.handcards[3] = 0
                    item.handcards.card1 = 0
                    item.handcards.card2 = 0
                end
            end
        end
        table.insert(t.reviews, tmp)
    end
    resp()
end

-- 预操作
function Room:userPreOperate(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userRreOperate() uid %s preop %s", self.id, self.mid, self.logid, uid,
        tostring(rev.preop))

    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not user then
        log.info("idx(%s,%s,%s) userPreOperate invalid user", self.id, self.mid, self.logid)
        return
    end
    if not seat then
        log.info("idx(%s,%s,%s) userPreOperate invalid seat", self.id, self.mid, self.logid)
        return
    end
    if not rev.preop or rev.preop < pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_None") or
        rev.preop >= pb.enum_id("network.cmd.PBTexasPreOPType", "PBTexasPreOPType_RaiseAny")
    then
        log.info("idx(%s,%s,%s) userPreOperate invalid type", self.id, self.mid, self.logid) -- 预操作类型无效
        return
    end

    seat:setPreOP(rev.preop)

    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPreOperateResp"),
        pb.encode("network.cmd.PBTexasPreOperateResp", { preop = seat:getPreOP() })
    )
end

-- 请求增加思考时间
function Room:userAddTime(uid, linkid, rev)
    log.info("idx(%s,%s,%s) req addtime uid:%s", self.id, self.mid, self.logid, uid)

    local function handleFailed(code) -- 失败处理
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasAddTimeResp"),
            pb.encode("network.cmd.PBTexasAddTimeResp", { idx = rev.idx, code = code or 0 })
        )
    end

    local seat = self:getSeatByUid(uid)
    if not seat then
        log.info("idx(%s,%s,%s) user add time: seat not valid", self.id, self.mid, self.logid)
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) user add time: user not valid", self.id, self.mid, self.logid)
        return
    end
    if user.expense and coroutine.status(user.expense) ~= "dead" then
        log.info("idx(%s,%s,%s) uid %s coroutine is expensing", self.id, self.mid, self.logid, uid)
        return false
    end
    if self.current_betting_pos ~= seat.sid then
        log.info("idx(%s,%s,%s) user add time: user is not betting pos", self.id, self.mid, self.logid)
        return
    end
    -- print(seat, user, self.current_betting_pos, seat and seat.sid)
    if self.conf and self.conf.addtimecost and seat.addon_count >= #self.conf.addtimecost then
        log.info("idx(%s,%s,%s) user add time: addtime count over limit %s", self.id, self.mid, self.logid,
            seat.addon_count)
        return
    end
    if self:getUserMoney(uid) < (self.conf and self.conf.addtimecost[seat.addon_count + 1] or 0) then
        log.info("idx(%s,%s,%s) user add time: not enough money %s", self.id, self.mid, self.logid, uid)
        handleFailed(1)
        return
    end
    if self.conf.addtimecost[seat.addon_count + 1] > 0 then
        user.expense = coroutine.create(
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
                    log.info("idx(%s,%s,%s) expense uid %s not enough money", self.id, self.mid, self.logid, uid)
                    handleFailed(1)
                    return false
                end
                seat.addon_time = seat.addon_time + (self.conf.addtime or 0)
                seat.addon_count = seat.addon_count + 1
                seat.total_time = seat:getChipinLeftTime()
                self:sendPosInfoToAll(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_BETING"))
                timer.cancel(self.timer, TimerID.TimerID_Betting[1])
                timer.tick(self.timer, TimerID.TimerID_Betting[1], seat.total_time * 1000, onBettingTimer, self)
            end
        )
        timer.tick(
            user.TimerID_Expense,
            TimerID.TimerID_Expense[1],
            TimerID.TimerID_Expense[2],
            onExpenseTimeout,
            { uid, self }
        )
        coroutine.resume(user.expense, user)
    end
end

function Room:userEnforceShowCard(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userEnforceShowCard:%s", self.id, self.mid, self.logid, uid)
end

function Room:userNextRoundPubCardReq(uid, linkid, rev)
    log.info("idx(%s,%s,%s) userNextRoundPubCardReq:%s", self.id, self.mid, self.logid, uid)
end

-- 获取桌子列表信息
function Room:userTableListInfoReq(uid, linkid, rev)
    -- log.info("idx(%s,%s,%s) userTableListInfoReq:%s", self.id, self.mid, self.logid, uid)
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
    log.info("idx(%s,%s,%s) userTableListInfoReq(),PBTexasTableListInfoResp=%s", self.id, self.mid, self.logid,
        cjson.encode(t))
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
        log.info("idx(%s,%s,%s) not in seat %s", self.id, self.mid, self.logid, uid)
        return false
    end

    log.info("idx(%s,%s,%s) userJackPotResp:%s,%s,%s,%s", self.id, self.mid, self.logid, uid, roomtype, value, jackpot)
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
                    wintype = seat.cardsType
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
            "idx(%s,%s,%s) jackpot animation is to be playing sid=%s,uid=%s,value=%s,cardsType=%s",
            self.id,
            self.mid,
            self.logid,
            seat.sid,
            uid,
            value,
            seat.cardsType
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
        { jackpot = jackpot },
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

-- 增加或减少玩家身上金额
function Room:phpMoneyUpdate(uid, rev)
    log.info("(%s,%s)phpMoneyUpdate %s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user then
        user.money = user.money + rev.money
        user.coin = user.coin + rev.coin
        log.info("(%s,%s)phpMoneyUpdate %s,%s,%s", self.id, self.mid, uid, tostring(rev.money), tostring(rev.coin))
    end
end

-- 是否需要保存统计数据
function Room:needLog()
    log.debug("idx(%s,%s,%s) needLog() has_player_inplay=%s", self.id, self.mid, self.logid,
        tostring(self.has_player_inplay))
    return self.has_player_inplay or (self.sdata and self.sdata.jp and self.sdata.jp.id)
end

-- 获取玩家IP地址
function Room:getUserIp(uid)
    local user = self.users[uid]
    if user then
        return user.ip or ""
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

-- 更新玩家身上金额
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
                if not self.conf.roomtype or
                    self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money")
                then
                    user.money = v.money
                elseif self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
                    user.coin = v.coin
                end
            end
            if user.buyin and coroutine.status(user.buyin) == "suspended" then
                coroutine.resume(user.buyin, v.code > 0) -- 唤醒买入协程
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

function Room:checkWinnerAndLoserAreAllReal()
    return false
end

-------------------------------------------------------------


-- 每轮结束后都会检测
-- 检测游戏是否结束，若结束则返回true
-- 结束条件:其他所有玩家弃牌 或 第二轮比牌获胜
function Room:checkGameOver()
    if self:isAllFold() then -- 如果所有玩家弃牌，则未弃牌者直接获胜，无需再发牌
        return true
    end
    -- 如果所有未弃牌玩家都allin或跟注了且发完第二轮牌，也结束游戏
    if self:isAllAllinOrCall() and
        self.state >= pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCard2") and
        not self:checkNeedReplay() then
        return true
    end
    return false
end

-- 检测是否一轮结束
-- 返回值: 成功结束则返回true
function Room:checkRoundOver()
    log.debug("idx(%s,%s,%s) checkRoundOver()", self.id, self.mid, self.logid)

    -- 判断该局所有玩家是否都操作了
    local hasNotBetPlayer = false -- 本轮是否还有未下注玩家
    local roundmoneyMax = 0 -- 本轮最大下注金额
    local notFoldPlayerNum = 0 -- 未弃牌玩家数

    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家未弃牌
            if seat.operateTypesRound == 0 and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")) then
                return false -- 还有玩家未操作
            end

            if seat.roundmoney > roundmoneyMax then -- 如果该玩家下注了
                roundmoneyMax = seat.roundmoney
            end
            notFoldPlayerNum = notFoldPlayerNum + 1
        end
    end

    if notFoldPlayerNum <= 1 then
        return true
    end

    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then
            if seat.roundmoney < roundmoneyMax then -- 如果该玩家下注了,但下注金额不够
                if not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")) then
                    return false -- 不是AllIn
                end
            end
        end
    end

    return true -- 该轮未结束
end

-- 洗牌
function Room:shuffleCards()
    local cardsNum = #self.cards
    local randValue = rand.rand_between(1, cardsNum)
    for i = 1, cardsNum do
        randValue = rand.rand_between(1, cardsNum)
        self.cards[i], self.cards[randValue] = self.cards[randValue], self.cards[i]
    end
    self.pokeridx = 0
    log.debug("idx(%s,%s,%s) shuffleCards() self.cards=%s", self.id, self.mid, self.logid,
        cjson.encode(self.cards))
end

-- 给未弃牌玩家发牌(前两每轮只发一张牌，之后每轮发2张牌)
-- 参数 type: 1-第一轮发牌  2-第二轮发牌 3-重赛发牌
function Room:dealCards(type)
    -- self:shuffleCards()  -- 发牌前必须已经洗完牌
    -- 配牌器

    if type == 1 then
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏且未弃牌
                self.pokeridx = self.pokeridx + 1
                seat.handcards[1] = self.cards[self.pokeridx] or 0 -- 发第一张牌
                self.pokeridx = self.pokeridx + 1
                seat.handcards[2] = self.cards[self.pokeridx] or 0 -- 发第二张牌
                self.pokeridx = self.pokeridx + 1
                seat.handcards[3] = self.cards[self.pokeridx] or 0 -- 发第三张牌
                seat.cardsType = Seotda:GetCardsType(seat.handcards) -- 牌型
                seat.secondCard = seat.handcards[2]
                seat.cardsNum = 2
                seat.roundNum = 1
                self.sdata.cards = self.sdata.cards or {} -- 牌数据
                if seat.uid then
                    self.sdata.users = self.sdata.users or {}
                    self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                    self.sdata.users[seat.uid].cards = { seat.handcards[1], seat.handcards[2] }
                end
            end
        end
    elseif type == 2 then -- 第二轮发牌
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏且未弃牌
                seat.cardsNum = 3
                seat.cardsType = Seotda:GetCardsType(seat.handcards) -- 牌型
                seat.roundNum = 1
                self.sdata.cards = self.sdata.cards or {} -- 牌数据
                if seat.uid then
                    self.sdata.users = self.sdata.users or {}
                    self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                    self.sdata.users[seat.uid].cards = { seat.handcards[1], seat.handcards[2], seat.handcards[3] }
                end
            end
        end
    else -- 重赛发牌
        self:shuffleCards() -- 发牌前必须已经洗完牌
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏且未弃牌
                if seat.roundNum < 3 then
                    seat.roundNum = 3
                    seat.replayCards = g.copy(seat.handcards) -- 保存原来的手牌数据
                else
                    seat.roundNum = seat.roundNum + 1
                end
                seat.cardsNum = 2 -- 给未弃牌玩家重新发牌
                self.pokeridx = self.pokeridx + 1
                seat.handcards[1] = self.cards[self.pokeridx] or 0 -- 发第一张牌
                self.pokeridx = self.pokeridx + 1
                seat.handcards[2] = self.cards[self.pokeridx] or 0 -- 发第二张牌
                seat.secondCard = seat.handcards[2]
                seat.handcards[3] = 0
                seat.cardsType = Seotda:GetCardsType(seat.handcards) -- 牌型

                self.sdata.cards = self.sdata.cards or {} -- 牌数据
                if seat.uid then
                    self.sdata.users = self.sdata.users or {}
                    self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                    table.insert(self.sdata.users[seat.uid].cards, seat.handcards[1])
                    table.insert(self.sdata.users[seat.uid].cards, seat.handcards[2])
                end
            else
                seat.cardsNum = 0
                seat.handcards = { 0, 0, 0 }
            end
        end
    end

    if self.cfgcard_switch then -- 如果使用配牌器发牌
        self.cfgcard:init()
        for sid, seat in ipairs(self.seats) do
            if seat and seat.isplaying and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏且未弃牌
                seat.handcards[1] = self.cfgcard:popHand()
                seat.handcards[2] = self.cfgcard:popHand()
                if seat.cardsNum >= 2 then
                    seat.cardsType = Seotda:GetCardsType(seat.handcards) -- 牌型
                end
            end
        end
    end


    local dealcard = {}
    local robotlist = {} -- 机器人UID 列表
    local hasplayer = false -- 是否有真实玩家参与游戏
    local realPlayerUID = 0 -- 真实玩家UID

    for _, seat in ipairs(self.seats) do
        table.insert(dealcard,
            { sid = seat.sid, handcards = { 0, 0, 0 }, cardsNum = seat.cardsNum or 0, roundNum = seat.roundNum })
        local user = self.users[seat.uid]
        if user and seat.isplaying then -- 如果该玩家在该桌
            if Utils:isRobot(user.api) then -- 如果是机器人
                table.insert(robotlist, seat.uid)
            else
                realPlayerUID = seat.uid
                hasplayer = true -- 有真人参与游戏
            end
        end
    end

    -- 广播牌背给所有在玩玩家
    for uid, user in pairs(self.users) do
        if user.state == EnumUserState.Playing then -- 如果该玩家参与游戏
            local seat = self:getSeatByUid(user.uid)

            if seat and seat.isplaying then -- 如果该玩家参与游戏(添加该玩家的牌数据)
                for _, item in ipairs(dealcard) do
                    if seat.sid == item.sid then
                        item.handcards = g.copy(seat.handcards) -- 拷贝牌数据
                        item.card1 = seat.handcards[1]
                        item.card2 = seat.handcards[2]
                        if seat.secondCard ~= item.card2 then
                            item.card1, item.card2 = item.card2, item.card1
                        end

                        item.cardsNum = seat.cardsNum
                        if seat.cardsNum == 1 then
                            item.handcards[2] = 0
                        elseif seat.cardsNum == 2 then
                            item.cardsType = seat.cardsType
                            item.handcards[3] = 0
                        elseif seat.cardsNum == 3 then
                            item.groups = {}
                            local group = { card1 = seat.handcards[1], card2 = seat.handcards[2],
                                cardsType = Seotda:GetCardsType({ seat.handcards[1], seat.handcards[2] }) }
                            table.insert(item.groups, group)
                            group = { card1 = seat.handcards[1], card2 = seat.handcards[3],
                                cardsType = Seotda:GetCardsType({ seat.handcards[1], seat.handcards[3] }) }
                            table.insert(item.groups, group)
                            group = { card1 = seat.handcards[2], card2 = seat.handcards[3],
                                cardsType = Seotda:GetCardsType({ seat.handcards[2], seat.handcards[3] }) }
                            table.insert(item.groups, group)
                        end
                        break
                    end
                end
            end

            net.send(
                user.linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaDealCard"),
                pb.encode("network.cmd.PBSeotdaDealCard", { cards = dealcard, isReplay = type })
            )
            log.debug("idx(%s,%s,%s) dealCards(),uid=%s,dealcard=%s,type=%s", self.id, self.mid, self.logid, uid,
                cjson.encode(dealcard), tostring(type))

            if seat and seat.isplaying then -- 如果该玩家参与游戏(移除该玩家的牌数据)
                for _, item in ipairs(dealcard) do
                    if seat.sid == item.sid then
                        item.handcards = { 0, 0, 0 } --
                        item.card1 = 0
                        item.card2 = 0
                        break
                    end
                end
            end
        end
    end

    -- 给机器人发送所有牌数据
    dealcard = {}
    for _, seat in ipairs(self.seats) do
        table.insert(dealcard,
            { sid = seat.sid, handcards = g.copy(seat.handcards), cardsNum = seat.cardsNum or 0, roundNum = seat.roundNum })
    end

    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and seat.uid then
            local user = self.users[seat.uid]
            if user and Utils:isRobot(user.api) then
                -- 发送所有牌数据给机器人
                net.send(
                    user.linkid,
                    user.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaDealCardOnlyRobot"),
                    pb.encode("network.cmd.PBSeotdaDealCard", { cards = dealcard, isReplay = type })
                )
            end
        end
    end
end

-- 检测是否有多个最大牌玩家
function Room:checkMultiLargestCards()
    local largestNum = 0
    local largestCards = {} -- 最大的牌
    local largestCardsSid = {}
    for _, seat in ipairs(self.seats) do
        if seat and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) and
            seat.cardsNum >= 2 then -- 如果该玩家参与游戏
            if largestNum == 0 then
                largestCards = g.copy(seat.handcards) -- 保存最大手牌
                largestNum = 1
                largestCardsSid = {}
                largestCardsSid[largestNum] = seat.sid
            else
                local ret = Seotda:Compare(largestCards, seat.handcards)
                if ret == 0 then
                    largestNum = largestNum + 1
                    largestCardsSid[largestNum] = seat.sid
                    log.debug("idx(%s,%s,%s) checkMultiLargestCards() ret==0, largestCards=%s, handcards=%s", self.id,
                        self.mid, self.logid, cjson.encode(largestCards), cjson.encode(seat.handcards))
                elseif ret < 0 then
                    largestCards = g.copy(seat.handcards)
                    largestNum = 1
                    largestCardsSid = {}
                    largestCardsSid[largestNum] = seat.sid
                end
            end
        end
    end
    if largestNum > 1 then
        -- 将比牌失败的玩家当做弃牌处理
        for _, seat in ipairs(self.seats) do
            if seat and seat.isplaying and
                not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏 且 未弃牌
                local ret = Seotda:Compare(largestCards, seat.handcards)
                if ret > 0 then
                    seat.chiptype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")
                    seat.operateTypes = seat.operateTypes |
                        (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_COMPARE"))
                end
            end
        end
        self.replayType = 1 -- 多个赢家需要比赛
        -- for k, v in pairs(largestCardsSid) do
        --     self.seats[v].operateTypes = self.seats[v].operateTypes | (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_COMPARE"))
        -- end

        return true
    end
    self.replayType = 0
    return false
end

-- 检测是否满足条件2(比牌玩家中有牌型멍텅구리구사(特殊牌型), 并且其他比牌玩家牌型小于等于点数9)
function Room:checkCondition2()
    local hasSpecial2 = false
    local notFoldPlayerNum = 0 -- 未弃牌玩家数
    for _, seat in ipairs(self.seats) do
        if seat and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏
            notFoldPlayerNum = notFoldPlayerNum + 1
            if 2 == Seotda:GetSpecialCardsType(seat.handcards) then -- EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x41_0x91
                self.replayType = 2
                hasSpecial2 = true
            elseif seat.cardsType > 3 then -- EnumSeotdaCardsType.EnumSeotdaCardsType_End_9
                self.replayType = 0 -- 不需要重赛
                return false
            end
        end
    end
    if notFoldPlayerNum < 2 then
        return false
    end
    return hasSpecial2
end

-- 检测是否满足条件3(比牌玩家中有牌型구사(特殊牌型)，并且其他参与比牌玩家最大牌型小于알리(1月和2月的组合))
function Room:checkCondition3()
    local hasSpecial3 = false
    local notFoldPlayerNum = 0 -- 未弃牌玩家数
    for _, seat in ipairs(self.seats) do
        if seat and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果该玩家参与游戏
            notFoldPlayerNum = notFoldPlayerNum + 1
            if 3 == Seotda:GetSpecialCardsType(seat.handcards) then -- EnumSeotdaSpecialCardsType.EnumSeotdaSpecialCardsType_0x4X_0x9X
                hasSpecial3 = true
                self.replayType = 3
            elseif seat.cardsType >= 9 then -- EnumSeotdaCardsType.EnumSeotdaCardsType_1_2
                self.replayType = 0 -- 不需要重赛
                return false
            end
        end
    end
    if notFoldPlayerNum < 2 then
        return false
    end
    return hasSpecial3
end

-- 检测是否需要重赛
function Room:checkNeedReplay()
    log.debug("idx(%s,%s,%s) checkNeedReplay()", self.id, self.mid, self.logid)

    if self.state < pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCard2") then
        return false
    end

    -- (1) 当最后比牌玩家中最大的两个或者多个玩家点数一样大（最大相同点数玩家重赛）
    -- (2) 比牌玩家中有牌型멍텅구리구사(特殊牌型), 并且其他比牌玩家牌型小于等于点数9
    -- (3) 比牌玩家中有牌型구사(特殊牌型)，并且其他参与比牌玩家最大牌型小于알리(1月和2月的组合)

    -- 检测是否满足条件2(比牌玩家中有牌型멍텅구리구사(特殊牌型), 并且其他比牌玩家牌型小于等于点数9)
    if self:checkCondition2() then
        log.debug("idx(%s,%s,%s) checkNeedReplay() condition 2 is true", self.id, self.mid, self.logid)
        return true -- 满足条件2
    end

    -- 检测是否满足条件3(比牌玩家中有牌型구사(特殊牌型)，并且其他参与比牌玩家最大牌型小于알리(1月和2月的组合))
    if self:checkCondition3() then
        log.debug("idx(%s,%s,%s) checkNeedReplay() condition 3 is true", self.id, self.mid, self.logid)
        return true -- 满足条件3
    end

    if self:checkMultiLargestCards() then
        log.debug("idx(%s,%s,%s) checkNeedReplay() condition 1 is true", self.id, self.mid, self.logid)
        return true -- 满足条件1
    end
    return false
end

-- 更新第一个操作玩家(每局开始时更新)
function Room:updateBankerPos()
    log.debug("idx(%s,%s,%s) updateBankerPos()", self.id, self.mid, self.logid)
    if self.lastWinnerUID ~= 0 then
        local seat = self:getSeatByUid(self.lastWinnerUID)
        if seat then
            self.buttonpos = seat.sid
            self.current_betting_pos = self.buttonpos
            return
        end
    end
    local sidList = {}
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying then
            table.insert(sidList, seat.sid)
        end
    end
    self.buttonpos = sidList[rand.rand_between(1, #sidList)] -- 随机一个座位作为庄家
    -- 庄家为第一个要操作的玩家
    self.current_betting_pos = self.buttonpos
end

-- 更新桌子状态
function Room:changeState(newState)
    log.debug("idx(%s,%s,%s) changeState(), oldState=%s, newState=%s", self.id, self.mid, self.logid, self.state,
        newState)

    self.state = newState
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)

    -- 通知每个玩家该状态剩余时长
    local seotdaRoomState = { state = newState }
    local needNotify = false
    if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ShowOneCard") then -- 公开显示一张牌
        needNotify = true
        seotdaRoomState.leftTime = TimerID.TimerID_ShowOneCard[2]
    elseif self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards") then -- 选择要比较的牌
        needNotify = true
        seotdaRoomState.leftTime = TimerID.TimerID_SelectCompareCards[2]
    end
    if needNotify then
        pb.encode(
            "network.cmd.PBSeotdaRoomState",
            seotdaRoomState,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaRoomState"),
                    pointer,
                    length
                )
            end
        )
        log.debug("idx(%s,%s,%s) changeState(),seotdaRoomState=%s", self.id, self.mid, self.logid,
            cjson.encode(seotdaRoomState))
    end
end

-- 获取最大的牌
-- 参数 cards: 牌数据
-- 参数 cardsNum：牌张数
function Room:getMaxCards(cards, cardsNum)
    local maxCards = {}
    if cardsNum == 2 then
        maxCards[1] = cards[1] or 0x11
        maxCards[2] = cards[2] or 0x12
    elseif cardsNum == 3 then
        maxCards[1] = cards[1] or 0x11
        maxCards[2] = cards[2] or 0x12
    end
    return maxCards
end

-- 获取所有未弃牌且下注了的玩家ID列表
function Room:getNoFoldUidList()
    local idList = {} -- ID列表
    local notFoldPlayerNum = self:getNotFoldPlayerNum()
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and
            not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) and
            seat.betmoney > 0 then
            table.insert(idList, seat.uid)
            if notFoldPlayerNum > 1 then
                seat.operateTypes = seat.operateTypes | (1 << 20) -- show牌
            end
        end
    end
    log.debug("idx(%s,%s,%s) getNoFoldUidList(), idList=%s", self.id, self.mid, self.logid, cjson.encode(idList))
    return idList
end

-- 判断 比牌时有其他玩家最大牌是18光对或者13光对，암행어사获胜


-- 获取牌型最大的牌的玩家ID列表(获取赢家UID列表)
function Room:getMaxCardsUid(idList)
    local maxCards = nil -- 最大的牌
    local maxCardsUidList = { idList[1] }
    local hasSpecial_0x41_0x71 = false
    local uid_0x41_0x71 = idList[1]
    local uid_0x31_0x71 = idList[1]
    local hasSpecial_0x31_0x71 = false

    for i = 1, #idList do
        local seat = self:getSeatByUid(idList[i])
        if seat then
            if not hasSpecial_0x41_0x71 and 4 == Seotda:GetSpecialCardsType(seat.handcards) then
                uid_0x41_0x71 = idList[i]
                hasSpecial_0x41_0x71 = true
            end
            if not hasSpecial_0x31_0x71 and 5 == Seotda:GetSpecialCardsType(seat.handcards) then
                hasSpecial_0x31_0x71 = true
                uid_0x31_0x71 = idList[i]
            end

            if not maxCards then
                maxCards = g.copy(seat.handcards)
            else
                local res = Seotda:Compare(seat.handcards, maxCards)
                if res > 0 then
                    maxCardsUidList = { idList[i] }
                    maxCards = g.copy(seat.handcards) -- 最大的牌
                elseif res == 0 then
                    table.insert(maxCardsUidList, idList[i])
                end
            end
        end
    end
    if hasSpecial_0x41_0x71 then -- 如果有特殊牌玩家存在
        -- 比牌时有其他玩家最大牌是18光对或者13光对，암행어사获胜
        if 11 == Seotda:GetCardsType(maxCards) then -- 光对
            maxCardsUidList = { uid_0x41_0x71 }
        end
    elseif hasSpecial_0x31_0x71 then
        -- 比牌时其他玩家最大牌是1-9对，땡잡이获胜
        if 10 == Seotda:GetCardsType(maxCards) and 0xA1 ~= maxCards[1] and 0xA2 ~= maxCards[2] then -- 1~9对子
            maxCardsUidList = { uid_0x31_0x71 }
        end
    end

    log.debug("idx(%s,%s,%s) getMaxCardsUid(), idList=%s,maxCardsUidList=%s", self.id, self.mid, self.logid,
        cjson.encode(idList), cjson.encode(maxCardsUidList))
    return maxCardsUidList
end

-- 获取某组玩家中最小押注筹码
-- 参数 idList： 玩家ID列表
function Room:getMinBet(uidList)
    local minBet = 0x7FFFFFFF -- 最小下注金额
    for i = 1, #uidList do
        local seat = self:getSeatByUid(uidList[i])
        if seat and seat.betmoney < minBet then
            minBet = seat.betmoney
        end
    end
    log.debug("idx(%s,%s,%s) getMinBet(), uidList=%s,minBet=%s", self.id, self.mid, self.logid, cjson.encode(uidList),
        minBet)
    return minBet
end

-- 获取各下注玩家总的下注额(每个玩家不超过minBet)
function Room:getTotalBetLow(minBet)
    local totalBet = 0
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying then
            if seat.betmoney >= minBet then
                totalBet = totalBet + minBet
                seat.betmoney = seat.betmoney - minBet
            else
                totalBet = totalBet + seat.betmoney
                seat.betmoney = 0
            end
        end
    end
    log.debug("idx(%s,%s,%s) getTotalBetLow(), totalBet=%s,minBet=%s", self.id, self.mid, self.logid, totalBet, minBet)
    return totalBet
end

-- 计算输赢(更新输赢金额)
-- 参数 winnerUidList: 赢家UID列表
-- 参数  totalBet: 总的下注额
function Room:updateResult(winnerUidList, totalBet)
    log.debug("idx(%s,%s,%s) updateResult(), winnerUidList=%s,totalBet=%s", self.id, self.mid, self.logid,
        cjson.encode(winnerUidList), totalBet)
    -- self.pots[self.potidx] = {}
    -- self.pots[self.potidx].money = totalBet
    -- self.pots[self.potidx].seats = {}
    local winnerNum = #winnerUidList -- 赢家总数目
    for i = 1, #winnerUidList, 1 do
        local seat = self:getSeatByUid(winnerUidList[i])
        if seat then
            --self.pots[self.potidx].seats[seat.sid] = seat.sid
            seat.winmoney = seat.winmoney + totalBet / winnerNum
        end
    end
    --self.potidx = self.potidx + 1
end

-- 计算各玩家的输赢情况
function Room:calcResult()
    log.debug("idx(%s,%s,%s) calcResult()", self.id, self.mid, self.logid)

    for i = 1, self.conf.maxuser do
        local uidList = self:getNoFoldUidList() -- 获取所有未弃牌玩家列表
        if #uidList > 0 then -- 如果有玩家未弃牌
            uidList = self:getMaxCardsUid(uidList) -- 获取赢家UID列表
            local minBet = self:getMinBet(uidList) -- 押注最小的赢家
            if minBet > 0 then
                -- 获取总的押注金额
                local totalBet = self:getTotalBetLow(minBet)
                self:updateResult(uidList, totalBet)
            end
        else
            break
        end
    end

    -- 更新玩家身上筹码
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and not seat.hasLeave then
            seat.chips = seat.chips + seat.winmoney
            log.debug("idx(%s,%s,%s) calcResult(),sid=%s,winmoney=%s", self.id, self.mid, self.logid, seat.sid,
                seat.winmoney)
        end
    end
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

-- 是否所有未弃牌玩家都allin
function Room:isAllAllin()
    local allin = 0 -- allin玩家数
    local playing = 0 -- 未弃牌玩家数(包括allin玩家)
    local pos = 0 -- 未弃牌未allin的玩家所在位置
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat.isplaying then
            if not self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 如果未弃牌
                playing = playing + 1
                if self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")) then -- allin
                    allin = allin + 1
                else
                    pos = i
                end
            end
        end
    end

    -- log.debug("Room:isAllAllin %s,%s playing:%s allin:%s self.maxraisepos:%s pos:%s", self.id,self.mid,playing, allin, self.maxraisepos, pos)

    if playing == allin + 1 then
        -- if self.maxraisepos == pos or self.maxraisepos == 0 then
        --     return true
        -- end
        if self.seats[pos].roundmoney >= self:getRoundMaxBet() then
            return true
        end
    end

    if playing == allin then
        return true
    end

    return false
end

-- 比牌
function Room:compareCards()
    if self:checkNeedReplay() then -- 检测是否需要重赛
        -- 重赛
        if self.replayType > 1 then
            self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips")) -- 进入补码重赛阶段

            local hasRelpayChips = false -- 是否有满足补齐筹码重赛玩家
            local allSeatsState = {}
            -- 通知其它弃牌玩家是否补齐筹码重赛
            for sid, seat in ipairs(self.seats) do
                if seat and seat.isplaying then
                    if not
                        self:checkOperate(seat, pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 该玩家未弃牌
                        seat.playerState = 2 -- 重赛
                        table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
                    elseif self:checkOperate(seat,
                        pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) and
                        not
                        self:checkOperate(seat,
                            pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_COMPARE")) -- 还未比过牌
                    then
                        -- 通知弃牌玩家是否补足筹码重赛
                        local user = self.users[seat.uid or 0]
                        if user then
                            local msg = { chips = seat.chips, uid = seat.uid or 0 }
                            msg.needChips = self.seats[self.maxraisepos].total_bets - seat.total_bets -- 需要补齐的筹码数
                            msg.leftTime = TimerID.TimerID_ReplayChips[2] -- 剩余时长(毫秒)
                            if msg.needChips <= seat.chips then
                                seat.playerState = 1 -- 等待确认是否重赛
                                hasRelpayChips = true
                            else
                                seat.playerState = 3 -- 不再重赛
                                hasRelpayChips = true
                            end

                            net.send(
                                user.linkid,
                                seat.uid,
                                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReplayReq"),
                                pb.encode("network.cmd.PBSeotdaReplayReq", msg)
                            )
                            log.debug("idx(%s,%s,%s) compareCards(),PBSeotdaReplayReq=%s", self.id, self.mid,
                                self.logid, cjson.encode(msg))
                            table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
                        end
                    else
                        seat.playerState = 3 -- 不再重赛
                        table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
                    end
                end
            end
            if hasRelpayChips then
                -- 通知所有玩家哪些玩家需要重赛
                pb.encode(
                    "network.cmd.PBSeotdaReplayState",
                    { allSeats = allSeatsState, replayType = self.replayType },
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReplayState"),
                            pointer,
                            length
                        )
                    end
                )
                log.debug("idx(%s,%s,%s) compareCards(),PBSeotdaReplayState=%s", self.id, self.mid, self.logid
                    , cjson.encode(allSeatsState))
                -- 设置定时器等待弃牌玩家确认是否重赛
                timer.tick(self.timer, TimerID.TimerID_ReplayChips[1], TimerID.TimerID_ReplayChips[2], onReplayChips,
                    self)
                return false
            end
        end
        log.debug("idx(%s,%s,%s) compareCards(),need deal cards", self.id, self.mid, self.logid)
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReDealCards")) -- 重新发牌
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3")) -- 重赛阶段下注
        return true
    else
        log.error("idx(%s,%s,%s) compareCards(), not Replay", self.id, self.mid, self.logid)
        self:finish() -- 不需要重赛则直接结束游戏
        return false
    end
end

-- 获取该局所有玩家总下注筹码
function Room:getTotalBet()
    local totalBet = 0
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying then -- 如果该座位参与游戏
            totalBet = totalBet + seat.total_bets
        end
    end
    return totalBet
end

-- 获取本轮最大下注位置
function Room:getMaxBetSid()
    local maxBetSid = 0
    local maxBetValue = -1
    for i = 1, #self.seats do
        local seat = self.seats[i]
        if seat and seat.isplaying then -- 如果该座位玩家参与游戏
            if seat.roundmoney > maxBetValue then
                maxBetValue = seat.roundmoney
                maxBetSid = i
            end
        end
    end
    return maxBetSid
end

-- 判断是否所有玩家都公开显示了一张牌
function Room:isAllShowOneCard()
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and not seat.hasLeave and seat.firstShowCard == 0 then
            return false
        end
    end
    return true
end

-- 获取未弃牌玩家数
function Room:getNotFoldPlayerNum()
    local notFoldPlayerNum = 0 -- 未弃牌玩家数

    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and not seat.hasLeave and
            seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then
            notFoldPlayerNum = notFoldPlayerNum + 1
        end
    end
    return notFoldPlayerNum
end

-- 获取本轮最大下注金额
function Room:getRoundMaxBet()
    local roundMaxBet = 0
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying then -- 如果该玩家参与游戏
            if roundMaxBet < seat.roundmoney then
                roundMaxBet = seat.roundmoney
            end
        end
    end
    return roundMaxBet
end

-- 获取总下注额>minBet的未弃牌玩家列表
function Room:getNotFoldLargerBetPlayerList(minBet)
    local playerList = {} -- 玩家ID列表
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and not seat.hasLeave and
            seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") and
            seat.total_bets > minBet then
            --table.insert(playerList, seat.uid)
            table.insert(playerList, sid)
        end
    end
    return playerList
end

-- 获取所有未弃牌玩家中最小下注额(>minBet)
-- 返回值: 返回未弃牌玩家中下注金额超过minBet的最小下注额
function Room:getNotFoldPlayerMinBet(minBet)
    local ret = 0
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and not seat.hasLeave and
            seat.chiptype ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") and
            seat.total_bets > minBet then
            if ret == 0 or ret > seat.total_bets then
                ret = seat.total_bets
            end
        end
    end
    return ret
end

-- 根据各玩家的总下注额生成边池
function Room:getPotsByBets()
    log.debug("idx(%s,%s,%s) getPotsByBets()", self.id, self.mid, self.logid)
    local playerSidList = self:getNotFoldLargerBetPlayerList(0)
    local minBet = self:getNotFoldPlayerMinBet(0)
    self.potidx = 1
    for i = 1, #self.seats do
        if #playerSidList > 0 then
            self.pots[self.potidx] = self.pots[self.potidx] or {}
            self.pots[self.potidx].money = 0
            for sid, seat in ipairs(self.seats) do
                if seat and seat.isplaying and seat.total_bets > 0 then
                    if seat.total_bets >= minBet then
                        self.pots[self.potidx].money = self.pots[self.potidx].money + minBet
                    else
                        self.pots[self.potidx].money = self.pots[self.potidx].money + seat.total_bets
                    end
                end
            end
            if self.potidx > 1 then
                self.pots[self.potidx].money = self.pots[self.potidx].money - self.pots[self.potidx - 1].money
            end
            self.pots[self.potidx].seats = {}
            for j = 1, #playerSidList do
                self.pots[self.potidx].seats[playerSidList[j]] = playerSidList[j]
            end
            self.potidx = self.potidx + 1
            playerSidList = self:getNotFoldLargerBetPlayerList(minBet)
            minBet = self:getNotFoldPlayerMinBet(minBet)
        else
            if self.potidx > 1 then
                self.potidx = self.potidx - 1
            end
            break
        end
    end

    -- 打印所有下注玩家信息
    for sid, seat in ipairs(self.seats) do
        if seat and seat.isplaying and seat.total_bets > 0 then
            log.debug("idx(%s,%s,%s) getPotsByBets(),sid=%s,uid=%s,total_bets=%s,operateTypes=%s", self.id, self.mid,
                self.logid, sid, tostring(seat.uid), seat.total_bets, seat.operateTypes)
        end
    end

    log.debug("idx(%s,%s,%s) getPotsByBets(),pots=%s,potidx=%s", self.id, self.mid, self.logid, cjson.encode(self.pots),
        self.potidx)
end

-- 获取最大牌座位ID列表
function Room:getMaxCardsSid(sidList)
    local maxCards = nil -- 最大的牌
    local maxCardsSidList = { sidList[1] }
    local hasSpecial_0x41_0x71 = false
    local sid_0x41_0x71 = sidList[1]
    local sid_0x31_0x71 = sidList[1]
    local hasSpecial_0x31_0x71 = false

    for i = 1, #sidList do
        local seat = self.seats[sidList[i]]
        if seat then
            if not hasSpecial_0x41_0x71 and 4 == Seotda:GetSpecialCardsType(seat.handcards) then
                sid_0x41_0x71 = sidList[i]
                hasSpecial_0x41_0x71 = true
            end
            if not hasSpecial_0x31_0x71 and 5 == Seotda:GetSpecialCardsType(seat.handcards) then
                hasSpecial_0x31_0x71 = true
                sid_0x31_0x71 = sidList[i]
            end

            if not maxCards then
                maxCards = g.copy(seat.handcards)
            else
                local res = Seotda:Compare(seat.handcards, maxCards)
                if res > 0 then
                    maxCardsSidList = { sidList[i] }
                    maxCards = g.copy(seat.handcards) -- 最大的牌
                elseif res == 0 then
                    table.insert(maxCardsSidList, sidList[i])
                end
            end
        end
    end
    if hasSpecial_0x41_0x71 then -- 如果有特殊牌玩家存在
        -- 比牌时有其他玩家最大牌是18光对或者13光对，암행어사获胜
        if 11 == Seotda:GetCardsType(maxCards) then -- 光对
            maxCardsSidList = { sid_0x41_0x71 }
        end
    elseif hasSpecial_0x31_0x71 then
        -- 比牌时其他玩家最大牌是1-9对，땡잡이获胜
        if 10 == Seotda:GetCardsType(maxCards) and 0xA1 ~= maxCards[1] and 0xA2 ~= maxCards[2] then -- 1~9对子
            maxCardsSidList = { sid_0x31_0x71 }
        end
    end

    log.debug("idx(%s,%s,%s) getMaxCardsSid(), idList=%s,maxCardsSidList=%s", self.id, self.mid, self.logid,
        cjson.encode(sidList), cjson.encode(maxCardsSidList))
    return maxCardsSidList
end

-- 获取未弃牌玩家列表
function Room:getNotFoldSidList(sidList)
    local notFoldSidList = {}
    for i = 1, #sidList do
        local seat = self.seats[sidList[i]]
        if seat and
            (seat.operateTypes & (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"))) == 0 then
            table.insert(notFoldSidList, sidList[i])
        end
    end
    return notFoldSidList
end

-- (12)检测指定座位玩家是否执行了某操作
function Room:checkOperate(seat, operate)
    if seat and seat.isplaying and seat.operateTypes and operate then -- 如果该座位玩家参与游戏
        if 0 ~= (seat.operateTypes & (1 << operate)) then
            return true
        end
    end
    return false
end

-- 进入下一轮
function Room:nextRound()
    --
end



-- 从庄家位置开始查找可下注玩家下注
function Room:bet()
    log.info("idx(%s,%s,%s) bet(),state=%s", self.id, self.mid, self.logid, self.state)
    local seat = self:getNextActionPosition(self.buttonpos) -- 从庄家位置开始操作
    if not seat then
        if self:checkGameOver() then
            self:finish() -- 立马结束游戏
            return true
        else
            -- 直接进入下一个状态
            if self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then
                self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCard2"))
            elseif self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting2") then
                self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards")) -- 选择2张要比较的牌比较
            elseif self.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3") then
                self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips")) -- 重赛前等待弃牌玩家补齐筹码重赛状态
            end
        end
    end

    -- 广播轮到某玩家操作
    self:betting(seat)
end

-- 重赛操作
function Room:replay()
    if self:checkNeedReplay() then -- 检测是否需要重赛
        -- 重赛
        if self.replayType > 1 then
            self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips"))

            local hasRelpayChips = false -- 是否有满足补齐筹码重赛玩家
            local allSeatsState = {}
            -- 通知其它弃牌玩家是否补齐筹码重赛
            for sid, seat in ipairs(self.seats) do
                if seat and seat.isplaying and not seat.hasLeave then
                    if not
                        self:checkOperate(seat,
                            pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD")) then -- 该玩家未弃牌
                        seat.playerState = 2 -- 重赛
                        table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
                    elseif self:checkOperate(seat,
                        pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD"))
                        and
                        (
                        seat.operateTypes &
                            (1 << pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_COMPARE"))) == 0 -- 还未比过牌
                    then
                        -- 通知弃牌玩家是否补足筹码重赛
                        local user = self.users[seat.uid or 0]
                        if user then
                            local msg = { chips = seat.chips, uid = seat.uid or 0 }
                            msg.needChips = self.seats[self.maxraisepos].total_bets - seat.total_bets -- 需要补齐的筹码数
                            msg.leftTime = TimerID.TimerID_ReplayChips[2] -- 剩余时长(毫秒)
                            if msg.needChips <= seat.chips then
                                seat.playerState = 1 -- 等待确认是否重赛
                                hasRelpayChips = true
                            else
                                seat.playerState = 3 -- 不再重赛
                                hasRelpayChips = true
                            end

                            net.send(
                                user.linkid,
                                seat.uid,
                                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReplayReq"),
                                pb.encode("network.cmd.PBSeotdaReplayReq", msg)
                            )
                            log.debug("idx(%s,%s,%s) roundOver(),PBSeotdaReplayReq=%s", self.id, self.mid,
                                self.logid, cjson.encode(msg))
                            table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
                        end
                    else
                        seat.playerState = 3 -- 不再重赛
                        table.insert(allSeatsState, { sid = seat.sid, playerState = seat.playerState })
                    end
                end
            end
            if hasRelpayChips then
                -- 通知所有玩家哪些玩家需要重赛
                pb.encode(
                    "network.cmd.PBSeotdaReplayState",
                    { allSeats = allSeatsState, replayType = self.replayType },
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SeotdaReplayState"),
                            pointer,
                            length
                        )
                    end
                )
                log.debug("idx(%s,%s,%s) roundOver(),PBSeotdaReplayState=%s", self.id, self.mid,
                    self.logid, cjson.encode(allSeatsState))
                -- 设置定时器等待弃牌玩家确认是否重赛
                timer.tick(self.timer, TimerID.TimerID_ReplayChips[1], TimerID.TimerID_ReplayChips[2], onReplayChips,
                    self)
                return false
            end
        end
        log.debug("idx(%s,%s,%s) roundOver() need deal cards", self.id, self.mid, self.logid)
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReDealCards")) -- 重赛发牌
        self:intoNextState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3")) -- 进入下注状态
        return true
    else
        log.error("idx(%s,%s,%s) replay() not Replay", self.id, self.mid, self.logid)
        self:finish() -- 不需要重赛则直接结束游戏
        return false
    end
end

-- 选择要比较的2张牌
function Room:selectCards()
    --self:changeState(pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards")) -- 进入选择比牌阶段
    -- 玩家需要选择2张要比较的牌
    timer.tick(self.timer, TimerID.TimerID_SelectCompareCards[1], TimerID.TimerID_SelectCompareCards[2],
        onSelectCompareCards, self)
end



-- 进入下一状态
function Room:intoNextState(nextState)
    --local  currentState = self.state

    -- 检测是否结束游戏
    if self:checkGameOver() then
        self:finish() -- 立马结束游戏
        return true
    end

    self:changeState(nextState) -- 更新当前房间状态

    if nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_PreChips") then
        self:dealPreChips() -- 前注，大小盲处理
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCards1") then
        self:dealCards(1) -- 第一轮发牌
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ShowOneCard") then
        timer.tick(self.timer, TimerID.TimerID_ShowOneCard[1], TimerID.TimerID_ShowOneCard[2], onShowOneCard, self)
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then
        self:bet() -- 第一轮下注状态
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_DealCard2") then
        self:dealCards(2) -- 第二轮发牌
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting2") then
        self:bet() -- 第二轮下注
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReplayChips") then --重赛前等待弃牌玩家补齐筹码重赛状态
        self:replay() -- 等待补码重赛
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_ReDealCards") then
        self:dealCards(3) -- 重赛发牌
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3") then
        self:bet() -- 重赛下注
    elseif nextState == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_SelectCards") then
        self:selectCards() -- 选择要比较的牌
    end
end
