local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])

-- dqw 玩家请求进入房间 消息处理
local function parseIntoGameRoomReq(uid, linkid, msg)
    log.info("parseIntoGameRoomReq(...) uid=%s", uid)
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
    local rm = MatchMgr:getMatchById(rev.matchid)
    if not rm and rev.matchid == 0 and rev.ante == 0 then -- 房间管理器不存在
        local toserverid
        rm, rev.roomid, toserverid = MatchMgr:getQuickRoom(rev.money, 1)

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

    if not rm then -- 房间管理器不存在
        log.debug("parseIntoGameRoomReq  uid=%s, rev.money=%s, rev.matchid=%s not valid matchid", uid, tostring(rev.money), tostring(rev.matchid))
        local t = {
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail"), -- 进入房间失败
            idx = {
                srvid = global.sid(),
                roomid = 0
            }
        }
        net.send( -- 返回进入房间失败消息
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
            code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
        }
        net.send( -- 返回进入房间失败消息
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
            pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
        )
        return
    end

    r:userInto(uid, linkid, rev.matchid, false, rev.ip, rev.api)

    --print("parseIntoGameRoomReq:", rm,r,rev.matchid)
    log.debug(
        "PBIntoGameRoomReq uid=%s,gameid=%s,matchid=%s,roomid=%s,api=%s",
        uid,
        rev.gameid,
        rev.matchid,
        tostring(rev.roomid),
        tostring(rev.api)
    )
end

-- dqw 玩家请求离开房间消息处理
local function parseLeaveGameRoomReq(uid, linkid, msg)
    log.info("parseLeaveGameRoomReq(...), uid=%s", uid)
    local rev = pb.decode("network.cmd.PBLeaveGameRoomReq_C", msg)
    if not rev or not rev.idx then
        log.debug("parseLeaveGameRoomReq %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid) -- 根据ID获取具体的房间
    if r then
        r:userLeave(uid, linkid, true)
    else
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            pb.encode(
                "network.cmd.PBLeaveGameRoomResp_S",
                {code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")} -- 默认离开成功
            )
        )
        log.info("parseLeaveGameRoomReq(...) LeaveGameSuccess")
    end
end

-- dqw 请求出牌
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
    r:userchipin(uid, rev.chipType, rev.chipinMoney, true)
end

-- dqw 请求牌桌信息(具体某一桌信息).
local function parseDominoTableInfoReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasTableInfoReq", msg)
    if not rev or not rev.idx then
        log.debug("table info %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    --print("parseDominoTableInfoReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    log.info("parseDominoTableInfoReq(...) uid=%s", uid)
    r:userTableInfo(uid, linkid, rev)
end

-- dqw 请求获取房间类型列表
local function parseGameMatchListReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameMatchListReq_C", msg)
    if not rev then
        log.debug("matchlist %s,%s not valid msg pass", uid, linkid)
        return
    else
        log.debug("rev=%s", cjson.encode(rev))
    end

    local t = {
        gameid = global.stype(), -- 游戏ID  36 ?
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
    log.info("parseGameMatchListResp_S:%s", cjson.encode(t))

    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameMatchListResp"),
        msg1
    )
end

-- dqw 请求换房间
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
    local rto = rm:getDominoRoom(r.id, r.conf.maxuser, uid, ip) -- Utils:isRobot(uid))

    if rto then
        log.info("parseChangeGameRoomReq(...) uid=%s,rto.id=%s", uid, tostring(rto.id))
        rto.islock = true
        r:userLeave(uid, 0)
        rto.islock = false
        rto:userInto(uid, linkid, rev.idx.matchid, false, ip)
    else
        log.info("parseChangeGameRoomReq(...) uid=%s failed", uid)
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

-- dqw 请求聊天
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

-- dqw 请求发送工具?
local function parseGameToolSendReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBGameToolSendReq_C", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid) -- 获取具体房间
    --print("parseGameToolSendReq", rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s", rev.idx.roomid)
        return
    end
    r:userTool(uid, linkid, rev)
end

-- 请求接收 实时牌局
local function parseDominoReviewReq(uid, linkid, msg)
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

-- dqw 请求预操作 ？
local function parseDominoPreOperateReq(uid, linkid, msg)
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

-- dqw 请求桌子列表信息?
local function parseDominoTableListInfoReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasTableListInfoReq", msg)
    if not rev or not rev.matchid or not rev.roomid then
        log.debug("parseDominoTableListInfoReq %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid) -- 具体房间
    if not r then
        Utils:mixtureTableInfo(uid, linkid, rev.matchid, rev.roomid, rev.serverid)
        return
    end
    r:userTableListInfoReq(uid, linkid, rev)
end

-- dqw 请求增加思考时间
local function parseDominoAddTimeReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasAddTimeReq", msg)
    if not rev or not rev.idx then
        log.debug("addtime %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userAddTime(uid, linkid, rev)
end

local function parseDominoStandReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasStandReq", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userStand(uid, linkid, rev)
end

local function parseDominoSitReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasSitReq", msg)
    if not rev or not rev.idx then
        log.debug("tool %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userSit(uid, linkid, rev)
end

local function parseDominoBuyinReq(uid, linkid, msg)
    local rev = pb.decode("network.cmd.PBTexasBuyinReq", msg)
    if not rev or not rev.idx then
        log.debug("domino buyin %s,%s not valid msg pass", uid, linkid)
        return
    end
    local r = MatchMgr:getRoomById(rev.idx.matchid, rev.idx.roomid)
    if r == nil then
        log.error("no room:%s,%s", uid, rev.idx.roomid)
        return
    end
    r:userBuyin(uid, linkid, rev)
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
    parseDominoTableInfoReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasChipinReq"),
    "",
    parseChipinReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameMatchListReq"),
    "",
    parseGameMatchListReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasStandReq"),
    "",
    parseDominoStandReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasSitReq"),
    "",
    parseDominoSitReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasBuyinReq"),
    "",
    parseDominoBuyinReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasReviewReq"),
    "",
    parseDominoReviewReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasPreOperateReq"),
    "",
    parseDominoPreOperateReq
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
    parseDominoTableListInfoReq
)
Register(
    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_TexasAddTimeReq"),
    "",
    parseDominoAddTimeReq
)
