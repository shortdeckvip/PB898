-- serverdev\luascripts\servers\45\vtablemgr.lua

-- 虚拟桌管理器 
VTableMgr = VTableMgr or { mgr = {} }

-- 增加一个虚拟桌 
function VTableMgr:addVTable()
	local vtable = VTable:new({id = #self.mgr + 1}) -- 
	table.insert(self.mgr, vtable)
	return vtable
end

-- 正常玩家 获取一个有效的虚拟桌 
function VTableMgr:getAvaiableVTable()
	for k, v in ipairs(self.mgr) do
		if not v:isFull() then
			return v
		end
	end
	return self:addVTable()
end

-- 跟桌玩家
function VTableMgr:getFollowableVTable()
	for k, v in ipairs(self.mgr) do
		if v:isEmpty() then
			return v
		end
	end
	return self:addVTable()
end

-- 打印所有虚拟桌数据 
function VTableMgr:printVTables()
	for k, v in ipairs(self.mgr) do
		v:printVTable()
	end
end
