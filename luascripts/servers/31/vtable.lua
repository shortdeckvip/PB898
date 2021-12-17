local g = require("luascripts/common/g")

VTable = VTable or {}

function VTable:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:reset()
    return o
end

function VTable:reset()
    --[[
	--	1号：神算子
	--	2+号：富豪
	--]]
    if self.seatsmgr then
        for _, v in ipairs(self.seatsmgr) do
            v:reset()
        end
    else
        self.seatsmgr = {
            Seat:new({sid = 1, vtable = self}),
            Seat:new({sid = 2, vtable = self}),
            Seat:new({sid = 3, vtable = self}),
            Seat:new({sid = 4, vtable = self}),
            Seat:new({sid = 5, vtable = self}),
            Seat:new({sid = 6, vtable = self}),
            Seat:new({sid = 7, vtable = self}),
            Seat:new({sid = 8, vtable = self}),
        }
    end

    self.empty = #self.seatsmgr -- 空余座位
end

function VTable:getTid()
    return self.id
end

function VTable:getSize()
    return #self.seatsmgr
end

-- 虚拟桌子满桌，五人即满桌
-- 用于普通玩家坐下判断
function VTable:isFull()
    return (self.empty <= 1)
end

-- 虚拟桌子有空位
-- 用于跟桌判断
function VTable:isEmpty()
    return (self.empty > 0)
end

function VTable:decEmpty()
    self.empty = self.empty - 1
end

function VTable:incEmpty()
    self.empty = self.empty + 1
end

-- 普通坐下
-- @param playerinfo {}: nickname, username, viplv, nickurl, gender, balance, currency
-- @return seat: 坐下成功
-- @return nil: 坐下失败
function VTable:sit(uid, playerinfo)
    -- 找个位置坐下
    for k, v in ipairs(self.seatsmgr) do
        if v:isEmpty() then
            v:sit(uid, playerinfo)
            return v
        end
    end
    return nil
end

-- 获取 uid 坐下的座位
function VTable:getSeat(uid)
    for k, v in ipairs(self.seatsmgr) do
        if v:getUid() == uid then
            return v
        end
    end
end

function VTable:getSeatsInfo()
    local seatsinfo = {}
    for k, v in ipairs(self.seatsmgr) do
        table.insert(seatsinfo, v:getSeatInfo())
    end
    return seatsinfo
end

function VTable:getSeats()
    return self.seatsmgr
end

-- 跟桌坐下
function VTable:follow(uid, playerinfo)
    local seat = self:sit(uid, playerinfo)
    if seat then
        seat:setFollow(true)
        seat:lockN(2)
    end
    return seat
end

function VTable:printVTable()
    print("*****************VTableInfo Begin********************")
    print("#", self)
    print("empty", self.empty)
    for k, v in ipairs(self.seatsmgr) do
        v:printSeat()
    end
    print("*****************VTableInfo End**********************")
end
