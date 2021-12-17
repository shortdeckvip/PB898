local timer = require(CLIBS["c_timer"])

JackpotMgr = JackpotMgr or {timer = timer.create(), mgr = {}}

local function onJackpot(self)
    local jackpots = self:getAllJackpots()
    Utils:requestJackpot({data = jackpots})
end

function JackpotMgr:getAllJackpots()
    local jackpots = {}
    for k, v in pairs(self.mgr) do
        table.insert(jackpots, {id = v.id, timestamp = v.timestamp})
    end
    return jackpots
end

function JackpotMgr:addJackpot(r)
    if r and self.mgr[r.id] == nil then
        self.mgr[r.id] = r
        return r
    end
    return nil
end

function JackpotMgr:removeJackpot(id)
    self.mgr[id] = nil
end

function JackpotMgr:hasJackpot(id)
    return self.mgr[id] ~= nil
end

function JackpotMgr:getJackpotById(id)
    return self.mgr[id] and self.mgr[id].jp or 0
end

function JackpotMgr:init()
    for _, v in ipairs(JACKPOT_CONF) do
        self:addJackpot({id = v.id, roomtype = v.roomtype, timestamp = -1})
    end
    timer.tick(self.timer, 1, 1000, onJackpot, self)
end

function JackpotMgr:onJackpotUpdate(jackpots)
    for _, v in ipairs(jackpots) do
        local r = self.mgr[v.id]
        if r and v.value and v.value > 0 and r.jp ~= v.value then
            --免费币不处理jackpot的跑马灯
            if r.roomtype == 2 then
                local rooms = MatchMgr:getAllRoomsByJackpotId(v.id)
                for _, vv in ipairs(rooms) do
                    vv:onJackpotUpdate(v.value)
                end
            end
            r.jp = v.value
        end
        r.timestamp = v.timestamp
    end
end
