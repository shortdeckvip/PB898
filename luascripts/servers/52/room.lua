local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local rand = require(CLIBS["c_rand"])
local global = require(CLIBS["c_global"])
local mutex = require(CLIBS["c_mutex"])
local cjson = require("cjson")
local redis = require(CLIBS["c_hiredis"])
local g = require("luascripts/common/g")

--require("luascripts/servers/45/Pve")

-- require(string.format("luascripts/servers/%d/seat", global.stype()))
-- require(string.format("luascripts/servers/%d/vtable", global.stype()))
-- require(string.format("luascripts/servers/%d/seotdawar", global.stype()))

require("luascripts/servers/common/statistic")

cjson.encode_invalid_numbers(true)

--increment
Room = Room or { uniqueid = 0 }

--
local EnumPveType = {
    EnumPveType_BetArea1 = 1 --下注区1(A赢)
}

-- 在各下注区的下注金额(默认为0)
local DEFAULT_BET_TABLE = {
    --胜平负
    [EnumPveType.EnumPveType_BetArea1] = 0

}

-- 下注区域(下注类型)
local DEFAULT_BET_TYPE = {
    EnumPveType.EnumPveType_BetArea1
}

--
local DEFAULT_BETST_TABLE = {
    --胜负
    [EnumPveType.EnumPveType_BetArea1] = {
        type = EnumPveType.EnumPveType_BetArea1, --
        hitcount = 0, -- 命中次数
        lasthit = 0 -- 距离上次命中的局数(即连续多少局未赢)
    }
}

local TimerID = {
    -- 游戏阶段
    TimerID_Start = { 2, 1 * 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Betting = { 3, 15 * 1000 }, --id, interval(ms), timestamp(ms)  下注阶段时长
    TimerID_Show = { 4, 10 * 1000 }, --id, interval(ms), timestamp(ms)     开牌时长不一致(根据发牌张数来确定)
    TimerID_Finish = { 5, 4 * 1000 }, --id, interval(ms), timestamp(ms)
    -- 协程
    TimerID_Timeout = { 7, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = { 8, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Result = { 9, 3 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Robot = { 10, 50, 0 } --id, interval(ms), timestamp(ms)
}

-- 小游戏房间状态
local EnumRoomState = {
    Check = 1, -- 检测状态
    Start = 2, -- 开始
    Betting = 3, -- 下注
    Show = 4, -- 摊牌
    Finish = 5, -- 结算(该状态下玩家还不能离开)
    WaitResult = 6 -- 等待结果
}

-- 玩家状态
local EnumUserState = {
    Intoing = 1, -- 进入
    Playing = 2, -- 正在玩
    Logout = 3, -- 退出
    Leave = 4 -- 离开
}

-- 获取房间配置信息
function Room:conf()
    return MatchMgr:getConfByMid(self.mid) -- 根据房间类型(房间级别)获取该类房间配置
end

-- 新建房间
function Room:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init() -- 房间初始化
    o:check()
    return o
end

-- 房间初始化
function Room:init()
    -- 定时器
    self.timer = timer.create() --创建定时管理器

    -- 用户相关
    self.users = self.users or {}
    self.user_count = 0 -- 玩家总数目

    -- 牌局相关
    self.start_time = global.ctms() -- 开始时刻(毫秒)


    self.finish_time = global.ctms() -- 结算时刻

    self.state = EnumRoomState.Check -- 房间状态
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.stateOnce = false -- 是否已经执行了一次

    self.logid = 0
    self.roundid = (self.id << 16) | global.ctsec() -- 局号(唯一!)  房间ID右移16位，再左移32位，再加上时间
    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家(包括机器人)在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有真实玩家在每个下注区下注累计值
    self.betst = {} -- 下注统计
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端, 元素类型为 PBPveBetData
    self.logmgr = LogMgr:new(
        self:conf() and self:conf().maxlogsavedsize, -- 历史记录最多留存条数
        tostring(global.sid()) .. tostring("_") .. tostring(self.id)-- 服务器ID_房间ID
    ) -- 历史记录

    self.onlinelst = {} -- 在线列表
    self.sdata = { roomtype = (self:conf() and self:conf().roomtype) } -- 统计数据

    self.statistic = Statistic:new(self.id, self:conf().mid) -- 统计资料

    self.total_bets = {} -- 存放各天的总下注额
    self.total_profit = {} -- 存放各天的总收益
    Utils:unSerializeMiniGame(self)


    self.update_games = 0 -- 更新经过的局数
    self.rand_player_num = 1
    self.realPlayerUID = 0

    self.lastCreateRobotTime = 0 -- 上次创建机器人时刻
    self.createRobotTimeInterval = 4 -- 定时器时间间隔(秒)
    self.lastRemoveRobotTime = 0 -- 上次移除机器人时刻(秒)

    self.needRobotNum = 30 -- 默认需要创建30个机器人
    self.lastNeedRobotTime = 0 -- 上次需要机器人时刻

    self.allBetInfo = {} -- 所有玩家下注信息  -- 玩家ID+下注金额 [uid] = {uid=123, betValue=100, winTimes=nil}
    self.needNotifyBet = false -- 是否需要通知给各玩家当前游戏状态
    self.currentWinTimes = 0
    self.lastWinTimes = 1.0 -- 最后爆炸点位置
    self.oldWinTimes = 0
    self.calcChipsTime = 0           -- 计算筹码时刻(秒)
end

-- 重置这一局数据
function Room:roundReset()
    --self.isTest = true
    -- 牌局相关
    self.update_games = self.update_games + 1 -- 更新经过的局数

    self.start_time = global.ctms()

    self.finish_time = global.ctms()

    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家(包括机器人)在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家(不包括机器人)在每个下注区下注累计值
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端
    self.sdata = { roomtype = (self:conf() and self:conf().roomtype) } -- 清空统计数据
    -- self.sdata.cards[1].cards = { } 中存放发出的牌数据



    -- 用户数据
    for k, v in pairs(self.users) do -- 遍历该房间所有玩家
        v.bets = g.copy(DEFAULT_BET_TABLE) --在各下注区的下注额为0
        v.totalbet = 0 -- 本局总下注额
        v.profit = 0 -- 本局总收益
        v.totalprofit = 0
        v.isbettimeout = false
    end

    self.allBetInfo = {}
    self.needNotifyBet = false
    self.hasRealPlayerBet = false
    self.hasGetResult = false
end

-- 广播消息
function Room:broadcastCmd(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.linkid then
            net.send(v.linkid, k, maincmd, subcmd, msg)
        end
    end
end

-- 广播消息给正在玩的玩家
function Room:broadcastCmdToPlayingUsers(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and v.linkid then
            net.send(v.linkid, k, maincmd, subcmd, msg)
        end
    end
end

-- 发送消息给在玩玩家
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

-- 玩家总数目
function Room:count(uid)
    local ret = self:recount(uid)
    if ret and self:conf() and self:conf().single_profit_switch then
        return self.user_count - 1, self.robot_count
    else
        return self.user_count, self.robot_count
    end
end

-- 重新计算该房间玩家总数目
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

-- 获取API玩家数 ?
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

-- 当前房间类型
function Room:roomtype()
    return self:conf().roomtype
end

-- 根据服务ID清除对应玩家
function Room:clearUsersBySrvId(srvid)
    for k, v in pairs(self.users) do
        if v.linkid == srvid then
            self:logout(k) -- 此时的k为玩家ID
        end
    end
end

-- 玩家退出房间
function Room:logout(uid)
    local user = self.users[uid]
    if user then
        user.state = EnumUserState.Logout -- 该玩家变成退出状态
        self.user_cached = false
        log.info("idx(%s,%s) %s room logout %s", self.id, self.mid, uid, self.user_count)
    end
end

-- 更新神算子大赢家等座位信息(更新排行榜，通知在线玩家)
function Room:updateSeatsInVTable(vtable)
    if vtable and type(vtable) == "table" then
        local t = { seats = vtable:getSeatsInfo() }
        -- 通知更新排行榜
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

-- 获取指定玩家身上金额
function Room:getUserMoney(uid)
    local user = self.users[uid]
    --print('getUserMoney roomtype', self:conf().roomtype, 'money', 'coin', user.coin)
    return user and (user.playerinfo and user.playerinfo.balance or 0) or 0
end

-- 玩家身上金额更新
function Room:onUserMoneyUpdate(data)
    if (data and #data > 0) then
        if data[1].code == 0 then
            local resp = pb.encode("network.cmd.PBNotifyGameMoneyUpdate_N", { val = data[1].extdata.balance })
            net.send(
                data[1].acid, -- 连接ID
                data[1].uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_NotifyGameMoneyUpdate"), -- 玩家金额更新
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

-- 玩家离开房间
function Room:userLeave(uid, linkid)
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
    }
    log.info("idx(%s,%s) userLeave:%s", self.id, self.mid, uid)
    local user = self.users[uid] -- 根据玩家ID获取玩家对象
    if user == nil then
        log.info("idx(%s,%s) user:%s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
        local resp = pb.encode("network.cmd.PBLeaveGameRoomResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
                resp
            )
        end
        log.info("idx(%s,%s) net.send() success, user:%s is not in room", self.id, self.mid, uid)
        return
    end

    if user.state == EnumUserState.Leave then -- 如果玩家处于离开状态
        log.info("idx(%s,%s) has leaveed:%s", self.id, self.mid, uid)
        return
    end

    local resp = pb.encode("network.cmd.PBLeaveGameRoomResp_S", t)
    if t.code == pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess") then
        user.state = EnumUserState.Leave -- 更改玩家状态为离开状态
        self.user_cached = false --
        mutex.request(
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
            pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
            pb.encode("network.cmd.PBMutexRemove", { uid = uid, srvid = global.sid(), roomid = self.id })
        )

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
        if linkid then
            net.shared(
                linkid,
                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                synto
            )
        end
        log.info("idx(%s,%s) net.shared 1", self.id, self.mid)
        return
    end
    if linkid then
        net.send(-- 发送离开房间回应消息
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
    end
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

-- 玩家请求进入房间
-- 参数 rev: 进入房间消息
function Room:userInto(uid, linkid, rev)
    log.debug("idx(%s,%s) userInto() uid=%s, linkid=%s", self.id, self.mid, uid, tostring(linkid))
    if not linkid then
        return
    end
    local t = {
        -- 对应 PBCrashIntoRoomResp_S 消息
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(), -- 游戏ID  52-Crash
        idx = {
            srvid = global.sid(), -- 服务器ID
            roomid = self.id, -- 房间ID
            matchid = self.mid, -- 房间级别 (1：初级场  2：中级场)
            roomtype = self:conf().roomtype
        },
        data = {
            state = self.state, -- 当前房间状态
            start = self.stateBeginTime or 0, -- 当前房间状态开始时刻
            current = global.ctms() or 0, -- 当前时刻
            leftTime = 0, -- 当前状态剩余时长(毫秒)

            roundid = self.roundid, -- 局号

            player = {}, -- 当前玩家信息
            bets = {}, -- 当前所有玩家下注信息
            logs = {}, -- 历史记录
            configchips = self:conf().chips, -- 下注筹码面值所有配置
            playerCount = Utils:getVirtualPlayerCount(self),
            currentWinTimes = self.currentWinTimes or 0, -- 当前时刻炸弹所处位置(赢的倍数)
            autoStopConfig = { 1.50, 2.0, 3.0, 5.0, 10.0, 50.0, 100.0 }
        }
        --data
    } --t

    if self.isStopping then
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入房间失败
        t.data = nil
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
            )
            Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
        end
        log.debug("userInto() uid=%s, linkid=%s  22", uid, tostring(linkid))
        return
    end

    self.users[uid] = self.users[uid] or
        { TimerID_MutexTo = timer.create(), TimerID_Timeout = timer.create() --[[TimerID_UserBet = timer.create(),]] }

    local user = self.users[uid]
    user.uid = uid -- 玩家ID
    user.state = EnumUserState.Intoing
    user.linkid = linkid
    user.ip = rev.ip or ""
    user.mobile = rev.mobile
    user.roomid = self.id
    user.matchid = self.mid
    user.playerinfo = user.playerinfo or { extra = {} }
    user.totalbet = user.totalbet or 0
    user.profit = user.profit or 0
    user.totalprofit = user.totalprofit or 0
    user.totalpureprofit = user.totalpureprofit or 0
    user.totalfee = user.totalfee or 0
    user.bets = user.bets or g.copy(DEFAULT_BET_TABLE)

    user.mutex = coroutine.create(-- 创建一个新协程。 返回这个新协程，它是一个类型为 `"thread"` 的对象。
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
            local ok = coroutine.yield() -- 挂起正在调用的协程的执行。
            if not ok then -- 如果出错
                if self.users[uid] ~= nil then -- 如果该玩家已经在用户列表中
                    timer.destroy(user.TimerID_MutexTo)
                    timer.destroy(user.TimerID_Timeout)
                    --timer.destroy(user.TimerID_UserBet)
                    self.users[uid] = nil -- 从玩家列表中移除
                    t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入房间失败
                    if linkid then
                        net.send(
                            linkid,
                            uid,
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                        )
                        Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
                    end
                end
                log.info("idx(%s,%s) player:%s has been in another room", self.id, self.mid, uid)
                return -- 出错则直接返回
            end

            log.debug("userInto() uid=%s, linkid=%s  54", uid, tostring(linkid))
            user.co = coroutine.create(-- 创建一个新协程。
                function(user) -- 函数参数由resume()中的第2个实参传递
                    Utils:queryUserInfo(--查询用户信息
                        { uid = uid, roomid = self.id, matchid = self.mid, carrybound = self:conf().carrybound }
                    )
                    local ok, ud = coroutine.yield() -- 挂起正在调用的协程的执行。等待结果
                    --print('ok', ok, 'ud', cjson.encode(ud))

                    if ud then -- 如果成功获取到玩家信息
                        -- userinfo
                        user.uid = uid
                        user.nobet_boardcnt = 0
                        user.playerinfo = {
                            uid = uid,
                            username = ud.name or "",
                            nickurl = ud.nickurl or "",
                            -- 玩家身上金额(momey或coin由房间类型决定)
                            balance = self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money")
                                and
                                ud.money or
                                ud.coin,
                            extra = {
                                ip = user.ip or "",
                                api = ud.api or ""
                            }
                        }
                        -- 携带数据
                        user.linkid = linkid
                        user.intots = user.intots or global.ctsec() -- 玩家进入时刻
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
                            self.users[uid].state = EnumUserState.Leave -- 玩家离开
                            t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
                            t.data = nil
                            if linkid then
                                net.send(
                                    linkid,
                                    uid,
                                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                                    pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                                )
                            end
                        end
                        log.info("idx(%s,%s) user %s not allowed into room", self.id, self.mid, uid)
                        return
                    end

                    log.debug("userInto() uid=%s, linkid=%s  55", uid, tostring(linkid))

                    -- 下面是玩家成功进入房间的情况
                    -- 填写返回数据   计算各状态下的剩余时长
                    if self.state == EnumRoomState.Start then
                        t.data.leftTime = TimerID.TimerID_Start[2] - (global.ctms() - self.stateBeginTime)
                    elseif self.state == EnumRoomState.Betting then
                        --t.data.leftTime = TimerID.TimerID_Betting[2] - (global.ctms() - self.stateBeginTime)
                    elseif self.state == EnumRoomState.Show then -- 开牌阶段
                        -- 在摊牌阶段剩余时长 (需要根据牌的张数确定)
                    elseif self.state == EnumRoomState.Finish then -- 结算阶段
                    end

                    t.data.leftTime = t.data.leftTime > 0 and t.data.leftTime or 0
                    t.data.player = user.playerinfo -- 玩家信息(玩家ID、昵称、金额等)

                    if self.logmgr:size() <= self:conf().maxlogshowsize then
                        t.data.logs = self.logmgr:getLogs() -- 历史记录信息(各局赢方信息)
                    else
                        g.move(--拷贝历史记录(最近各局输赢情况)
                            self.logmgr:getLogs(),
                            self.logmgr:size() - self:conf().maxlogshowsize + 1,
                            self.logmgr:size(),
                            1,
                            t.data.logs
                        )
                    end
                    log.debug("userInto() uid=%s, linkid=%s  60", uid, tostring(linkid))

                    for k, v in pairs(self.allBetInfo) do
                        if v then
                            local item = { name = v.name, uid = v.uid, bet = v.betValue, winTimes = v.winTimes }
                            table.insert(t.data.bets, item)
                        end
                    end
                    log.info(
                        "idx(%s,%s) userInto() : user=%s,linkid=%s,state=%s,balance=%s,user_count=%s t=%s",
                        self.id,
                        self.mid,
                        uid,
                        linkid,
                        self.state, -- 当前房间状态
                        user.playerinfo and user.playerinfo.balance or 0, -- 玩家身上金额
                        self.user_count, -- 玩家数目
                        cjson.encode(t)-- 进入房间消息响应包详情
                    )

                    local resp = pb.encode("network.cmd.PBCrashIntoRoomResp_S", t) -- 进入房间返回消息
                    log.info("idx(%s,%s) PBCrashIntoRoomResp_S=%s", self.id, self.mid, cjson.encode(t))
                    local to = {
                        uid = uid,
                        srvid = global.sid(),
                        roomid = self.id,
                        matchid = self.mid,
                        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashIntoRoomResp"),
                        data = resp
                    }
                    local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)
                    if linkid then
                        net.shared(
                            linkid,
                            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                            pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                            synto
                        )
                    end

                    user.state = EnumUserState.Playing
                    self.user_cached = false
                    self:recount() -- 重新计算该房间玩家数目
                end
            )
            timer.tick(
                user.TimerID_Timeout,
                TimerID.TimerID_Timeout[1],
                TimerID.TimerID_Timeout[2],
                onTimeout,
                { uid, self }
            )
            coroutine.resume(user.co, user) -- 第一次唤醒协程
        end
    )
    log.debug("userInto() uid=%s, linkid=%s  66", uid, tostring(linkid))
    timer.tick(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1], TimerID.TimerID_MutexTo[2], onMutexTo, { uid, self })
    coroutine.resume(user.mutex, user) -- 唤醒协程  开始或继续协程 `user.mutex` 的运行。
end

-- 处理玩家下注消息
function Room:userBet(uid, linkid, rev)
    local t = {
        -- 待返回的结构  PBCrashBetResp_S
        code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_Succ"),
        uid = uid, -- 当前下注玩家UID
        value = rev.value or 0 -- 下注金额
    }
    local user = self.users[uid] -- 根据玩家ID获取玩家对象
    local ok = true -- 默认下注成功
    local user_bets = g.copy(DEFAULT_BET_TABLE) -- 玩家本次在各下注区的下注情况
    local user_totalbet = rev.value or 0 -- 玩家此次总下注金额

    log.debug("userBet(),uid=%s", uid)
    -- 非法玩家
    if not user then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidUser") -- 非法用户
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
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidGameState") -- 非下注状态
        ok = false
        goto labelnotok
    end

    -- 下注总额为 0
    if user_totalbet == 0 then
        log.info("idx(%s,%s) user %s totalbet 0", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue") -- 无效的下注区或值
        ok = false
        goto labelnotok
    end

    -- 判断是否已经下注过
    if self.allBetInfo and self.allBetInfo[uid] then
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_Fail") -- 通用下注失败(一局只能下注一次)
        ok = false
        goto labelnotok
    end

    -- 余额不足
    if user_totalbet > self:getUserMoney(uid) then
        log.info(
            "idx(%s,%s) user %s, totalbet over user's balance, user_totalbet=%s, getUserMoney()=%s",
            self.id,
            self.mid,
            uid,
            user_totalbet,
            self:getUserMoney(uid)
        )
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverBalance") -- 余额不足
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    log.info(
        "idx(%s,%s) user %s userBet: %s",
        self.id,
        self.mid,
        uid,
        cjson.encode(rev or {})
    )

    if not ok then -- 如果出错
        t.uid = uid
        t.value = self:getUserMoney(t.uid) - (user and user.totalbet or 0) -- 玩家身上金额

        -- for _, v in ipairs((rev.data and rev.data.areabet) or {}) do
        --     table.insert(t.data.areabet, v)
        -- end
        local resp = pb.encode("network.cmd.PBCrashBetResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashBetResp"), -- 下注失败回应
                resp
            )
        end
        log.info("idx(%s,%s) user %s, PBCrashBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    --扣费
    user.playerinfo = user.playerinfo or {}
    if user.playerinfo.balance and user.playerinfo.balance > user_totalbet then
        user.playerinfo.balance = user.playerinfo.balance - user_totalbet
    else
        user.playerinfo.balance = 0
    end

    self.allBetInfo[uid] = { uid = uid, betValue = user_totalbet, name = user.playerinfo.username } -- 保存玩家的下注信息
    self.needNotifyBet = true
    if user.linkid and not Utils:isRobot(user.api) then -- 如果是真实玩家下注
        self.hasRealPlayerBet = true
        log.debug("hasRealPlayerBet=true,uid=%s", uid)
    end

    if not self:conf().isib and linkid then
        Utils:walletRpc(
            uid,
            user.api,
            user.ip,
            -user_totalbet,
            pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_BET"),
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

    -- 记录下注数据
    user.bets = user.bets or g.copy(DEFAULT_BET_TABLE) -- 玩家这一局在各下注区的下注情况
    user.totalbet = user.totalbet or 0 -- 玩家这一局的总下注金额(各下注区下注总和)
    user.totalbet = user.totalbet + user_totalbet -- 玩家总下注额

    user.bets[1] = user_totalbet -- 本局该玩家在该下注区的下注额
    self.bets[1] = self.bets[1] + user_totalbet -- 本局所有玩家在该下注区的下注额

    if not Utils:isRobot(user.api) then
        self.userbets[1] = self.userbets[1] + user_totalbet -- 本局非机器人在该下注区的下注金额
        self.realPlayerUID = uid
    end

    t.balance = self:getUserMoney(uid) -- 该玩家身上剩余金额

    local resp = pb.encode("network.cmd.PBCrashBetResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashBetResp"), -- 成功下注回应
            resp
        )
    end
    -- 打印玩家成功下注详细信息
    log.info("idx(%s,%s) user %s, PBCrashBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

-- 处理玩家取消下注消息
function Room:userCancelBet(uid, linkid, rev)
    local t = {
        -- 待返回的结构  PBCrashCancelBetResp_S
        code = 0,
        uid = uid, -- 当前取消下注玩家UID
        balance = 0
    }
    local user = self.users[uid] -- 根据玩家ID获取玩家对象
    local ok = true -- 默认取消下注成功
    local currentTimeMS = global.ctms() -- 当前时刻(毫秒)

    log.debug("userCancelBet(),uid=%s", uid)

    -- 非法玩家
    if not user then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        t.code = 1 -- 非法用户
        ok = false
        goto labelnotok
    end

    -- 游戏下注状态
    if self.state < EnumRoomState.Betting or self.state >= EnumRoomState.Show then -- 非下注状态
        log.info(
            "idx(%s,%s) user %s, game state %s, game state is not allow to cancel bet",
            self.id,
            self.mid,
            uid,
            self.state
        )
        t.code = 2 -- 非下注状态
        ok = false
        goto labelnotok
    end

    -- 判断是否已经下注过
    if self.allBetInfo and not self.allBetInfo[uid] then
        t.code = 3 -- 还未下注过
        ok = false
        goto labelnotok
    end


    if (currentTimeMS - self.stateBeginTime) >= (TimerID.TimerID_Betting[2] - 2000) then
        t.code = 4 -- 下注阶段最后2秒不能取消下注
        ok = false
        goto labelnotok
    end


    ::labelnotok::
    log.info(
        "idx(%s,%s) user %s userBet: %s",
        self.id,
        self.mid,
        uid,
        cjson.encode(rev or {})
    )

    if not ok then -- 如果出错
        t.uid = uid

        local resp = pb.encode("network.cmd.PBCrashCancelBetResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashCancelBetResp"), -- 下注失败回应
                resp
            )
        end
        log.info("idx(%s,%s) user %s, PBCrashCancelBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    --扣费
    user.playerinfo = user.playerinfo or {}
    if user.playerinfo.balance then
        user.playerinfo.balance = user.playerinfo.balance + (self.allBetInfo[uid].betValue or 0)
    end

    if user.linkid and not Utils:isRobot(user.api) then -- 如果是真实玩家取消下注
        self.hasRealPlayerBet = false
        log.debug("hasRealPlayerBet=false,uid=%s", uid)
    end

    if not self:conf().isib and linkid then
        Utils:walletRpc(
            uid,
            user.api,
            user.ip,
            (self.allBetInfo[uid].betValue or 0),
            pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_SETTLE"),
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

    -- 记录下注数据
    user.bets = g.copy(DEFAULT_BET_TABLE) -- 玩家这一局在各下注区的下注情况
    user.totalbet = 0 -- 玩家这一局的总下注金额(各下注区下注总和)


    if not Utils:isRobot(user.api) then
        self.userbets[1] = self.userbets[1] - (self.allBetInfo[uid].betValue or 0) -- 本局非机器人在该下注区的下注金额
        self.realPlayerUID = 0
    end

    t.balance = self:getUserMoney(uid) -- 该玩家身上剩余金额

    local resp = pb.encode("network.cmd.PBCrashCancelBetResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashCancelBetResp"), -- 成功取消下注回应
            resp
        )
    end
    self.allBetInfo[uid] = nil
    self.needNotifyBet = true

    -- 打印玩家成功下注详细信息
    log.info("idx(%s,%s) user %s, PBCrashCancelBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

function Room:userStop(uid, linkid, rev)
    local t = {
        -- 待返回的结构  PBCrashStopResp_S
        code = 0, -- 默认正常停止  0-正常
        uid = uid, -- 当前下注玩家UID
        winTimes = self.currentWinTimes, -- 赢得的倍数
        value = 0,
        balance = 0
    }
    local user = self.users[uid] -- 根据玩家ID获取玩家对象
    if user and user.totalbet and user.totalbet > 0 then
        t.value = user.totalbet
        if self.state == EnumRoomState.Show then -- 只有在show阶段才可以停止
            if self.allBetInfo[uid] and not self.allBetInfo[uid].winTimes then
                self.allBetInfo[uid].winTimes = self.currentWinTimes
                t.value = self.allBetInfo[uid].betValue -- 该玩家总下注金额
                t.balance = self:getUserMoney(uid) + math.floor(t.value * t.winTimes + 0.5)
                local resp = pb.encode("network.cmd.PBCrashStopResp_S", t)
                if linkid then
                    net.send(
                        linkid,
                        uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashStopResp"), -- 成功停止回应
                        resp
                    )
                end

                self.needNotifyBet = true

                log.debug("userStop(),uid=%s,PBCrashStopResp_S=%s", uid, cjson.encode(t))
                -- 如果所有真实玩家都stop了，则延迟爆炸
                if user.linkid and not Utils:isRobot(user.api) then -- 如果当前玩家是真实玩家
                    -- -- 更新玩家身上金额
                    -- if not self:conf().isib and linkid then
                    --     Utils:walletRpc(
                    --         uid,
                    --         user.api,
                    --         user.ip,
                    --         (self.allBetInfo[uid].betValue * self.allBetInfo[uid].winTimes),
                    --         pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_SETTLE"),
                    --         linkid,
                    --         self:conf().roomtype,
                    --         self.id,
                    --         self.mid,
                    --         {
                    --             api = "debit",
                    --             sid = user.sid,
                    --             userId = user.userId,
                    --             transactionId = g.uuid(),
                    --             roundId = user.roundId,
                    --             gameId = tostring(global.stype())
                    --         }
                    --     )
                    -- end

                    -- 判断是否是最后一个真实玩家停止
                    local isAllRealPlayerStop = true
                    for k, v in pairs(self.allBetInfo) do
                        if v and (not v.winTimes) and self.users[k] and self.users[k].linkid then
                            isAllRealPlayerStop = false
                            break
                        end
                    end
                    if isAllRealPlayerStop then
                        self.lastWinTimes = self.lastWinTimes + 1.0
                        local randValue = rand.rand_between(1, 10000)
                        if randValue < 7000 then
                        elseif randValue < 8000 then
                            self.lastWinTimes = self.lastWinTimes + rand.rand_between(100, 500) / 100.0
                        elseif randValue < 9000 then
                            self.lastWinTimes = self.lastWinTimes + rand.rand_between(500, 1000) / 100.0
                        elseif randValue < 9800 then
                            self.lastWinTimes = self.lastWinTimes + rand.rand_between(1000, 2000) / 100.0
                        else
                            self.lastWinTimes = self.lastWinTimes + rand.rand_between(2000, 5000) / 100.0
                        end
                    end
                end
            end
        else
            t.code = 1
        end
    else
        t.code = 2
    end
end

-- 请求获取历史记录
function Room:userHistory(uid, linkid, rev)
    if not linkid then
        return
    end
    -- PBCrashHistoryResp_S
    local t = {
        results = {} -- 最近n局的结果
    }
    local ok = true
    local user = self.users[uid] -- 根据玩家ID获取玩家对象

    -- 非法玩家
    if user == nil then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        ok = false
        return
    end

    if self.logmgr:size() <= self:conf().maxlogshowsize then
        t.results = self.logmgr:getLogs()
    else
        g.move(
            self.logmgr:getLogs(),
            self.logmgr:size() - self:conf().maxlogshowsize + 1, --开始位置
            self.logmgr:size(),
            1,
            t.results
        )
    end

    local resp = pb.encode("network.cmd.PBCrashHistoryResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashHistoryResp"), -- 历史记录回应
            resp
        )
    end
    log.info(
        "idx(%s,%s) user %s, PBCrashHistoryResp_S: %s, logmgr:size: %s",
        self.id,
        self.mid,
        uid,
        cjson.encode(t),
        self.logmgr:size()
    )
end

-- 在线列表请求 (请求获取最近20局玩家的输赢下注情况)
function Room:userOnlineList(uid, linkid, rev)
    if not linkid then
        return
    end

    --[[
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
        local resp = pb.encode("network.cmd.PBPveOnlineListResp_S", t)
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PveOnlineListResp"),
                resp
            )
        end
        log.info("idx(%s,%s) user %s, PBPveOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    -- 返回前 300 条
    g.move(self.onlinelst, 1, math.min(300, #self.onlinelst), 1, t.list)
    -- 返回前 300 条
    local resp = pb.encode("network.cmd.PBPveOnlineListResp_S", t)
    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PveOnlineListResp"),
            resp
        )
    end
    log.info("idx(%s,%s) user %s, PBPveOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
    --]]
end

-- 检测定时器回调函数
local function onCheck(self)
    local function doRun()
        if self.stateOnce then -- 如果已经执行过
            return -- 直接返回，避免多次执行
        end
        self.stateOnce = true

        if self.isStopping then
            Utils:onStopServer(self)
            return
        end

        self:start() -- 调用开始函数
    end

    g.call(doRun)
end

-- 结算结束  结算定时器回调函数
local function onFinish(self)
    local function doRun()
        if self.stateOnce then -- 如果已经执行过
            return -- 直接返回，避免多次执行
        end
        self.stateOnce = true

        -- 清算在线列表
        self.onlinelst = {}
        local bigwinneridx = 1 --神算子(赢的次数最多的玩家)索引值
        for k, v in pairs(self.users) do
            local totalbet = 0 -- 总下注额
            local wincnt = 0 -- 赢的次数
            for _, l in ipairs(v.logmgr and v.logmgr:getLogs() or {}) do
                totalbet = totalbet + l.bet -- 该玩家最近20局的总下注额
                wincnt = wincnt + ((l.profit > 0) and 1 or 0) -- 该玩家最近20局赢的总次数
            end
            if totalbet > 0 then -- 如果该玩家在最近20局下注过
                table.insert(
                    self.onlinelst, -- 插入在线列表
                    {
                        player = {
                            -- 玩家信息
                            uid = k, --玩家ID
                            username = v.playerinfo and v.playerinfo.username or "", --玩家昵称
                            nickurl = v.playerinfo and v.playerinfo.nickurl or "",
                            balance = self:getUserMoney(k) -- 玩家身上金额
                        },
                        totalbet = totalbet, --总下注额
                        wincnt = wincnt -- 赢得次数
                    }
                )
                if wincnt > self.onlinelst[bigwinneridx].wincnt then
                    bigwinneridx = #self.onlinelst -- 更新神算子索引
                end
            end
        end -- ~for
        local bigwinner = g.copy(self.onlinelst[bigwinneridx])
        table.remove(self.onlinelst, bigwinneridx)
        table.sort(
            self.onlinelst, -- 根据总下注额排序
            function(a, b)
                return a.totalbet > b.totalbet
            end
        )
        table.insert(self.onlinelst, 1, bigwinner) -- 将大赢家插入到第一个位置


        -- 清除玩家
        for k, v in pairs(self.users) do
            if not v.totalbet or v.totalbet == 0 then -- 如果该玩家这一局未下注
                v.nobet_boardcnt = (v.nobet_boardcnt or 0) + 1 -- 累加未下注的局数
            end
            local is_need_destry = false
            if v.state == EnumUserState.Leave then
                is_need_destry = true
            end
            if v.state == EnumUserState.Logout and (v.nobet_boardcnt or 0) >= 1 then
                is_need_destry = true
            end
            if is_need_destry then
                if v.TimerID_Timeout then
                    timer.destroy(v.TimerID_Timeout) -- 销毁定时器
                end
                if v.TimerID_MutexTo then
                    timer.destroy(v.TimerID_MutexTo)
                end
                if v.state == EnumUserState.Logout then
                    mutex.request(
                        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
                        pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
                        pb.encode("network.cmd.PBMutexRemove", { uid = k, srvid = global.sid(), roomid = self.id })
                    )
                end
                log.info("idx(%s,%s) kick user:%s state:%s", self.id, self.mid, k, tostring(v.state))
                self.users[k] = nil
                self.user_cached = false --玩家缓存无效
                self:recount() -- 重新计算玩家数目
            end
        end

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
            rm:destroyRoom(self.id) -- 销毁当前房间
        else
            self:check()
        end
    end

    g.call(doRun)
end

-- 定时检测创建机器人
local function onCreateRobot(self)
    local function doRun()
        local current_time = global.ctsec() -- 当前时刻(秒)
        local currentTimeMS = global.ctms() -- 当前时刻(毫秒)

        if current_time - self.lastNeedRobotTime > 600 then
            self.lastNeedRobotTime = current_time
            if self:conf().global_profit_switch then
                self.needRobotNum = rand.rand_between(3, 30)
            else
                --self.needRobotNum = 30
                self.needRobotNum = rand.rand_between(2, 30)
            end
        end
        Utils:checkCreateRobot(self, current_time, self.needRobotNum) -- 检测创建机器人

        if self.state == EnumRoomState.Check then -- 检测状态
            onCheck(self)
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
                    if user and not user.linkid then -- 如果是机器人
                        if user.playerinfo and user.playerinfo.balance <= self.minChips then
                            self.users[uid] = nil
                        elseif user.createtime and user.lifetime and current_time - user.createtime >= user.lifetime then
                            self.users[uid] = nil
                        end
                    end
                end
            end

            if currentTimeMS - self.stateBeginTime >= TimerID.TimerID_Start[2] then -- 如果超出下注阶段时长
                self:betting() -- 开始下注
            end
        elseif self.state == EnumRoomState.Betting then -- 如果是下注状态
            if (TimerID.TimerID_Betting[2] - 100 > currentTimeMS - self.stateBeginTime) and
                (currentTimeMS - self.stateBeginTime >= 1100)
            then
                Utils:robotBet(self) -- 机器人下注

                self:robotCancelBet() -- 机器人取消下注
            end

            if currentTimeMS - self.stateBeginTime > TimerID.TimerID_Betting[2] then --
                self:changeState(EnumRoomState.WaitResult)
                self:calcResult()
            end
            self:sendAllBetInfo()
        elseif self.state == EnumRoomState.WaitResult then --
            if self.hasGetResult then
                self:show() -- 开牌(发牌)   进入show牌阶段
                self.currentWinTimes = 1.0
            end
        elseif self.state == EnumRoomState.Show then -- 如果是Show牌状态
            -- 在该阶段，随时检测更新当前赢倍数; 等待所有下注玩家点击crash
            local t = (currentTimeMS - self.stateBeginTime) / 1000.0
            self.currentWinTimes = (1.06 ^ t) + 0.005 --math.pow(1.06, t)
            self.currentWinTimes = self.currentWinTimes - self.currentWinTimes % 0.01

            -- 1.06的t次方
            --机器人随机点击crash
            if self.currentWinTimes >= self.lastWinTimes then
                self.currentWinTimes = self.lastWinTimes
                self:finish() -- 结算
            else
                if self.oldWinTimes ~= self.currentWinTimes then
                    self.oldWinTimes = self.currentWinTimes
                    -- 广播消息 PBCrashStateNotify
                    pb.encode(
                        "network.cmd.PBCrashStateNotify",
                        { winTimes = self.currentWinTimes },
                        function(pointer, length)
                            self:sendCmdToPlayingUsers(
                                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashStateNotify"),
                                pointer,
                                length
                            )

                        end
                    )
                end

                self:robotStop()
            end
            self:sendAllBetInfo()
        elseif self.state == EnumRoomState.Finish then -- 如果是结算状态
            if currentTimeMS - self.stateBeginTime > TimerID.TimerID_Finish[2] then
                onFinish(self)
            end
        else -- 未知状态
            log.debug("[error] unknown state,state=%s", self.state)
        end
    end

    g.call(doRun)
end

-- 检测
function Room:check()
    log.info("idx(%s,%s) check game state - %s %s", self.id, self.mid, self.state, tostring(global.stopping()))
    if global.stopping() then -- 判断游戏是否停止
        return
    end

    self:changeState(EnumRoomState.Check) -- 房间进入检测状态

    if not self.hasCreateTimer then
        self.hasCreateTimer = true

        timer.tick(self.timer, TimerID.TimerID_Robot[1], TimerID.TimerID_Robot[2], onCreateRobot, self)
    end
end

-- 开始游戏
function Room:start()
    self:roundReset() --
    self.roundid = (self.id << 16) | global.ctsec() -- 生成唯一局号
    self:changeState(EnumRoomState.Start) -- 进入开始阶段

    self.start_time = global.ctms() -- 该阶段开始时刻(毫秒)

    self.logid = self.statistic:genLogId(self.start_time / 1000) -- 日志ID

    local t = {
        leftTime = TimerID.TimerID_Start[2], -- 该阶段剩余时长
        roundid = self.roundid, -- 轮次
        playerCount = Utils:getVirtualPlayerCount(self)
    }

    -- 通知玩家游戏开始了
    pb.encode(
        "network.cmd.PBPveNotifyStart_N", -- 通知游戏开始
        t,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PveNotifyStart"),
                pointer,
                length
            )
        end
    )

    log.info(
        "idx(%s,%s) start room game, state %s roundid %s logid %s",
        self.id, -- 房间ID
        self.mid, -- 房间级别ID
        self.state, --房间状态
        tostring(self.roundid), --轮次ID
        tostring(self.logid)-- 日志ID
    )
end

-- 开始下注
function Room:betting()
    log.info("idx(%s,%s) betting state-%s", self.id, self.mid, self.state)

    self:changeState(EnumRoomState.Betting) -- 进入下注阶段
end

-- 开牌阶段
function Room:show()
    log.info("idx(%s,%s) show room game, state - %s", self.id, self.mid, self.state)

    if self:conf().isib then -- 如果是Indibet版本
        Utils:debit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_BET"))
        Utils:balance(self, EnumUserState.Playing)
        for uid, user in pairs(self.users) do
            if user and Utils:isRobot(user.api) then
                user.isdebiting = false
            end
        end
    end

    self:changeState(EnumRoomState.Show) -- 进入开牌阶段
end

-- 结算 Room:finish
function Room:finish()
    log.info("idx(%s,%s) finish room game, state - %s", self.id, self.mid, self.state)
    self:changeState(EnumRoomState.Finish) -- 进入结算阶段
    self.logmgr:push(self.lastWinTimes)
    self.finish_time = global.ctms() -- 结算开始时刻(毫秒)

    -- PBCrashHistoryResp_S
    local t = {
        results = {} -- 最近n局的结果
    }
    if self.logmgr:size() <= self:conf().maxlogshowsize then
        t.results = self.logmgr:getLogs()
    else
        g.move(
            self.logmgr:getLogs(),
            self.logmgr:size() - self:conf().maxlogshowsize + 1, --开始位置
            self.logmgr:size(),
            1,
            t.results
        )
    end
    pb.encode(
        "network.cmd.PBCrashHistoryResp_S", --
        t,
        function(pointer, length)
            self:sendCmdToPlayingUsers(-- 通知所有玩家
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashHistoryResp"),
                pointer,
                length
            )
        end
    )
    --local lastlogitem = self.logmgr:back() -- 最近一个历史记录(也就是这一局的结果：哪一方赢)

    local totalbet, usertotalbet = 0, 0 -- 该局所有玩家总押注，该局所有真实玩家总押注
    local totalprofit, usertotalprofit = 0, 0 -- 该局所有玩家收益和，该局所有真实玩家收益和
    local totalfee = 0 -- 服务费

    --self.hasRealPlayerBet = false
    self.sdata.users = self.sdata.users or {}
    for k, v in pairs(self.users) do -- 遍历该房间所有玩家
        -- 计算下注的玩家  k为玩家ID, v为user
        -- if (v.totalbet and v.totalbet > 0) or self.bankmgr:banker() == k then
        if not v.isdebiting and v.totalbet and v.totalbet > 0 then
            -- if not Utils:isRobot(v.api) then
            --     self.hasRealPlayerBet = true
            -- end
            -- 牌局统计
            self.sdata.users = self.sdata.users or {} -- 玩家列表
            self.sdata.users[k] = self.sdata.users[k] or {} -- 该玩家信息
            self.sdata.users[k].areas = self.sdata.users[k].areas or {} -- 下注信息
            self.sdata.users[k].stime = self.start_time / 1000 -- 开始时刻(秒)
            self.sdata.users[k].etime = self.finish_time / 1000 -- 结束时刻(秒)
            --self.sdata.users[k].sid = v.seat and v.seat:getSid() or 0 -- 座位号
            --self.sdata.users[k].tid = v.vtable and v.vtable:getTid() or 0 -- 虚拟桌号
            self.sdata.users[k].money = self.sdata.users[k].money or (self:getUserMoney(k) or 0) -- 余额
            self.sdata.users[k].nickname = v.playerinfo and v.playerinfo.nickname -- 昵称
            self.sdata.users[k].username = v.playerinfo and v.playerinfo.username -- 用户名
            self.sdata.users[k].nickurl = v.playerinfo and v.playerinfo.nickurl
            self.sdata.users[k].currency = v.playerinfo and v.playerinfo.currency

            -- 结算
            v.totalprofit = 0 -- 该玩家本局总收益(未扣除下注额，只扣除了服务费)
            v.totalpureprofit = 0 -- 该玩家本局纯收益(扣除了下注额，也扣除了服务费)
            v.totalfee = 0 -- 该局总服务费用
            totalbet = totalbet + v.totalbet -- 该局所有玩家总押注额

            --[[
            -- 计算闲家盈利
            for _, bettype in ipairs(DEFAULT_BET_TYPE) do -- 遍历所有下注区
                local profit = 0 -- 玩家在当前下注区赢利(未扣除下注额)
                local pureprofit = 0 -- 玩家在当前下注区纯利(扣除了下注额)
                local bets = v.bets[bettype] -- 玩家在当前下注区总下注值
                local fee = 0

                if bets > 0 then -- 如果该玩家在该下注区下注了
                    -- 计算赢利
                    if g.isInTable(lastlogitem.wintype, bettype) then -- 押中 判断当前区域是否赢
                        profit = bets * (self:conf() and self:conf().betarea and self:conf().betarea[bettype][1]) -- 赢利(未扣除下注额)
                        --扣除服务费 盈利下注区的5%
                        --fee = math.floor((profit - bets) * (self:conf() and (self:conf().fee or 0) or 0))
                        v.totalfee = v.totalfee + fee -- 累计服务费
                        profit = profit - fee
                    end
                    pureprofit = profit - bets -- 在该下注区的纯收益=本次返回-该下注区的下注额

                    v.totalprofit = v.totalprofit + profit -- 该玩家本局总收益(未扣除下注额)
                    v.totalpureprofit = v.totalpureprofit + pureprofit -- 该玩家本局总纯收益(扣除了下注额)

                    self.profits[bettype] = self.profits[bettype] or 0
                    self.profits[bettype] = self.profits[bettype] + profit -- 这一局该下注区的总收益(未扣除下注额)

                    -- 牌局统计
                    table.insert(
                        self.sdata.users[k].areas,
                        {
                            bettype = bettype, -- 下注区
                            betvalue = bets, -- 该玩家在该下注区的下注总金额
                            profit = profit, -- 在该下注区的收益(未扣除下注额，只扣除服务费)
                            pureprofit = pureprofit, --该玩家本局在该下注区的纯收益
                            fee = fee -- 该玩家本局在该下注区的服务费
                        }
                    )
                end -- end of if bets > 0 then
            end -- end of for _, bettype in ipairs(DEFAULT_BET_TYPE) do
            --]]

            if self.allBetInfo[k] and self.allBetInfo[k].winTimes then
                v.totalprofit = self.allBetInfo[k].betValue * self.allBetInfo[k].winTimes
                v.totalpureprofit = v.totalprofit - self.allBetInfo[k].betValue
            end

            --盈利扣水
            if v.totalpureprofit > 0 and (self:conf().rebate or 0) > 0 then
                local rebate = math.floor(v.totalpureprofit * self:conf().rebate)
                v.totalprofit = v.totalprofit - rebate
                v.totalpureprofit = v.totalpureprofit - rebate
            end

            v.playerinfo = v.playerinfo or {}
            v.playerinfo.balance = v.playerinfo.balance or 0
            v.playerinfo.balance = v.playerinfo.balance + v.totalprofit

            if 0 >= v.totalpureprofit or (self.allBetInfo[k] and self.allBetInfo[k].winTimes >= 2.0) then
                v.playchips = self.allBetInfo[k].betValue or 0
            else
                v.playchips = 0
            end
            self.sdata.users[k].extrainfo = cjson.encode(
                {
                    ip = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.ip,
                    api = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.api,
                    roomtype = self:conf().roomtype, -- 房间类型(金币/豆子)
                    -- bankeruid = self.bankmgr:banker()
                    bankeruid = 0,
                    money = self:getUserMoney(k) or 0,
                    maxwin = v.maxwin or 0,
                    playchips = v.playchips or 0 -- 2021-12-24  打码量
                }
            )

            log.info(
                "idx(%s,%s) player uid=%s, rofit settlement profit %s, totalbets=%s, totalpureprofit=%s",
                self.id,
                self.mid,
                k, -- 玩家id
                tostring(v.totalprofit), -- 该玩家本局总收益(未扣除下注额)
                tostring(v.totalbet), -- 该玩家本局总下注额
                tostring(v.totalpureprofit)-- 该玩家本局总纯收益(扣除下注额)
            )

            totalprofit = totalprofit + v.totalprofit -- 该局所有玩家的收益和
            totalfee = totalfee + v.totalfee -- 该局所有玩家的费用和

            -- 牌局统计
            self.sdata.users = self.sdata.users or {}
            self.sdata.users[k] = self.sdata.users[k] or {}
            self.sdata.users[k].totalbet = v.totalbet -- 该玩家各局总下注和
            self.sdata.users[k].totalprofit = v.totalprofit -- 该玩家各局总收益和
            self.sdata.users[k].totalpureprofit = v.totalpureprofit -- 该玩家各局纯收益总和
            self.sdata.users[k].totalfee = v.totalfee -- 该玩家各局服务费总和

            if not Utils:isRobot(v.api) then -- 如果该玩家不是机器人
                usertotalprofit = usertotalprofit + v.totalprofit -- 本局真实玩家总收益和
                usertotalbet = usertotalbet + v.totalbet -- 本局真实玩家总下注额
                self.sdata.users[k].ugameinfo = { texas = { inctotalhands = 1 } }
            end

            -- 保存该玩家最近 20 局的记录(每局的总下注和总收益)
            v.logmgr = v.logmgr or LogMgr:new(20)
            v.logmgr:push({ bet = v.totalbet or 0, profit = v.totalprofit or 0 }) --存放该玩家本局记录{总下注，各赢的区域总收益}
        end -- end of [if (v.totalbet and v.totalbet > 0) or self.bankmgr:banker == k then]
    end -- end of [for k,v in pairs(self.users) do]


    if self:conf().global_profit_switch then -- 如果是全局控制模式
        local curday = global.cdsec()
        self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet
        self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit
    end


    Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_SETTLE")) -- 增加金额



    for k, v in pairs(self.users) do -- 遍历所有玩家
        local rank = {}
        --if (v.totalbet and v.totalbet > 0) or self.bankmgr:banker() == k then
        if not v.isdebiting and v.totalbet and v.totalbet > 0 then -- 如果该玩家下注了
            rank = {
                uid = k, -- 玩家ID
                --rank		= 0,
                player = v.seat and v.seat:getSeatInfo().playerinfo,
                totalprofit = v.totalprofit, -- 该玩家总收益
                areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
            }
        end
    end

    -- 牌局统计数据上报
    self.sdata.areas = {}
    for _, bettype in ipairs(DEFAULT_BET_TYPE) do
        table.insert(
            self.sdata.areas,
            {
                bettype = bettype, -- 下注区域
                betvalue = self.bets[bettype], -- 该下注区总下注额
                profit = self.profits[bettype] -- 该下注区总收益
            }
        )
    end

    self.sdata.stime = self.start_time / 1000 -- 开始时刻(秒)
    self.sdata.etime = self.finish_time / 1000 -- 结束时刻(秒)
    self.sdata.totalbet = totalbet -- 该局总下注额
    self.sdata.totalprofit = totalprofit -- 该局总收益

    --  self.sdata.extrainfo =
    --      cjson.encode({bankeruid = self.bankmgr:banker(), bankerprofit = banker_profit, totalfee = totalfee})
    self.sdata.extrainfo = cjson.encode(
        {
            bankeruid = 0,
            bankerprofit = 0,
            totalfee = 0,
            playercount = self:getRealPlayerCount(),
            playerbet = usertotalbet,
            playerprofit = usertotalprofit
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
                        if self.allBetInfo[k] and self.allBetInfo[k].winTimes then
                            extrainfo["wintimes"] = tostring(self.allBetInfo[k].winTimes)
                        else
                            extrainfo["wintimes"] = tostring(0) -- 玩家停止时倍数
                        end
                        extrainfo["crashwintimes"] = tostring(self.lastWinTimes) -- 最终爆炸点倍数
                        self.sdata.users[user.uid].extrainfo = cjson.encode(extrainfo)
                    end
                end
            end
        end
        log.debug("idx(%s,%s) appendLogs(),self.sdata=%s", self.id, self.mid, cjson.encode(self.sdata))
        self.statistic:appendLogs(self.sdata, self.logid)
    end
    --local curday = global.cdsec() -- 获取当天标识值
    --self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet -- 当天真实玩家总下注额
    --self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit -- 当天真实玩家总收益
    Utils:serializeMiniGame(self)

end

-- 踢出玩家
function Room:kickout()
    if self.state ~= EnumRoomState.Finish then
        Utils:repay(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_SETTLE"))
    end
    for k, v in pairs(self.users) do -- 遍历该房间所有玩家
        if self.state ~= EnumRoomState.Finish and v.totalbet and v.totalbet > 0 then -- 如果不在结算阶段且下注了
            v.totalbet = 0
        end
        self:userLeave(k, v.linkid) -- 玩家离开
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

-- 获取系统盈利比例
function Room:getTotalProfitRate()
    local totalbets, totalprofit = 0, 0 -- 总下注额,总收益
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
        totalbets = totalbets + v -- 累计玩家总下注额
        sn = sn + 1
    end

    self.total_bets[sn] = nil -- 将最前那个移除掉  防止超过 profitrate_threshold_maxdays 天
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
        totalprofit = totalprofit + v -- 累计玩家总盈利
        sn = sn + 1
    end
    self.total_profit[sn] = nil

    totalbets = totalbets + (self.userbets[1] or 0) -- 玩家总下注

    -- local peilv = 0 -- 赔率
    -- if totalbets > 100000 and self.userbets[1] > 0 then
    --     -- 赔率 = 1 - (最近3天总盈利/(最近3天总投注 + 本局总投注))/本局总投注
    --     peilv = 1.0 + (totalprofit * 1.0 / totalbets) / self.userbets[1]
    -- end

    local profit_rate = totalbets > 0 and 1 - totalprofit / totalbets or 0 -- 系统总盈利比例

    log.info(
        "idx(%s,%s) total_bets=%s total_profit=%s totalbets=%s,totalprofit=%s,profit_rate=%s",
        self.id,
        self.mid,
        cjson.encode(self.total_bets),
        cjson.encode(self.total_profit),
        totalbets,
        totalprofit,
        profit_rate
    )
    return profit_rate
    --return totalbets, peilv -- 返回总下注及赔率

end

function Room:phpMoneyUpdate(uid, rev)
    log.info("(%s,%s)phpMoneyUpdate %s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user and user.playerinfo then
        local balance =
        self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and rev.money or rev.coin

        user.playerinfo.balance = user.playerinfo.balance + balance -- 更新玩家身上金额
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
        if v.code > 0 then
            if user then
                user.isdebiting = false
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
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_CRASH_SETTLE"),
                v,
                user,
                EnumRoomState.Show
            )
        end
    end
end

-- 获取真实玩家数目
function Room:getRealPlayerCount()
    local realPlayerCount = 0
    for _, user in pairs(self.users) do
        --if user and user.state == EnumUserState.Playing then
        if user then
            if not Utils:isRobot(user.api) then
                if not user.isdebiting and user.totalbet and user.totalbet > 0 then -- 如果该玩家下注了
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
        -- 对应 PBCrashIntoRoomResp_S 消息
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(), -- 游戏ID  52-Crash
        idx = {
            srvid = global.sid(), -- 服务器ID ?
            roomid = self.id, -- 房间ID
            matchid = self.mid -- 房间级别 (1：初级场  2：中级场)
        },
        data = {
            state = self.state, -- 当前房间状态
            start = self.stateBeginTime or 0, -- 当前房间状态开始时刻
            current = global.ctms() or 0, -- 当前时刻
            leftTime = 0, -- 当前状态剩余时长(毫秒)

            roundid = self.roundid, -- 局号

            player = {}, -- 当前玩家信息
            bets = {}, -- 当前所有玩家下注信息
            logs = {}, -- 历史记录
            configchips = self:conf().chips, -- 下注筹码面值所有配置
            playerCount = Utils:getVirtualPlayerCount(self),
            currentWinTimes = self.currentWinTimes or 0, -- 当前时刻炸弹所处位置(赢的倍数)
            autoStopConfig = { 1.50, 2.0, 3.0, 5.0, 10.0, 50.0, 100.0 }
        }
        --data
    } --t

    -- 填写返回数据   计算各状态下的剩余时长
    if self.state == EnumRoomState.Start then
        t.data.leftTime = TimerID.TimerID_Start[2] - (global.ctms() - self.stateBeginTime)
    elseif self.state == EnumRoomState.Betting then
        t.data.leftTime = TimerID.TimerID_Betting[2] - (global.ctms() - self.stateBeginTime)
    elseif self.state == EnumRoomState.Show then -- 开牌阶段
        t.data.leftTime = TimerID.TimerID_Show[2] - (global.ctms() - self.stateBeginTime)
    elseif self.state == EnumRoomState.Finish then -- 结算阶段
        t.data.leftTime = TimerID.TimerID_Finish[2] - (global.ctms() - self.finish_time) -- 该状态剩余时长
    end

    t.data.leftTime = t.data.leftTime > 0 and t.data.leftTime or 0

    local user = self.users[uid]
    if user then
        --t.data.player = user.playerinfo -- 玩家信息(玩家ID、昵称、金额等)
        user.playerinfo = user.playerinfo or {}
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

        if self.logmgr:size() <= self:conf().maxlogshowsize then
            t.data.logs = self.logmgr:getLogs() -- 历史记录信息(各局赢方信息)
        else
            g.move(--拷贝历史记录(最近各局输赢情况)
                self.logmgr:getLogs(),
                self.logmgr:size() - self:conf().maxlogshowsize + 1,
                self.logmgr:size(),
                1,
                t.data.logs
            )
        end
    end

    for k, v in pairs(self.allBetInfo) do
        if v then
            local item = { name = v.name, uid = v.uid, bet = v.betValue, winTimes = v.winTimes }
            table.insert(t.data.bets, item)
        end
    end

    if linkid then
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashIntoRoomResp"),
            pb.encode("network.cmd.PBCrashIntoRoomResp_S", t)
        )

        log.debug("userTableInfo(),uid=%s, t=%s", uid, cjson.encode(t))
    end
end

function Room:queryUserResult(ok, ud)
    if self.timer and self:conf().single_profit_switch then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.info("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

-- 2022-10-26
function Room:queryProfitInfoRet(ok, data)
    self.rebateadd = data.rebateadd or 0 -- 放水标记
    self.rebatesub = data.rebatesub or 0 -- 扣水标记
    log.debug("queryProfitInfoRet(),uid=%s,data=%s", data.uid, cjson.encode(data))
end

-- 获取真实玩家赢取到的金额
-- 参数 winTimes: 最大赢的倍数
-- 返回值: 返回真实玩家该局总盈利额
function Room:GetRealPlayerWin(winTimes)
    local realPlayerWin = 0
    local userTotalBet = 0 -- 真实玩家下注总金额

    realPlayerWin = realPlayerWin - userTotalBet
    return realPlayerWin
end

function Room:destroy()
    self:kickout()
    -- 销毁定时器
    timer.destroy(self.timer)
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

-- 更新房间状态
function Room:changeState(newState)
    -- 检测是否可以更新到指定的房间状态
    if newState < EnumRoomState.Check or newState > EnumRoomState.WaitResult then
        return
    end
    log.info("idx(%s,%s,%s) old state = %s, new state = %s", self.id, self.mid, tostring(self.logid), self.state,
        newState)
    self.state = newState
    self.stateBeginTime = global.ctms() -- 当前状态开始时刻(毫秒)
    self.stateOnce = false -- 是否已经执行了一次

    local t = { state = newState, start = self.stateBeginTime, current = self.stateBeginTime }
    if newState == EnumRoomState.Betting then -- 如果是下注状态
        t.leftTime = TimerID.TimerID_Betting[2]
    elseif newState == EnumRoomState.Finish then
        t.currentWinTimes = self.lastWinTimes
    end
    if newState ~= EnumRoomState.WaitResult then
        -- 通知玩家可以下注了
        pb.encode(
            "network.cmd.PBCrashRoomStateResp_S", -- 开始下注倒计时
            t,
            function(pointer, length)
                self:sendCmdToPlayingUsers(-- 通知玩家可以下注
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashRoomStateResp"),
                    pointer,
                    length
                )
            end
        )
    end
end

-- 发送房间下注、停止状态通知
function Room:sendAllBetInfo()
    -- PBCrashAllBetInfoResp_S
    if self.needNotifyBet then
        self.needNotifyBet = false
        local t = { bets = {} }

        for k, v in pairs(self.allBetInfo) do
            if v and v.uid then
                table.insert(t.bets, { uid = v.uid, bet = v.betValue, winTimes = v.winTimes, name = v.name })
            end
        end

        pb.encode(
            "network.cmd.PBCrashAllBetInfoResp_S",
            t,
            function(pointer, length)
                self:sendCmdToPlayingUsers(-- 通知玩家可以下注
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashAllBetInfoResp"),
                    pointer,
                    length
                )
            end
        )
    end
end

-- 机器人停止
function Room:robotStop()
    for k, v in pairs(self.allBetInfo) do
        if v and not v.winTimes then -- 如果还未停止
            if v.uid and self.users[v.uid] and not self.users[v.uid].linkid then -- 如果该玩家是机器人
                if rand.rand_between(1, 2000) <= 5 then
                    v.winTimes = self.currentWinTimes
                    self.needNotifyBet = true
                end
            end
        end
    end
end

-- 机器人取消下注
function Room:robotCancelBet()
    if rand.rand_between(1, 10000) <= 1000 then
        for k, v in pairs(self.allBetInfo) do
            if v and not v.winTimes then -- 如果还未停止
                if v.uid and self.users[v.uid] and not self.users[v.uid].linkid then -- 如果该玩家是机器人
                    if rand.rand_between(1, 10000) <= 100 then
                        -- 取消下注
                        self.users[v.uid].totalbet = 0
                        v.betValue = 0
                        self.allBetInfo[v.uid] = nil
                        self.needNotifyBet = true
                        break
                    end
                end
            end
        end
    end
end

-- 根据控制信息计算结果(爆炸点位置)
function Room:calcResult()
    if self.hasGetResult then
        return
    end
    self.lastWinTimes = 1.0 -- 最后爆炸点位置

    if self.hasRealPlayerBet then -- 如果有真实玩家下注了
        log.debug("calcResult() self.hasRealPlayerBet")
        if self:conf().global_profit_switch then -- 如果是全局控制模式
            log.debug("calcResult() global_profit_switch=true")
            local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {}, gameid = global.stype() }
            for k, v in pairs(self.users) do
                if not Utils:isRobot(v.api) and self.allBetInfo[k] then
                    table.insert(msg.data,
                        { uid = k, chips = v.playchips or 0, betchips = self.allBetInfo[k].betValue or 0 })
                end
            end
            if #msg.data > 0 then
                Utils:queryProfitResult(msg)
            end

            local profit_rate = self:getTotalProfitRate() -- 系统盈利率

            if profit_rate < self:conf().profitrate_threshold_lowerlimit then -- 系统总盈利比例 < 盈利比例限制

                local rnd = rand.rand_between(1, 10000)
                if profit_rate < self:conf().profitrate_threshold_minilimit then
                    if rnd < 8000 then -- 80%  1.0
                        self.lastWinTimes = 1.0
                        self.hasGetResult = true
                    else

                    end
                else
                    -- 50% 1.00
                    if rnd < 5000 then
                        self.lastWinTimes = 1.0
                        self.hasGetResult = true
                    end
                end
            end
            if not self.hasGetResult then
                -- 正常概率
                local randV = rand.rand_between(1, 10000)
                if randV < 800 then
                    self.lastWinTimes = 1.0
                else
                    randV = rand.rand_between(1, 10000)
                    if randV < 2000 then
                        self.lastWinTimes = rand.rand_between(100, 125) / 100.0
                    elseif randV < 3000 then
                        self.lastWinTimes = rand.rand_between(125, 150) / 100.0
                    elseif randV < 5000 then
                        self.lastWinTimes = rand.rand_between(150, 200) / 100.0
                    elseif randV < 8000 then
                        self.lastWinTimes = rand.rand_between(200, 300) / 100.0
                    elseif randV < 9400 then
                        self.lastWinTimes = rand.rand_between(300, 500) / 100.0
                    elseif randV < 9900 then
                        self.lastWinTimes = rand.rand_between(500, 1000) / 100.0
                    else
                        self.lastWinTimes = rand.rand_between(1000, 5000) / 100.0
                    end
                end
                self.hasGetResult = true
            end
        elseif self:conf().single_profit_switch then -- 单人控制模式
            log.debug("calcResult() single_profit_switch=true")
            self.result_co = coroutine.create(
                function()
                    local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {}, gameid = global.stype() }
                    for k, v in pairs(self.users) do
                        if self.allBetInfo[k] and not Utils:isRobot(v.api) then
                            table.insert(msg.data, { uid = k, chips = v.playchips or 0, betchips = v.totalbet or 0 })
                        end
                    end
                    log.info("idx(%s,%s) start result request %s", self.id, self.mid, cjson.encode(msg))
                    Utils:queryProfitResult(msg)
                    --Utils:queryProfitInfo(msg)
                    local ok, res = coroutine.yield() -- 等待查询结果
                    log.info("idx(%s,%s) finish result %s", self.id, self.mid, cjson.encode(res))
                    if ok and res then
                        for _, v in ipairs(res) do
                            local uid, r, maxwin = v.uid, v.res, v.maxwin
                            local user = self.users[uid]
                            if user then
                                if r > 0 then -- 控制赢
                                    user.maxwin = 1 * maxwin
                                    local add = rand.rand_between(0, 300) / 100.0
                                    if rand.rand_between(0, 10000) < 5000 then
                                        add = rand.rand_between(400, 1000) / 100.0
                                    end
                                    -- 正常概率
                                    local randV = rand.rand_between(1, 10000)
                                    if randV < 800 then
                                        self.lastWinTimes = 1.0
                                    else
                                        randV = rand.rand_between(1, 10000)
                                        if randV < 2000 then
                                            self.lastWinTimes = rand.rand_between(100, 125) / 100.0
                                        elseif randV < 3000 then
                                            self.lastWinTimes = rand.rand_between(125, 150) / 100.0
                                        elseif randV < 5000 then
                                            self.lastWinTimes = rand.rand_between(150, 200) / 100.0
                                        elseif randV < 8000 then
                                            self.lastWinTimes = rand.rand_between(200, 300) / 100.0
                                        elseif randV < 9400 then
                                            self.lastWinTimes = rand.rand_between(300, 500) / 100.0
                                        elseif randV < 9900 then
                                            self.lastWinTimes = rand.rand_between(500, 1000) / 100.0
                                        else
                                            self.lastWinTimes = rand.rand_between(1000, 5000) / 100.0
                                        end
                                    end
                                    local t = math.log(self.lastWinTimes or 1.0) / math.log(1.06) + add
                                    self.lastWinTimes = (1.06 ^ t) + 0.005 --math.pow(1.06, t)
                                    self.lastWinTimes = self.lastWinTimes - self.lastWinTimes % 0.01
                                    self.hasGetResult = true
                                elseif r < 0 then -- 控制输
                                    user.maxwin = -1 * maxwin
                                    local randV = rand.rand_between(1, 10000)
                                    if randV < 8000 then
                                        self.lastWinTimes = 1.0
                                        self.hasGetResult = true
                                    elseif randV < 6000 then
                                        self.lastWinTimes = rand.rand_between(100, 125) / 100.0
                                        self.hasGetResult = true
                                    else
                                        -- 正常概率
                                        local randV = rand.rand_between(1, 10000)
                                        if randV < 800 then
                                            self.lastWinTimes = 1.0
                                        else
                                            randV = rand.rand_between(1, 10000)
                                            if randV < 2000 then
                                                self.lastWinTimes = rand.rand_between(100, 125) / 100.0
                                            elseif randV < 3000 then
                                                self.lastWinTimes = rand.rand_between(125, 150) / 100.0
                                            elseif randV < 5000 then
                                                self.lastWinTimes = rand.rand_between(150, 200) / 100.0
                                            elseif randV < 8000 then
                                                self.lastWinTimes = rand.rand_between(200, 300) / 100.0
                                            elseif randV < 9400 then
                                                self.lastWinTimes = rand.rand_between(300, 500) / 100.0
                                            elseif randV < 9900 then
                                                self.lastWinTimes = rand.rand_between(500, 1000) / 100.0
                                            else
                                                self.lastWinTimes = rand.rand_between(1000, 5000) / 100.0
                                            end
                                        end
                                        self.hasGetResult = true
                                    end
                                else
                                    user.maxwin = 0
                                    -- 正常概率
                                    local randV = rand.rand_between(1, 10000)
                                    if randV < 800 then
                                        self.lastWinTimes = 1.0
                                    else
                                        randV = rand.rand_between(1, 10000)
                                        if randV < 2000 then
                                            self.lastWinTimes = rand.rand_between(100, 125) / 100.0
                                        elseif randV < 3000 then
                                            self.lastWinTimes = rand.rand_between(125, 150) / 100.0
                                        elseif randV < 5000 then
                                            self.lastWinTimes = rand.rand_between(150, 200) / 100.0
                                        elseif randV < 8000 then
                                            self.lastWinTimes = rand.rand_between(200, 300) / 100.0
                                        elseif randV < 9400 then
                                            self.lastWinTimes = rand.rand_between(300, 500) / 100.0
                                        elseif randV < 9900 then
                                            self.lastWinTimes = rand.rand_between(500, 1000) / 100.0
                                        else
                                            self.lastWinTimes = rand.rand_between(1000, 5000) / 100.0
                                        end
                                    end
                                    self.hasGetResult = true
                                end
                                --user.maxwin = r * maxwin
                                log.warn("uid=%s, r=%s, maxwin=%s, self.lastWinTimes=%s", tostring(uid), tostring(r),
                                    tostring(maxwin), self.lastWinTimes)
                            end
                            --log.warn("uid=%s, r=%s, maxwin=%s", tostring(uid), tostring(r), tostring(maxwin))
                            -- if uid and uid == self.realPlayerUID then
                            --     self.lastWinTimes = r / 100.0
                            --     self.hasGetResult = true
                            --     log.debug("3 lastWinTimes = %s", tostring(self.lastWinTimes))
                            -- end
                        end
                        log.info("idx(%s,%s) result success", self.id, self.mid)
                    end

                    -- 填写返回数据

                    -- 牌局统计
                    self.sdata.cards = {}

                    -- self.sdata.wintypes = winTypes
                    --self.sdata.winpokertype = winPokerType
                end
            )
            timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, { self })
            coroutine.resume(self.result_co)
        else
            log.debug("calcResult() other single_profit_switch=false")
        end
    else
        -- 正常概率
        local randV = rand.rand_between(1, 10000)
        if randV < 800 then
            self.lastWinTimes = 1.0
        else
            randV = rand.rand_between(1, 10000)
            if randV < 2000 then
                self.lastWinTimes = rand.rand_between(100, 125) / 100.0
            elseif randV < 3000 then
                self.lastWinTimes = rand.rand_between(125, 150) / 100.0
            elseif randV < 5000 then
                self.lastWinTimes = rand.rand_between(150, 200) / 100.0
            elseif randV < 8000 then
                self.lastWinTimes = rand.rand_between(200, 300) / 100.0
            elseif randV < 9400 then
                self.lastWinTimes = rand.rand_between(300, 500) / 100.0
            elseif randV < 9900 then
                self.lastWinTimes = rand.rand_between(500, 1000) / 100.0
            else
                self.lastWinTimes = rand.rand_between(1000, 5000) / 100.0
            end
        end
        self.hasGetResult = true
        log.debug("4 lastWinTimes = %s", tostring(self.lastWinTimes))
    end
end


