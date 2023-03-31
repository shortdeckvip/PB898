local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])

-- 进入游戏房间
local function parseIntoGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBIntoGameRoomReq_C", msg) -- 请求进入房间消息
    if not rev then
        log.debug("parseIntoGameRoomReq() uid=%s,linkid=%s not valid msg pass", uid, linkid)
        return
    end
    --print("%s", cjson.encode(rev))
    local rm = MatchMgr:getMatchById(rev.matchid) -- 根据房间级别ID获取房间管理器
    if not rm then
        return
    end

    -- 根据房间ID获取房间
    local r = rm:getRoomById(rev.roomid)
    if not r then
        r = rm:getAvaiableRoom(1, uid) -- 获取一个人数最多的房间
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
        log.debug(
            "parseIntoGameRoomReq(), room not find! uid:%s,gameid=%s, matchid=%s, roomid=%s",
            uid,
            rev.gameid,
            rev.matchid,
            rev.roomid
        )
        return
    end

    log.debug(
        "parseIntoGameRoomReq(), uid:%s,gameid=%s, matchid=%s, roomid=%s",
        uid,
        rev.gameid,
        rev.matchid,
        rev.roomid
    )
    r:userInto(uid, linkid, rev) -- 玩家进入指定房间
end

-- 请求离开房间
local function parseLeaveGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBLeaveGameRoomReq_C", msg)
    if not rev or not rev.idx then
        log.debug("parseLeaveGameRoomReq(), uid=%s, linkid=%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r then
        r:userLeave(uid, linkid)
    else
        log.debug(
            "parseLeaveGameRoomReq(), r==nil, uid=%s, linkid=%s, matchid=%s, roomid=%s",
            uid,
            linkid,
            rev.idx.matchid,
            rev.idx.roomid
        )
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

-- 请求旋转操作
local function parseChipinReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasChipinReq", msg)
    if not rev or not rev.idx then
        log.debug("bet %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)

    if r == nil then
        log.error("no room:%s %s", uid, rev.idx.roomid)
        return
    end
    r:userchipin(uid, rev.chipType, rev.chipinMoney, linkid)
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


-- 请求获取桌子信息
local function parseSlotConfReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBSlotConfReq_C", msg)
    if not rev or not rev.idx then
        log.debug("table info %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)

    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userSlotConfInfo(uid, linkid, rev)
end

Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasTableInfoReq"),
    "",
    parseTableInfoReq
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

Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasChipinReq"),
    "",
    parseChipinReq
)

Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotConfReq"),
    "",
    parseSlotConfReq
)
