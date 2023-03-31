-- serverdev\luascripts\servers\52\usermsg.lua

local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])


-- 请求获取房间列表信息
local function parseGameMatchListReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameMatchListReq_C", msg)
    if not rev then
        log.debug("matchlist %s,%s not valid msg pass", uid, linkid)
        return
    end

    local t = {
        gameid = global.stype(), -- 游戏ID
        data = {data = {}}
    }
    local conf = MatchMgr:getConf() or {}
    for k, m in ipairs(conf) do
        table.insert(
            t.data.data,
            {
                serverid = global.sid(), -- 服务器ID ?
                matchid = m.mid, -- 房间级别(1：初级场 2：中级场)
                minchips = m.limit_min,
                online = MatchMgr:getUserNumByMid(m.mid), -- 在线玩家数
                name = m.name -- 房间名，初级场
            }
        )
    end
    log.debug("PBGameMatchListResp_S", cjson.encode(t))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameMatchListResp"),
        pb.encode("network.cmd.PBGameMatchListResp_S", t)
    )
end

-- 进入游戏房间
local function parseIntoGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBIntoGameRoomReq_C", msg) -- 请求进入房间消息
    if not rev then
        log.debug("parseIntoGameRoomReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end
    log.debug("parseIntoGameRoomReq(): uid=%s, matchid=%s, roomid=%s", uid, rev.matchid, rev.roomid)
    --print("%s", cjson.encode(rev))
    local rm = MatchMgr:getMatchById(rev.matchid) -- 根据房间级别ID获取房间管理器
    if not rm then
        log.debug("parseIntoGameRoomReq() rm=nil uid=%s",uid)
        return
    end

    -- 根据房间ID获取房间
    local r = rm:getRoomById(rev.roomid)

    if (rev.roomid or 0) == 0 and not r then
        r = rm:getAvaiableRoom(500, uid) -- 获取一个人数最多的房间
    end

    if not r then -- 获取房间失败
        local t = {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
        }
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
        )
        return
    end

    r:userInto(uid, linkid, rev) -- 玩家进入指定房间
    log.debug("PBIntoGameRoomReq_C uid:%s,gameid=%s", uid, rev.gameid)
end

-- 玩家离开房间
local function parseLeaveGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBLeaveGameRoomReq_C", msg)
    if not rev or not rev.idx then
        log.debug("parseLeaveGameRoomReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end

    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r ~= nil then -- 如果房间存在
        r:userLeave(uid, linkid)
    else
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            pb.encode(
                "network.cmd.PBLeaveGameRoomResp_S",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")}
            )
        )
    end
end

-- 处理下注请求
-- 参数 uid: 玩家ID
-- 参数 linkid:
-- 参数 msg: 下注请求消息
local function parseBetReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBCrashBetReq_C", msg) -- 解析消息包
    if not rev or not rev.idx then
        log.debug("user bet request %s,%s not valid msg pass", uid, linkid)
        return
    end

    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid) -- 获取房间
    if r == nil then -- 如果未找到指定房间
        log.debug("not find room %s,%s", tostring(rev.idx.matchid), tostring(rev.idx.roomid))
        return
    end

    r:userBet(uid, linkid, rev)
end


local function parseCancelBetReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBCrashCancelBetReq_C", msg) -- 解析消息包
    if not rev or not rev.idx then
        log.debug("user cancel bet request %s,%s not valid msg pass", uid, linkid)
        return
    end

    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid) -- 获取房间
    if r == nil then -- 如果未找到指定房间
        log.debug("not find room %s,%s", tostring(rev.idx.matchid), tostring(rev.idx.roomid))
        return
    end

    r:userCancelBet(uid, linkid, rev)
end


-- 历史记录
local function parseHistoryReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBCrashHistoryReq_C", msg)
    if not rev or not rev.idx then
        log.debug("network.cmd.PBCrashHistoryReq_C uid=%s,linkid=%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then -- 房间不存在
        log.debug("not find room")
        return
    end
    r:userHistory(uid, linkid, rev)
end

-- 在线列表
local function parseOnlineListReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBPveOnlineListReq_C", msg)
    if not rev or not rev.idx then
        log.debug("network.cmd.PBPveOnlineListReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.debug("not find room")
        return
    end
    r:userOnlineList(uid, linkid, rev)
end


-- 请求获取桌子信息
local function parseTableInfoReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasTableInfoReq", msg)
    if not rev or not rev.idx then
        log.debug("table info %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)

    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userTableInfo(uid, linkid, rev)
end

-- 处理停止请求
-- 参数 uid: 玩家ID
-- 参数 linkid:
-- 参数 msg: 下注请求消息
local function parseStopReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBCrashStopReq_C", msg) -- 解析消息包
    if not rev or not rev.idx then
        log.debug("parseStopReq(), user stop request %s,%s not valid msg pass", uid, linkid)
        return
    end
    log.debug("parseStopReq(), uid=%s, PBCrashStopReq_C=%s", uid, cjson.encode(rev))

    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid) -- 获取房间
    if r == nil then -- 如果未找到指定房间
        log.debug("not find room %s,%s", tostring(rev.idx.matchid), tostring(rev.idx.roomid))
        return
    end

    r:userStop(uid, linkid, rev)
end

---------------------------------------------------------------------------

Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasTableInfoReq"),
    "",
    parseTableInfoReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameMatchListReq"),
    "",
    parseGameMatchListReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomReq"),
    "",
    parseIntoGameRoomReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomReq"),
    "",
    parseLeaveGameRoomReq
)
--Register(pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"), pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameInfoReq"), "", parseGameInfoReq)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashBetReq"),
    "",
    parseBetReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashCancelBetReq"),
    "",
    parseCancelBetReq
)

Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashHistoryReq"),
    "",
    parseHistoryReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_PveOnlineListReq"),
    "",
    parseOnlineListReq
)

Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_CrashStopReq"),
    "",
    parseStopReq
)



