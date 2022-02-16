local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])

local function parseGameMatchListReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameMatchListReq_C", msg)
    if not rev then
        log.debug("matchlist %s,%s not valid msg pass", uid, linkid)
        return
    end

    local t = {
        gameid = global.stype(),
        data = {data = {}}
    }
    local conf = MatchMgr:getConf() or {}
    for k, m in ipairs(conf) do
        table.insert(
            t.data.data,
            {
                serverid = global.sid(),
                matchid = m.mid,
                minchips = m.limit_min,
                online = MatchMgr:getUserNumByMid(m.mid),
                name = m.name
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

local function parseIntoGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBIntoGameRoomReq_C", msg)
    if not rev then
        log.debug("parseIntoGameRoomReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end
    log.debug("parseIntoGameRoomReq() uid=%s, matchid=%s, roomid=%s", uid, tostring(rev.matchid), tostring(rev.roomid))
    --print("%s", cjson.encode(rev))
    local rm = MatchMgr:getMatchById(rev.matchid)
    if not rm then
        log.error(
            "parseIntoGameRoomReq() uid=%s, matchid=%s, roomid=%s, rm=nil",
            uid,
            tostring(rev.matchid),
            tostring(rev.roomid)
        )
        return
    end

    local r = rm:getRoomById(rev.roomid)

    if (rev.roomid or 0) == 0 and not r then
        r = rm:getAvaiableRoom(500, uid)
    end

    if not r then
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

    r:userInto(uid, linkid, rev)
    log.debug("PBIntoGameRoomReq_C uid:%s,%s", uid, rev.gameid)
end

local function parseLeaveGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBLeaveGameRoomReq_C", msg)
    if not rev or not rev.idx then
        log.debug("parseLeaveGameRoomReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end

    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r ~= nil then
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

local function parseBetReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBDragonTigerBetReq_C", msg)
    if not rev or not rev.idx then
        log.debug("user bet request %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.debug("not find room %s,%s", tostring(rev.idx.matchid), tostring(rev.idx.roomid))
        return
    end
    r:userBet(uid, linkid, rev)
end

local function parseHistoryReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBDragonTigerHistoryReq_C", msg)
    if not rev or not rev.idx then
        log.debug("network.cmd.PBDragonTigerHistoryReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.debug("not find room")
        return
    end
    r:userHistory(uid, linkid, rev)
end

local function parseOnlineListReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBDragonTigerOnlineListReq_C", msg)
    if not rev or not rev.idx then
        log.debug("network.cmd.PBDragonTigerOnlineListReq_C %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.debug("not find room")
        return
    end
    r:userOnlineList(uid, linkid, rev)
end

local function parseBankReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameOpBank_C", msg)
    if not rev or not rev.idx then
        log.debug("network.cmd.PBGameOpBank_C %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if not r then
        log.debug("parseBankReq not find room(%s,%s)", tostring(rev.idx.matchid), tostring(rev.idx.roomid))
        return
    end
    r:userBankOpReq(uid, linkid, rev)
end

--local function parseGameInfoReq(uid, linkid, msg)
--local rev = pb.decode("network.cmd.PBGameInfoReq", msg)
--if not rev or not rev.idx then
--log.debug("gameinfo %s,%s not valid msg pass", uid,linkid)
--return
--end

--log.debug("PBGameInfoReq: %s", cjson.encode(rev))
--local r = MatchMgr:getRoomById(rev.idx.matchid,rev.idx.roomid)
--if r == nil then
--log.error("no room:%s", rev.idx.roomid)
--return
--end
--r:userGameInfo(uid, linkid, rev)
--end

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
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerBetReq"),
    "",
    parseBetReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerHistoryReq"),
    "",
    parseHistoryReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_DragonTigerOnlineListReq"),
    "",
    parseOnlineListReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameOpBankReq"),
    "",
    parseBankReq
)
