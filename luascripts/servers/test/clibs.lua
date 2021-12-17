local pb = require("protobuf")
local u = require("utils")

-------------log module test begin--------------------------
local log = require("log")

log.debug("service start")
--[[
for i=1,10000 do
	local data = "玩家ID，名字:" .. 2 .."奥利奥"
	log.debug(data)
end
]]--
-------------log module test end--------------------------

-------------redis module test begin--------------------------
local pwd = u.pwd()
print(pwd)
local f = package.loadlib("/home/JimyLi/dev/server/trunk/bpt_dev/luascripts/clibs/redis/.libs/redis.so", "luaopen_redis")
if f ~=nil then
	local redis = f()
	--print("redis", redis)
	print(redis)
	for i,v in pairs(redis) do
		print(i,v)
	end
	redis.init("ok")
end
if R ~= nil then
	for i,v in pairs(R) do
		print(i,v)
	end
end
--R.init("192.168.202.128:4500")
local str = R.strget("hakeem")
print(str)
R.strset("hakeem", "hakeemc")
str = R.strget("hakeem")
print(str)
-------------redis module test end--------------------------

-------------mongo module test begin--------------------------
print(M)
if M ~= nil then
	for i,v in pairs(M) do
		print(i,v)
	end
end
--M.init("bpttest", "192.168.202.123:5000", "192.168.202.124:5000", "192.168.202.125:5000")
-------------mongo module test end--------------------------

-------------rand module test begin--------------------------
print(D)
if D ~= nil then
	for i,v in pairs(D) do
		print(i,v)
	end
end

for i=1,1 do
	print(D.rand(), D.rand_between(1, 4))
end
-------------rand module test end--------------------------

--------net module test begin--------------------------
local mytimer = 0
local function test_timer(arg)
	print("current time ", G.ctms(), G.ctsec())
	--print(os.time())
	for i,v in pairs(arg) do
		print(i,v)
	end
end

local function c11(msg)
	local m = pb.decode("network.cmd.PBReqJoinTable", msg);
	print(m.uid)
	local t = {
		type = 17,
		flag = 786433,
	}
	local p = pb.encode("network.cmd.PBNotifyServiceUnavailable", t)
	--linkid,uid,maincmd,subcmd,msgbytes
	bpt.accli.send(196610, 7488, 0, 4100, p)
	--timerhandle,timerid
	T.cancel(mytimer, 1)
	--[[
	mytimer = T.create()
	local targ={
		a=1,
		b="string",
	}
	T.tick(mytimer, 1, 5000, test_timer, targ)
	]]--
	--T.destroy(mytimer)
end
--maincmd, subcmd, cmdname, cmd callback function
Register(17, 1, c11)

local function test_rp_multicheck_resp(msg)
	print("test_rp_multicheck_resp")
	local c = pb.decode("network.inter.TS2RedisProxyCheckMultiTable" , msg)
	for i,_ in pairs(c.arg) do
		print(i)
	end
end

local function test_multiup_resp(msg)
	print("test_multiup_resp")
	local c = pb.decode("network.inter.MultiUpdateRecordResp" , msg)
	for i,v in pairs(c) do
		print(i,v)
	end
end


function net_test()
	--redis proxy module
	local m = {
		arg = {
			uid = 7488,
			idx = {
				flag = 58123,
				mid = 1,
				tid = 0,
				time = 14012121,
			},
		},
	}
	print(bpt.rpcli, pb)
	local em = pb.encode("network.inter.TS2RedisProxyCheckMultiTable", m)
	--msg, response callback function
	bpt.rpcli.request(em, test_rp_multicheck_resp)

	--mserver module
	local m1 = {
		orders = {
			{
				uid = 7488,
				kvs = {
					{
						key = "s",
						sval = "ok",
						ival = 1212,
						fval = 232.0,
					},
				},
			},
		},
		cb = {
			seq = 1,
		},
	}
	local e1 = pb.encode("network.inter.MultiUpdateRecordReq", m1)
	--bpt.mscli.request_multi_update(e1, test_multiup_resp)

	--access
	--shuffle
	--create poker
	local p = S.create()
	--deal one card
	local card = S.deal(p);
	--shuffle poker
	S.shuffle(p);
	--destroy poker
	S.destroy(p);
	print("deal card:" .. string.format("0x%x", card))

	--utils
	for fname in u.dir("luascripts/corelibs") do
		if string.find(fname, "[%d%w].lua") ~= nil then
			print(fname)
		end
	end

	--timer
	--create timer handle
	mytimer = T.create()
	local targ={
		a=1,
		b="string",
	}
	--start timer
	--timerhandle, timerid, interval(ms), callback function,  callback function arguments
	T.tick(mytimer, 1, 5000, test_timer, targ)
	print("timer...")
end
--timer
--[[
mytimer = T.create()
local targ={
	a=1,
	b="string",
}
T.tick(mytimer, 1, 5000, test_timer, targ)
]]--

-------------net module test end--------------------------
