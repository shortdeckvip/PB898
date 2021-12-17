local pb    = require("protobuf")
local log   = require(CLIBS["c_log"])
local timer = require(CLIBS["c_timer"])

Reservation = {}

function Reservation:new(t, s)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init(t, s)
    return o
end

function Reservation:init(t, s)
    self.table = t
    self.seat = s
    self.chipin_timeout_count = 0
    self.chipin_timeout_round = 0
    self.state = pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Cancel")
    self.is_standup = false
	self.reservation_timer = timer.create()
	self.is_set_rvtimer = false
end

function Reservation:destroy()
    timer.destroy(self.reservation_timer)
end

function Reservation:reset()
    self.chipin_timeout_count = 0
    self.chipin_timeout_round = 0   
    self.state = pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Cancel")
    self.is_standup = false
	self.is_set_rvtimer = false
end

-- 留作的时候，如果玩家自己chipin，会对count和round 清0，但如果是系统帮用户(chipin[大盲,小盲]), 不清0
function Reservation:resetBySys()
    if self.state ~= pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Reserve") and self.state ~= pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Leave") then
        self:reset()
    end   
end

-- 所有的场次超时操作 2(次)就要设置为留座
function Reservation:chipinTimeoutCount()
    local count = 2
	--[[
    if self.table.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBTexasMatchType_Regular") or
        self.table.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBMatchType_SelfRegular")  then
        count = 1
    end
	]]--

    if self.state == pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Cancel") then
        self.chipin_timeout_count = self.chipin_timeout_count + 1
        if self.chipin_timeout_count >= count then
			self:setReservation(pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Leave"))
        end
    end 
    return true
end

-- 普通场留座2(轮)要站起(这个函数只有普通场玩法用)
function Reservation:chipinTimeoutRound()
    if not self.is_standup then
        self.chipin_timeout_round = self.chipin_timeout_round + 1
        if self.chipin_timeout_round >= 2 then
            self.is_standup = true
        end
    end
    return true
end

-- 预留成功或已经留桌都返回true
function Reservation:isReservation()
    return self.state ~= pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Cancel")
end

function Reservation:getReservation()
    return self.state
end

function Reservation:setReservation(s)
    self.state = s
    if self.state == pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Cancel") then
		--[[
		if self.table.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBMatchType_SelfRegular") then
			if self.is_set_rvtimer then
				timer.cancel(self.reservation_timer, 1)
			end
		end
		]]--
        self:reset()
    end
	--[[自建普通场留座 10 分钟后站起
	if self.table.conf.matchtype == pb.enum_id("network.cmd.PBTexasMatchType", "PBMatchType_SelfRegular") then
		if self.state == pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Leave") then
			timer.tick(self.reservation_timer, 1, 10 * 60 * 1000, function(arg)
				timer.cancel(self.reservation_timer, 1)
				if self.state == pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Leave") and self.is_set_rvtimer then
					local stand_type = pb.enum_id("network.cmd.PBTexasStandType", "PBTexasStandType_ReservationOnTimer")
					self.table.match:stand(self.seat.uid, self.table.tid, stand_type)
				end
				self.is_set_rvtimer = false
			end, self)
			self.is_set_rvtimer = true
		end
	end
	]]--
end

function Reservation:isStandup()
    return self.is_standup
end

-- 检查是否立刻留座生效
function Reservation:checkSitResultSuccInTime()
    if self.state == pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Reserve") then
        local result = pb.enum_id("network.cmd.PBTexasLeaveToSitState", "PBTexasLeaveToSitState_Leave")
        self:setReservation(result)
        self.table:notifyReservation(self.seat, result)
    end
end
