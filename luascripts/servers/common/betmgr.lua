local timer	= require(CLIBS["c_timer"])
local global= require(CLIBS["c_global"])
local cjson	= require("cjson")
local log	= require(CLIBS["c_log"])

local TimerID = {
    TimerID_Timeout	= { 1, 5000 }, 	--id, interval(ms), timestamp(ms)
}

BetMgr = BetMgr or {}

function BetMgr:new(roomid, matchid)
	local o = {roomid = roomid, matchid = matchid}
	o.mgr = {}
	setmetatable(o, self)
	self.__index = self
	return o
end

local function onBetReqTimeout(usermgr)
    --print("onBetReqTimeout", uid, usermgr, usermgr.co, usermgr.TimerID_Timeout)
    if usermgr and usermgr.TimerID_Timeout then
        --print(usermgr, timer)
        timer.cancel(usermgr.TimerID_Timeout, TimerID.TimerID_Timeout[1])
        coroutine.resume(usermgr.co, false, nil)
		usermgr.self:checkBet(usermgr.uid)
    end
end

function BetMgr:userBetResp(success, uid, jdata)
	local usermgr = self.mgr[uid]
	if usermgr and usermgr.TimerID_Timeout then
		timer.cancel(usermgr.TimerID_Timeout, TimerID.TimerID_Timeout[1])
		coroutine.resume(usermgr.co, success, jdata)
		self:checkBet(uid)
	end
end

function BetMgr:userBet(uid, usermgr)
	assert(uid > 0 and usermgr)
	usermgr.co = coroutine.create(function(usermgr)
		usermgr.isbetting = true
		local que_item = table.remove(usermgr.que, 1)
		local reqdata = que_item.reqdata
		local extra = que_item.extra
		log.debug("user bet coroutine start : %s", tostring(cjson.encode(reqdata)))
		Utils:sendRequestToWallet({
			uid		= uid,
			roomid	= self.roomid,
			matchid	= self.matchid,
			request	= "game/bet",
			jdata	= cjson.encode(reqdata),
		})
		local succ, respdata = coroutine.yield()
		log.debug("user bet coroutine end : %s,%s", tostring(succ), tostring(respdata))
		usermgr.isbetting = false
		extra.room:onBetResp(uid, succ, reqdata, respdata and cjson.decode(respdata) or nil, extra)
	end)
	coroutine.resume(usermgr.co, usermgr)
	timer.tick(usermgr.TimerID_Timeout, TimerID.TimerID_Timeout[1], TimerID.TimerID_Timeout[2], onBetReqTimeout, usermgr)
end

function BetMgr:checkBet(uid)
	assert(self.mgr[uid] and self.mgr[uid].que)
	--print('checkBet', self, uid)
	--print('self.mgr[uid]', cjson.encode(self.mgr[uid].que), self.mgr[uid].isbetting)

	local usermgr = self.mgr[uid]
	if not usermgr.isbetting then -- 不在下注状态
		if #usermgr.que > 0 then 
			self:userBet(uid, usermgr)
		else
			-- 清理工作
			if usermgr.TimerID_Timeout then
				timer.destroy(usermgr.TimerID_Timeout)
			end
			self.mgr[uid] = nil
			--print('checkBet 清理 uid', uid)
		end
	end
end

-- 判断用户队列是否为空
-- @return empty:
--	true - 玩家下注队列为空
--	false - 玩家下注队列非空
function BetMgr:isUserBetQueEmpty(uid)
	return (self.mgr[uid] == nil)
end

-- 清空用户队列
function BetMgr:clearUserBetQue(uid)
	local usermgr = self.mgr[uid]
	if usermgr then
		usermgr.que = {}
	end
	--print('clearUserBetQue 清理 uid', uid)
end

-- 下注数据压入到队列
-- @param uid number: 用户 uid
-- @param reqdata table: wallet bet 下注请求数据
-- @param extra table: 回传携带数据
function BetMgr:userPushBetReq(uid, reqdata, extra)
	self.mgr[uid] = self.mgr[uid] or {
		uid			= uid,
		self		= self,
		que			= {},		-- 下注队列
		isbetting	= false,	-- 下注锁
		TimerID_Timeout = timer.create(),	-- 下注超时定时器
	}
	table.insert(self.mgr[uid].que, {reqdata = reqdata, extra = extra})
	self:checkBet(uid)
end
