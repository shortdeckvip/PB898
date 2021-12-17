local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])

local function parseIntoGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBIntoGameRoomReq_C", msg)
    if not rev then
        log.debug("parseIntoGameRoomReq %s,%s not valid msg pass", uid, linkid)
        return
    end

    log.debug("parseIntoGameRoomReq uid:%s,msg:%s", uid, cjson.encode(rev))

    -- 2021-9-14
    if rev.matchid == 0 and rev.ante ~= 0 then
        local toserverid
        rev.matchid, toserverid = MatchMgr:getMatchByAnte(rev.ante)
        if rev.matchid and rev.matchid ~= 0 then
            rev.roomid = 0
            log.info("rev.ante=%s,rev.matchid=%s find", rev.ante, rev.matchid)
        else
            if toserverid then
                return Utils:forwardToGame(
                    toserverid,
                    {
                        uid = uid,
                        linkid = linkid,
                        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomReq"),
                        data = msg
                    }
                )
            end
        end
    end
    local quick = false
    local rm = MatchMgr:getMatchById(rev.matchid)

    if not rm and rev.matchid == 0 and rev.ante == 0 then
        local toserverid
        rm, rev.roomid, toserverid = MatchMgr:getQuickRoom(rev.money, 5)
        quick = true

        if toserverid then
            return Utils:forwardToGame(
                toserverid,
                {
                    uid = uid,
                    linkid = linkid,
                    maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomReq"),
                    data = msg
                }
            )
        end
    end

    if not rm then
        log.debug("parseIntoGameRoomReq %s,%s not valid matchid", uid, tostring(rev.matchid))
        local t = {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail"),
            idx = {
                srvid = global.sid(),
                roomid = 0
            }
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

    local r
    if not rev.roomid or rev.roomid == 0 then -- 融合桌 rev.roomid 0
        r = rm:getMiniEmptyRoom(uid, rev.ip, rev.api)
    else
        r = rm:getRoomById(rev.roomid)
    end
    if not r then
        local t = {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail"),
            idx = {
                srvid = global.sid(),
                roomid = 0
            }
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

    r:userInto(uid, linkid, rev.matchid, quick, rev.ip, rev.api)

    --print("parseIntoGameRoomReq:", rm,r,rev.matchid)
    log.debug(
        "PBIntoGameRoomReq uid:%s,%s,%s,%s,%s",
        uid,
        rev.gameid,
        rev.matchid,
        tostring(rev.roomid),
        tostring(rev.api)
    )
end

local function parseLeaveGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBLeaveGameRoomReq_C", msg)
    if not rev or not rev.idx then
        log.debug("parseLeaveGameRoomReq %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r then
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

local function parseChipinReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasChipinReq", msg)
    if not rev or not rev.idx then
        log.debug("bet %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("parseChipinReq", rev.idx.matchid, rev.idx.roomid, rev.chipType)
    if r == nil then
        log.error("no room:%s %s", uid, rev.idx.roomid)
        return
    end
    r:userchipin(uid, rev.chipType, rev.chipinMoney, true)
end

local function parseTexasTableInfoReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasTableInfoReq", msg)
    if not rev or not rev.idx then
        log.debug("table info %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("parseTexasTableInfoReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userTableInfo(uid, linkid, rev)
end

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
        local i = {
            serverid = global.sid(),
            matchid = m.mid,
            minchips = m.minbuyinbb
            --sb = BlindConf[m.mid][1].sb,
        }
        table.insert(t.data.data, i)
    end
    local msg1 = pb.encode("network.cmd.PBGameMatchListResp_S", t)
    --print("parseGameMatchListResp_S:", cjson.encode(t))
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameMatchListResp"),
        msg1
    )
end

local function parseChangeGameRoomReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBChangeGameRoom_C", msg)
    if not rev or not rev.idx then
        log.debug("changeroom %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s", rev.idx.roomid)
        return
    end
    local rm = MatchMgr:getMatchById(rev.idx.matchid)
    if not rm then
        return
    end
    --离开原房间，进入新房间
    local ip = r:getUserIp(uid)
    local rto = rm:getDiffRoom(rev.idx.roomid, r.conf.maxuser, uid, ip)
    if rto then
        rto.islock = true
        r:userLeave(uid, 0)
        rto.islock = false
        rto:userInto(uid, linkid, rev.idx.matchid, false, ip)
    else
        local t = {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_Fail")
        }
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_ChangeGameRoomResp"),
            pb.encode("network.cmd.PBChangeGameRoom_S", t)
        )
    end
end

local function parseGameChatReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameChatReq_C", msg)
    if not rev or not rev.idx then
        log.debug("chat %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("parseGameChatReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s", rev.idx.roomid)
        return
    end
    r:userChat(uid, linkid, rev)
end

local function parseGameToolSendReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameToolSendReq_C", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("parseGameToolSendReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s", rev.idx.roomid)
        return
    end
    r:userTool(uid, linkid, rev)
end

local function parseShowCardReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasShowDealCardReq", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("PBTexasShowDealCardReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userShowCard(uid, linkid, rev)
end

local function parseTexasStandReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasStandReq", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("PBTexasStandReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userStand(uid, linkid, rev)
end

local function parseTexasSitReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasSitReq", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("PBTexasSitReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userSit(uid, linkid, rev)
end

local function parseTexasBuyinReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasBuyinReq", msg)
    --print(cjson.encode(rev))
    if not rev or not rev.idx then
        log.debug("texas buyin %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userBuyin(uid, linkid, rev)
end

local function parseTexasSituationReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasSituationReq", msg)
    if not rev or not rev.idx then
        log.debug("texas situation %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userSituation(uid, linkid, rev)
end

local function parseTexasReviewReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasReviewReq", msg)
    if not rev or not rev.idx then
        log.debug("texas review %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userReview(uid, linkid, rev)
end

local function parseTexasPreOperateReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasPreOperateReq", msg)
    if not rev or not rev.idx then
        log.debug("texas preoperate %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userPreOperate(uid, linkid, rev)
end

local function parseTexasAddTimeReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasAddTimeReq", msg)
    if not rev or not rev.idx then
        log.debug("addtime %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("parseTexasAddTimeReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userAddTime(uid, linkid, rev)
end

local function parseTexasEnforceShowCardReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasEnforceShowCardReq", msg)
    if not rev or not rev.idx then
        log.debug("enforce show card %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if not r then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userEnforceShowCard(uid, linkid, rev)
end

local function parseTexasNextRoundPubCardReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasNextRoundPubCardReq", msg)
    if not rev or not rev.idx then
        log.debug("next round pub card %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if not r then
        log.error("not room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userNextRoundPubCardReq(uid, linkid, rev)
end

local function parseTexasTableListInfoReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasTableListInfoReq", msg)
    if not rev or not rev.matchid or not rev.roomid then
        log.debug("parseTexasTableListInfoReq %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
    if not r then
        Utils:mixtureTableInfo(uid, linkid, rev.matchid, rev.roomid, rev.serverid)
        return
    end
    r:userTableListInfoReq(uid, linkid, rev)
end

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
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasTableInfoReq"),
    "",
    parseTexasTableInfoReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasChipinReq"),
    "",
    parseChipinReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasShowDealCardReq"),
    "",
    parseShowCardReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasStandReq"),
    "",
    parseTexasStandReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitReq"),
    "",
    parseTexasSitReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameMatchListReq"),
    "",
    parseGameMatchListReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasBuyinReq"),
    "",
    parseTexasBuyinReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSituationReq"),
    "",
    parseTexasSituationReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasReviewReq"),
    "",
    parseTexasReviewReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPreOperateReq"),
    "",
    parseTexasPreOperateReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasAddTimeReq"),
    "",
    parseTexasAddTimeReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasEnforceShowCardReq"),
    "",
    parseTexasEnforceShowCardReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasNextRoundPubCardReq"),
    "",
    parseTexasNextRoundPubCardReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_ChangeGameRoomReq"),
    "",
    parseChangeGameRoomReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameChatReq"),
    "",
    parseGameChatReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameToolSendReq"),
    "",
    parseGameToolSendReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasTableListInfoReq"),
    "",
    parseTexasTableListInfoReq
)
