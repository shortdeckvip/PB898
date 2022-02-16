local pb = require("protobuf")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local log = require(CLIBS["c_log"])
local redis = require(CLIBS["c_hiredis"])
local cjson = require("cjson")
local g = require("luascripts/common/g")
local rand = require(CLIBS["c_rand"])

--overwrite
Utils = {}
SLOT_INFO = {total_bets = {}, total_profit = {}}

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

function Utils:updateUserInfo(msg)
    return net.forward(
        USERINFO_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
        pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_UserAtomUpdate"),
        pb.encode("network.inter.PBUserAtomUpdate", msg)
    )
end

function Utils:queryUserInfo(msg)
    return net.forward(
        MONEY_SERVER_TYPE,
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

function Utils:updateMoney(msg)
    return net.forward(
        MONEY_SERVER_TYPE,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
        pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_MoneyAtomUpdate"),
        pb.encode("network.inter.PBMoneyAtomUpdate", msg)
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
    Utils:updateMoney(money_update_msg)
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
                    gameId = tostring(global.stype())
                }
            )
        end
    end
end

function Utils:credit(room, reason)
    for uid, user in pairs(room.users) do
        if user.totalbet and user.totalbet > 0 then
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
                    gameId = tostring(global.stype())
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
                    api = "credit",
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
function Utils:debitRepay(room, reason, v, showstate)
    local extrainfo = rawget(v, "extrainfo") and cjson.decode(v.extrainfo) or nil
    if
        extrainfo and extrainfo["api"] == "debit" and extrainfo["roundId"] and
            (extrainfo["roundId"] ~= room.logid or room.state ~= showstate)
     then
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
                api = "credit",
                sid = extrainfo["sid"],
                userId = extrainfo["userId"],
                transactionId = g.uuid(v.uid),
                roundId = extrainfo["roundId"],
                gameId = tostring(global.stype())
            }
        )
    end
end

--transfer成功后直接离开游戏、需要补回
function Utils:transferRepay(room, reason, v)
    local extrainfo = rawget(v, "extrainfo") and cjson.decode(v.extrainfo) or nil
    if
        v.code > 0 and (v.reason or 0) == pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_BUYINCHIPS") and
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

local function unserialize(key)
    local result = {}
    local data = redis.get(5001, key)
    if data then
        data = cjson.decode(data)
        for k, v in pairs(data) do
            result[tonumber(k)] = v
        end
    end
    return result
end
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
        room.rand_player_num =
            rand.rand_between(room:conf().min_player_num * robotCount, room:conf().max_player_num * robotCount)
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
end

-- 停服操作
function Utils:onStopServer(room)
    -- 通知所有玩家
    pb.encode(
        "network.cmd.PBKickOutNotify",
        {msg = "!!KICKOUT!!"},
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
