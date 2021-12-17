local pb    = require("protobuf")
local log   = require(CLIBS["c_log"])
local timer = require(CLIBS["c_timer"])
local global = require(CLIBS["c_global"])

Blind = Blind or {}

local TimerID = {
	TimerID_UpBlind       = {1,1000},      --id, interval(ms), timestamp(ms)
}

--盲注表
BlindConf = {
	[1] = {
		{ante=50, sb=50, bb=100, time=60, minchips=10,},
	},
	[2] = {
		{ante=100, sb=100, bb=200, time=60, minchips=10,},
	},
	[3] = {
		{ante=200, sb=200, bb=400, time=60, minchips=10,},
	},
	[4] = {
		{ante=300, sb=300, bb=600, time=60, minchips=10,},
	},
	[5] = {
		{ante=1000, sb=1000, bb=2000, time=60, minchips=10,},
	},
}

function Blind:new(o)
	o = o or {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    return o    
end

function Blind:init()
    --[[
    self.blind_open = true
    self.blind_conf = {}
    table.insert(self.blind_conf, {level=1,sb=25,bb=50,ante=0,time=10,minchips=1})
    table.insert(self.blind_conf, {level=2,sb=50,bb=100,ante=0,time=10,minchips=1})
    table.insert(self.blind_conf, {level=3,sb=100,bb=200,ante=0,time=10,minchips=1})
    table.insert(self.blind_conf, {level=4,sb=200,bb=400,ante=0,time=10,minchips=1})
    --]]

    
    --self.table = t
    self.blind_starttime = 0 -- 每个level开始涨盲时间戳(单位:秒)
    self.blind_level = 1     -- 盲注等级
    self.blind_timer = timer.create()
    
    self.blind_conf = BlindConf[self.id]
    if not self.blind_conf then
        log.debug("blind_conf is nil, matchid:%s", self.id)
    end
end

function Blind:reset()
    self.blind_starttime = 0
    self.blind_level = 1
end

function Blind:getBlindBB()
    local conf = self.blind_conf[self.blind_level]
    return conf and conf.bb or 0
end

function Blind:getBlindSB()
    local conf = self.blind_conf[self.blind_level]
    return conf and conf.sb or 0
end

function Blind:getBlindAnte()
    local conf = self.blind_conf[self.blind_level]
    return conf and conf.ante or 0
end

function Blind:getBlindTime()
    local conf = self.blind_conf[self.blind_level]
    return conf and conf.time or 0
end

function Blind:getBlindMinchips()
    local conf = self.blind_conf[self.blind_level]
    return conf and conf.minchips or 0
end

-- level 超过 max, return nil
function Blind:getBlindConfByLevel(level)
    return self.blind_conf[level]
end

function Blind:startUpBlind()
    log.debug("blind startUpBlind")
    if not self.blind_conf.blind_open then
        log.debug("blind_open is close")
        return true
    end
    
    local function onBlindTimer(arg)
        local blind = arg
        log.debug("onBlindTimer ... now_lv:%s #self.blind_conf:%s", blind.blind_level, #self.blind_conf)
        
        timer.cancel(blind.blind_timer, TimerID.TimerID_UpBlind[1])
        if blind.blind_level < #self.blind_conf then
            local old_level = blind.blind_level
            blind.blind_level = blind.blind_level + 1
            blind.blind_starttime = global.ctsec()
            
            local t = blind:getBlindTime() * 1000
            timer.tick(blind.blind_timer, TimerID.TimerID_UpBlind[1], t, onBlindTimer, blind)
            log.debug("up blind old_level:%s=>new_leve:%s time:%s", old_level, blind.blind_level, blind:getBlindTime())
            
            -- 通知客户端下局涨盲
            blind:notifyRaiseBlind()
        else
            -- 已经是最大的盲注了
            log.debug("now is top level:%s", blind.blind_level)
        end
        
    end
    self.blind_starttime = global.ctsec()
    local t = self:getBlindTime() * 1000
	timer.tick(self.blind_timer, TimerID.TimerID_UpBlind[1], t, onBlindTimer, self)
    return true
end

function Blind:stopBlind()
	timer.cancel(self.blind_timer, TimerID.TimerID_UpBlind[1])
end

function Blind:notifyRaiseBlind()
    log.debug("notifyRaiseBlind ...")
    local nextsb = 0
    local nextante = 0
    local leftsec = 0
    local next_conf = self:getBlindConfByLevel(self.blind_level + 1)
    if next_conf then
        nextsb = next_conf.sb
        nextante = next_conf.ante
        leftsec = self.blind_starttime + self:getBlindTime() - global.ctsec()
        if leftsec <= 0 then
            leftsec = 0
        end
    end
    
    -- 文字提示内容为：下一局盲注上涨XX/XX
    local notifyRaiseBlind  = {}
    notifyRaiseBlind.sb     = self:getBlindSB()
    notifyRaiseBlind.ante   = self:getBlindAnte()
    if next_conf then
        notifyRaiseBlind.next_sb   = nextsb
        notifyRaiseBlind.next_ante = nextante
        notifyRaiseBlind.left_secs = leftsec
    end
    
    local content = pb.encode("network.cmd.PBNotifyRaiseBlind", notifyRaiseBlind)
    self.table:broadcastToAllObserver(0x0011, 0x1019, content) -- PBTexasSubCmdID_NotifyRaiseBlind
end

return Blind
