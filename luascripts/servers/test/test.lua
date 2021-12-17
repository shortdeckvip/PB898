local pb = require "protobuf"
local log = require(CLIBS["c_log"])
local http = require(CLIBS["c_http"])

local function c11(uid, linkid, msg)
	local addressbook1 = pb.decode("tutorial.MyMessage", msg)
	--local name = addressbook1.person[1].name
	----[[
	--local name = addressbook1.person[1].name
	--local id = addressbook1.person[1].id
	--local email = addressbook1.person[1].email
	--local number = addressbook1.person[1].phone[1].number
	--local number1 = addressbook1.person[1].phone[2].number
	--local type = addressbook1.person[1].phone[1].type
	--local t1 = addressbook1.person[1].test[1]
	--local t2 = addressbook1.person[1].test[2]

	--]]--

	--print(pb.unpack("tutorial.Person name id"), t.person)
	--print(addressbook1.person[1].name)
	--for i,v in pairs(addressbook1.person[1]) do
	--	print(i,v)
	--end
	--print(pb)
	--for i,v in pairs(addressbook1.person[1].phone[1]) do
	--	print(i,v)
	--end
	local person = {
		--name = "Alice",
		--id = 12345,
		email = "magicminglee@gmail.com",
		phone = {
			{ number = "1209021902", type = "WORK" },
			{ number = "1209021902", type = "WORK" },
		},
		test = { 200,200,200,200,200,200},
	}
	local addressbook = {}
	addressbook.person = {}
    addressbook.person[1] = person
    addressbook.person[1].id = addressbook1.id
    addressbook.person[1].name = addressbook1.name

    addressbook.person[2] = person
    addressbook.person[2].id = addressbook1.id
    addressbook.person[2].name = addressbook1.name

    addressbook.person[3] = person
    addressbook.person[3].id = addressbook1.id
    addressbook.person[3].name = addressbook1.name
	---[[
	--]]--
	--[[
	local addressbook={person={{phone={{}},test={}}}}
	addressbook.person[1].name = addressbook1.person[1].name
	addressbook.person[1].id = addressbook1.person[1].id
	addressbook.person[1].email = addressbook1.person[1].email
	addressbook.person[1].phone[1].number = addressbook1.person[1].phone[1].number
	addressbook.person[1].phone[1].type = addressbook1.person[1].phone[1].type
	addressbook.person[1].test[1] = addressbook1.person[1].test[1]
	addressbook.person[1].test[2] = addressbook1.person[1].test[2]
	--]]--
	code = pb.encode("tutorial.AddressBook", addressbook)
	msgpush(code, #code)

	--[[
	local texasm = {
		idx = {
			flag = 1,
			mid = 2,
			tid = 3,
			time = 1411209121,
		},
		contentData = "1l21o21i2",
	}
	code = pb.encode("network.cmd.PBTableCmd", texasm)
	local decode = pb.decode("network.cmd.PBTableCmd" , code)
	print(decode.idx.flag, decode.idx.mid, decode.idx.tid, decode.idx.time, decode.contentData)
	]]--
end

Register(1, 1, nil, c11)

local function onResp(code, resp, context)
	print(code, resp, context)
end
function testcase()
	--http.get("https://httpbin.org/get", onResp)
	-- http.post("https://httpbin.org/post", "[1,2,3]", onResp)
	print("dengqingwu")
	print("123")
end

--testcase()