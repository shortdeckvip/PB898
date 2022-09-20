local pb = require("protobuf")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local log = require(CLIBS["c_log"])
local redis = require(CLIBS["c_hiredis"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
local rand = require(CLIBS["c_rand"])

-- 房间状态
local EnumRoomState = {
    Check = 1,
    Start = 2,
    Betting = 3, -- 下注状态
    Show = 4,
    Finish = 5
}

--overwrite
Utils = {}
SLOT_INFO = { total_bets = {}, total_profit = {} }

local USERINFO_SERVER_TYPE = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_UserInfo") << 16
local MONEY_SERVER_TYPE = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Money") << 16
local NOTIFY_SERVER_TYPE = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Notify") << 16
local STATISTIC_SERVER_TYPE = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Statistic") << 16
local ROBOT_SERVER_TYPE = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Robot") << 16
local ROBOT_API = "2001"
local UNIQUE_TID = 0

function Utils:isRobot(api)
    return tostring(api) == ROBOT_API
end

-- 判断该房间是否有机器人坐下
function Utils:hasRobotSit(room)
    if room.seats then
        for k, seat in ipairs(room.seats) do
            if seat and seat.uid and seat.uid > 0 then
                if room.users and room.users[seat.uid] then
                    if self:isRobot(room.users[seat.uid].api) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- 获取某房间空闲座位数
function Utils:getEmptySeatNum(room)
    local emptySeatNum = 0
    if room.seats then
        for k, seat in ipairs(room.seats) do
            if seat then
                if not seat.uid or seat.uid <= 0 then
                    emptySeatNum = emptySeatNum + 1
                end
            end
        end
    end
    return emptySeatNum
end

-- 判断该房间是否有机器人
function Utils:hasRobot(room)
    for k, user in pairs(room.users) do
        if user and user.api then
            if self:isRobot(user.api) and user.state == 1 then
                return true
            end
        end
    end
    return false
end

function Utils:sendTipsToMe(linkid, uid, tips, gameid)
    local c = {
        type = pb.enum_id("network.cmd.PBChatChannelType", "PBChatChannelType_Tips"),
        msg = tips,
        gameId = global.stype()
    }
    if gameid ~= nil then
        c.gameId = gameid
    end
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Chat"),
        pb.enum_id("network.cmd.PBChatSubCmdID", "PBChatSubCmdID_NotifySysChatMsg"),
        pb.encode("network.cmd.PBNotifySysChatMsg", c)
    )
end

-- 投递到系统邮件
function Utils:postMail(acid, uids, mailtype, title, content)
    if not uids or not mailtype or not title or not content then
        return
    end
    if type(uids) ~= "table" then
        return
    end

    net.forward(
        USERINFO_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
        pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_PostMail"),
        pb.encode(
            "network.inter.PBPostMailReq",
            {
            acid = acid,
            uid = uids,
            type = mailtype,
            title = title,
            content = content
        }
        )
    )
end

-- 更新用户信息
function Utils:updateUserInfo(msg)
    return net.forward(
        USERINFO_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
        pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_UserAtomUpdate"),
        pb.encode("network.inter.PBUserAtomUpdate", msg)
    )
end

-- 查询用户信息
function Utils:queryUserInfo(msg)
    return net.forward(
        MONEY_SERVER_TYPE, --发送消息给金币服
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
        pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_QueryUserInfo"),
        pb.encode("network.inter.PBQueryUserInfo", msg)
    )
end

function Utils:sendRequestToWallet(msg)
    return net.forward(
        MONEY_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
        pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_MoneySingleWalletOperationReq"),
        pb.encode("network.inter.PBMoneySingleWalletOperationReq", msg)
    )
end

function Utils:reportResult(msg)
    return net.forward(
        MONEY_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
        pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_ReportResult"),
        pb.encode("network.inter.PBReportResult", msg)
    )
end

function Utils:updateMoney(msg, uid)
    return net.forward(
        MONEY_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
        pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_MoneyAtomUpdate"),
        pb.encode("network.inter.PBMoneyAtomUpdate", msg),
        uid
    )
end

function Utils:requestJackpot(msg)
    return net.forward(
        STATISTIC_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
        pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_JackpotReqResp"),
        pb.encode("network.inter.PBJackpotReqResp", msg)
    )
end


-- 请求更新jackpot值  2022-8-20 10:49:17
function Utils:requestJackpotChange(msg)
    return net.forward(
        STATISTIC_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
        pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_JackpotChangeReqResp"),
        --pb.encode("network.inter.PBJackpotChangeReqResp", msg)
        pb.encode("network.inter.PBGameLog", msg)
    )
end


-- 使用 NotifyServer 向用户透传任意消息
function Utils:pushMsgToUsers(msg)
    return net.forward(
        NOTIFY_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Servers2Notify"),
        pb.enum_id("network.inter.Servers2NotifySubCmdID", "Servers2NotifySubCmdID_PushMsgToUser"),
        pb.encode("network.inter.PBPushMsgToUser", msg)
    )
end

function Utils:broadcastSysChatMsgToAllUsers(msg)
    if not msg then
        return
    end
    local mm = {
        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Chat"),
        subcmd = pb.enum_id("network.cmd.PBChatSubCmdID", "PBChatSubCmdID_NotifySysChatMsg"),
        content = pb.encode("network.cmd.PBNotifySysChatMsg", msg)
    }
    Utils:pushMsgToUsers(mm)
end

function Utils:forwardToGame(serverid, msg)
    return net.forward(
        serverid,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Game"),
        pb.enum_id("network.inter.Game2GameSubCmdID", "Game2GameSubCmdID_ClientForward"),
        pb.encode("network.inter.PBGame2GameClientForward", msg)
    )
end

function Utils:queryProfitResult(msg)
    return net.forward(
        USERINFO_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
        pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_ProfitResultReqResp"),
        pb.encode("network.inter.Game2UserProfitResultReqResp", msg)
    )
end

-- 请求更新盈利信息(未调用该函数)
function Utils:updateProfitInfo(msg)
    if #msg.data > 0 then
        return net.forward(
            USERINFO_SERVER_TYPE,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
            pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_UpdateProfitInfo"),
            pb.encode("network.inter.Game2UserUpdateProfitInfo", msg)
        )
    end
end

function Utils:walletRpc(uid, api, ip, money, reason, linkid, roomtype, roomid, matchid, extrainfo, op)
    local updatemoney = 0
    local updatecoin = 0

    if roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
        updatemoney = money
    elseif roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
        updatecoin = money
    end

    local money_update_msg = {
        op = op or 2,
        srvid = global.sid(),
        roomid = roomid,
        matchid = matchid,
        disable_echo = false,
        data = {}
    }
    table.insert(
        money_update_msg.data,
        {
        uid = uid,
        money = updatemoney,
        coin = updatecoin,
        acid = linkid,
        api = api or "",
        notify = 1,
        reason = reason,
        ip = ip or "",
        extrainfo = extrainfo and cjson.encode(extrainfo) or nil
    }
    )
    --log.dblog("idx(%s,%s) roomtype:%s,%s", roomid, matchid, tostring(roomtype), cjson.encode(money_update_msg))
    Utils:updateMoney(money_update_msg, uid)
end

function Utils:balance(room, state)
    for uid, user in pairs(room.users) do
        if user.state and user.state == state and user.totalbet and user.totalbet == 0 then
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                0,
                0,
                user.linkid,
                room:conf().roomtype,
                room.id,
                room.mid,
                {
                    api = "balance",
                    sid = user.sid,
                    userId = user.userId
                },
                1
            )
        end
    end
end

function Utils:debit(room, reason)
    for uid, user in pairs(room.users) do
        if user.totalbet and user.totalbet > 0 then
            user.isdebiting = true
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                -1 * user.totalbet,
                reason,
                user.linkid,
                room:conf().roomtype,
                room.id,
                room.mid,
                {
                api = "debit",
                sid = user.sid,
                userId = user.userId,
                transactionId = g.uuid(uid),
                roundId = room.logid,
                gameId = tostring(global.stype()),
                bet = user.totalbet,
                fee = user.totalfee,
                time = room.start_time / 1000
            }
            )
        end
    end
end

function Utils:credit(room, reason)
    for uid, user in pairs(room.users) do
        if not user.isdebiting and user.totalbet and user.totalbet > 0 then
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                user.totalprofit,
                reason,
                user.linkid,
                room:conf().roomtype,
                room.id,
                room.mid,
                {
                api = "credit",
                sid = user.sid,
                userId = user.userId,
                transactionId = g.uuid(uid),
                roundId = room.logid,
                gameId = tostring(global.stype()),
                bet = user.totalbet,
                fee = user.totalfee,
                profit = user.totalpureprofit,
                time = room.start_time / 1000
            }
            )
        end
    end
end

--停服补回
function Utils:repay(room, reason)
    for uid, user in pairs(room.users) do
        if user.totalbet and user.totalbet > 0 then
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                user.totalbet,
                reason,
                user.linkid,
                room:conf().roomtype,
                room.id,
                room.mid,
                {
                api = "cancel",
                sid = user.sid,
                userId = user.userId,
                transactionId = g.uuid(uid),
                roundId = room.logid,
                gameId = tostring(global.stype())
            }
            )
        end
    end
end

--该局结算后才debit成功、需要补回
function Utils:debitRepay(room, reason, v, user, showstate)
    if type(v) == "table" and rawget(v, "extrainfo") and v.extrainfo and v.extrainfo ~= "" then
        local extrainfo = rawget(v, "extrainfo") and cjson.decode(v.extrainfo) or nil
        if extrainfo and extrainfo["api"] == "debit" then
            if user then
                user.isdebiting = false
            end
            if extrainfo["roundId"] and (extrainfo["roundId"] ~= room.logid or room.state ~= showstate) then
                if user then
                    user.totalbet = 0
                end
                Utils:walletRpc(
                    v.uid,
                    v.api,
                    v.ip,
                    math.abs(rawget(v, "deltacoin") or 0),
                    reason,
                    v.acid,
                    room:conf().roomtype,
                    room.id,
                    room.mid,
                    {
                    api = "cancel",
                    sid = extrainfo["sid"],
                    userId = extrainfo["userId"],
                    transactionId = g.uuid(v.uid),
                    roundId = extrainfo["roundId"],
                    gameId = tostring(global.stype())
                }
                )
            end
        end
    end
end

--transfer成功后直接离开游戏、需要补回
function Utils:transferRepay(room, reason, v)
    if type(v) == "table" and rawget(v, "extrainfo") and v.extrainfo and v.extrainfo ~= "" then
        local extrainfo = rawget(v, "extrainfo") and cjson.decode(v.extrainfo) or nil
        if v.code > 0 and (v.reason or 0) == pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_BUYINCHIPS") and
            extrainfo and
            extrainfo["api"] == "transfer" and
            extrainfo["roundId"]
        then
            Utils:walletRpc(
                v.uid,
                v.api,
                v.ip,
                math.abs(rawget(v, "deltacoin") or 0),
                reason,
                v.acid,
                room.conf.roomtype,
                room.id,
                room.mid,
                {
                api = "transfer",
                sid = extrainfo["sid"],
                userId = extrainfo["userId"],
                transactionId = g.uuid(v.uid),
                roundId = extrainfo["roundId"]
            }
            )
        end
    end
end

-- 判断是否有与该ip相同的玩家
function Utils:hasIP(room, uid, ip, api)
    if room.conf.checkip and room.conf.checkip <= 0 then
        return false
    end
    if Utils:isRobot(api) then
        return false
    end

    for k, user in pairs(room.users) do
        if user then
            if k ~= uid and user.ip == ip then
                return true
            end
        end
    end
    return false
end

function Utils:mixtureTableInfo(uid, linkid, mid, roomid, serverid)
end

-- 参数 num: 要创建的机器人个数
function Utils:notifyCreateRobot(roomtype, matchid, roomid, num)
    local msg = {
        srvid = global.sid(),
        roomtype = roomtype,
        matchid = matchid,
        roomid = roomid,
        num = num
    }

    return net.forward(
        ROBOT_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Robot"),
        pb.enum_id("network.inter.Game2RobotSubCmdID", "Game2RobotSubCmdID_NotifyCreateRobot"),
        pb.encode("network.inter.PBGame2RobotNotifyCreateRobot", msg)
    )
end

-- PVE游戏通知创建机器人  2022-3-9
-- 参数 num: 要创建的机器人个数
function Utils:notifyCreateRobot2(roomtype, matchid, roomid, num)
    local msg = {
        srvid = global.sid(),
        roomtype = roomtype,
        matchid = matchid,
        roomid = roomid,
        num = num
    }
    log.debug("DQW notifyCreateRobot2() roomid=%s, matchid=%s", roomid, matchid)

    return net.forward(
        ROBOT_SERVER_TYPE, --目的服务器ID
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Robot"),
        pb.enum_id("network.inter.Game2RobotSubCmdID", "Game2RobotSubCmdID_NotifyCreateRobot2"),
        pb.encode("network.inter.PBGame2RobotNotifyCreateRobot", msg)
    )
end

-- 反序列化  将字符串数据转为对象
local function unserialize(key)
    local result = {}
    local data = redis.get(5001, key) -- 获取key对应的数据
    if data then
        data = cjson.decode(data) -- 将json格式数据转换为对象
        for k, v in pairs(data) do -- 遍历表数据
            result[tonumber(k)] = v
        end
    end
    return result -- 返回对象
end

--
local function serialize(key, data)
    redis.set(5001, key, data, true)
end

-- 获取押注信息
-- id: 游戏ID
function Utils:unSerializeMiniGame(room, sid, id)
    if (room.conf and room:conf() and room:conf().global_profit_switch) or not room.conf then
        sid = sid or global.sid()
        id = id or room.id
        if room.total_bets and room.total_profit then
            local key1 = string.format("%d|%d|PLAYER|BETS", sid, id)
            room.total_bets = unserialize(key1)
            local key2 = string.format("%d|%d|PLAYER|PROFIT", sid, id)
            room.total_profit = unserialize(key2)
            log.info(
                "unserialize player %s %s %s %s",
                key1,
                cjson.encode(room.total_bets),
                key2,
                cjson.encode(room.total_profit)
            )
        end
        if room.robottotal_bets and room.robottotal_profit then
            local key1 = string.format("%d|%d|BANKER|BETS", sid, id)
            room.robottotal_bets = unserialize(key1)
            local key2 = string.format("%d|%d|BANKER|PROFIT", sid, id)
            room.robottotal_profit = unserialize(key2)
            log.info(
                "unserialize banker %s %s %s %s",
                key1,
                cjson.encode(room.robottotal_bets),
                key2,
                cjson.encode(room.robottotal_profit)
            )
        end
    end
end

function Utils:serializeMiniGame(room, sid, id)
    if (room.conf and room:conf() and room:conf().global_profit_switch) or not room.conf then
        id = id or room.id
        sid = sid or global.sid()
        if room.total_bets and room.total_profit then
            local key = string.format("%d|%d|PLAYER|BETS", sid, id)
            serialize(key, cjson.encode(room.total_bets))
            key = string.format("%d|%d|PLAYER|PROFIT", sid, id)
            serialize(key, cjson.encode(room.total_profit))
        end
        if room.robottotal_bets and room.robottotal_profit then
            local key = string.format("%d|%d|BANKER|BETS", sid, id)
            serialize(key, cjson.encode(room.robottotal_bets))
            key = string.format("%d|%d|BANKER|PROFIT", sid, id)
            serialize(key, cjson.encode(room.robottotal_profit))
        end
    end
end

-- 在线人数
function Utils:getVirtualPlayerCount(room)
    local playerCount = 0
    for k, user in pairs(room.users) do
        if user then
            playerCount = playerCount + 1
        end
    end
    local onlinenum = #room.onlinelst
    if onlinenum > 0 then
        return onlinenum
    else
        return playerCount
    end

    --[[
    local needUpdate = false
    local interval = 3
    if room:conf() and room:conf().update_interval then
        interval = room:conf().update_interval
    end

    if room.update_games >= interval then -- 检测是否更新
        needUpdate = true
        room.update_games = 0
    end

    local robotCount = 0 -- 机器人总数
    local virtualPlayerCount = 0
    for k, user in pairs(room.users) do
        if user then
            if self:isRobot(user.api) then
                robotCount = robotCount + 1
            else
                virtualPlayerCount = virtualPlayerCount + 1
            end
        end
    end
    if needUpdate then
        room.rand_player_num = rand.rand_between(room:conf().min_player_num * robotCount, room:conf().max_player_num * robotCount)
    end
    virtualPlayerCount = virtualPlayerCount + room.rand_player_num

    local onlinenum = #room.onlinelst
    if onlinenum > virtualPlayerCount then
        virtualPlayerCount = onlinenum + 2
    end

    log.info(
        "[idx:%s,%s] interval=%s, update_games=%s, rand_player_num=%s, min_player_num=%s, max_player_num=%s, onlinenum=%s, virtualPlayerCount=%s",
        room.id,
        room.mid,
        interval,
        room.update_games,
        room.rand_player_num,
        room:conf().min_player_num or 0,
        room:conf().max_player_num or 0,
        onlinenum,
        virtualPlayerCount
    )
    return virtualPlayerCount
    --]]
end

-- 停服操作
function Utils:onStopServer(room)
    -- 通知所有玩家
    pb.encode(
        "network.cmd.PBKickOutNotify",
        { msg = "!!KICKOUT!!" },
        function(pointer, length)
        room:sendCmdToPlayingUsers(
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Notify"),
            pb.enum_id("network.cmd.PBNotifySubCmdID", "PBNotifySubCmdID_KickOutNotify"),
            pointer,
            length
        )
    end
    )
    room:kickout()
end

-------------------------------------------------------
-- 添加机器人
-- 参数 room: 房间对象
-- 参数 robotsInfo: 机器人信息
function Utils:addRobot(room, robotsInfo)
    room.users = room.users or {}
    robotsInfo = robotsInfo or
        {
            { uid = 11, name = "zhang", api = "2001", nickurl = "p_13" },
            { uid = 22, name = "liu", api = "2001", nickurl = "p_12" },
            { uid = 33, name = "T555", api = "2001", nickurl = "p_11" },
            { uid = 44, name = "AJ", api = "2001", nickurl = "p_11" },
            { uid = 55, name = "Qing", api = "2001", nickurl = "p_10" },
            { uid = 66, name = "Jimmy", api = "2001", nickurl = "p_10" },
            { uid = 77, name = "T99", api = "2001", nickurl = "p_10" },
            { uid = 88, name = "T100", api = "2001", nickurl = "p_10" }
        }
    if robotsInfo and type(robotsInfo) == "table" then -- 确保是表类型
        for i = 1, #robotsInfo do
            if not robotsInfo[i] then
                break
            end
            local uid = robotsInfo[i].uid
            -- 查看该玩家是否已在玩家列表中
            if uid and not room.users[uid] then -- 如果未在玩家列表中
                room.users[uid] = {}
                room.users[uid].uid = uid
                room.users[uid].linkid = nil -- 手动增加的机器人将该值设置为nil
                -- local user = room.users[robotsInfo[i].uid]
                -- user.uid = robotsInfo[i].uid
                room.users[uid].api = robotsInfo[i].api or "2001"
                room.users[uid].state = 2     -- EnumUserState.Playing
                -- local balance                       = 1000000 + rand.rand_between(2000, 1000000) -- 随机剩余金额
                local balance                       = self:getRandMoney()
                room.users[uid].money               = balance -- 金币
                room.users[uid].coin                = balance -- 金豆
                room.users[uid].diamond             = balance --
                room.users[uid].playerinfo          = room.users[uid].playerinfo or {}
                room.users[uid].playerinfo.balance  = balance
                room.users[uid].playerinfo.nickname = robotsInfo[i].name or ""
                room.users[uid].playerinfo.username = robotsInfo[i].name or ""
                room.users[uid].playerinfo.nickurl  = robotsInfo[i].nickurl or "p_13"
                --room.users[uid].playerinfo.currency
                room.users[uid].playerinfo.extra    = {}
                room.users[uid].createtime          = global.ctsec() -- 创建时刻(秒)
                room.users[uid].lifetime            = self:getRandLiftTime()   --rand.rand_between(600, 6000) -- 生存时间长度(秒)
                --room.users[uid].playerinfo.extra.ip
                --room.users[uid].playerinfo.extra.api
            end
        end
    end
end

-- 根据概率分布信息获取索引值(值越大，出现的概率越大) 参考：getProbabilityIdx
function Utils:getIndexByProb(prob)
    if type(prob) ~= "table" then
        return 1
    end
    local num = #prob
    local totalValue = 0
    for i = 1, num do
        totalValue = totalValue + prob[i]
    end
    totalValue = math.floor(totalValue)
    if totalValue <= 0 then
        log.debug("DQW getIdxByProb() totalValue <=0")
        return 1
    end
    local r = rand.rand_between(1, totalValue, 3) -- 获取随机值
    for k, v in ipairs(prob) do
        if r <= v then
            return k
        end
        r = r - v
    end
    return 1
end

-- 随机获取下注筹码
function Utils:getBetChip(room, userMoney)
    local confInfo = room:conf()
    if confInfo then
        if confInfo.chips and #confInfo.chips > 0 then
            if not confInfo.robotBetChipProb then
                confInfo.robotBetChipProb = { 1000, 1000, 2000, 1000, 2000, 1000, 1000, 1000 } -- 机器人下注筹码概率
                log.debug("DQW getBetChip() reset confInfo.robotBetChipProb")
            end
            -- -- return confInfo.chips[self:getIdxByProb(confInfo.chips)]
            -- local chip = confInfo.chips[self:getIndexByProb(confInfo.robotBetChipProb)]
            -- if chip <= userMoney then
            --     return chip
            -- end
            -- 余额<200,余额/10 最接近的投注选项筹码
            -- 余额>=200,余额/20 最接近的投注选项筹码
            local chip = confInfo.chips[1]
            local index = 1
            if userMoney < 20000 then
                for i = 2, #confInfo.chips do
                    if confInfo.chips[i] > userMoney/10 then
                        index = i
                        break
                    end
                end
            elseif userMoney < 1000000 then
                for i = 2, #confInfo.chips do
                    if confInfo.chips[i] > userMoney/20 then
                        index = i
                        break
                    end
                end
            else
                for i = 2, #confInfo.chips do
                    if confInfo.chips[i] > userMoney/50 then
                        index = i
                        break
                    end
                end
            end
            if index >= 3 then
                local randV = rand.rand_between(0, 2)
                return confInfo.chips[index - randV]
            elseif index >= 2 then
                local randV = rand.rand_between(0, 1)
                return confInfo.chips[index - randV]
            end

            return chip
        end
    end
    return 100
end

-- 随机获取下注区域
function Utils:getBetArea(room)
    local confInfo = room:conf()
    if confInfo then
        if confInfo.betarea and #confInfo.betarea > 0 then
            if not confInfo.robotBetAreaProb then
                confInfo.robotBetAreaProb = {} -- 机器人下注区域概率
                local total = 0
                for i = 1, #confInfo.betarea do
                    if type(confInfo.betarea[i]) == "table" and confInfo.betarea[i][1] then
                        total = total + confInfo.betarea[i][1]
                    end
                end
                total = total * 100
                for i = 1, #confInfo.betarea do
                    if type(confInfo.betarea[i]) == "table" and confInfo.betarea[i][1] then
                        confInfo.robotBetAreaProb[i] = total / confInfo.betarea[i][1]
                    end
                end
                log.debug("DQW getBetArea() reset confInfo.robotBetAreaProb")
            end

            --return rand.rand_between(1, #confInfo.betarea)
            return self:getIndexByProb(confInfo.robotBetAreaProb)
        end
    end
    return 1 -- 默认是第一个下注区
end

-- 参数 room: 房间对象
-- 参数 current_time: 当前时刻
function Utils:checkCreateRobot(room, current_time, needRobotNum)
    if room.createRobotTimeInterval <= current_time - room.lastCreateRobotTime then
        room.lastCreateRobotTime = current_time -- 上次创建机器人时刻
        -- if room.createRobotTimeInterval < 100 then  -- 间隔时间  秒
        --     room.createRobotTimeInterval = room.createRobotTimeInterval + 5
        -- end
        if room and type(room.conf) == "function" then
            local config = room:conf()
            if config then --
                -- 检测机器人个数
                if type(room.count) == "function" then
                    local allPlayerNum, robotNum = room:count()
                    if allPlayerNum and robotNum and room.id and room.mid then
                        needRobotNum = needRobotNum or 30
                        log.debug("idx(%s,%s) notify create robot %s, %s", room.id, room.mid, allPlayerNum, robotNum)
                        if robotNum < needRobotNum then -- 如果机器人人数不足30人
                            -- Utils:notifyCreateRobot(self:conf().roomtype, self.mid, self.id, 9 - robotNum) -- 动态创建机器人 old
                            local createRobotNum = needRobotNum - robotNum
                            -- if createRobotNum > 10 then
                            --     createRobotNum = 10 -- 每次最多创建10个机器人
                            -- end
                            createRobotNum = rand.rand_between(1,2)  -- 每次创建1-2个机器人
                            if config.roomtype and room.mid and room.id then
                                self:notifyCreateRobot2(config.roomtype, room.mid, room.id, createRobotNum) -- 动态创建机器人
                            end
                        end
                    end
                end
            end
        end
    end
end

-- 机器人下注
function Utils:robotBet(room)
    local confInfo = room:conf()

    if room.state == EnumRoomState.Betting then -- 如果是在下注状态
        -- 遍历所有机器人
        for uid, user in pairs(room.users) do -- 遍历所有玩家
            if user and not user.linkid then  -- 如果是机器人
                -- 获取随机值
                local randValue = rand.rand_between(0, 10000)
                if randValue < 300 then -- 3%的概率下注
                    local betInfo = { idx = {}, data = {} } -- 下注信息
                    betInfo.idx.roomid = room.id
                    betInfo.idx.matchid = room.mid
                    betInfo.data.uid = uid -- 玩家ID
                    betInfo.data.areabet = {} -- 下注区域信息
                    betInfo.data.areabet[1] = {}
                    betInfo.data.areabet[1].bettype = self:getBetArea(room) -- 下注区域
                    betInfo.data.areabet[1].betvalue = self:getBetChip(room, room:getUserMoney(uid)) --下注金额
                    room:userBet(uid, nil, betInfo)
                end
            end
        end
    end
end

--[[
function Utils:requestJackpot(msg)
    return net.forward(
        STATISTIC_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
        pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_JackpotReqResp"),
        pb.encode("network.inter.PBJackpotReqResp", msg)
    )
end

]]
-- 请求获取玩家已玩指定游戏局数  参考requestJackpot(.)
function Utils:queryPlayHand(uid, gameID, matchID, roomID, roomType)
    local msg = { uid = uid, matchid = matchID, roomid = roomID, roomtype = roomType, gameid = gameID }
    return net.forward(
        STATISTIC_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
        pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_PlayHandReqResp"),
        pb.encode("network.inter.PBPlayHandReqResp", msg)
    )
end

-- 请求获取玩家已充值信息
function Utils:queryChargeInfo(userID, gameID, matchID, roomID)
    local msg = { uid = userID, matchid = matchID, roomid = roomID, gameid = gameID }

    return net.forward(
        USERINFO_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
        pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_QueryChargeInfo"),
        pb.encode("network.inter.Game2UserQueryChargeInfo", msg)
    )
end


-- 获取机器人余额
function Utils:getRandMoney()
    --[[
        余额（余额下限-余额上限：概率）
5000-10000:2500 10000-100000:5000 100000-1000000:2000 1000000-10000000:500
    ]]
    local randV = rand.rand_between(1, 10000)
    if randV <= 1500 then
        return rand.rand_between(5000, 10000)
    elseif randV <= 5800 then
        return rand.rand_between(10000, 100000)
    elseif randV <= 8800 then
        return rand.rand_between(100000, 1000000)
    elseif randV <= 9800 then
        return rand.rand_between(1000000, 2000000)
    else
        return rand.rand_between(2000000, 10000000)
    end
end


-- 获取机器人剩余时间
function Utils:getRandLiftTime()
    --离开时间
-- 60-300:1500 300-600:4000 600-1200:3000 1200-3600:1000 3600-7200:500
    local randV = rand.rand_between(1, 10000)
    if randV <= 1500 then
        return rand.rand_between(60, 300)
    elseif randV <= 5500 then
        return rand.rand_between(300, 600)
    elseif randV <= 8500 then
        return rand.rand_between(600, 1200)
    elseif randV <= 9500 then
        return rand.rand_between(1200, 3600)
    else
        return rand.rand_between(3600, 7200)
    end
end
