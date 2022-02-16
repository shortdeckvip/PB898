local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local timer = require(CLIBS["c_timer"])
local mutex = require(CLIBS["c_mutex"])

local function parseQueryUserInfo(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBQueryUserInfo", msg)
    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
    if r then
        r:userQueryUserInfo(rev.uid, true, rev.ud)
    end
end

local function parseWalletOpResp(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBMoneyAtomUpdate", msg)
    --log.info("parseWalletOpResp:%s", cjson.encode(rev))
    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
    if r and r.userWalletResp then
        r:userWalletResp(rev)
    end
end

local function parseJackPotUserWinning(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBStatisticJackpotUserWinning", msg)
    --print("PBStatisticJackpotUserWinning", cjson.encode(msg))
    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
    if r and r:userJackPotResp(rev.uid, rev) then
        return true
    end
    local money_update_msg = {
        op = 2,
        data = {}
    }
    table.insert(
        money_update_msg.data,
        {
            uid = msg.uid,
            money = msg.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") and rev.value or 0,
            coin = msg.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") and rev.value or 0,
            notify = 1
        }
    )
    Utils:updateMoney(money_update_msg)
    log.info("reward the jackpot to user %s", cjson.encode(money_update_msg))
end

local function parseJackpotUpdate(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBJackpotReqResp", msg)
    --log.info("jackpot update infos %s", cjson.encode(rev.data))
    JackpotMgr:onJackpotUpdate(rev.data)
    --[[
	for _,v in ipairs(rev.data) do
		if v.value and v.value > 0 then
			local rooms = MatchMgr:getAllRoomsByJackpotId(v.id)
			for _,vv in ipairs(rooms) do
				vv:onJackpotUpdate(v.value)
			end
		end
	end
	--]]
    --
end

local function parseGame2GameForward(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBGame2GameClientForward", msg)

    log.info("parseGame2GameForward %s %s %s %s", rev.uid, tostring(rev.linkid), rev.maincmd, rev.subcmd)
    Dispatch(rev.uid, rev.linkid, rev.maincmd, rev.subcmd, rev.data)
end

local function parseGame2GameToolsForward(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBGame2GameToolsForward", msg)
    if rev.matchid == 0 and rev.roomid == 0 then
        log.info("parseGame2GameToolsForward  rev.jdata = %s", rev.jdata)
        MatchMgr:notifyStopServer(rev.jdata) -- 通知关服等
    else
        local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
        if r and type(r.tools) == "function" then
            r:tools(rev.jdata)
        end
    end
end

local function parseUser2GameAtomUpdateForward(srvid, linkid, msg)
    local rev = pb.decode("network.inter.PBUserAtomUpdate", msg)

    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
    if r and type(r.kvdata) == "function" then
        r:kvdata(rev.data)
    end
end

local function parseUser2GameProfitResultReqResp(srvid, linkid, msg)
    local rev = pb.decode("network.inter.Game2UserProfitResultReqResp", msg)

    local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
    if r and type(r.queryUserResult) == "function" then
        r:queryUserResult(true, rev.data)
    end
end

Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
    pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_QueryUserInfo"),
    "",
    parseQueryUserInfo
)
Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Money"),
    pb.enum_id("network.inter.Game2MoneySubCmd", "Game2MoneySubCmd_MoneyAtomUpdate"),
    "",
    parseWalletOpResp
)
Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
    pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_JackpotUserWinning"),
    "",
    parseJackPotUserWinning
)
Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Statistic"),
    pb.enum_id("network.inter.Game2StatisticSubCmd", "Game2StatisticSubCmd_JackpotReqResp"),
    "",
    parseJackpotUpdate
)

Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Game"),
    pb.enum_id("network.inter.Game2GameSubCmdID", "Game2GameSubCmdID_ClientForward"),
    "",
    parseGame2GameForward
)

Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Game"),
    pb.enum_id("network.inter.Game2GameSubCmdID", "Game2GameSubCmdID_ToolsForward"),
    "",
    parseGame2GameToolsForward
)

Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
    pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_UserAtomUpdate"),
    "",
    parseUser2GameAtomUpdateForward
)

Forward_Register(
    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2UserInfo"),
    pb.enum_id("network.inter.Game2UserInfoSubCmd", "Game2UserInfoSubCmd_ProfitResultReqResp"),
    "",
    parseUser2GameProfitResultReqResp
)
