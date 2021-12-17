local cjson = require "cjson"
local lom = require "lom"

local t=[[
{
	uid:7488, type:18, text:"magicminglee@gmail.com", pushtype:1,
	json:{tableidx:{mid:1230, flag:7632112, tid:1, time:141920100}}
}
]]
print(cjson)
local tj = cjson.encode(t)
print(tj)
local jt = cjson.decode(tj)
print(jt)


--[[
for line in io.lines("Config/Table/blind.xml") do 
	local l = lom.parse(line)
	if l ~= nil then
		for i,v in pairs(l) do
			if type(v) == "table" then
				print("============================being==============")
				for x,y in pairs(v) do
					print(x,y)
				end
				print("============================end==============")
			end
		end
	end
end
]]--
local function PrintTable(t)
	if type(t) == "table" then
		for i,v in pairs(t) do
			PrintTable(v)
			print(i,v)
		end
	end
end
local f = io.open("Config/Table/blind.xml")
local txt = f:read("*a")
if txt ~= nil then
	local l = lom.parse(txt)
	print(l[2][2].attr.minchips)
end

f = io.open("Config/Table/mtt.xml")
txt = f:read("*a")
if txt ~= nil then
	local l = lom.parse(txt)
	for i,v in pairs(l[2].attr) do
		print(i,v)
	end
end
