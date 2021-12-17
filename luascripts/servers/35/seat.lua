-- serverdev\luascripts\servers\35\seat.lua

local g = require("luascripts/common/g")

Seat = Seat or {}

function Seat:new(o)
	o = o or {}
	setmetatable(o, {__index = self})
	
	-- o.sid = 0  -- 座位ID 
	-- o.vtable = {} -- 排行榜 
	o:reset()
	return o
end

-- 重置该座位  
function Seat:reset()
	self.uid = 0
	self.lock = 0			-- 座位锁住局数
	self.isfollow = false	-- 是否因跟桌坐下
	self.playerinfo = {     -- 该座位上的玩家信息 
		uid     = 0,
		nickname= '',
		username= '',
		viplv   = 0,   -- VIP等级 
		nickurl = '',
		gender  = 0,
		balance	= 0,
		currency= '',
		extra	= {
			api			= '',
			ip			= '',
			platuid		= '',
		},
	}
end

-- 是否跟桌坐下  
function Seat:isFollow()
	return self.isfollow
end

-- 设置是否跟随 
function Seat:setFollow(follow)
	self.isfollow = follow
end

-- 锁住 n 局
function Seat:lockN(n)
	self.lock = n
end

-- 锁住座位
-- 调用情形：
-- 1）玩家离开或者离线时
-- 2）跟桌当时, 请求保留座位，这个时候玩家还没有进游戏，可以先坐下，并设置状态为 Logout，两局结束后座位会被重置
function Seat:lockSeat()
	if self.isfollow then
		self:lockN(2)
	else
		self:lockN(1)
	end
end

-- 解锁座位 1 局
-- 调用情形：每局 onFinish
function Seat:unlockSeat()
	if self.lock > 0 then
		self.lock = self.lock - 1
	end

	if self.lock == 0 then
		self:stand()
	end
end

-- 该桌位是否为空座 
function Seat:isEmpty()
	return (self.uid == 0 and self.lock == 0)
end

-- 更新玩家身上金额 
function Seat:updateBalance(balance)
	self.playerinfo.balance = balance
end

-- 更新该座位上玩家的VIP等级 
function Seat:updateViplv(viplv)
	self.playerinfo.viplv = viplv
end

-- 获取该座位上的玩家信息 
function Seat:getPlayerInfo()
	return self.playerinfo
end

-- 获取座位信息 
function Seat:getSeatInfo()
	return {
		sid			= self.sid,  -- 座位ID  
		tid			= self.vtable:getTid(),  -- 排行榜ID(虚拟桌ID) 
		playerinfo	= g.copy(self.playerinfo), -- 该座位上的玩家信息 
	}
end

-- 指定玩家坐下 
function Seat:sit(uid, playerinfo)
	self:reset()  -- 重置该座位 
	self.uid = uid  -- 玩家ID 
	self.playerinfo		= g.copy(playerinfo) -- 玩家信息 
	self.playerinfo.uid	= uid
	self.playerinfo.extra.api = ''
	self.playerinfo.extra.ip = ''
	self.playerinfo.extra.platuid = ''
	self.vtable:decEmpty()  -- 减少空座位数  
end

-- 退出，清空座位所有信息
function Seat:stand()
	self:reset() -- 重置该座位 
	self.vtable:incEmpty()  --增加空座位数  
end

-- 获取座位号 
function Seat:getSid()
	return self.sid
end

-- 获取该座位玩家ID 
function Seat:getUid()
	return self.uid
end

-- 打印座位信息 
function Seat:printSeat()
	print('---------SeatInfo Begin------------')
	print('sid', self.sid)
	print('uid', self.uid)
	print('lock', self.lock)
	print('follow', self.isfollow)
	print('nickname', self.playerinfo.nickname)
	print('username', self.playerinfo.username)
	print('viplv', self.playerinfo.viplv)
	print('nickurl', self.playerinfo.nickurl)
	print('gender', self.playerinfo.gender)
	print('balance', self.playerinfo.balance)
	print('currency', self.playerinfo.currency)
	print('accessory', self.playerinfo.accessory)
	print('frame', self.playerinfo.frame)
	print('---------SeatInfo End------------')
end
