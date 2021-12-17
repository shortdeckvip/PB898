--increment
local global = require(CLIBS["c_global"])

MatchMgr = MatchMgr or {mgr = {}}

function MatchMgr:init(conf)
    self.conf = conf
    for k, v in ipairs(conf) do
        if not self.mgr[v.mid] then -- 判断指定级别的房间管理器是否存在
            if v.gameid ~= nil and v.serverid ~= nil then
                if v.gameid == global.stype() and v.serverid == global.lowsid() then
                    local o = RoomMgr:new({mid = v.mid, conf = v})
                    self.mgr[v.mid] = o
                end
            else
                local o = RoomMgr:new({mid = v.mid, conf = v}) -- 新建一个房间管理器
                self.mgr[v.mid] = o -- 保存级别为v.mid的房间管理器
            end
        end
    end
    self:reloadAllMatchConf()
end

function MatchMgr:getMatchMgr()
    return self.mgr
end

function MatchMgr:getRoomByRandom()
    local t = {}
    for _, v in pairs(self.mgr) do
        for _, room in pairs(v.mgr) do
            table.insert(t, room)
        end
    end
    if #t > 0 then
        return t[math.random(1, #t)]
    end
    return nil
end

-- 获取底注值获取对应matchid  2021-9-13
function MatchMgr:getMatchByAnte(ante)
    for _, v in pairs(self:getConf()) do
        local confante = (v.gameid == 26 or v.gameid == 28) and v.sb or v.ante
        if confante == ante and v.roomtype == 2 then
            if v.serverid == global.lowsid() then
                return v.mid, nil
            else
                return 0, (v.gameid << 16) | v.serverid
            end
        end
    end
    return 0, nil
end

-- 获取指定级别的房间管理器
function MatchMgr:getMatchById(id)
    return self.mgr[id]
end

--
function MatchMgr:getAllUsers(t)
    for k, v in pairs(self.mgr) do
        v:getAllUsers(t)
    end
end

-- 通知关服
function MatchMgr:notifyStopServer(param)
    for k, v in pairs(self.mgr) do -- 遍历所有房间管理器
        v:notifyStopServer(param)
    end
end

-- 根据级别ID和房间ID获取房间对象
function MatchMgr:getRoomById(mid, rid)
    local m = self.mgr[mid]
    if m then
        return m:getRoomById(rid) -- 根据房间ID获取房间对象
    end
    return nil
end

function MatchMgr:clearRoomUsersBySrvId(srvid)
    for k, v in pairs(self.mgr) do
        v:clearRoomUsersBySrvId(srvid)
    end
end

function MatchMgr:reloadAllMatchConf()
    for k, v in pairs(self.mgr) do
        v:reloadAllRoomConf()
    end
end

-- 获取配置列表
function MatchMgr:getConf()
    return self.conf
end

-- 根据房间级别号获取该类房间的配置信息
function MatchMgr:getConfByMid(mid)
    if not self.conf then
        return nil
    end
    for _, v in ipairs(self.conf) do
        if v.mid == mid then
            return v
        end
    end
    return nil
end

-- 根据房间级别号获取该类房间中所有玩家数目
function MatchMgr:getUserNumByMid(mid)
    local num = 0
    for k, v in pairs(self.mgr) do
        if v.mid == mid then
            num = num + v:getUserNum()
        end
    end
    return num
end

function MatchMgr:getAllRoomsByJackpotId(id)
    local rooms = {}
    for _, v in pairs(self.mgr) do
        v:getRoomsByJackpotId(id, rooms)
    end
    return rooms
end

-- 踢出所有
function MatchMgr:kickout()
    for _, v in pairs(self.mgr) do
        v:kickout()
    end
end

function MatchMgr:getQuickRoom(money, multi, isrummy)
    local confs = {}
    for _, v in pairs(self:getConf()) do
        local minbuyin = v.minbuyinbb * v.sb * 2
        if not (money < minbuyin) then
            table.insert(confs, {v, math.abs(money - (minbuyin * multi))})
        end
    end
    table.sort(
        confs,
        function(r1, r2)
            return r1[2] < r2[2]
        end
    )
    if #confs == 0 then
        return nil, nil
    end
    local rooms, dfrm, dfr, conf = {}, nil, nil, confs[1][1]
    local rm = self:getMatchById(conf.mid)
    if rm then
        dfrm = dfrm or rm
        for _, vv in pairs(rm:getRoomMgr()) do
            dfr = dfr or vv
            if not (vv:getUserNum() == 0 or vv:getUserNum() == conf.maxuser) then
                table.insert(rooms, {rm, vv})
            end
        end
    else
        return nil, nil, (conf.gameid << 16) | conf.serverid
    end

    if #rooms > 0 then
        if isrummy then
            for _, v in ipairs(rooms) do
                if v[2]:isInStartOrDeclardState() then
                    return v[1], v[2].id
                end
            end
        end
        return rooms[1][1], rooms[1][2].id
    end
    return dfrm, dfr.id
end
