Uniqueid = Uniqueid or {uniqueid = 0, list={}}

-- 联合成房间ID = (mid<<16)+id-1 ;
local function compbinationRoomId(mid, id)
	return (mid << 16) + id - 1
end

-- 获取一个唯一的ID 
function Uniqueid:getUniqueid(mid, maxcnt)
	if not self.list[mid] then
		self.list[mid] = {} -- 只创建一次 
		for k=1,maxcnt do
			table.insert(self.list[mid], {compbinationRoomId(mid, k), false})--id,isused    {房间ID,是否被使用}
		end
	end
	--print("====", #self.list[mid])
	for k,v in ipairs(self.list[mid]) do
		if not v[2] then  -- 如果该ID未被使用 
			v[2] = true  -- 标记该ID已被使用 
			--print(v[1])
			return v[1]  -- 返回ID值 
		end
	end

	return -1  -- 未找到 
end

-- 释放一个ID，使其可以被再次使用  
function Uniqueid:putUniqueid(mid, id)
	if type(self.list[mid]) ~= "table" then return -1 end
	for k,v in ipairs(self.list[mid]) do
		if v[1] == id then
			--print(k, id)
			v[2] = false
			return v[1]
		end
	end
	return -1
end

local function test()
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 1), "101 failed 0")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 2), "101 failed 1")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 3), "101 failed 2")
	--assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 3), "101 failed 3")

	--assert(Uniqueid:getUniqueid(102, 3) == compbinationRoomId(102, 1), "102 failed 1")

	assert(Uniqueid:putUniqueid(101, compbinationRoomId(101, 1)) == compbinationRoomId(101, 1), "101 recycle failed 1")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 1), "101 failed 1")
	assert(Uniqueid:getUniqueid(101, 3) == -1, "101 failed 2")
	assert(Uniqueid:putUniqueid(101, compbinationRoomId(101, 2)) == compbinationRoomId(101, 2), "101 recycle failed 2")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 2), "101 failed 2")

	assert(Uniqueid:putUniqueid(101, compbinationRoomId(101, 2)) == compbinationRoomId(101, 2), "101 recycle failed 2")
	assert(Uniqueid:putUniqueid(101, compbinationRoomId(101, 1)) == compbinationRoomId(101, 1), "101 recycle failed 1")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 1), "101 failed 1")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 2), "101 failed 2")

	assert(Uniqueid:putUniqueid(101, compbinationRoomId(101, 1)) == compbinationRoomId(101, 1), "101 recycle failed 1")
	assert(Uniqueid:putUniqueid(101, compbinationRoomId(101, 2)) == compbinationRoomId(101, 2), "101 recycle failed 2")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 1), "101 failed 1")
	assert(Uniqueid:getUniqueid(101, 3) == compbinationRoomId(101, 2), "101 failed 2")

	print("all test ok")
end

--test()
--os.exit(1)