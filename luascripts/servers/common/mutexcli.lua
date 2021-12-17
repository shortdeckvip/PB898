local pb = require("protobuf")
local log= require(CLIBS["c_log"])
local cjson = require("cjson")
local mutex = require(CLIBS["c_mutex"])

local function parseMutexCheck(linkid, msg)
	local rev = pb.decode("network.cmd.PBMutexCheck", msg)
	local r = MatchMgr:getRoomById(rev.matchid, rev.roomid)
	if r then
		r:userMutexCheck(rev.uid, rev.code)
	end
end

local function parsePlazaCheckSeatStatusReq(linkid, msg)
	local rev = pb.decode("network.cmd.PBMutexPlazaCheckSeatStatusReq", msg)
	log.debug("PBMutexPlazaCheckSeatStatusReq %s %s %s", tostring(rev.servervid), tostring(rev.targetusername), tostring(rev.requestusername))

	local isAbleFollow = false
	for mid, m in pairs(MatchMgr:getMatchMgr()) do
		local conf = MatchMgr:getConfByMid(mid)
		if conf.gamevid and rev.servervid == conf.gamevid then
			for roomid, r in pairs(MatchMgr:getMatchById(mid):getRoomMgr()) do
				local requid = r:getUidByUsername(rev.requestusername)
				local targetuid = r:getUidByUsername(rev.targetusername)
				log.debug("requid %s targetuid %s", tostring(requid), tostring(targetuid))
				if requid and targetuid then
					isAbleFollow = r:isAbleFollow(requid, targetuid)
					log.debug("isAbleFollow %s", tostring(isAbleFollow))
					goto labelbreakloop
				end
			end
		end
	end

	::labelbreakloop::
	local send = {
		requestusername	= rev.requestusername,
		targetusername	= rev.targetusername,
		isAbleFollow	= isAbleFollow,
	}
	--print(cjson.encode(send))
	mutex.request(pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"), pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexPlazaCheckSeatStatusResp"), pb.encode("network.cmd.PBMutexPlazaCheckSeatStatusResp", send))
end

local function parseUserMoneyUpdateReq(linkid, msg)
	local rev = pb.decode("network.cmd.PBMutexUserMoneyUpdateNotify", msg)
    if not rev then
        log.debug("parseUserMoneyUpdateReq %s not valid msg pass", linkid)
        return
    end
	log.debug("parseUserMoneyUpdateReq %s", cjson.encode(rev))
    local r = MatchMgr:getRoomById(rev.mid, rev.roomid)
    if r then
        r:phpMoneyUpdate(rev.uid, rev)
    end
end

Mutexcli_Register(pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"), pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexCheck"), "", parseMutexCheck)
Mutexcli_Register(pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"), pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexPlazaCheckSeatStatusReq"), "", parsePlazaCheckSeatStatusReq)
Mutexcli_Register(pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"), pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexUserMoneyUpdateNotify"), "", parseUserMoneyUpdateReq)
