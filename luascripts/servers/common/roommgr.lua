--increment
local g = require("luascripts/common/g")
local log = require(CLIBS["c_log"])
local rand = require(CLIBS["c_rand"])
local global = require(CLIBS["c_global"])
RoomMgr = RoomMgr or {}

-- 新建一个房间管理器(管理同一级别的房间)
function RoomMgr:new(o)
    o = o or {}
    o.mgr = {}
    setmetatable(o, self)
    self.__index = self

    -- 最低限桌
    if o.conf and o.conf.mintable then
        for i = 1, o.conf.mintable do
            o:createRoom() -- 创建房间(桌子)
        end
    end
    return o
end

-- 增加一个房间到房间管理器中
function RoomMgr:addRoom(r)
    if r and self.mgr[r.id] == nil then
        self.mgr[r.id] = r
        return r
    end
    return nil
end

-- 移除指定ID的房间
function RoomMgr:removeRoom(id)
    self.mgr[id] = nil
end

-- 判断是否有房间ID为id的房间
function RoomMgr:hasRoom(id)
    return self.mgr[id] ~= nil
end

-- 获取房间管理器
function RoomMgr:getRoomMgr()
    return self.mgr
end

-- 通知关服
function RoomMgr:notifyStopServer(param)
    for _, v in pairs(self.mgr) do -- 遍历每一个房间
        if v and type(v.tools) == "function" then
            v:tools(param)
        end
    end
end

-- 根据房间ID获取对应的房间对象
function RoomMgr:getRoomById(id)
    local r = self.mgr[id]
    return r ~= nil and r or nil
end

-- 找一个人数最多的空房间
function RoomMgr:getMiniEmptyRoom(uid, ip, api)
    local conf = self.conf -- 该级别房间的配置信息
    local room
    local mini_id = 0xFFFFFFFF
    local emptynum = 1
    if not Utils:isRobot(api) then
        emptynum = 0
    end
    for _, v in pairs(self.mgr) do
        local empty = conf.maxuser - v:count()
        if empty > emptynum and not Utils:hasIP(v, uid, ip, api) then -- 如果v房间还有空座位
            if empty < mini_id then
                mini_id = empty -- 保存最小的房间ID
                room = v --房间
            end
        end
    end
    if not room then
        room = self:createRoom()
    end
    return room
end

-- 获取一个满足要求的房间
function RoomMgr:getAvaiableRoom2(uid, ip, api)
    -- local conf = self.conf   -- 该级别房间的配置信息
    local conf = MatchMgr:getConfByMid(self.mid)
    local room
    local isRobot = false
    local isNew = false

    if Utils:isRobot(api) then
        isRobot = true
    end

    if conf then
        if conf.special and conf.special == 1 then -- 如果是新人专场
            isNew = true
        end
    end

    for _, v in pairs(self.mgr) do   -- 遍历所有房间
        local playerNum, robotNum = v:count() -- 获取所有玩家数及机器人人数
        local empty = conf.maxuser - playerNum   -- 空座位数
        if empty > 0 and not Utils:hasIP(v, uid, ip, api) then -- 如果v房间还有空座位
            if isRobot then
                if empty > 1 then   -- 超过1个空座位时机器人才可进入
                    return v
                end
            else -- 真实玩家
                if isNew then  -- 如果是新手专场
                    if playerNum == robotNum then  -- 如果还未有真人
                        return v
                    end
                else
                    return v
                end
            end
        end
    end

    if not room then
        room = self:createRoom()  -- 新建一个房间
        log.debug("getAvaiableRoom2(), createRoom(),uid=%s", uid)
    end
    return room
end

-- 扩充房间
function RoomMgr:expandRoom()
    local totalempty = 0
    for _, v in pairs(self.mgr) do -- 遍历每个房间
        local conf = MatchMgr:getConfByMid(v.mid) -- 获取某一级别的房间配置
        if conf then
            totalempty = totalempty + conf.maxuser - v:count() -- 累计空余的座位数
        end
    end
    if totalempty < 3 then -- 如果累计空余座位不足3个
        self:createRoom() -- 创建一个新房间
    end
end

-- 获取空余房间数
function RoomMgr:getEmptyRoomCount()
    local emptyRoomNum = 0 -- 空房间数
    local userNum, robotNum
    for _, v in pairs(self.mgr) do -- 遍历每个房间
        userNum, robotNum = v:count()
        if userNum == robotNum then -- 如果该房间全是机器人
            emptyRoomNum = emptyRoomNum + 1
        end
    end
    return emptyRoomNum
end
-- 收缩房间
function RoomMgr:shrinkRoom()
    local roomcnt = 0
    local emptyroom = {}
    local totalempty = 0
    local conf = MatchMgr:getConfByMid(self.mid) -- 获取某一级别的房间配置
    if not conf then
        return
    end
    for k, v in pairs(self.mgr) do
        roomcnt = roomcnt + 1
        log.debug("idx(%s,%s,%s) usercount %s", v.id, self.mid, tostring(self.logid), g.count(v.users))
        if g.count(v.users) == 0 and not v:lock() then
            table.insert(emptyroom, k)
        else
            totalempty = totalempty + conf.maxuser - v:count() -- 累计有人房间空座位数
        end
    end
    if #emptyroom > 0 then
        log.info(
            "idx(%s,%s) try shrink rooms emptyroom %s roomcnt %s mintable %s",
            self.mid,
            tostring(self.logid),
            #emptyroom,
            roomcnt,
            tostring(conf.mintable)
        )
    end
    if roomcnt > conf.mintable and #emptyroom > 0 and totalempty >= 3 then --如果房间数超过最小桌子数 & 有空房间 & 有人的房间总的空座位3个及以上 则将至最小桌子数
        local nonemptyroom_cnt = roomcnt - #emptyroom -- 有玩家的房间数目
        while #emptyroom > 0 and nonemptyroom_cnt + #emptyroom > conf.mintable do
            self:destroyRoom(table.remove(emptyroom, 1))
        end
        if nonemptyroom_cnt ~= (roomcnt - #emptyroom) then
            UploadPlayerModule.onRoomChange()
        end
    end
end

-- 找一个人数最多的未满的房间
-- 参数 c：房间人数限制，默认为500
-- 参数 uid: 玩家ID   slot游戏中uid作为房间ID
function RoomMgr:getAvaiableRoom(c, uid)
    local cnt = -1
    local r = nil
    local conf = MatchMgr:getConfByMid(self.mid) -- 获取某一级别的房间配置
    for _, v in pairs(self.mgr) do --遍历所有房间
        local vc, robotCount = v:count(uid) -- 该房间中总玩家数
        if vc < (c or 100) and (not v:lock()) and vc > cnt then
            if conf and conf.single_profit_switch then
                if vc == robotCount then
                    r = v
                    cnt = vc -- 保存该值是为了尽量选择人数最多的房间
                end
            else
                r = v
                cnt = vc -- 保存该值是为了尽量选择人数最多的房间
            end
        end
    end
    if not r then
        if 43 == global.stype() then -- slot游戏是根据玩家ID作为房间ID
            r = self:createRoom(uid) -- 创建一个新房间
        else
            for i = 1, (conf.mintable or 1) do
                --r = self:createRoom(uid) -- 创建一个新房间
                r = self:createRoom() -- 创建一个新房间(房间ID唯一)
            end
        end
    end
    return r
end

function RoomMgr:getDiffRoom(roomid, c, uid, ip, rnd)
    local dc, alldc = {}, {}
    for k, v in pairs(self.mgr) do
        local uc = v:count()
        if k ~= roomid and not Utils:hasIP(v, uid, ip) then
            if uc < c then
                table.insert(dc, {uc, v})
            end
            table.insert(alldc, {uc, v})
        end
    end
    --random
    if #dc > 0 and rnd then
        return dc[rand.rand_between(1, #dc)][2]
    end
    --优先人数最多的桌子
    table.sort(
        dc,
        function(a, b)
            return a[1] > b[1]
        end
    )
    if #dc > 0 then
        return dc[1][2]
    end
    --否则优先不同的桌子
    if #alldc > 0 then
        return alldc[1][2]
    end
    return nil
end

-- 参数 roomid: 房间ID
-- 参数 c: 房间最大人数
function RoomMgr:getDominoRoom(roomid, c, uid, ip)
    roomid = roomid or 0
    local dc, alldc = {}, {}

    -- 判断房间当前状态是否适合
    if not self.mgr[roomid]:canChangeRoom(uid) then
        return nil
    end

    for k, v in pairs(self.mgr) do
        local uc = v:count()
        if k ~= roomid and not Utils:hasIP(v, uid, ip) then
            if uc < c then -- 未超出最大人数
                table.insert(dc, {uc, v})
            end
            table.insert(alldc, {uc, v})
        end
    end
    --优先人数最多的桌子
    table.sort(
        dc,
        function(a, b)
            return a[1] > b[1]
        end
    )
    if #dc > 0 then
        return dc[1][2]
    end
    --否则优先不同的桌子
    if #alldc > 0 then
        return alldc[1][2]
    end
    return self:createRoom()
end

--1.只有1个人坐下的牌桌
--2.在开始之前或Declare之后
--3.已经开始游戏的牌桌
--4.空房间的牌桌
--5.没有则分配新的桌子
function RoomMgr:getRummyRoom(roomid, isrobot, uid, ip)
    roomid = roomid or 0
    local readyroom, startroom, emptyroom
    local mr
    for k, v in pairs(self.mgr) do
        --在座数
        local vc, rc = v:count()
        --空座位数
        local ec = self.conf.maxuser - vc
        --机器人优先进入一个真实玩家的桌子
        if isrobot and vc == 1 and rc == 0 then
            mr = v
            break
        end
        if vc == 0 then
            emptyroom = emptyroom or {}
            table.insert(emptyroom, v)
        end
        if roomid ~= k and (not isrobot) and ec > 0 and not Utils:hasIP(v, uid, ip) then
            --只有1个人坐下的牌桌
            if vc == 1 then
                mr = v
                break
            end
            if vc > 0 and v:isInStartOrDeclardState() then
                readyroom = readyroom or {}
                table.insert(readyroom, v)
            elseif vc > 0 then
                startroom = startroom or {}
                table.insert(startroom, v)
            end
        end
    end
    if not mr then
        if readyroom then
            mr = readyroom[rand.rand_between(1, #readyroom)]
        elseif startroom then
            mr = startroom[rand.rand_between(1, #startroom)]
        elseif emptyroom then
            mr = emptyroom[rand.rand_between(1, #emptyroom)]
        end
    end
    if not mr then
        mr = self:createRoom()
    end
    return mr
end

function RoomMgr:clearRoomUsersBySrvId(srvid)
    for _, v in pairs(self.mgr) do
        v:clearUsersBySrvId(srvid)
    end
end

-- 获取房间管理器中所有玩家数据
function RoomMgr:getAllUsers(t)
    for _, v in pairs(self.mgr) do
        table.insert(t.data, {mid = v.mid, roomid = v.id, roomtype = v:roomtype(), uids = {}})
        for x in pairs(v.users) do
            table.insert(t.data[#t.data].uids, x)
        end
    end
end

-- 获取该房间管理器中玩家数目
function RoomMgr:getUserNum()
    local num = 0
    for _, v in pairs(self.mgr) do
        num = num + v:count()
    end
    return num
end

-- 获取该房间管理器中房间数目
function RoomMgr:getRoomNum()
    local c = 0
    for _, v in pairs(self.mgr) do
        c = c + 1
    end
    return c
end

-- 创建一个新房间
function RoomMgr:createRoom(roomid)
    self.conf = self.conf or {}
    self.conf.maxtable = self.conf.maxtable or 500
    local id = roomid or Uniqueid:getUniqueid(self.mid, self.conf.maxtable) -- 获取唯一房间ID
    if id == -1 then -- 获取ID失败
        return nil
    end
    log.debug("idx(%s,%s) create room", id, self.mid)
    return self:addRoom(Room:new({id = id, mid = self.mid}))
end

-- 销毁房间ID为rid的房间
function RoomMgr:destroyRoom(rid)
    local room = self.mgr[rid]
    if room then
        log.info("idx(%s,%s,%s) destroy room", self.mid, room.id, tostring(self.logid))
        room:destroy()
        Uniqueid:putUniqueid(self.mid, room.id) -- 释放该房间ID
        room = nil
        self.mgr[rid] = nil
    end
end

-- 销毁多余的空闲房间(最多保留2个空闲房间)
function RoomMgr:makeSure2FreeRoom()
    local num = 0
    local userNum, robotNum
    for _, v in pairs(self.mgr) do
        userNum, robotNum = v:count()
        if userNum == robotNum then
            if num >= 2 and v.state == 5 then
                self:destroyRoom(v.id)
            else
                num = num + 1
            end
        end
    end
    if num < 2 then
        self:createRoom()
        if num == 0 then
            self:createRoom()
        end
    end
end

-- 获取该房间管理器中所有房间的机器人数
function RoomMgr:getRobotNum()
    local c = 0
    for _, v in pairs(self.mgr) do
        c = c + v:robotCount()
    end
    return c
end

function RoomMgr:getRoomsByJackpotId(id, rooms)
    for _, v in pairs(self.mgr) do
        local r = v:getJackpotId(id)
        if r then
            table.insert(rooms, r)
        end
    end
    return rooms
end

-- 调用kickout函数
function RoomMgr:kickout()
    for _, v in pairs(self.mgr) do
        if type(v.kickout) == "function" then -- 如果有kickout函数
            v:kickout()
        end
    end
end

function RoomMgr:reloadAllRoomConf()
    for _, v in pairs(self.mgr) do
        if type(v.reload) == "function" then
            v:reload()
        end
    end
end
