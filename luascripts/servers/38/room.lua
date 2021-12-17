-- serverdev\luascripts\servers\38\room.lua

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
require("luascripts/servers/38/seat")
require("luascripts/servers/38/pokdeng")
require("luascripts/servers/common/bankmgr")

Room = Room or {}

-- 定时器
local TimerID = {
    TimerID_Check = {1, 200}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4000}, --id, interval(ms), timestamp(ms)
    TimerID_Run = {3, 1000}, -- 定时器(毫秒)
    TimerID_Timeout = {4, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {5, 2000}, --id, interval(ms), timestamp(ms)
    TimerID_Bet = {6, 10}, --id, interval(s)  下注时长(s)
    TimerID_Ready = {7, 3}, -- 准备剩余时长(秒)
    TimerID_GetThirdCard = {8, 10}, -- 补牌处理时长(秒)
    TimerID_DealCard = {9, 3} -- 发牌时长(秒)
}

-- 玩家状态
local EnumUserState = {
    Playing = 1, -- 在房间中，且坐下
    Leave = 2, -- 真正离开了
    Logout = 3, -- 退出(将要离开)
    Intoing = 4 --
}

-- 填充座位信息
local function fillSeatInfo(seat, self)
    local seatinfo = {}
    local user = self.users[seat.uid]
    seatinfo.seat = {
        sid = seat.sid, --座位ID
        tid = 0, -- 桌子ID
        playerinfo = {
            uid = seat.uid or 0, -- 该座位上的玩家ID
            nickname = "",
            username = user and user.username or "",
            viplv = 0,
            gender = user and user.sex or 0,
            nickurl = user and user.nickurl or "",
            balance = 1000, -- 玩家身上剩余金额
            currency = "",
            extra = {api = "", ip = "", platuid = ""}
        }
    }

    seatinfo.isPlaying = seat.isplaying and 1 or 0
    seatinfo.seatMoney = seat.chips

    seatinfo.chipinType = seat.chiptype or 0 -- 此时玩家所处状态

    seatinfo.chipinValue = seat.chipinnum -- 该玩家在该状态下的操作值

    seatinfo.pot = self:getOnePot() -- 该座位总的下注金额?

    return seatinfo
end

-- 填充所有座位信息
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

local function onRun(self)
    local function doRun()
        self:run()
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

        for uid, user in pairs(self.users) do -- 遍历该桌所有玩家
            -- clear logout users after 10 mins
            if user.state == EnumUserState.Logout and global.ctsec() >= user.logoutts + MYCONF.logout_to_kickout_secs then -- 如果该玩家超出离线时长
                log.info("idx(%s,%s) onCheck user logout %s %s", self.id, self.mid, user.logoutts, global.ctsec())
                self:userLeave(uid, user.linkid) -- 玩家离开
            end
        end

        -- check all seat users issuses
        for k, v in ipairs(self.seats) do -- 遍历所有座位
            local user = v.uid and self.users[v.uid]
            if user then -- 如果该座位有玩家坐下
                local userID = v.uid  -- 玩家ID(此时ID一定有效) 

                -- 超时两轮自动站起
                if v.tostandup then
                    self:stand(v, v.uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
                elseif user.notOperateTimes and user.notOperateTimes >= 2 and v.uid ~= 0 then   -- 玩家操作超时 
                    user.notOperateTimes = 0
                    log.debug("idx(%s,%s) uid=%s notOperateTimes=%s", self.id, self.mid, v.uid, user.notOperateTimes)
                    self:stand(v, v.uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
                end

                if user.toleave then  -- 如果玩家将要离开 
                    log.info(
                        "idx(%s,%s) onCheck user(%s,%s) betting timeout %s",
                        self.id,
                        self.mid,
                        userID,
                        k,
                        tostring(user.toleave)
                    )
                    self:userLeave(userID, user.linkid) -- 玩家离开
                elseif v.uid then  -- 如果该位置还有玩家坐下
                    if v.chips >= (self.conf and self.conf.ante * 80 + self.conf.fee or 0) then
                        v:reset() -- 重置座位
                        v.isplaying = true
                    else  -- 金额不足
                        if v.uid ~= 0 then  -- 如果不是系统
                            log.info(
                                "idx(%s,%s) onCheck user(%s,%s) not enough chips, chips=%s ",
                                self.id,
                                self.mid,
                                userID,
                                k,
                                v.chips
                            )
                            self:userLeave(userID, user.linkid)
                            v:reset() -- 重置座位
                        elseif self.bankerUID == v.uid then  -- 如果是系统，且是系统坐庄
                            v.chips = self.conf and self.conf.ante * 80 + self.conf.fee or 0
                        end
                    end
                end
            end
        end

        --log.info("idx(%s,%s) onCheck playing size=%s", self.id, self.mid, self:getPlayingSize())

        if self.bankerUID == 0 then -- 如果是系统坐庄
            self.seats[self.buttonpos].isplaying = true -- 确保系统参与游戏
        end

        local playingcount = self:getPlayingSize() -- 准备玩的玩家数目

        if playingcount <= 1 then -- 如果准备好的玩家人数未满足开始条件，则需要继续等待玩家
            self.has_started = nil -- 还未开始游戏
            self.ready_start_time = nil
            return
        else
            self:ready()
        end
    end
    g.call(doRun)
end

function Room:getOnePot()
    return 0
end

-- 获取玩家身上金额
function Room:getUserMoney(uid)
    local user = self.users[uid]
    if self.conf and user then
        if not self.conf.roomtype or self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
            user.money = user.money or 0
            return user.money
        elseif self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
            user.coin = user.coin or 0
            return user.coin
        end
    end
    return 0
end

function Room:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init()
    o:check()
    return o
end

function Room:destroy()
    timer.destroy(self.timer) -- 销毁定时器管理器
end

--  房间初始化
function Room:init()
    log.info("idx(%s,%s) room init", self.id, self.mid)
    self.conf = MatchMgr:getConfByMid(self.mid) -- 根据房间类型ID获取配置信息
    if not self.conf then
        log.info("[error] self.conf == nil")
    else
        --log.info("self.conf.minplayercount=%s", self.conf.minplayercount)
        -- 设置配置信息
        self.conf.max_bank_list_size = self.conf.max_bank_list_size or 10 -- 上庄申请列表最大申请人数
        self.conf.min_onbank_moneycnt = self.conf.min_onbank_moneycnt or 5000000 -- 上庄需要最低金币数量
        self.conf.max_bank_successive_cnt = self.conf.max_bank_successive_cnt or 10 -- 上庄连庄最大次数
        self.conf.min_outbank_moneycnt = self.conf.min_outbank_moneycnt or 2000000 -- 下庄需要最低金币数量
        self.conf.chips = self.conf.chips or {10, 20, 40, 100} -- 下注筹码列表
        self.conf.minbuyinbb = self.conf.minbuyinbb or 2000
        self.conf.addbetmin = self.conf.addbetmin or 10
        self.conf.addbetmax = self.conf.addbetmax or 100

        log.info("self.conf=%s", cjson.encode(self.conf)) -- 打印配置信息
    end

    self.users = {} -- 存放该房间的所有玩家
    self.timer = timer.create() -- 创建定时器管理器
    self.poker = PokDeng:new() -- 新建一副牌
    self.gameId = 0 -- 标识是哪一局

    self.bankmgr = BankMgr:new() -- 庄家管理器

    self.buttonpos = self.conf.maxuser or 8 -- 庄家所在座位号 (默认庄家在最大号码位置 8)
    self.buttonposOld = self.buttonpos
    self.bankerUID = self.bankmgr:banker() or 0 -- 庄家ID

    self.state = pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_None") -- 当前房间状态(准备状态)
    self.stateBeginTime = global.ctsec() -- 当前状态开始时刻
    log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 更新了桌子状态


    self.seats = {} -- 所有座位
    for sid = 1, self.conf.maxuser do -- 根据每桌玩家最大数目创建座位
        local s = Seat:new(self, sid) -- 新建座位
        table.insert(self.seats, s)
    end
    --self.seats[self.conf.maxuser].uid = 0  -- 默认系统坐庄
    -- log.info("self.seats=%s", cjson.encode(self.seats))   -- 打印座位信息

    self.sdata = {
        -- 游戏数据
        roomtype = self.conf.roomtype, -- 房间类型(1:金币  2:金豆)
        tag = self.conf.tag -- (1:低级场  2:中级场  3:高级场)
    }

    self.starttime = 0 -- 牌局开始时刻
    self.endtime = 0 -- 牌局结束时刻

    self.ready_start_time = nil -- 准备阶段开始时刻

    self.config_switch = false
    self.statistic = Statistic:new(self.id, self.conf.mid)

    self.last_playing_users = {} -- 上一局参与的玩家列表

    self.reviewlogs = LogMgr:new(1)
    --实时牌局
    self.reviewlogitems = {} --暂存站起玩家牌局

    self.tableStartCount = 0 -- 开始局数

    self.hasCalcResult = false -- 本局是否结算完
    self.users = self.users or {}
    self.users[0] = self.users[0] or {money = 2000000}
    self:sit(self.seats[self.conf.maxuser], self.bankerUID, 2000000) -- 默认系统坐庄
end

-- 重新加载配置文件
function Room:reload()
    self.conf = MatchMgr:getConfByMid(self.mid)
end

-- 玩家站起
function Room:userStand(uid, linkid, rev)
    log.info("idx(%s,%s) req stand up uid:%s", self.id, self.mid, uid)

    local seat = self:getSeatByUid(uid)
    local user = self.users[uid]

    if self:canStandup(uid) then
        if uid == self.bankerUID then  -- 如果该站起的玩家是庄家
            self:updateBanker(true) -- 强制换庄
        else
            self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand"))
        end
        if self:getPlayingSize() <= 1 then
            -- 重置桌子后，关闭定时器，进入检测阶段
            timer.cancel(self.timer, TimerID.TimerID_Run[1])
            self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_None"))
            self:check()
        end
    else
        seat.tostandup = true -- 将要站起
        if linkid then
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
end

-- 玩家坐下
function Room:userSit(uid, linkid, rev)
    log.info("idx(%s,%s) req sit down uid:%s", self.id, self.mid, uid)

    local user = self.users[uid]
    local srcs = self:getSeatByUid(uid) -- 原座位
    local dsts = self.seats[rev.sid] -- 目的座位
    --local is_buyin_ok = rev.buyinMoney and user.money >= rev.buyinMoney and (rev.buyinMoney >= (self.conf.minbuyinbb*self.bigblind)) and (rev.buyinMoney <= (self.conf.maxbuyinbb*self.bigblind))
    --print(user.money,rev.buyinMoney,self.bigblind,self.conf.maxbuyinbb,self.conf.minbuyinbb, srcs,dsts)
    if not user or srcs or not dsts or (dsts and dsts.uid) --[[or not is_buyin_ok ]] then
        log.info("idx(%s,%s) sit failed uid:%s ", self.id, self.mid, uid)

        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitFailed"), -- 坐下失败
            pb.encode(
                "network.cmd.PBTexasSitFailed",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")}
            )
        )
    else
        -- self:sit(dsts, uid, self.conf.minbuyinbb * self.conf.sb * 2)
        self:sit(dsts, uid, self:getUserMoney(uid))
        log.info("dfr idx(%s,%s) uid=%s ", self.id, self.mid, uid)
    end
end

-- 发送消息给该桌所有参与该局游戏的玩家
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

-- 检测让机器人离开
function Room:checkLeave()
    local c = self:count() -- 获取该桌坐下的玩家总数及坐下的机器人总数
    if c > 2 then -- 如果超过2个玩家
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if user then
                if Utils:isRobot(user.api) then -- 如果是机器人
                    self:userLeave(v.uid, user.linkid) -- 让机器人离开
                    break
                end
            end
        end
    end
end

--玩家准备离开房间
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
function Room:userLeave(uid, linkid, client)
    log.info("Room:userLeave(...) idx(%s,%s) uid=%s, linkid=%s, client=%s", self.id, self.mid, tostring(uid), tostring(linkid), tostring(client))

    local function handleFailed() -- 处理离开失败的情况
        local resp =
            pb.encode(
            "network.cmd.PBLeaveGameRoomResp_S",
            {
                code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed")
            }
        )
        if linkid and uid ~= 0 then
            net.send( -- 发送离开失败消息
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
                resp
            )
        end
        log.info("handleFailed() send LeaveGameFailed message")
    end

    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        handleFailed()
        return
    end

    -- 如果玩家正在上庄列表中,则从上庄列表中移除
    self.bankmgr:remove(uid)

    local seat = self:getSeatByUid(uid)
    if seat and seat.isplaying then -- 如果该离开的玩家坐下且正在玩，不能立即离开
        if
            self.state >= pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Finish") and
                seat.isplaying
         then
            user.toleave = true -- 将要离开
            log.info("idx(%s,%s) user:%s isplaying", self.id, self.mid, uid)
            handleFailed()
            return
        end
    end

    -- 如果玩家正在坐庄
    if uid == self.bankerUID then -- 如果该玩家正在坐庄
        self:updateBanker(true)
    elseif seat then
        self:stand(seat, uid, pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")) -- 玩家起立
    end

    user.state = EnumUserState.Leave -- 玩家状态变成离开状态

    -- 结算
    local val = user.room_delta or 0 -- 身上金额变化值
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
                gameId = self.logid,
                gameType = global.stype(),
                tableId = global.stype()
            }
        )

        log.info(
            "idx(%s,%s) money change uid:%s val:%s %s,%s",
            self.id,
            self.mid,
            uid,
            val,
            seat and seat.chips or 0,
            seat and seat.buyinToMoney or 0
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
            seconds = global.ctsec() - (seat and (seat.intots or 0) or 0),
            changed = user.room_delta or 0,
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
            seat and seat.sid or 0,
            cjson.encode(logdata)
        )
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

    self.users[uid] = nil
    self.user_cached = false -- 玩家缓存变更(无效)
    local resp =
        pb.encode(
        "network.cmd.PBLeaveGameRoomResp_S",
        {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess"), -- 成功离开
            roomtype = self.conf.roomtype
        }
    )
    if linkid and uid ~= 0 then
        net.send( --发送离开成功消息
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
    end
    log.info("idx(%s,%s) userLeave:%s,%s", self.id, self.mid, uid, user.gamecount or 0)

    if not next(self.users) then -- 如果该房间没有玩家
        MatchMgr:getMatchById(self.conf.mid):shrinkRoom() -- 移除空房间
    end
end

local function onMutexTo(arg)
    arg[2]:userMutexCheck(arg[1], -1)
end

-- 查询玩家信息超时
local function onTimeout(arg)
    arg[2]:userQueryUserInfo(arg[1], false, nil)
end

-- 玩家进入房间
function Room:userInto(uid, linkid, mid, quick, ip)
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

    if self.isStopping then
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入房间失败
        net.send( -- 发送进入房间失败消息
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
        )
        return
    end

    self.users[uid] = self.users[uid] or {TimerID_MutexTo = timer.create(), TimerID_Timeout = timer.create()}
    local user = self.users[uid]
    user.money = 0
    user.diamond = 0
    user.linkid = linkid
    user.ip = ip
    user.state = EnumUserState.Intoing
    user.totalbet = user.totalbet or 0

    --座位互斥
    local seat, inseat = nil, false -- 可坐下的座位信息 , 玩家是否已经坐下
    local first_null_seat = nil -- 第一个空座位

    for k, v in ipairs(self.seats) do -- 遍历该桌所有座位
        if v.uid then -- 如果该座位上有人
            -- 其他人在该座位上
            if v.uid == uid then -- 如果该玩家已经在该座位
                inseat = true
                seat = v
                break
            end
        else
            -- seat = v -- 空闲的座位
            if first_null_seat == nil and k ~= 8 then
                first_null_seat = v
            end
        end
    end
    if not inseat then
        seat = first_null_seat -- 使用第一个空座位
    end
    if not seat then -- 如果没有空闲的座位可坐下
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
            if not ok then -- 如果进入房间失败
                if self.users[uid] ~= nil then
                    timer.destroy(user.TimerID_MutexTo)
                    timer.destroy(user.TimerID_Timeout)
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
                log.info("idx(%s,%s) player:%s has been in another room", self.id, self.mid, uid) -- 该玩家已经在其他房间中
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
                    --print("start coroutine", self, user, uid)
                    local ok, ud = coroutine.yield()
                    --print('ok', ok, 'ud', ud)
                    if ud then -- 如果查询到玩家信息
                        -- userinfo
                        user.uid = uid --玩家ID
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
                        user.ud = ud

                        user.playerinfo = {
                            uid = uid,
                            username = ud.name or "",
                            nickurl = ud.nickurl or "",
                            balance = self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and
                                ud.money or
                                ud.coin,
                            extra = {
                                ip = user.ip or "",
                                api = ud.api or ""
                            }
                        }
                    end

                    -- 防止协程返回时，玩家实质上已离线
                    if ok and user.state ~= EnumUserState.Intoing then
                        ok = false
                        log.info("idx(%s,%s) user %s logout or leave", self.id, self.mid, uid)
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                    end
                    if ok and self:getUserMoney(uid) > self.conf.maxinto then
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

                    if ok and not inseat and self.conf.minbuyinbb * self.conf.ante > self:getUserMoney(uid) then -- 身上金额不足
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
                        if self.users[uid] ~= nil then
                            timer.destroy(user.TimerID_MutexTo)
                            timer.destroy(user.TimerID_Timeout)
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

                    quick = (0x2 == (self.conf.buyin & 0x2)) and true or false

                    if not inseat and self:count() < self.conf.maxuser and quick then
                        self:sit(seat, uid, self:getUserMoney(uid)) -- 玩家坐下
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

-- 获取庄家UID及其座位号
function Room:getBankerUidPos()
    local uid = 0
    local pos = 0
    uid = self.bankmgr:banker() or 0
    -- 从座位列表中查找该玩家
    for k, v in ipairs(self.seats) do
        if v.uid == uid then -- 如果该座位玩家正在玩
            v.isplaying = true
            pos = k
            break
        end
    end

    return uid, pos
end

--   房间重置
function Room:reset()
    self.pots = {money = 0, seats = {}}
    --奖池中包含哪些人共享

    self.roundcount = 0 -- 轮数？
    self.hasFinished = false
    self.hasSendUpdatePotsToAll = false

    self.sdata = {
        roomtype = self.conf.roomtype,
        tag = self.conf.tag
    }
    self.reviewlogitems = {}

    self.poker:start() -- 开始洗牌

    self.betque = {} -- 下注数据队列, 用于重放给其它客户端, 元素类型为 PBPokDengBetData

    self.winner_seats = nil

    self.m_join_type = 0
    self.buttonpos = self.conf.maxuser or 8 -- 庄家始终在该位置?

    self.hasSendCard = false

    for k, v in pairs(self.users) do
        if v then
            v.totalbet = 0
        end
    end
    self.hasCalcResult = false
    self.bankmgr:successive()
end

-- 获取桌子信息
function Room:userTableInfo(uid, linkid, rev)
    log.info(
        "idx(%s,%s) user table info req uid:%s ante:%s, buttonpos=%s,bankerUID=%s",
        self.id,
        self.mid,
        uid,
        self.conf.ante,
        self.buttonpos,
        self.bankerUID
    )
    local tableinfo = {
        gameId = self.gameId,
        seatCount = self.conf.maxuser,
        tableName = self.conf.name,
        gameState = self.state or 1, -- 当前游戏状态
        stateLeftTime = 10, -- 当前状态剩余时长（秒）
        buttonSid = self.buttonpos or 8, -- 庄家所在座位号
        chips = g.copy(self.conf.chips), -- 筹码配置信息
        serialBankTimes = 10, -- 最大连庄次数
        matchType = self.conf.matchtype,
        matchState = self.conf.matchState or 0,
        roomType = self.conf.roomtype,
        toolCost = self.conf.toolcost,
        ante = self.conf.ante, -- 底注
        minbuyinbb = self.conf.minbuyinbb or 1000,
        maxbuyinbb = self.conf.maxbuyinbb or 100000,
        bankertimes = self.conf.max_bank_successive_cnt - self.bankmgr:successiveCnt() + 1,
        bankeruid = self.bankerUID or 0,
        addBetMin = self.conf.addbetmin * self.conf.ante or 10 * self.conf.ante,
        addBetMax = self.conf.addbetmax * self.conf.ante or 100 * self.conf.ante,
        bankerMinMoney = self.conf.min_onbank_moneycnt or 10000,
        stateTimeLength = self:getCurrentStateTimeLength()
    }

    tableinfo.serialBankTimes = self.conf.max_bank_successive_cnt or 10
    if
        self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") or
            self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard")
     then
        tableinfo.stateLeftTime = TimerID.TimerID_Bet[2] - (global.ctsec() - self.stateBeginTime)
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_DealCard") then
        tableinfo.stateLeftTime = TimerID.TimerID_DealCard[2] - (global.ctsec() - self.stateBeginTime)
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") then
        tableinfo.stateLeftTime = 2
    end

    self:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    --log.info("idx(%s,%s) uid:%s discardCard:%s", self.id, self.mid, uid, cjson.encode(tableinfo.discardCard))
end

function Room:sendAllSeatsInfoToMe(uid, linkid, tableinfo)
    tableinfo.seatInfos = {}
    for i = 1, #self.seats do  -- 遍历所有座位
        local seat = self.seats[i] -- 第i个座位
        if seat.uid then
            local seatinfo = fillSeatInfo(seat, self)
            seatinfo.handcards = {} -- 手牌
            seatinfo.cardtype = seat.cardtype
            if self.state >= pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ShowCard") then
                seatinfo.handcards = g.copy(seat.handcards) -- 拷贝手牌数据
            elseif self.state >= pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_DealCard") then
                if seat.uid == uid then
                    seatinfo.handcards = g.copy(seat.handcards) -- 拷贝手牌数据
                    seatinfo.wintimes = self.poker:getTimesByCard(seat.handcards)
                else
                    if seat.isplaying then
                        if seat.cardtype and seat.cardtype >= 8 then
                            -- table.insert(seatinfo.handcards, seat.handcards) -- 如果为博定牌，则直接发牌
                            seatinfo.handcards = g.copy(seat.handcards)
                            seatinfo.wintimes = self.poker:getTimesByCard(seat.handcards)
                        else
                            local num = #seat.handcards
                            if num == 2 then
                                seatinfo.handcards = {0, 0}
                            elseif num == 3 then
                                seatinfo.handcards = {0, 0, 0}
                            end
                        end
                    end
                end
            end
            table.insert(tableinfo.seatInfos, seatinfo)
        end
    end

    local resp = pb.encode("network.cmd.PBPokDengTableInfoResp", {tableInfo = tableinfo})
    log.info("tableinfo=%s", cjson.encode(tableinfo))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengTableInfoResp"), -- 发送桌子信息
        resp
    )
end

--判断某玩家是否坐下
function Room:inTable(uid)
    for i = 1, #self.seats do
        if self.seats[i].uid == uid then
            return true
        end
    end
    return false
end

-- 根据玩家ID获取该玩家所坐座位
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

-- 获取该局游戏ID
function Room:getGameId()
    return self.gameId + 1 -- 游戏局号增1
end

-- 玩家起立
-- 参数 seat: 座位对象
-- 参数 stype：站起方式 PBTexasStandType 中的值，如：PBTexasStandType_PlayerStand 正常站起
function Room:stand(seat, uid, stype)
    local user = self.users[uid]
    if not seat then
        seat = self:getSeatByUid(uid)
    end
    log.info("idx(%s,%s) stand uid=%s,sid=%s,%s", self.id, self.mid, uid, seat and seat.sid or 0, tostring(stype))
    if seat and user then
        if self:canStandup(uid) then
            -- 判断该玩家是否在申请上庄列表中
            self.bankmgr:remove(uid)

            -- 判断该玩家是否正在坐庄
            if uid == self.bankerUID then
                log.debug("Room:stand(), uid=%s", uid)
                self:updateBanker(true) -- 强制换庄
                return true
            end
        end

        if
            self.state >= pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") and
                self.state < pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Finish") and
                seat.isplaying
         then
            -- 统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[uid] = self.sdata.users[uid] or {}
            self.sdata.users[uid].totalpureprofit = self.sdata.users[uid].totalpureprofit or seat.profit
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
                    roomtype = self.conf.roomtype
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
                    handcards = g.copy(seat.handcards),
                    win = seat.room_delta,
                    showcard = false,
                    wintype = 1
                }
        end
        user.room_delta = seat.room_delta

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
    -- log.info("idx(%s,%s) stand uid=%s,sid:%s,%s", self.id, self.mid, uid, seat.sid, tostring(stype))
end

-- 玩家坐下到指定位置
function Room:sit(seat, uid, buyinmoney, isplaying)
    log.info("idx(%s,%s) sit uid %s,sid %s", self.id, self.mid, uid, seat.sid)
    local user = self.users[uid]
    if user then
        -- MatchMgr:getMatchById(self.conf.mid):expandRoom()
        log.info("idx(%s,%s) sit uid %s,sid %s, buyinmoney=%s", self.id, self.mid, uid, seat.sid, buyinmoney)
        seat:sit(uid, buyinmoney, 0, 0, isplaying)
        local seatinfo = fillSeatInfo(seat, self)
        local sitcmd = {seatInfo = seatinfo}
        pb.encode(
            "network.cmd.PBPokDengPlayerSit",
            sitcmd,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengPlayerSit"),
                    pointer,
                    length
                )
            end
        )
        log.info("idx(%s,%s) player sit in seatinfo:%s", self.id, self.mid, cjson.encode(sitcmd))
    end
end

--通知该桌所有玩家轮到某人出牌了
function Room:sendPosInfoToAll(seat, chiptype)
    local updateseat = {}
    if chiptype then
        seat.chiptype = chiptype
    end

    if seat.uid then
        updateseat.seatInfo = fillSeatInfo(seat, self)
        pb.encode(
            "network.cmd.PBPokDengUpdateSeat",
            updateseat,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengUpdateSeat"),
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

--
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
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengUpdateSeat"),
            pb.encode("network.cmd.PBPokDengUpdateSeat", updateseat)
        )
        log.info("idx(%s,%s) checkcard:%s", self.id, self.mid, cjson.encode(updateseat))
    end
end

-- 准备开始游戏
function Room:ready()
    if not self.ready_start_time then -- 如果还未准备
        self.ready_start_time = global.ctsec() -- 准备阶段开始时刻(秒)

        -- 广播准备
        local gameready = {
            readyLeftTime = TimerID.TimerID_Ready[2] - (global.ctsec() - self.ready_start_time) -- 准备阶段还剩多少秒
        }
        pb.encode(
            "network.cmd.PBPokDengGameReady",
            gameready,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengGameReady"),
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
        self:start() -- 真正开始游戏
    end
end

-- 更新庄家
-- 参数 force: 是否强制更新庄家
function Room:updateBanker(force)
    local needChangeBanker = false -- 是否需要换庄

    local old_onbankcnt = self.bankmgr:count() -- 申请上庄人数

    local banker_money = self:getUserMoney(self.bankerUID)

    -- local banker_money = self.bankmgr:banker() > 0 and self:getUserMoney(self.bankmgr:banker()) or self.conf.min_outbank_moneycnt

    log.info(
        "idx(%s,%s) updateBanker() bankerUID=%s, banker_money=%s, old_onbankcnt=%s, min_outbank_moneycnt=%s, successiveCnt=%s",
        self.id,
        self.mid,
        self.bankerUID,
        banker_money,
        old_onbankcnt,
        self.conf.min_outbank_moneycnt,
        self.bankmgr:successiveCnt()
    )

    if not force then
        if self.bankmgr:successiveCnt() > self.conf.max_bank_successive_cnt then -- 坐庄次数
            needChangeBanker = true
        elseif banker_money < self.conf.min_outbank_moneycnt then -- 玩家身上金额不足
            needChangeBanker = true
        elseif not self.users[self.bankmgr:banker()] then -- 庄家不在线
            needChangeBanker = true
        elseif self.bankmgr:banker() == 0 then
            needChangeBanker = true
        else
            needChangeBanker = false
        end
    else
        needChangeBanker = true
    end
    if self.bankmgr:isGoingDown() then
        needChangeBanker = true
    end

    local oldBankerUID = self.bankerUID -- 原庄家UID
    local newBankerUID = 0 -- 新庄家UID
    if needChangeBanker then
        -- 从庄家列表中获取一个满足条件的玩家坐庄
        local i = 1
        while i <= old_onbankcnt do
            i = i + 1
            -- if self.bankmgr:count() == 0 then
            --     break
            -- end
            self.bankmgr:pop()
            newBankerUID = self.bankmgr:banker()
            if newBankerUID == 0 then -- 系统坐庄
                break
            end
            -- 判断该新庄家是否在线以及金额是否足够
            if self.users[newBankerUID] then -- 确保该玩家在线
                if self:getUserMoney(newBankerUID) >= self.conf.min_onbank_moneycnt then -- 金额足够
                    break
                end
            end
        end

        if oldBankerUID == newBankerUID then
            return
        end

        log.info(
            "dqw idx(%s,%s) updateBanker() needChangeBanker oldBankerUID=%s,newBankerUID=%s",
            self.id,
            self.mid,
            oldBankerUID,
            newBankerUID
        )
        pb.encode(
            "network.cmd.PBGameNotifyOnBankCnt_N",
            {cnt = self.bankmgr:count() or 0},
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyOnBankCnt"),
                    pointer,
                    length
                )
            end
        )

        local bankerSid = 0 -- 新庄家原来的位置
        for k, v in ipairs(self.seats) do
            if newBankerUID == v.uid then
                bankerSid = k
                break
            end
        end

        local updateBankerSit = {
            sid = bankerSid,
            count = self.conf.max_bank_successive_cnt
        }
        self.bankerUID = newBankerUID  -- 新庄家UID

        pb.encode(
            "network.cmd.PBPokDengUpdateBanker",
            updateBankerSit,
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengUpdateBanker"),
                    pointer,
                    length
                )
            end
        )

        log.info(
            "stand updatebanker oldBankerUID=%s, self.bankerUID=%s, sid=%s,count=%s",
            oldBankerUID,
            self.bankerUID,
            bankerSid,   -- 新庄家原来的位置
            updateBankerSit.count
        )

        self.seats[self.conf.maxuser]:stand(oldBankerUID) -- 原庄家站起
        pb.encode(
            "network.cmd.PBTexasPlayerStand",
            {sid = self.conf.maxuser, type = pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")},
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerStand"),
                    pointer,
                    length
                )
            end
        )

        if bankerSid > 0 then  -- 新庄家原来的位置
            pb.encode(
                "network.cmd.PBTexasPlayerStand",
                {sid = bankerSid, type = pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")},
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPlayerStand"),
                        pointer,
                        length
                    )
                end
            )
            self.seats[bankerSid]:stand(newBankerUID)  -- 新庄家从原来位置站起 
            log.info("dqw player stand  uid=%s, sid=%s", newBankerUID, bankerSid)
        -- self:stand(
        --     self.seats[bankerSid],
        --     newBankerUID,
        --     pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
        -- )
        end

        -- self:stand(
        --     self.seats[self.conf.maxuser],
        --     oldBankerUID,
        --     pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_PlayerStand")
        -- )

        if self.bankerUID ~= 0 then -- 如果非系统坐庄
            log.info("dqw idx(%s,%s) self.bankerUID=%s", self.id, self.mid, self.bankerUID)
            self:sit(self.seats[self.conf.maxuser], self.bankerUID, self:getUserMoney(self.bankerUID), true)  -- 新庄家坐下 
        else -- 如果是系统坐庄
            log.info("dqw idx(%s,%s) system on bank", self.id, self.mid)
            self.users[0] = self.users[0] or {money = 2000000}
            self:sit(self.seats[self.conf.maxuser], self.bankerUID, 2000000, true)
        end
        self.seats[self.conf.maxuser].isplaying = true
    end

    -- -- 检测是否换庄
    -- self.bankmgr:checkSwitch(
    --     self.conf.max_bank_successive_cnt, -- 最大连庄次数
    --     self.users[self.bankmgr:banker()] and true or false, -- 庄家是否在线
    --     banker_money >= self.conf.min_outbank_moneycnt and true or false -- 上庄金额是否足够
    -- )
end

-- 游戏开始 所有人准备好后就开始游戏
function Room:start()
    self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start"))

    self.has_started = self.has_started or true -- 标识已经开始

    self:reset() -- 重置该桌信息
    self.gameId = self:getGameId() -- 更新游戏ID
    self.tableStartCount = self.tableStartCount + 1
    self.starttime = global.ctsec() -- 开始时刻(秒)
    self.logid = self.statistic:genLogId(self.starttime) -- 日志ID

    log.info(
        "start() idx(%s,%s) start ante:%s gameId:%s logid:%s",
        self.id,
        self.mid,
        self.conf.ante,
        self.gameId,
        tostring(self.logid)
    )

    -- 服务费
    for k, v in ipairs(self.seats) do
        if v.uid and v.isplaying then -- 如果该座位玩家正在玩
            local user = self.users[v.uid] or {}
            if user then
                user.gamecount = (user.gamecount or 0) + 1 -- 统计数据
            end
            if self.conf and self.conf.fee and v.chips > self.conf.fee then
                v.last_chips = v.chips

                self.sdata.users = self.sdata.users or {}
                self.sdata.users[v.uid] = self.sdata.users[v.uid] or {}
                if v.uid > 0 then
                    self.sdata.users[v.uid].totalfee = self.conf.fee
                    v.chips = v.chips - self.conf.fee -- 扣除该座位玩家的服务费
                    v.room_delta = v.room_delta - self.conf.fee -- 总的纯收益
                    v.profit = v.profit - self.conf.fee
                end
            end
        end
    end

    local gamestart = {
        gameId = self.gameId,
        gameState = self.state,
        buttonSid = self.buttonpos,
        ante = self.conf.ante, -- 前注
        chiplist = g.copy(self.conf.chips), -- 下注筹码列表,如：{10, 20, 50, 100}
        tableStarttime = self.starttime,
        seats = fillSeats(self),
        bankertimes = self.conf.max_bank_successive_cnt - self.bankmgr:successiveCnt() + 1,
        bankeruid = self.bankerUID
    }

    pb.encode(
        "network.cmd.PBPokDengGameStart",
        gamestart,
        function(pointer, length)
            self:sendCmdToPlayingUsers( -- 通知玩家游戏开始，准备下注
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengGameStart"),
                pointer,
                length
            )
        end
    )
    log.info(
        "start() idx(%s,%s) playingcnt=%s, PBPokDengGameStart=%s",
        self.id,
        self.mid,
        self:getPlayingSize(),
        cjson.encode(gamestart)
    )

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

    --self:dealPreChips()

    self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet"))

    timer.tick(self.timer, TimerID.TimerID_Run[1], TimerID.TimerID_Run[2], onRun, self)
end

-- 玩家下注
-- 参数 uid: 操作者玩家ID
-- 参数 value：下注金额
function Room:userBet(uid, value, client, linkid)
    uid = uid or 0
    value = value or 0

    if client then
        log.info("idx(%s,%s) userBet(...) uid=%s, value=%s, client=true", self.id, self.mid, uid, value)
    else
        log.info("idx(%s,%s) userBet(...) uid=%s, value=%s ,client=false", self.id, self.mid, uid, value)
    end

    local t = {
        -- 待返回的结构
        code = 0, -- 默认操作成功
        betValue = value,
        totalValue = value,
        balance = 0
    }
    local user = self.users[uid]
    local ok = true -- 默认下注成功
    local user_totalbet = value -- 玩家此次总下注金额

    -- 根据玩家ID获取座位
    local seat = self:getSeatByUid(uid)
    if not seat then
        ok = false
        goto labelnotok
    end

    -- 检测是否是非法玩家
    if not user then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidUser") -- 非法用户
        ok = false
        goto labelnotok
    end

    -- 庄家不允许下注
    if uid == self.bankerUID then
        log.info("idx(%s,%s) user %s is not is banker", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_IsBanker")
        ok = false
        goto labelnotok
    end

    -- 检测下注状态
    if self.state ~= pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") then
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidGameState") -- 非下注状态
        ok = false
        goto labelnotok
    end

    -- 下注金额校验
    if value <= 0 then
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue")
        ok = false
        goto labelnotok
    end

    -- 余额不足
    if user_totalbet > self:getUserMoney(uid) then
        log.info("idx(%s,%s) user %s, totalbet over user's balance", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverBalance")
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    if not ok then
        if client and linkid then
            local resp = pb.encode("network.cmd.PBPokDengBetResp_S", t)
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengBetResp"), -- 成功下注回应
                resp
            )
        end

        return
    end

    seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_BET")
    -- 扣费
    user.playerinfo = user.playerinfo or {}
    if user.playerinfo.balance and user.playerinfo.balance > user_totalbet then
        user.playerinfo.balance = user.playerinfo.balance - user_totalbet
    else
        user.playerinfo.balance = 0
    end

    -- 记录下注数据
    -- local areabet = {}
    user.totalbet = user.totalbet or 0
    user.totalbet = user.totalbet + user_totalbet

    self.sdata.users = self.sdata.users or {}
    self.sdata.users[uid] = self.sdata.users[uid] or {}
    self.sdata.users[uid].totalbet = user.totalbet

    -- 将下注记录插入队列末尾
    table.insert(
        self.betque,
        {uid = uid, balance = self:getUserMoney(uid), usertotal = user.totalbet, betarea = seat.sid}
    )

    -- 返回数据
    t.balance = self:getUserMoney(uid) -- 该玩家身上剩余金额
    t.totalValue = user.totalbet
    t.sid = seat.sid or 0

    pb.encode(
        "network.cmd.PBPokDengBetResp_S",
        t,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengBetResp"), -- 成功下注回应
                pointer,
                length
            )
        end
    )

    -- 打印玩家成功下注详细信息
    log.info("idx(%s,%s) user %s, PBPokDengBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

-- 更新座位状态
function Room:updateSeatsInfo()
    if self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") then
        for k, seat in ipairs(self.seats) do
            local user = self.users[seat.uid]
            if user and self.buttonpos ~= k then
                if user.totalbet == 0 then
                    seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_BETING") -- 准备下注
                else
                    seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_BET") -- 已经下注
                end
            end
        end
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard") then -- 补牌阶段
        for k, seat in ipairs(self.seats) do
            if seat.thirdCardOperate == 0 then
                local cardPoint = self.poker:getCardPoint(seat.handcards)
                if cardPoint == 9 or cardPoint == 8 then
                    seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_Get")
                else
                    seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_Getting") -- 准备补牌
                end
            else
                seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_Get") -- 已经补牌
            end
        end
    end
end

-- 玩家补牌
-- 参数 uid: 补牌者玩家ID
-- 参数 value：补牌操作方式 (1:double 2:补牌  3:不补牌)
function Room:userGetThirdCard(uid, value, client, linkid)
    uid = uid or 0
    value = value or 0

    local t = {
        code = 0, -- 操作结果(0:操作成功 1:玩家不存在  2:已操作过  3:庄家不能下注  4:操作码错误 5:余额不足 6:不是补牌阶段 7:博定不需要补牌)
        value = value
    }
    local user = self.users[uid]
    local seat = self:getSeatByUid(uid)
    if not seat or not user then
        t.code = 1
        goto labelnotok
    end
    if seat.thirdCardOperate and seat.thirdCardOperate > 0 then
        t.code = 2
        goto labelnotok
    end
    if value < 1 or value > 3 then
        t.code = 4
        goto labelnotok
    end

    if uid == self.bankerUID then --
        if value == 2 then -- 补牌
            t.code = 0
        elseif value == 3 then -- 不补牌
            t.code = 0
        else
            t.code = 3
            goto labelnotok
        end
    else
        t.code = 0
    end

    -- 判断此时是否为补牌阶段
    if self.state ~= pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard") then
        t.code = 6
        goto labelnotok
    end
    -- 判断该玩家的牌型是否为博定
    if self.poker:getCardType(seat.handcards) >= 8 then
        t.code = 7
        goto labelnotok
    end

    seat.thirdCardOperate = value -- 保存操作码
    seat.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_Get")
    if value == 1 then -- double
        -- 余额不足
        if user.totalbet > self:getUserMoney(uid) then
            t.code = 5
            goto labelnotok
        end
        if not user.playerinfo or user.playerinfo.balance then
            t.code = 6
            goto labelnotok
        end
        user.playerinfo.balance = user.playerinfo.balance - user.totalbet
        user.totalbet = user.totalbet * 2
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_NotifyGameCoinUpdate"),
            pb.encode("network.cmd.PBNotifyGameCoinUpdate_N", {val = user.playerinfo.balance})
        )

        self.sdata.users = self.sdata.users or {}
        self.sdata.users[uid] = self.sdata.users[uid] or {}
        self.sdata.users[uid].totalbet = user.totalbet

        t.totalBet = user.totalbet
        t.balance = user.playerinfo.balance
        seat.handcards[3] = self.poker:pop() -- 第3张牌
        t.cards = g.copy(seat.handcards)
        -- 补牌后需重新计算牌型
        seat.cardtype = self.poker:getCardType(seat.handcards)
        log.info("idx(%s,%s), self.id, self.mid")
    elseif value == 2 then -- 补牌
        seat.handcards[3] = self.poker:pop() -- 第3张牌
        -- 补牌后需重新计算牌型
        seat.cardtype = self.poker:getCardType(seat.handcards)
        t.cards = g.copy(seat.handcards)
        t.totalBet = user.totalbet

        if not user.playerinfo or not user.playerinfo.balance then
            log.info("[error]userGetThirdCard() uid=%s,value=%s", uid, value)
            user.playerinfo = user.playerinfo or {}
            user.playerinfo.balance = user.playerinfo.balance or 0
        end
        t.balance = user.playerinfo.balance
    elseif value == 3 then -- 不补牌
        t.cards = g.copy(seat.handcards)
        t.totalBet = user.totalbet
        if not user.playerinfo or user.playerinfo.balance then
            log.info("[error]userGetThirdCard() uid=%s,value=%s", uid, value)
            user.playerinfo = user.playerinfo or {}
            user.playerinfo.balance = user.playerinfo.balance or 0
        end
        t.balance = user.playerinfo.balance
    end
    t.cardtype = seat.cardtype
    t.wintimes = self.poker:getTimesByCard(seat.handcards)

    ::labelnotok::

    -- 返回操作结果
    if client then
        local resp = pb.encode("network.cmd.PBPokDengGetThirdCardResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengGetThirdCardResp"), -- 操作回应
            resp
        )
        log.info(
            "idx(%s,%s) user %s, client=1, PBPokDengGetThirdCardResp_S: %s",
            self.id,
            self.mid,
            uid,
            cjson.encode(t)
        )

        if t.code == 0 and t.value ~= 3 then
            local notify = {sid = seat.sid, value = t.value, totalBet = t.totalBet, balance = t.balance}
            pb.encode(
                "network.cmd.PBPokDengGetThirdCardNotify",
                notify,
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengGetThridCard"),
                        pointer,
                        length
                    )
                end
            )
            log.info("getThirdCardNotify = %s", cjson.encode(notify))
        end
    else -- 如果是超时后系统自动帮其补牌
        local resp = pb.encode("network.cmd.PBPokDengGetThirdCardResp_S", t)
        local user = self.users[uid]
        if user and user.linkid then
            net.send(
                user.linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengGetThirdCardResp"), -- 操作回应
                resp
            )
        end
        log.info(
            "idx(%s,%s) user %s, client=0, PBPokDengGetThirdCardResp_S: %s",
            self.id,
            self.mid,
            uid,
            cjson.encode(t)
        )
        if t.code == 0 and t.value ~= 3 then
            local notify = {sid = seat.sid, value = t.value, totalBet = t.totalBet, balance = t.balance}
            pb.encode(
                "network.cmd.PBPokDengGetThirdCardNotify",
                notify,
                function(pointer, length)
                    self:sendCmdToPlayingUsers(
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengGetThridCard"),
                        pointer,
                        length
                    )
                end
            )
            log.info("getThirdCardNotify = %s", cjson.encode(notify))
        end
    end
end

-- 更新房间状态
function Room:changeState(currentState)
    local oldState = self.state
    self.state = currentState
    self.stateBeginTime = global.ctsec()

    if oldState ~= currentState then
        if
            currentState == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") or
                currentState == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard")
         then
            self:updateSeatsInfo()
        end
        self:notifyChangeState()
    end
end

function Room:betTimeout()
    log.info("idx(%s,%s) bet timeout", self.id, self.mid)

    -- 检测是否有未下注的玩家，若还未下注，则自动压房间最小注
    for k, v in ipairs(self.seats) do
        local user = self.users[v.uid]
        if v.isplaying and user and (user.totalbet == 0) then
            --local minChip = self.conf.chips[1] * self.conf.ante or 10 -- 最小筹码
            local minChip = self.conf.ante or 10 -- 最小筹码
            if v.uid ~= self.bankerUID then -- 如果不是庄家
                if self.users[v.uid] then
                    self:userBet(v.uid, minChip, false, self.users[v.uid].linkid)
                    self.users[v.uid].notOperateTimes = self.users[v.uid].notOperateTimes or 0
                    self.users[v.uid].notOperateTimes = self.users[v.uid].notOperateTimes + 1
                end
            end
        end
    end
end

-- 补牌操作超时
function Room:getThirdCardTimeout()
    log.info("idx(%s,%s) getThirdCard timeout", self.id, self.mid)
    for _, v in ipairs(self.seats) do
        if v.uid and v.isplaying then
            if v.thirdCardOperate == 0 then -- 如果还未操作过
                v.cardtype = self.poker:getCardType(v.handcards) -- 根据手牌判断牌型
                if v.cardtype and v.cardtype >= 8 then
                    v.thirdCardOperate = 3 -- 博定不需要补牌
                else
                    local totalPoint = self.poker:getCardPoint(v.handcards)
                    if totalPoint <= 3 then -- 三点（含）补牌一张
                        self:userGetThirdCard(v.uid, 2, false, nil)
                        v.thirdCardOperate = 2
                    else
                        v.thirdCardOperate = 3 -- 四点（含）及以上不补牌。
                    end

                    self.users[v.uid].notOperateTimes = self.users[v.uid].notOperateTimes or 0
                    self.users[v.uid].notOperateTimes = self.users[v.uid].notOperateTimes + 1
                end
            end
            v.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_Get")
        end
    end
end

function Room:notifyChangeState()
    local stateInfo = {
        state = self.state,
        stateLeftTime = 10
    }

    pb.encode(
        "network.cmd.PBPokDengStateInfo",
        stateInfo,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengChangeState"),
                pointer,
                length
            )
        end
    )
    log.info(
        "notifyChangeState() idx(%s,%s) playingcnt=%s, stateInfo:%s",
        self.id,
        self.mid,
        self:getPlayingSize(),
        cjson.encode(stateInfo)
    )
end

-- 通知玩家开牌
function Room:showCards()
    -- --通知
    local allSeatCards = {
        allCards = {}
    }
    local index = 1
    --local bankCardType = self.seats[self.buttonpos].cardtype -- 获取庄家牌型
    for k, seat in ipairs(self.seats) do
        if seat.uid and seat.isplaying then
            local seatCards = {uid = seat.uid, sid = k, card = g.copy(seat.handcards), cardtype = seat.cardtype}
            seatCards.wintimes = self.poker:getTimesByCard(seat.handcards)

            log.info("uid=%s,wintimes=%s,cardtype=%s", seat.uid, seatCards.wintimes, seat.cardtype)
            table.insert(allSeatCards.allCards, seatCards)
        end
    end

    pb.encode(
        "network.cmd.PBPokDengShowCard",
        allSeatCards,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengShowCard"),
                pointer,
                length
            )
        end
    )
    log.info("showCards() idx(%s,%s) allSeatCards=%s", self.id, self.mid, cjson.encode(allSeatCards))
end

function Room:run()
    local currentTime = global.ctsec()
    if self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_None") then
        --log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state))
        if global.stopping() then
            return
        end
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") then --
        --log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state))
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") then
        if currentTime - self.stateBeginTime >= TimerID.TimerID_Bet[2] then
            self:betTimeout()
        end
        local c, n = 0, 0
        for k, v in ipairs(self.seats) do
            local user = self.users[v.uid]
            if v.isplaying and k ~= self.buttonpos then
                c = c + 1
                if user and (user.totalbet or 0) > 0 then
                    n = n + 1
                end
            end
        end
        local isallconfirm = c == n and c > 0
        if isallconfirm then
            self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_DealCard"))
        end
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_DealCard") then
        -- log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state))
        if not self.hasSendCard then
            self.hasSendCard = true
            self:dealHandCards()

            -- 判断庄家的牌型是否为博定，若为博定，则直接开牌()
            local seat = self.seats[self.buttonpos] -- 庄家位置
            if seat and seat.handcards then
                seat.cardtype = self.poker:getCardType(seat.handcards)
                if seat.cardtype and seat.cardtype >= 8 then -- 如果庄家牌型为博定类型，则直接进入开牌状态
                    self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ShowCard"))
                    return
                end
            end
            -- 判断所有闲家的牌型是否为博定，若为博定，则直接开牌()
            local c, n = 0, 0
            for k, v in ipairs(self.seats) do
                if v.isplaying and k ~= self.buttonpos then
                    c = c + 1
                    if v.cardtype and v.cardtype >= 8 then
                        n = n + 1
                    end
                end
            end
            if c == n and c > 0 then
                self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ShowCard"))
                return
            end
        end

        if currentTime - self.stateBeginTime >= TimerID.TimerID_DealCard[2] then
            -- 判断庄家牌型是否为博定，若状态博定，则直接进入亮牌阶段(跳过补牌阶段)
            self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard"))
        end
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard") then -- 补牌阶段
        -- log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 打印桌子状态
        -- 检测是否所有非博定玩家都做出选择，若都做出选择则直接进入亮牌阶段
        if currentTime - self.stateBeginTime >= TimerID.TimerID_GetThirdCard[2] then
            -- 系统自动帮其选择是否补牌
            self:getThirdCardTimeout()
        end
        if self.bankerUID == 0 and (currentTime - self.stateBeginTime >= 2) then
            local v = self.seats[self.conf.maxuser]
            if v and v.thirdCardOperate == 0 then -- 如果还未操作过
                v.cardtype = self.poker:getCardType(v.handcards) -- 根据手牌判断牌型
                if v.cardtype and v.cardtype >= 8 then
                    v.thirdCardOperate = 3 -- 博定不需要补牌
                else
                    local totalPoint = self.poker:getCardPoint(v.handcards)
                    if totalPoint <= 3 then -- 三点（含）补牌一张
                        self:userGetThirdCard(v.uid, 2, false, nil)
                        v.thirdCardOperate = 2
                    else
                        v.thirdCardOperate = 3 -- 四点（含）及以上不补牌。
                    end
                end
                v.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_Get")
            end
        end

        local c, n = 0, 0
        for k, v in ipairs(self.seats) do
            -- if v.isplaying and k ~= self.buttonpos then
            if v.isplaying then
                c = c + 1
                if (v.thirdCardOperate or 0) > 0 or (v.cardtype or 0) >= 8 then
                    n = n + 1
                end
            end
        end
        local isallconfirm = c == n and c > 0
        if isallconfirm then
            self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ShowCard"))
        end
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ShowCard") then
        --  log.info("idx(%s,%s) self.state = %s", self.id, self.mid, tostring(self.state)) -- 打印桌子状态
        -- 将该桌所有牌数据广播给该桌所有玩家
        self:showCards()
        -- 进入结算阶段
        self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Finish"))
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Finish") then
        -- 发送游戏结果，增加玩家身上金额
        if currentTime - self.stateBeginTime >= 2 then
            self:finish()
        end

        if currentTime - self.stateBeginTime >= 5 then
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
            -- 重置桌子后，关闭定时器，进入检测阶段
            timer.cancel(self.timer, TimerID.TimerID_Run[1])
            self:changeState(pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_None"))
            self:check()
        end
    end
end

-- 发牌
function Room:dealHandCards()
    for k, seat in ipairs(self.seats) do
        local user = seat.uid and self.users[seat.uid]
        if user and seat.isplaying then
            if self.config_switch then
                --
                log.info("[error]dealHandCards() idx(%s,%s)", self.id, self.mid)
            else
                seat.handcards = self.poker:getNCard(2) -- 发牌
                seat.cardtype = self.poker:getCardType(seat.handcards) -- 牌型
            end
            log.info(
                "idx(%s,%s) sid=%s,uid=%s deal handcard:%s cardtype:%s",
                self.id,
                self.mid,
                seat.sid,
                seat.uid,
                string.format("0x%04x,0x%04x", seat.handcards[1] & 0xFFFF, seat.handcards[2] & 0xFFFF),
                seat.cardtype
            )
        end
    end

    local cards = {
        cards = {},
        allCards = {}
    }

    for k, seat in ipairs(self.seats) do
        if seat.cardtype > 0 then
            table.insert(
                cards.cards, -- 所有玩家牌数据
                {
                    sid = k,
                    handcards = g.copy(seat.handcards),
                    cardtype = seat.cardtype,
                    wintimes = self.poker:getTimesByCard(seat.handcards)
                }
            )
        end
        if seat.cardtype >= 8 then
            table.insert(
                cards.allCards, -- 博定牌数据
                {
                    sid = k,
                    uid = seat.uid,
                    card = g.copy(seat.handcards),
                    cardtype = seat.cardtype,
                    wintimes = self.poker:getTimesByCard(seat.handcards)
                }
            )
        end
    end

    for k, user in pairs(self.users) do
        if user and user.state == EnumUserState.Playing then
            local current_seat = self:getSeatByUid(user.uid) or {sid = 0}

            local localcards = g.copy(cards)
            for k, v in ipairs(localcards.cards) do
                if v.sid ~= current_seat.sid then
                    v.handcards = nil
                    v.cardtype = nil
                end
            end

            if user.linkid then
                net.send(
                    user.linkid,
                    user.uid,
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengDealCard"),
                    pb.encode("network.cmd.PBPokDengDealCard", localcards)
                )
            end

            log.info(
                "idx(%s,%s) sid:%s,uid:%s, PBPokDengDealCard=%s",
                self.id,
                self.mid,
                current_seat.sid,
                user.uid,
                cjson.encode(localcards)
            )

            if current_seat.sid ~= 0 then
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[user.uid] = self.sdata.users[user.uid] or {}
                self.sdata.users[user.uid].sid = current_seat.sid
                self.sdata.users[user.uid].username = user.username
                self.sdata.users[user.uid].cards = g.copy(current_seat.handcards)
                if current_seat.sid == self.buttonpos then
                    self.sdata.users[user.uid].role = pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_BANKER")
                else
                    self.sdata.users[user.uid].role =
                        pb.enum_id("network.inter.USER_ROLE_TYPE", "USER_ROLE_TEXAS_PLAYER")
                end
            end
        end
    end

    -- 如果是系统当庄
end

-- 结算处理
function Room:finish()
    if self.hasFinished then
        return
    end
    self.hasFinished = true
    log.info("idx(%s,%s) finish()", self.id, self.mid)

    local pot = self:getOnePot() -- 当前底池
    self.endtime = global.ctsec() -- 结束时刻

    local FinalGame = {
        potInfos = {},
        readyLeftTime = 5
    }

    local bankCardType = self.poker:getCardType(self.seats[self.buttonpos].handcards) -- 获取庄家牌型
    local bankCardPoint = self.poker:getCardPoint(self.seats[self.buttonpos].handcards) --
    local bankWinScore = 0 -- 庄家输赢金额
    for k, seat in ipairs(self.seats) do
        local user = self.users[seat.uid]
        if user and seat.isplaying then
            local potInfo = {sid = k, nickname = user.nickname, nickurl = user.nickurl, winMoney = 0}
            if k ~= self.buttonpos then -- 若不是庄家
                local currentCardType = self.poker:getCardType(seat.handcards) -- 牌型
                local result = self.poker:compare(seat.handcards, self.seats[self.buttonpos].handcards)
                if result > 0 then -- 玩家赢
                    potInfo.winTimes = self.poker:getWinTimes(currentCardType, bankCardType)
                    potInfo.winMoney = potInfo.winTimes * user.totalbet
                    seat.room_delta = seat.room_delta + potInfo.winMoney
                    seat.profit = seat.profit + potInfo.winMoney
                    user.playerinfo.balance = user.playerinfo.balance + potInfo.winMoney + user.totalbet
                    bankWinScore = bankWinScore - potInfo.winMoney
                elseif result == 0 then -- 和
                    potInfo.winTimes = 0
                    potInfo.winMoney = 0
                    user.playerinfo.balance = user.playerinfo.balance + user.totalbet
                else -- 玩家输
                    potInfo.winTimes = -1 * self.poker:getWinTimes(bankCardType, currentCardType)
                    potInfo.winMoney = potInfo.winTimes * user.totalbet
                    user.playerinfo.balance = user.playerinfo.balance + potInfo.winMoney + user.totalbet
                    bankWinScore = bankWinScore - potInfo.winMoney
                    seat.room_delta = seat.room_delta + potInfo.winMoney
                    seat.profit = seat.profit + potInfo.winMoney
                end
                potInfo.seatMoney = user.playerinfo.balance
                potInfo.handcards = g.copy(seat.handcards)
                table.insert(FinalGame.potInfos, potInfo)

                -- 统计信息
                self.sdata.users = self.sdata.users or {}
                self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
                -- self.sdata.users[seat.uid].totalpureprofit = seat.room_delta -- 总的纯盈利
                self.sdata.users[seat.uid].totalpureprofit = seat.profit -- 总的纯盈利
                self.sdata.users[seat.uid].ugameinfo = self.sdata.users[seat.uid].ugameinfo or {}
                self.sdata.users[seat.uid].ugameinfo.texas = self.sdata.users[seat.uid].ugameinfo.texas or {}
                self.sdata.users[seat.uid].ugameinfo.texas.inctotalhands = 1 -- 该玩家玩的局数相对之前增加的局数
                self.sdata.users[seat.uid].ugameinfo.texas.inctotalwinhands = (potInfo.winMoney > 0) and 1 or 0 -- 该玩家赢的局数
                self.sdata.users[seat.uid].cards = g.copy(seat.handcards) -- 牌数据
                if k ~= self.buttonpos then -- 若不是庄家
                    self.sdata.users[seat.uid].role = 2 -- 1:庄家  2:闲家
                else
                    self.sdata.users[seat.uid].role = 1 -- 1:庄家  2:闲家
                end
            end
        end
    end
    local seat = self.seats[self.buttonpos]
    local user = self.users[seat.uid] or {}
    local bankPotInfo = {sid = self.buttonpos, nickname = user.nickname or "", nickurl = user.nickurl or ""}
    bankPotInfo.winMoney = bankWinScore
    seat.room_delta = seat.room_delta + bankWinScore -- 庄家总盈利
    seat.profit = seat.profit + bankWinScore
    bankPotInfo.handcards = g.copy(seat.handcards)

    user.playerinfo = user.playerinfo or {}
    user.playerinfo.balance = user.playerinfo.balance or 0

    user.playerinfo.balance = user.playerinfo.balance + bankPotInfo.winMoney -- 更新玩家身上金额
    bankPotInfo.seatMoney = user.playerinfo.balance
    table.insert(FinalGame.potInfos, bankPotInfo)

    -- 统计信息
    self.sdata.users = self.sdata.users or {}
    if seat.uid then
        self.sdata.users[seat.uid] = self.sdata.users[seat.uid] or {}
        self.sdata.users[seat.uid].sid = seat.sid
        self.sdata.users[seat.uid].totalpureprofit = seat.profit -- 总的纯盈利
        self.sdata.users[seat.uid].ugameinfo = self.sdata.users[seat.uid].ugameinfo or {}
        self.sdata.users[seat.uid].ugameinfo.texas = self.sdata.users[seat.uid].ugameinfo.texas or {}
        self.sdata.users[seat.uid].ugameinfo.texas.inctotalhands = 1 -- 该玩家玩的局数相对之前增加的局数
        self.sdata.users[seat.uid].ugameinfo.texas.inctotalwinhands = (bankPotInfo.winMoney > 0) and 1 or 0 -- 该玩家赢的局数
        self.sdata.users[seat.uid].cards = g.copy(seat.handcards) -- 牌数据
        self.sdata.users[seat.uid].role = 1 -- 1:庄家  2:闲家
    end

    pb.encode(
        "network.cmd.PBPokDengFinalGame",
        FinalGame,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PokDengFinalGame"),
                pointer,
                length
            )
        end
    )
    log.info("idx(%s,%s) finish %s", self.id, self.mid, cjson.encode(FinalGame))

    self.sdata.etime = self.endtime

    -- -- 已出牌数据(公共牌数据)
    self.sdata.cards = {}

    log.info("idx(%s,%s) appendLogs(),self.sdata=%s", self.id, self.mid, cjson.encode(self.sdata))
    self.statistic:appendLogs(self.sdata)

    for k, u in pairs(self.users) do
        if u then
            u.totalbet = 0
        end
    end
    self.hasCalcResult = true
end

-- 准备阶段
function Room:check()
    if global.stopping() then
        local banker = self.users[self.bankmgr:banker()]
        if banker then
            log.info("idx(%s,%s) is on bank kickout:%s", self.id, self.mid, self.mid, banker.uid)
            self.bankmgr:checkSwitch(0, false, false)
            self:userLeave(banker.uid, banker.linkid)
        end
        return
    end

    -- 准备好的玩家数(本桌正在玩的玩家数目)
    local cnt = self:getPlayingSize()

    self:updateBanker()

    log.info("idx(%s,%s) room:check playing size=%s", self.id, self.mid, cnt)

    timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 启动检测定时器(1s检测一次)
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
    local function handleFailed()
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameToolSendResp"),
            pb.encode(
                "network.cmd.PBGameToolSendResp_S",
                {
                    code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail"),
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
    local seat = self.seats[rev.fromsid]
    if seat.chips < (self.conf and self.conf.toolcost or 0) + self.conf.ante * 5 then
        log.info("idx(%s,%s) not enough money %s", self.id, self.mid, uid)
        handleFailed()
        return
    end
    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s) invalid user %s", self.id, self.mid, uid)
        handleFailed()
        return
    end
    if self.conf and self.conf.toolcost then
        seat.chips = seat.chips - self.conf.toolcost
    end
    pb.encode(
        "network.cmd.PBGameNotifyTool_N",
        {fromsid = rev.fromsid, tosid = rev.tosid, toolID = rev.toolID, seatMoney = seat.chips},
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

--
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

        local balance =
            self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and rev.money or rev.coin
        user.playerinfo = user.playerinfo or {}
        user.playerinfo.balance = user.playerinfo.balance or 0
        user.playerinfo.balance = user.playerinfo.balance + balance

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

function Room:isInCheckOrStartState()
    return self.state < pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") or
        self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Finish")
end

-- 判断指定玩家是否可以站起
function Room:canStandup(uid)
    if self.state < pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") then
        return true
    else
        local seat = self:getSeatByUid(uid)
        -- local user = self.users[uid]
        if seat and seat.isplaying then
            if self.hasCalcResult then
                return true
            end
            return false
        else
            return true
        end
    end
end

-- 判断是否可以更新房间
function Room:canChangeRoom(uid)
    if
        self.state < pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") or
            self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Finish")
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
    log.info("userWalletResp(.)")
    for _, v in ipairs(rev.data) do
        local seat = self:getSeatByUid(v.uid)
        local user = self.users[v.uid]
        if user and seat then
            user.playerinfo = user.playerinfo or {}
            if v.code > 0 then
                if
                    not self.conf.roomtype or
                        self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money")
                 then
                    user.money = v.money
                    user.playerinfo.balance = v.money
                elseif self.conf.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
                    user.coin = v.coin
                    user.playerinfo.balance = v.coin
                end
                log.info("userWalletResp(.) v.code=%s", v.code)
            end
            if user.buyin and coroutine.status(user.buyin) == "suspended" then
                coroutine.resume(user.buyin, v.code > 0)
            end
        end
    end
end

---------------------------------------------------------------------------------------------------------
-- 上下庄相关操作
-- 参数 uid： 玩家ID
--
function Room:userBankOpReq(uid, linkid, rev)
    local t = {op = rev.op, code = 0, list = {}}
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

    log.info("idx(%s,%s)userBankOpReq(...) user %s, rev.op=%s", self.id, self.mid, uid, rev.op)
    local function f_on_bank_req() -- 申请上庄
        if self.bankmgr:count() > self.conf.max_bank_list_size then -- 上庄列表人数已满
            t.code = pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_OverListSize")
            return
        end

        if user.playerinfo.balance < self.conf.min_onbank_moneycnt then -- 上庄金额不够
            t.code = pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_NotEnoughMoney")
            return
        end

        t.code = self.bankmgr:add(uid) -- 添加到上庄列表中(成功则返回0)
    end

    local function f_cancel_bank_req() -- -- 取消申请
        t.code =
            self.bankmgr:remove(uid) and pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Success") or
            pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Failed")
    end

    local function f_out_bank_req() -- -- 请求下庄
        local players = self:getPlayingSize()
        if players <= 1 and uid == self.bankerUID then
            -- self:updateBanker(true)
            t.code =
                self.bankmgr:down(uid) and pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Success") or
                pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Failed")
        else
            t.code =
                self.bankmgr:down(uid) and pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Success") or
                pb.enum_id("network.cmd.PBBankOperatorCode", "PBBankOperatorCode_Failed")
        end
    end

    local function f_list_bank_req() -- 获取上庄列表
        if self.bankerUID and self.bankerUID ~= 0 then
            local u = self.users[self.bankerUID] -- 根据UID获取对应玩家
            if u and u.playerinfo then
                table.insert(
                    t.list,
                    {
                        uid = u.uid,
                        nickurl = u.playerinfo.nickurl, -- 玩家头像URL
                        nickname = u.playerinfo.username,
                        balance = u.playerinfo.balance -- 玩家身上金额
                    }
                )
            end
        end

        local uidlist = self.bankmgr:getBankList() -- 获取申请上庄玩家列表
        for _, v in ipairs(uidlist) do
            local u = self.users[v] -- 根据UID获取对应玩家
            if u and u.playerinfo then
                table.insert(
                    t.list,
                    {
                        uid = u.uid,
                        nickurl = u.playerinfo.nickurl, -- 玩家头像URL
                        nickname = u.playerinfo.username,
                        balance = u.playerinfo.balance -- 玩家身上金额
                    }
                )
            end
        end
    end

    local switch = {
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_OnBank")] = f_on_bank_req, -- 申请上庄
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_CancelBank")] = f_cancel_bank_req, -- 取消申请上庄
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_OutBank")] = f_out_bank_req, -- 下庄
        [pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_BankList")] = f_list_bank_req -- 获取上庄列表
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
    if
        rev.op == pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_OnBank") or
            rev.op == pb.enum_id("network.cmd.PBBankOperatorType", "PBBankOperatorType_CancelBank")
     then
        if t.code == 0 then
            pb.encode(
                "network.cmd.PBGameNotifyOnBankCnt_N", --实时申请上庄人数
                {cnt = self.bankmgr:count()},
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

function Room:getCurrentStateTimeLength()
    local stateTimeLength = 10

    if
        self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Bet") or
            self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_ThirdCard")
     then
        stateTimeLength = TimerID.TimerID_Bet[2]
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_DealCard") then
        stateTimeLength = TimerID.TimerID_DealCard[2]
    elseif self.state == pb.enum_id("network.cmd.PBPokDengTableState", "PBPokDengTableState_Start") then
        stateTimeLength = 2
    end
    return stateTimeLength
end
