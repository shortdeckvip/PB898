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
require("luascripts/servers/35/andarbahar")
require("luascripts/servers/35/seat")
require("luascripts/servers/35/vtable")
require("luascripts/servers/common/statistic")

cjson.encode_invalid_numbers(true)

--increment
Room = Room or {uniqueid = 0}

local EnumAndarBaharType = {
    --胜负
    EnumAndarBaharType_Andar = 1,
    EnumAndarBaharType_Bahar = 2
}

-- 在各下注区的下注金额(默认为0)
local DEFAULT_BET_TABLE = {
    --胜负
    [EnumAndarBaharType.EnumAndarBaharType_Andar] = 0,
    [EnumAndarBaharType.EnumAndarBaharType_Bahar] = 0
}

-- 下注区域(下注类型)
local DEFAULT_BET_TYPE = {
    EnumAndarBaharType.EnumAndarBaharType_Andar,
    EnumAndarBaharType.EnumAndarBaharType_Bahar
}

--
local DEFAULT_BETST_TABLE = {
    --胜负
    [EnumAndarBaharType.EnumAndarBaharType_Andar] = {
        type = EnumAndarBaharType.EnumAndarBaharType_Andar, -- Andar方
        hitcount = 0, -- 命中次数
        lasthit = 0 -- 距离上次命中的局数(即连续多少局未赢)
    },
    [EnumAndarBaharType.EnumAndarBaharType_Bahar] = {
        type = EnumAndarBaharType.EnumAndarBaharType_Bahar,
        hitcount = 0, -- 命中次数
        lasthit = 0 -- 距离上次命中的局数(即连续多少局未赢)
    }
}

local TimerID = {
    -- 游戏阶段
    TimerID_Check = {1, 100}, --id, interval(ms), timestamp(ms)
    TimerID_Start = {2, 4 * 1000}, --id, interval(ms), timestamp(ms)
    TimerID_Betting = {3, 15 * 1000}, --id, interval(ms), timestamp(ms)  下注阶段时长
    -- TimerID_Show = {4, 7 * 1000}, --id, interval(ms), timestamp(ms)     开牌时长不一致(根据发牌张数来确定)
    TimerID_Show = {4, 5 * 1000}, --id, interval(ms), timestamp(ms)     开牌时长不一致(根据发牌张数来确定)
    TimerID_Finish = {5, 4 * 1000}, --id, interval(ms), timestamp(ms)
    TimerID_NotifyBet = {6, 200, 0}, --id, interval(ms), timestamp(ms)  定时通知下注情况
    -- 协程
    TimerID_Timeout = {7, 5 * 1000, 0}, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = {8, 5 * 1000, 0} --id, interval(ms), timestamp(ms)
}

-- 房间状态
local EnumRoomState = {
    Check = 1, -- 检测状态
    Start = 2, -- 开始
    Betting = 3, -- 下注
    Show = 4, -- 摊牌
    Finish = 5 -- 结算
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
    self.start_time = global.ctms() -- 开始时刻
    self.betting_time = global.ctms() -- 开始下注时刻
    self.show_time = global.ctms() -- 摊牌时刻
    self.finish_time = global.ctms() -- 结算时刻
    self.round_start_time = 0 -- 这一局开始时刻

    self.state = EnumRoomState.Check -- 房间状态
    self.roundid = (self.id << 32) | global.ctsec() -- 局号(唯一!)  房间ID右移16位，再左移32位，再加上时间
    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家(包括机器人)在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有真实玩家在每个下注区下注累计值
    self.betst = {} -- 下注统计
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端, 元素类型为 PBAndarBaharBetData
    self.logmgr =
        LogMgr:new(
        self:conf() and self:conf().maxlogsavedsize, -- 历史记录最多留存条数
        tostring(global.sid()) .. tostring("_") .. tostring(self.id) -- 服务器ID_房间ID
    ) -- 历史记录

    self:calBetST() -- 计算牌局统计(各下注区总赢次数+最近连续未赢次数)

    --self.lastclaerlogstime		= nil				-- 上次清历史数据时间，UTC 时间
    --self.forceclientclearlogs	= false					-- 是否强制客户端清除历史
    self.onlinelst = {} -- 在线列表
    self.sdata = {roomtype = (self:conf() and self:conf().roomtype)} -- 统计数据
    self.vtable = VTable:new({id = 1}) -- 虚拟桌(排行榜)

    self.poker = AndarBahar:new() -- 每个房间一副牌
    self.statistic = Statistic:new(self.id, self:conf().mid) -- 统计资料
    -- self.bankmgr = BankMgr:new()  -- 庄家管理器
    self.total_bets = {} -- 存放各天的总下注额
    self.total_profit = {} -- 存放各天的总收益
    Utils:unSerializeMiniGame(self)
    --self.betmgr = BetMgr:new(o.id, o.mid)
    --self.keepsession = KeepSessionAlive:new(o.users, o.id, o.mid)

    self.update_games = 0 -- 更新经过的局数
    self.rand_player_num = 1
end

-- 重置这一局数据
function Room:roundReset()
    -- 牌局相关
    self.update_games = self.update_games + 1 -- 更新经过的局数

    self.start_time = global.ctms()
    self.betting_time = global.ctms()
    self.show_time = global.ctms()
    self.finish_time = global.ctms()
    self.round_start_time = 0

    self.profits = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家在每个下注区赢亏累计值
    self.bets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家(包括机器人)在每个下注区下注累计值
    self.userbets = g.copy(DEFAULT_BET_TABLE) -- 当局所有玩家(不包括机器人)在每个下注区下注累计值
    self.betque = {} -- 下注数据队列, 用于重放给其它客户端
    self.sdata = {roomtype = (self:conf() and self:conf().roomtype)} -- 清空统计数据
    -- self.sdata.cards[1].cards = { } 中存放发出的牌数据

    -- 记录每日北京时间中午 12 时（UTC 时间早上 4 时）清空一次
    --local currentime = os.date("!*t")
    --if currentime.hour == 4 and
    --( not self.lastclaerlogstime or currentime.day ~= self.lastclaerlogstime.day ) then
    --self.logs = {}
    --self.lastclaerlogstime		= os.date("!*t")
    --self.forceclientclearlogs	= true
    --log.info("[idx:%s] clear log", self.id)
    --end

    -- 用户数据
    for k, v in pairs(self.users) do -- 遍历该房间所有玩家
        v.bets = g.copy(DEFAULT_BET_TABLE) --在各下注区的下注额为0
        v.totalbet = 0 -- 本局总下注额
        v.profit = 0 -- 本局总收益
        v.totalprofit = 0
        v.isbettimeout = false
    end
end

-- 广播消息
function Room:broadcastCmd(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        net.send(v.linkid, k, maincmd, subcmd, msg)
    end
end

-- 广播消息给正在玩的玩家
function Room:broadcastCmdToPlayingUsers(maincmd, subcmd, msg)
    for k, v in pairs(self.users) do
        if v.state == EnumUserState.Playing then
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
            if v.state == EnumUserState.Playing then
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
function Room:count()
    return self.user_count
end

-- 重新计算该房间玩家总数目
function Room:recount()
    self.user_count = 0
    for k, v in pairs(self.users) do
        self.user_count = self.user_count + 1
    end
end

-- 获取API玩家数 ?
function Room:getApiUserNum()
    local t = {}
    local conf = self:conf()
    for _, v in pairs(self.users) do
        if v.state == EnumUserState.Playing and conf and conf.roomtype then
            local api = v.ud.api
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
        local t = {seats = vtable:getSeatsInfo()}
        -- dqw 通知更新排行榜
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
            local resp = pb.encode("network.cmd.PBNotifyGameMoneyUpdate_N", {val = data[1].extdata.balance})
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

-- dqw 玩家离开房间
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
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
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
            pb.encode("network.cmd.PBMutexRemove", {uid = uid, srvid = global.sid(), roomid = self.id})
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
        net.shared(
            linkid,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
            pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
            synto
        )
        log.info("idx(%s,%s) net.shared 1", self.id, self.mid)
        return
    end
    net.send( -- 发送离开房间回应消息
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
        resp
    )
    log.info("idx(%s,%s) userLeave:%s,%s", self.id, self.mid, uid, t.code)
end

local function onMutexTo(arg)
    arg[2]:userMutexCheck(arg[1], -1)
end

local function onTimeout(arg)
    arg[2]:userQueryUserInfo(arg[1], false, nil)
end

-- dqw 玩家请求进入房间
-- 参数 rev: 进入房间消息
function Room:userInto(uid, linkid, rev)
    local t = {
        -- 对应 PBIntoAndarBaharRoomResp_S 消息
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(), -- 游戏ID  35-AndarBahar
        idx = {
            srvid = global.sid(), -- 服务器ID ?
            roomid = self.id, -- 房间ID
            matchid = self.mid, -- 房间级别 (1：初级场  2：中级场)
            roomtype = self:conf().roomtype
        },
        data = {
            state = self.state, -- 当前房间状态
            lefttime = 0, -- 当前状态剩余时长(毫秒)
            roundid = self.roundid, -- 局号
            --jackpot = JackPot,  -- 奖池
            player = {}, -- 玩家信息
            seats = {}, -- 座位信息
            logs = {}, -- 历史记录
            sta = self.betst, -- 下注统计(牌局统计)
            betdata = {
                --  当局下注
                uid = uid,
                usertotal = 0,
                areabet = {}
            },
            card = {}, -- 牌数据(张数不确定)
            configchips = self:conf().chips, -- 下注筹码面值所有配置
            odds = {}, -- 下注区域设置(赔率, limit-min, limit-max)
            playerCount = Utils:getVirtualPlayerCount(self)
        }
        --data
    } --t

    if self.isStopping then
        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入房间失败
        t.data = nil
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
        )
        Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
        return
    end

    for _, v in ipairs(self:conf().betarea) do -- 下注区域设置(赔率, limit-min, limit-max)
        table.insert(t.data.odds, v[1])
    end

    self.users[uid] =
        self.users[uid] or
        {TimerID_MutexTo = timer.create(), TimerID_Timeout = timer.create() --[[TimerID_UserBet = timer.create(),]]}

    local user = self.users[uid]
    user.uid = uid -- 玩家ID
    user.state = EnumUserState.Intoing
    user.linkid = linkid
    user.ip = rev.ip or ""
    user.mobile = rev.mobile
    user.roomid = self.id
    user.matchid = self.mid

    user.mutex =
        coroutine.create( -- 创建一个新协程。 返回这个新协程，它是一个类型为 `"thread"` 的对象。
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
                    net.send(
                        linkid,
                        uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                        pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                    )
                    Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
                end
                log.info("idx(%s,%s) player:%s has been in another room", self.id, self.mid, uid)
                return -- 出错则直接返回
            end

            user.co =
                coroutine.create( -- 创建一个新协程。
                function(user) -- 函数参数由resume()中的第2个实参传递
                    Utils:queryUserInfo( --查询用户信息
                        {uid = uid, roomid = self.id, matchid = self.mid, carrybound = self:conf().carrybound}
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
                            balance = self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and
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
                            net.send(
                                linkid,
                                uid,
                                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                                pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                            )
                        end
                        log.info("idx(%s,%s) user %s not allowed into room", self.id, self.mid, uid)
                        return
                    end

                    -- 下面是玩家成功进入房间的情况
                    -- 填写返回数据   计算各状态下的剩余时长
                    if self.state == EnumRoomState.Start then
                        t.data.lefttime = TimerID.TimerID_Start[2] - (global.ctms() - self.start_time)
                    elseif self.state == EnumRoomState.Betting then
                        t.data.lefttime = TimerID.TimerID_Betting[2] - (global.ctms() - self.betting_time)
                    elseif self.state == EnumRoomState.Show then -- 开牌阶段
                        -- 在摊牌阶段剩余时长 (需要根据牌的张数确定)
                        local cardnum = self.sdata.cards and #self.sdata.cards[1].cards or 0 -- 计算所发的牌张数
                        local time_per_card = self:conf().time_per_card or 300 -- 每发一张牌需要多长时间(毫秒)
                        t.data.lefttime =
                            TimerID.TimerID_Show[2] - (global.ctms() - self.show_time) + cardnum * time_per_card -- +  TimerID.TimerID_Finish[2]
                        --t.data.card = g.copy(self.sdata.cards[1].cards)  -- 已发的牌数据
                        if cardnum > 0 then
                            for i = 1, cardnum, 1 do
                                table.insert(
                                    t.data.card,
                                    {
                                        color = self.poker:cardColor(self.sdata.cards[1].cards[i]), -- 牌花色
                                        count = self.poker:cardValue(self.sdata.cards[1].cards[i]) -- 牌点数
                                    }
                                )
                            end
                        end
                    elseif self.state == EnumRoomState.Finish then -- 结算阶段
                        t.data.lefttime = TimerID.TimerID_Finish[2] - (global.ctms() - self.finish_time)
                        -- t.data.card = g.copy(self.sdata.cards[1].cards) -- 已发的牌数据
                        local cardnum = self.sdata.cards and #self.sdata.cards[1].cards or 0 -- 计算所发的牌张数
                        if cardnum > 0 then
                            for i = 1, cardnum, 1 do
                                table.insert(
                                    t.data.card,
                                    {
                                        color = self.poker:cardColor(self.sdata.cards[1].cards[i]), -- 牌花色
                                        count = self.poker:cardValue(self.sdata.cards[1].cards[i]) -- 牌点数
                                    }
                                )
                            end
                        end
                    end

                    t.data.lefttime = t.data.lefttime > 0 and t.data.lefttime or 0
                    t.data.player = user.playerinfo -- 玩家信息(玩家ID、昵称、金额等)
                    t.data.seats = g.copy(self.vtable:getSeatsInfo()) -- 所有座位信息

                    if self.logmgr:size() <= self:conf().maxlogshowsize then
                        t.data.logs = self.logmgr:getLogs() -- 历史记录信息(各局赢方信息)
                    else
                        g.move( --拷贝历史记录(最近各局输赢情况)
                            self.logmgr:getLogs(),
                            self.logmgr:size() - self:conf().maxlogshowsize + 1,
                            self.logmgr:size(),
                            1,
                            t.data.logs
                        )
                    end

                    t.data.betdata.uid = uid
                    t.data.betdata.usertotal = user.totalbet or 0 -- 玩家本局总下注金额
                    for k, v in pairs(self.bets) do -- 所有玩家在各下注区的下注情况
                        if v ~= 0 then -- 如果有玩家在该下注区下注了
                            table.insert(
                                t.data.betdata.areabet,
                                {
                                    bettype = k, -- 下注区域
                                    betvalue = 0, --
                                    userareatotal = user.bets and user.bets[k] or 0, -- 当前玩家在该下注区的下注额
                                    areatotal = v -- 该区域的总下注额
                                    --odds			= self:conf() and self:conf().betarea and self:conf().betarea[k][1],
                                }
                            )
                        end
                    end
                    log.info(
                        "idx(%s,%s) into room: user %s linkid %s state %s balance %s user_count %s t %s",
                        self.id,
                        self.mid,
                        uid,
                        linkid,
                        self.state, -- 当前房间状态
                        user.playerinfo and user.playerinfo.balance or 0, -- 玩家身上金额
                        self.user_count, -- 玩家数目
                        cjson.encode(t) -- 进入房间消息响应包详情
                    )

                    local resp = pb.encode("network.cmd.PBIntoAndarBaharRoomResp_S", t) -- 进入房间返回消息
                    log.info("idx(%s,%s) encode room response", self.id, self.mid)
                    local to = {
                        uid = uid,
                        srvid = global.sid(),
                        roomid = self.id,
                        matchid = self.mid,
                        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoAndarBaharRoomResp"),
                        data = resp
                    }
                    local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)
                    net.shared(
                        linkid,
                        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                        pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                        synto
                    )

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
                {uid, self}
            )
            coroutine.resume(user.co, user) -- 第一次唤醒协程
        end
    )
    timer.tick(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1], TimerID.TimerID_MutexTo[2], onMutexTo, {uid, self})
    coroutine.resume(user.mutex, user) -- 唤醒协程  开始或继续协程 `user.mutex` 的运行。
end

-- dqw 处理玩家下注消息
function Room:userBet(uid, linkid, rev)
    local t = {
        -- 待返回的结构
        code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_Succ"),
        data = {
            uid = uid, -- 玩家ID
            usertotal = 0, -- 该玩家在所有下注区总下注值
            areabet = {}
        }
    }
    local user = self.users[uid] -- 根据玩家ID获取玩家对象
    local ok = true -- 默认下注成功
    local user_bets = g.copy(DEFAULT_BET_TABLE) -- 玩家本次在各下注区的下注情况(一局中可能有多次下注)
    local user_totalbet = 0 -- 玩家此次总下注金额

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

    -- 下注类型及下注额校验
    if not rev.data or not rev.data.areabet then
        log.info("idx(%s,%s) user %s, bad guy", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue") -- 无效下注区或下注额
        ok = false
        goto labelnotok
    end

    -- 遍历所有下注区
    for k, v in ipairs(rev.data.areabet) do
        if v and v.bettype and type(v.bettype) == "number" and v.betvalue and type(v.betvalue) == "number" then
            if
                not g.isInTable(DEFAULT_BET_TYPE, v.bettype) or -- 下注类型非法(下注区域非法)
                    (self:conf() and not g.isInTable(self:conf().chips, v.betvalue))
             then -- 下注金额非法  -- 下注筹码较验
                log.info("idx(%s,%s) user %s, bettype or betvalue invalid", self.id, self.mid, uid)
                t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue") -- 非法下注类型或下注值
                ok = false
                goto labelnotok
            else
                -- 单下注区游戏限红
                if
                    self:conf() and self:conf().betarea and
                        (v.betvalue > self:conf().betarea[v.bettype][3] or
                            v.betvalue + self.bets[v.bettype] > self:conf().betarea[v.bettype][3])
                 then
                    log.info("idx(%s,%s) user %s, betvalue over limits", self.id, self.mid, uid)
                    t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverLimits") -- 超出最大下注限制
                    ok = false
                    goto labelnotok
                end
                -- 下面是可以下注
                user_bets[v.bettype] = user_bets[v.bettype] + v.betvalue -- 增加某一区域的下注金额
                user_totalbet = user_totalbet + v.betvalue -- 增加总下注金额(该玩家此次总下注额)
            end
        end
    end -- for

    -- 下注总额为 0
    if user_totalbet == 0 then
        log.info("idx(%s,%s) user %s totalbet 0", self.id, self.mid, uid)
        t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidBetTypeOrValue") -- 无效的下注区或值
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
        cjson.encode(rev.data and rev.data.areabet or {})
    )

    if not ok then -- 如果出错
        --t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
        --t.data = g.copy(rev.data) or nil
        t.data.uid = rev.data and rev.data.uid or 0 -- 玩家ID
        t.data.balance = self:getUserMoney(t.data.uid) - (user.totalbet or 0) -- 玩家身上金额
        t.data.usertotal = rev.data and rev.data.usertotal or 0 -- 该玩家在所有下注区总下注值(服务器填)
        for _, v in ipairs((rev.data and rev.data.areabet) or {}) do
            table.insert(t.data.areabet, v)
        end
        local resp = pb.encode("network.cmd.PBAndarBaharBetResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharBetResp"), -- 下注失败回应
            resp
        )
        log.info("idx(%s,%s) user %s, PBAndarBaharBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    --扣费
    user.playerinfo = user.playerinfo or {}
    if user.playerinfo.balance and user.playerinfo.balance > user_totalbet then
        user.playerinfo.balance = user.playerinfo.balance - user_totalbet
    else
        user.playerinfo.balance = 0
    end

    if not self:conf().isib then
        Utils:walletRpc(
            uid,
            user.api,
            user.ip,
            -user_totalbet,
            pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_ANDARBAHAR_BET"),
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
    local areabet = {}
    user.bets = user.bets or g.copy(DEFAULT_BET_TABLE) -- 玩家这一局在各下注区的下注情况
    user.totalbet = user.totalbet or 0 -- 玩家这一局的总下注金额(各下注区下注总和)
    user.totalbet = user.totalbet + user_totalbet
    for k, v in pairs(user_bets) do -- 玩家本次在各下注区的下注情况(一局中可能有多次下注)
        if v ~= 0 then -- 如果在该区域下注了  k为下注区域编号  v为在该下注区的下注额
            user.bets[k] = user.bets[k] + v -- 本局该玩家在该下注区的下注额
            self.bets[k] = self.bets[k] + v -- 本局所有玩家在该下注区的下注额

            if not Utils:isRobot(user.ud.api) then
                self.userbets[k] = self.userbets[k] + v -- 本局非机器人在该下注区的下注金额
            end
        -- betque
        --table.insert(areabet, { bettype = k, betvalue = v, userareatotal = user.bets[k], areatotal = self.bets[k], })
        end
    end

    for k, v in ipairs(rev.data.areabet) do
        -- betque
        table.insert(
            areabet, -- 本次在各下注区域下注情况
            {
                bettype = v.bettype, -- 在哪个下注区下注
                betvalue = v.betvalue, -- 下注金额
                userareatotal = user.bets[v.bettype], -- 本局该玩家在该区域的总下注额
                areatotal = self.bets[v.bettype] -- 本局所有玩家在该下注区的总下注额
            }
        )
    end
    --  将下注记录插入队列末尾
    table.insert(
        self.betque,
        {
            uid = uid,
            balance = self:getUserMoney(uid),
            usertotal = user.totalbet,
            areabet = areabet
        }
    )

    -- 返回数据
    t.data.balance = self:getUserMoney(uid) -- 该玩家身上剩余金额
    t.data.usertotal = user.totalbet --该玩家本局在各下注区的总下注金额
    t.data.areabet = rev.data.areabet --该玩家本次在各下注区下注情况
    for k, v in pairs(t.data.areabet) do -- 遍历本次所有下注区
        t.data.areabet[k].userareatotal = user.bets[v.bettype] -- 本局该玩家在该下注区的总下注额
        t.data.areabet[k].areatotal = self.bets[v.bettype] -- 本局所有玩家在该下注区的总下注额
    end

    local resp = pb.encode("network.cmd.PBAndarBaharBetResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharBetResp"), -- 成功下注回应
        resp
    )
    -- 打印玩家成功下注详细信息
    log.info("idx(%s,%s) user %s, PBAndarBaharBetResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

-- dqw 请求获取历史记录
function Room:userHistory(uid, linkid, rev)
    local t = {
        logs = {}, -- 最近n局的输赢情况
        sta = {} -- 胜负统计(各区域赢的次数以及最近连输次数)
    }
    local ok = true
    local user = self.users[uid] -- 根据玩家ID获取玩家对象

    -- 非法玩家
    if user == nil then
        log.info("idx(%s,%s) user %s is not in room", self.id, self.mid, uid)
        ok = false
        goto labelnotok
    end

    ::labelnotok::
    if not ok then -- 如果出错
        local resp = pb.encode("network.cmd.PBAndarBaharHistoryResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharHistoryResp"), -- 历史记录回应
            resp
        )
        log.info("idx(%s,%s) user %s, PBAndarBaharHistoryResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    if self.logmgr:size() <= self:conf().maxlogshowsize then
        t.logs = self.logmgr:getLogs()
    else
        g.move(
            self.logmgr:getLogs(),
            self.logmgr:size() - self:conf().maxlogshowsize + 1, --开始位置
            self.logmgr:size(),
            1,
            t.logs
        )
    end
    t.sta = self.betst -- 胜负统计(各区域赢的次数以及最近连输次数)

    local resp = pb.encode("network.cmd.PBAndarBaharHistoryResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharHistoryResp"), -- 历史记录回应
        resp
    )
    log.info(
        "idx(%s,%s) user %s, PBAndarBaharHistoryResp_S: %s, logmgr:size: %s",
        self.id,
        self.mid,
        uid,
        cjson.encode(t),
        self.logmgr:size()
    )
end

-- 在线列表请求 (请求获取最近20局玩家的输赢下注情况)
function Room:userOnlineList(uid, linkid, rev)
    local t = {list = {}}
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
        local resp = pb.encode("network.cmd.PBAndarBaharOnlineListResp_S", t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharOnlineListResp"),
            resp
        )
        log.info("idx(%s,%s) user %s, PBAndarBaharOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
        return
    end

    -- 返回前 300 条
    g.move(self.onlinelst, 1, math.min(300, #self.onlinelst), 1, t.list)
    -- 返回前 300 条
    local resp = pb.encode("network.cmd.PBAndarBaharOnlineListResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharOnlineListResp"),
        resp
    )
    log.info("idx(%s,%s) user %s, PBAndarBaharOnlineListResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

-- dqw 定时通知玩家下注详情
local function onNotifyBet(self)
    local function doRun()
        if
            self.state == EnumRoomState.Betting or -- 如果在下注阶段 或者 在摊牌阶段的前2秒
                (self.state == EnumRoomState.Show and global.ctms() <= self.show_time + 2000)
         then
            -- 单线程，betque 不考虑竞争问题
            local t = {bets = {}}
            for i = 1, 300 do -- 防止单个包过大，分割开
                if #self.betque == 0 then
                    break
                end
                table.insert(t.bets, table.remove(self.betque, 1))
            end

            if #t.bets > 0 then
                pb.encode(
                    "network.cmd.PBAndarBaharNotifyBettingInfo_N", -- 通知下注信息
                    t,
                    function(pointer, length)
                        self:sendCmdToPlayingUsers(
                            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharNotifyBettingInfo"),
                            pointer,
                            length
                        )
                        --log.info("idx(%s,%s) PBAndarBaharNotifyBettingInfo_N : %s %s", self.id, #t.bets, cjson.encode(t))
                    end
                )
            end
        --log.info("idx:%s notifybet", self.id)
        end
    end
    g.call(doRun)
end

-- 定时通知下注信息
function Room:notifybet()
    log.info("idx(%s,%s) notifybet room game:%s", self.id, self.mid, self.state)
    timer.tick(self.timer, TimerID.TimerID_NotifyBet[1], TimerID.TimerID_NotifyBet[2], onNotifyBet, self)
end

-- 检测定时器回调函数
local function onCheck(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Check[1]) -- 关闭检测定时器

        if self.isStopping then
            Utils:onStopServer(self)
            return
        end

        self:start() -- 调用开始函数
    end
    g.call(doRun)
end

-- 检测
function Room:check()
    log.info("idx(%s,%s) check game state - %s %s", self.id, self.mid, self.state, tostring(global.stopping()))
    if global.stopping() then -- 判断游戏是否停止
        return
    end
    self.state = EnumRoomState.Check -- 房间进入检测状态
    timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self)
end

-- 开始游戏定时器回调函数
local function onStart(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Start[1]) -- 关闭定时器
        self:betting() -- 开始下注
    end
    g.call(doRun)
end

-- 开始游戏
function Room:start()
    self:roundReset() --
    self.roundid = (self.id << 16) | global.ctsec() -- 生成唯一局号
    self.state = EnumRoomState.Start -- 进入开始阶段
    self.round_start_time = global.utcstr() -- 该局开始时刻
    self.start_time = global.ctms() -- 该阶段开始时刻(毫秒)
    self.logid = self.statistic:genLogId(self.start_time / 1000) -- 日志ID?

    local t = {
        t = TimerID.TimerID_Start[2], -- 该阶段剩余时长
        roundid = self.roundid, -- 轮次
        --[[needclearlog = self.forceclientclearlogs ]]
        playerCount = Utils:getVirtualPlayerCount(self)
    }

    -- dqw 通知玩家游戏开始了
    pb.encode(
        "network.cmd.PBAndarBaharNotifyStart_N", -- 通知游戏开始
        t,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharNotifyStart"),
                pointer,
                length
            )
        end
    )
    timer.tick(self.timer, TimerID.TimerID_Start[1], TimerID.TimerID_Start[2], onStart, self)

    log.info(
        "idx(%s,%s) start room game, state %s roundid %s logid %s",
        self.id, -- 房间ID
        self.mid, -- 房间级别ID
        self.state, --房间状态
        tostring(self.roundid), --轮次ID
        tostring(self.logid) -- 日志ID
    )

    -- 重置数据
    --self.forceclientclearlogs = false
end

-- 下注定时器回调函数 (下注结束)
local function onBetting(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Betting[1]) -- 关闭定时器
        self:show() -- 开牌(发牌)
    end
    g.call(doRun)
end

-- 开始下注
function Room:betting()
    log.info("idx(%s,%s) betting state-%s", self.id, self.mid, self.state)

    self:notifybet() -- 定时更新下注信息
    self.betting_time = global.ctms() -- 下注的开始时刻
    self.state = EnumRoomState.Betting -- 进入下注阶段

    -- dqw 通知玩家可以下注了
    pb.encode(
        "network.cmd.PBAndarBaharNotifyBet_N", -- 开始下注倒计时
        {t = TimerID.TimerID_Betting[2]}, -- 离下注结束还有多久
        function(pointer, length)
            self:sendCmdToPlayingUsers( -- 通知玩家可以下注
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharNotifyBet"), -- 通知玩家可以下注了
                pointer,
                length
            )
        end
    )

    timer.tick(self.timer, TimerID.TimerID_Betting[1], TimerID.TimerID_Betting[2], onBetting, self) -- 启动定时器
end

-- 摊牌定时器回调函数  准备进入下一阶段
local function onShow(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Show[1])
        self:finish() -- 结算
    end
    g.call(doRun)
end

-- 计算牌型统计(各下注区总赢次数+最近连续未赢次数)
function Room:calBetST()
    self.betst = g.copy(DEFAULT_BETST_TABLE) -- 相当于初始化

    for _, v in ipairs(self.logmgr:getLogs()) do -- 遍历所有输赢日志(记录各局的赢方)
        for _, bt in ipairs(DEFAULT_BET_TYPE) do -- 遍历各下注区
            if g.isInTable(v.wintype, bt) then -- 如果该下注区赢
                self.betst[bt].lasthit = 0 -- 距离上次赢的局数为0   -- 该区域连续多少局未赢
                self.betst[bt].hitcount = self.betst[bt].hitcount + 1 -- 该下注区赢的次数增1
            else
                self.betst[bt].lasthit = self.betst[bt].lasthit + 1 -- 该区域连续多少局未赢
            end
        end
    end
end

-- 开牌阶段
function Room:show()
    log.info("idx(%s,%s) show room game, state - %s", self.id, self.mid, self.state)

    self.state = EnumRoomState.Show -- 进入开牌阶段
    self.show_time = global.ctms() -- 开牌阶段开始时刻
    timer.cancel(self.timer, TimerID.TimerID_NotifyBet[1]) -- 关闭下注定时器

    onNotifyBet(self) -- 最后一次通知下注信息

    if self:conf().isib then
        Utils:debit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_ANDARBAHAR_BET"))
        Utils:balance(self, EnumUserState.Playing)
    end

    -- 生成牌，计算牌型
    self.poker:reset()

    local cards = self.poker:getNCard(52) -- 获取50张牌(一局最多发50张牌)

    local cardNum, wintype = self.poker:getWinType(cards) -- 获取赢的一方及赢牌所在位置

    --根据盈利率触发胜负策略
    local needExchange = false -- 是否需要换牌

    --根据盈利率触发胜负策略
    local usertotalbet = 0
    for _, v in pairs(EnumAndarBaharType) do
        usertotalbet = usertotalbet + (self.userbets[v] or 0)
    end
    -- 根据系统盈利率设置是否需要换牌(更改输赢方)
    if usertotalbet > 0 then
        local profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(wintype)
        local last_profitrate = profit_rate
        if profit_rate < self:conf().profitrate_threshold_lowerlimit then
            log.info("idx(%s,%s) tigh mode is trigger", self.mid, self.id)
            local rnd = rand.rand_between(1, 10000)
            if profit_rate < self:conf().profitrate_threshold_minilimit or rnd <= 5000 then
                needExchange = true -- 需要换牌
                if wintype == EnumAndarBaharType.EnumAndarBaharType_Andar then
                    wintype = EnumAndarBaharType.EnumAndarBaharType_Bahar
                else
                    wintype = EnumAndarBaharType.EnumAndarBaharType_Andar
                end
                profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(wintype)
                log.info("idx(%s,%s) swap cards is trigger", self.mid, self.id)
                if profit_rate < self:conf().profitrate_threshold_minilimit and profit_rate < last_profitrate then
                    needExchange = false
                    if wintype == EnumAndarBaharType.EnumAndarBaharType_Andar then
                        wintype = EnumAndarBaharType.EnumAndarBaharType_Bahar
                    else
                        wintype = EnumAndarBaharType.EnumAndarBaharType_Andar
                    end
                    log.info("idx(%s,%s) greator swap cards is trigger", self.mid, self.id)
                    profit_rate, usertotalbet_inhand, usertotalprofit_inhand = self:getTotalProfitRate(wintype)
                end
            end
        end
        local curday = global.cdsec()
        self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet_inhand
        self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit_inhand
    end

    if needExchange then -- 如果需要换牌(更改输赢方)
        if cardNum > 2 then
            cards[cardNum - 1], cards[cardNum] = cards[cardNum], cards[cardNum - 1]
            cardNum = cardNum - 1
        else
            for i = 3, 6, 1 do
                if self.poker:cardValue(cards[1]) ~= self.poker:cardValue(cards[i]) then
                    cards[2], cards[i] = cards[i], cards[2]
                    cards[3], cards[i] = cards[i], cards[3]
                    cardNum = cardNum + 1
                    break
                end
            end
        end
    end

    -- 填写返回数据
    local t = {
        cardnum = cardNum, -- 本轮发出的牌总张数
        card = {}, -- 牌数据
        areainfo = {}
    }

    -- 拷贝牌数据
    for i = 1, cardNum, 1 do
        table.insert(
            t.card,
            {
                color = self.poker:cardColor(cards[i]), -- 牌花色
                count = self.poker:cardValue(cards[i]) -- 牌点数
            }
        )
    end

    -- 遍历所有下注区
    for _, v in pairs(DEFAULT_BET_TYPE) do
        table.insert(
            t.areainfo,
            {
                bettype = v,
                iswin = wintype == v
            }
        )
    end

    --print("PBAndarBaharNotifyShow_N", cjson.encode(t))
    -- dqw 通知玩家摊牌(发送牌数据)
    pb.encode(
        "network.cmd.PBAndarBaharNotifyShow_N", -- 摊牌
        t,
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharNotifyShow"),
                pointer,
                length
            )
            log.info("idx(%s,%s) PBAndarBaharNotifyShow_N : %s", self.id, self.mid, cjson.encode(t))
        end
    )
    -- 每多发一张牌多300ms
    local time_per_card = self:conf().time_per_card or 300
    timer.tick(self.timer, TimerID.TimerID_Show[1], TimerID.TimerID_Show[2] + cardNum * time_per_card, onShow, self)

    --print(self:conf().maxlogsavedsize, self:conf().roomtype)
    --print(cjson.encode(self.logmgr))

    -- 生成一条记录
    local logitem = {wintype = {wintype}} -- 存放哪一方赢
    self.logmgr:push(logitem) -- 添加记录(这一局的输赢结果)
    log.info("idx(%s,%s) log %s", self.id, self.mid, cjson.encode(logitem))

    self:calBetST() --计算牌局统计(各下注区总赢次数+最近连续未赢次数)

    -- 牌局统计
    -- self.sdata.cards = {{cards = {cards[1]}}, {cards = {cards[2]}}}  -- 牌数据 ?
    self.sdata.cards = {{cards = {}}}
    self.sdata.cardstype = {} -- 牌型
    -- self.sdata.cards = g.copy(t.card)  -- 保存这一局所发的牌数据

    for i = 1, cardNum, 1 do
        table.insert(self.sdata.cards[1].cards, cards[i])
    end

    --table.insert(self.sdata.cardstype, pokertypeA)
    --table.insert(self.sdata.cardstype, pokertypeB)
    self.sdata.wintypes = {wintype} -- 赢方
    --self.sdata.winpokertype = winPokerType
end

-- 结算结束  结算定时器回调函数
local function onFinish(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_Finish[1]) -- 关闭定时器
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
        --log.info("[idx:%s] onlinelst %s", self.id, cjson.encode(self.onlinelst))
        -- 分配座位
        self.vtable:reset() -- 重置排行榜(虚拟桌)
        for i = 1, math.min(self.vtable:getSize(), #self.onlinelst) do
            local o = self.onlinelst[i] -- 第i个玩家
            local uid = o.player.uid -- 玩家ID
            self.vtable:sit(uid, self.users[uid].playerinfo)
        end

        self:updateSeatsInVTable(self.vtable) -- 更新排行榜，通知在线玩家

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
                timer.destroy(v.TimerID_Timeout) -- 销毁定时器
                timer.destroy(v.TimerID_MutexTo)

                if v.state == EnumUserState.Logout then
                    mutex.request(
                        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
                        pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
                        pb.encode("network.cmd.PBMutexRemove", {uid = k, srvid = global.sid(), roomid = self.id})
                    )
                end
                log.info("idx(%s,%s) kick user:%s state:%s", self.id, self.mid, k, tostring(v.state))
                self.users[k] = nil
                self.user_cached = false --玩家缓存无效
                self:recount() -- 重新计算玩家数目
            end
        end

        -- 广播赢分大于 100 万
        --self.statistic:broadcastBigWinner()
        self:check() -- 进入检测阶段，开始下一局
    end
    g.call(doRun)
end

-- dqw 结算 Room:finish
function Room:finish()
    log.info("idx(%s,%s) finish room game, state - %s", self.id, self.mid, self.state)
    self.state = EnumRoomState.Finish -- 进入结算阶段
    self.finish_time = global.ctms() -- 结算开始时刻(毫秒)

    local lastlogitem = self.logmgr:back() -- 最近一个历史记录(也就是这一局的结果：哪一方赢)
    local totalbet, usertotalbet = 0, 0 -- 该局所有玩家总押注，该局所有真实玩家总押注
    local totalprofit, usertotalprofit = 0, 0 -- 该局所有玩家收益和，该局所有真实玩家收益和
    local totalfee = 0 -- 服务费
    local ranks = {} -- 排序使用的表

    local onlinerank = {
        uid = 0, -- 玩家ID
        --rank		= 0,
        --player		= v.seat and v.seat:getSeatInfo().playerinfo,
        totalprofit = 0, -- 总收益
        areas = {}
    }

    for k, v in pairs(self.users) do -- 遍历该房间所有玩家
        -- 计算下注的玩家  k为玩家ID, v为user
        -- if (v.totalbet and v.totalbet > 0) or self.bankmgr:banker() == k then
        if not v.isdebiting and v.totalbet and v.totalbet > 0 then
            -- 牌局统计
            self.sdata.users = self.sdata.users or {} -- 玩家列表
            self.sdata.users[k] = self.sdata.users[k] or {} -- 该玩家信息
            self.sdata.users[k].areas = self.sdata.users[k].areas or {} -- 下注信息
            self.sdata.users[k].stime = self.start_time / 1000 -- 开始时刻(秒)
            self.sdata.users[k].etime = self.finish_time / 1000 -- 结束时刻(秒)
            self.sdata.users[k].sid = v.seat and v.seat:getSid() or 0 -- 座位号
            self.sdata.users[k].tid = v.vtable and v.vtable:getTid() or 0 -- 虚拟桌号
            self.sdata.users[k].money = self.sdata.users[k].money or (self:getUserMoney(k) or 0) -- 余额
            self.sdata.users[k].nickname = v.playerinfo and v.playerinfo.nickname -- 昵称
            self.sdata.users[k].username = v.playerinfo and v.playerinfo.username -- 用户名
            self.sdata.users[k].nickurl = v.playerinfo and v.playerinfo.nickurl
            self.sdata.users[k].currency = v.playerinfo and v.playerinfo.currency
            self.sdata.users[k].extrainfo =
                cjson.encode(
                {
                    ip = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.ip,
                    api = v.playerinfo and v.playerinfo.extra and v.playerinfo.extra.api,
                    roomtype = self:conf().roomtype, -- 房间类型(金币/豆子)
                    -- bankeruid = self.bankmgr:banker()
                    bankeruid = 0,
                    money = self:getUserMoney(k) or 0
                }
            )

            -- 结算
            v.totalprofit = 0 -- 该玩家本局总收益(未扣除下注额，只扣除了服务费)
            v.totalpureprofit = 0 -- 该玩家本局纯收益(扣除了下注额，也扣除了服务费)
            v.totalfee = 0 -- 该局总服务费用
            totalbet = totalbet + v.totalbet -- 该局所有玩家总押注额

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

            log.info(
                "idx(%s,%s) player %s, rofit settlement profit %s, totalbets %s, totalpureprofit %s",
                self.id,
                self.mid,
                k, -- 玩家id
                tostring(v.totalprofit), -- 该玩家本局总收益(未扣除下注额)
                tostring(v.totalbet), -- 该玩家本局总下注额
                tostring(v.totalpureprofit) -- 该玩家本局总纯收益(扣除下注额)
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

            if not Utils:isRobot(v.ud.api) then -- 如果该玩家不是机器人
                usertotalprofit = usertotalprofit + v.totalprofit -- 本局真实玩家总收益和
                usertotalbet = usertotalbet + v.totalbet -- 本局真实玩家总下注额
                self.sdata.users[k].ugameinfo = {texas = {inctotalhands = 1}}
            end

            -- ranks
            -- TODO：优化
            if self.vtable:getSeat(k) then -- 如果该玩家已经在排行榜中  根据玩家ID判断是否在排行榜中
                local rank = {
                    uid = k, -- 玩家ID
                    --rank		= 0,
                    player = v.seat and v.seat:getSeatInfo().playerinfo,
                    totalprofit = v.totalprofit, -- 该玩家该局总收益  (客户端结算发放金币用?)
                    areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
                }
                table.insert(ranks, rank) -- 插入在排行榜中的玩家排名信息
            else -- 该玩家还未在排行榜中
                -- 在线玩家 uid 为 0    其他在线玩家
                for _, bettype in ipairs(DEFAULT_BET_TYPE) do
                    local areas = self.sdata.users[k] and self.sdata.users[k].areas or {}
                    local area = areas[bettype] -- 该玩家在该下注区的信息
                    if area and area.bettype then
                        onlinerank.totalprofit = (onlinerank.totalprofit or 0) + (area.profit or 0) -- 各区域总收益
                        onlinerank.areas[area.bettype] = onlinerank.areas[area.bettype] or {}
                        onlinerank.areas[area.bettype].bettype = area.bettype -- 下注区域
                        onlinerank.areas[area.bettype].betvalue =
                            (onlinerank.areas[area.bettype].betvalue or 0) + (area.betvalue or 0) -- 增加下注额
                        if g.isInTable(lastlogitem.wintype, area.bettype) then -- 押中 判断当前区域是否赢
                            onlinerank.areas[area.bettype].profit =
                                (onlinerank.areas[area.bettype].profit or 0) + (area.profit or 0) -- 增加该下注区收益
                            onlinerank.areas[area.bettype].pureprofit =
                                (onlinerank.areas[area.bettype].pureprofit or 0) + (area.pureprofit or 0) -- 增加该下注区纯收益
                        else
                            onlinerank.areas[area.bettype].profit = 0
                            onlinerank.areas[area.bettype].pureprofit = 0
                        end
                    end
                end
            end
            -- 保存该玩家最近 20 局的记录(每局的总下注和总收益)
            v.logmgr = v.logmgr or LogMgr:new(20)
            v.logmgr:push({bet = v.totalbet or 0, profit = v.totalprofit or 0}) --存放该玩家本局记录{总下注，各赢的区域总收益}
        end -- end of [if (v.totalbet and v.totalbet > 0) or self.bankmgr:banker == k then]
    end -- end of [for k,v in pairs(self.users) do]

    Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_ANDARBAHAR_SETTLE"))

    -- ranks
    table.insert(ranks, onlinerank) -- 插入其他所有在线玩家排名信息(合并到一个中)

    --log.info('ranks %s', cjson.encode(ranks))
    --log.info('onlinerank %s', cjson.encode(onlinerank))

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

        local t = {
            ranks = g.copy(ranks), -- 大赢家  排名信息  排行榜中的玩家信息+其他在线玩家信息
            log = lastlogitem, --最近记录(游戏结果) 赢的区域
            sta = self.betst -- 牌型统计(各区域累计赢的次数及连续未赢次数)
            -- banker = {uid = self.bankmgr:banker(), totalprofit = banker_profit}
        }
        table.insert(t.ranks, rank) -- 插入真正的每个在线玩家的排行信息

        -- dqw 通知玩家该局游戏结束
        net.send(
            v.linkid,
            k,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_AndarBaharNotifyFinish"),
            pb.encode("network.cmd.PBAndarBaharNotifyFinish_N", t)
        )
        --log.info("idx(%s,%s) uid: %s, PBAndarBaharNotifyFinish_N : %s", self.id, self.mid, k, cjson.encode(t))
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
    self.sdata.extrainfo =
        cjson.encode({bankeruid = 0, bankerprofit = 0, totalfee = 0, playercount = self:getRealPlayerCount(),playerbet = usertotalbet,playerprofit = usertotalprofit}) -- 因为该游戏没有庄家

    self.statistic:appendLogs(self.sdata, self.logid)

    --local curday = global.cdsec() -- 获取当天标识值
    --self.total_bets[curday] = (self.total_bets[curday] or 0) + usertotalbet -- 当天真实玩家总下注额
    --self.total_profit[curday] = (self.total_profit[curday] or 0) + usertotalprofit -- 当天真实玩家总收益
    Utils:serializeMiniGame(self)

    timer.tick(self.timer, TimerID.TimerID_Finish[1], TimerID.TimerID_Finish[2], onFinish, self)
end

-- 踢出玩家
function Room:kickout()
    if self.state ~= EnumRoomState.Finish then
        Utils:repay(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_ANDARBAHAR_SETTLE"))
    end
    for k, v in pairs(self.users) do -- 遍历该房间所有玩家
        if self.state ~= EnumRoomState.Finish and v.totalbet and v.totalbet > 0 then -- 如果不在结算阶段且下注了
            v.totalbet = 0
        end
        self:userLeave(k, v.linkid) -- 玩家离开
    end
end

-- 获取系统盈利比例
function Room:getTotalProfitRate(wintype)
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

    local usertotalbet_inhand, usertotalprofit_inhand = 0, 0
    for _, v in pairs(EnumAndarBaharType) do
        usertotalbet_inhand = usertotalbet_inhand + (self.userbets[v] or 0)
        if wintype == v then
            usertotalprofit_inhand =
                usertotalprofit_inhand +
                (self.userbets[v] or 0) * (self:conf() and self:conf().betarea and self:conf().betarea[v][1])
        end
    end
    totalbets = totalbets + usertotalbet_inhand
    totalprofit = totalprofit + usertotalprofit_inhand

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
    return profit_rate, usertotalbet_inhand, usertotalprofit_inhand
end

function Room:phpMoneyUpdate(uid, rev)
    log.info("(%s,%s)phpMoneyUpdate %s", self.id, self.mid, uid)
    local user = self.users[uid]
    if user then
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
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_ANDARBAHAR_SETTLE"),
                v,
                EnumRoomState.Show
            )
        end
    end
end

-- 获取真实玩家数目
function Room:getRealPlayerCount()
    local realPlayerCount = 0
    for _, user in pairs(self.users) do
        if user and user.state == EnumUserState.Playing then
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
        -- 对应 PBIntoAndarBaharRoomResp_S 消息
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(), -- 游戏ID  35-AndarBahar
        idx = {
            srvid = global.sid(), -- 服务器ID ?
            roomid = self.id, -- 房间ID
            matchid = self.mid -- 房间级别 (1：初级场  2：中级场)
        },
        data = {
            state = self.state, -- 当前房间状态
            lefttime = 0, -- 当前状态剩余时长(毫秒)
            roundid = self.roundid, -- 局号
            --jackpot = JackPot,  -- 奖池
            player = {}, -- 玩家信息
            seats = {}, -- 座位信息
            logs = {}, -- 历史记录
            sta = self.betst, -- 下注统计(牌局统计)
            betdata = {
                --  当局下注
                uid = uid,
                usertotal = 0,
                areabet = {}
            },
            card = {}, -- 牌数据(张数不确定)
            configchips = self:conf().chips, -- 下注筹码面值所有配置
            odds = {}, -- 下注区域设置(赔率, limit-min, limit-max)
            playerCount = Utils:getVirtualPlayerCount(self)
        }
        --data
    } --t

    for _, v in ipairs(self:conf().betarea) do -- 下注区域设置(赔率, limit-min, limit-max)
        table.insert(t.data.odds, v[1])
    end

    -- 填写返回数据   计算各状态下的剩余时长
    if self.state == EnumRoomState.Start then
        t.data.lefttime = TimerID.TimerID_Start[2] - (global.ctms() - self.start_time)
    elseif self.state == EnumRoomState.Betting then
        t.data.lefttime = TimerID.TimerID_Betting[2] - (global.ctms() - self.betting_time)
    elseif self.state == EnumRoomState.Show then -- 开牌阶段
        -- 在摊牌阶段剩余时长 (需要根据牌的张数确定)
        local cardnum = self.sdata.cards and #self.sdata.cards[1].cards or 0 -- 计算所发的牌张数
        local time_per_card = self:conf().time_per_card or 300 -- 每发一张牌需要多长时间(毫秒)
        t.data.lefttime = TimerID.TimerID_Show[2] - (global.ctms() - self.show_time) + cardnum * time_per_card -- +  TimerID.TimerID_Finish[2]
        --t.data.card = g.copy(self.sdata.cards[1].cards)  -- 已发的牌数据
        if cardnum > 0 then
            for i = 1, cardnum, 1 do
                table.insert(
                    t.data.card,
                    {
                        color = self.poker:cardColor(self.sdata.cards[1].cards[i]), -- 牌花色
                        count = self.poker:cardValue(self.sdata.cards[1].cards[i]) -- 牌点数
                    }
                )
            end
        end
    elseif self.state == EnumRoomState.Finish then -- 结算阶段
        t.data.lefttime = TimerID.TimerID_Finish[2] - (global.ctms() - self.finish_time)
        -- t.data.card = g.copy(self.sdata.cards[1].cards) -- 已发的牌数据
        local cardnum = self.sdata.cards and #self.sdata.cards[1].cards or 0 -- 计算所发的牌张数
        if cardnum > 0 then
            for i = 1, cardnum, 1 do
                table.insert(
                    t.data.card,
                    {
                        color = self.poker:cardColor(self.sdata.cards[1].cards[i]), -- 牌花色
                        count = self.poker:cardValue(self.sdata.cards[1].cards[i]) -- 牌点数
                    }
                )
            end
        end
    end

    t.data.lefttime = t.data.lefttime > 0 and t.data.lefttime or 0

    local user = self.users[uid]
    t.data.player = user.playerinfo -- 玩家信息(玩家ID、昵称、金额等)
    t.data.seats = g.copy(self.vtable:getSeatsInfo()) -- 所有座位信息

    if self.logmgr:size() <= self:conf().maxlogshowsize then
        t.data.logs = self.logmgr:getLogs() -- 历史记录信息(各局赢方信息)
    else
        g.move( --拷贝历史记录(最近各局输赢情况)
            self.logmgr:getLogs(),
            self.logmgr:size() - self:conf().maxlogshowsize + 1,
            self.logmgr:size(),
            1,
            t.data.logs
        )
    end

    t.data.betdata.uid = uid
    t.data.betdata.usertotal = user.totalbet or 0 -- 玩家本局总下注金额
    for k, v in pairs(self.bets) do -- 所有玩家在各下注区的下注情况
        if v ~= 0 then -- 如果有玩家在该下注区下注了
            table.insert(
                t.data.betdata.areabet,
                {
                    bettype = k, -- 下注区域
                    betvalue = 0, --
                    userareatotal = user.bets and user.bets[k] or 0, -- 当前玩家在该下注区的下注额
                    areatotal = v -- 该区域的总下注额
                    --odds			= self:conf() and self:conf().betarea and self:conf().betarea[k][1],
                }
            )
        end
    end

    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoAndarBaharRoomResp"),
        pb.encode("network.cmd.PBIntoAndarBaharRoomResp_S", t)
    )
end
