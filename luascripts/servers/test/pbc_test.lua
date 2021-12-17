local pb = require "protobuf"
--[[
addr = io.open("External/pbc/build/addressbook.pb","rb")
buffer = addr:read "*a"
addr:close()

protobuf.register(buffer)
--]]
pb.register_file "External/pbc/build/addressbook.pb"

--[[
t = protobuf.decode("google.protobuf.FileDescriptorSet", buffer)

proto = t.file[1]

print(proto.name)
print(proto.package)

message = proto.message_type

for _,v in ipairs(message) do
	print(v.name)
	for _,v in ipairs(v.field) do
		print("\t".. v.name .. " ["..v.number.."] " .. v.label)
	end
end
]]--

function dispatch(m, s, bin)
		local addressbook = {
			name = "Alice",
			id = 12345,
			email = "oeijfo31291029",
			phone = {
				{ number = "1301234567" },
				{ number = "87654321", type = "WORK" },
			},
			test = { 1,2,3,4,5},
		}


	--for i=1,100000 do
		local code = pb.encode("tutorial.Person", addressbook)
		--local decode = pb.decode("tutorial.Person" , bin)
--		print(decode.name)
--		print(decode.id)
--for _,v in ipairs(decode.phone) do
--	print("\t"..v.number, v.type)
--end
msgpush(code, #code)

	--end
end

--[[
print(decode.name)
print(decode.id)
for _,v in ipairs(decode.phone) do
	print("\t"..v.number, v.type)
end

phonebuf = protobuf.pack("tutorial.Person.PhoneNumber number","87654321")
buffer = protobuf.pack("tutorial.Person name id phone", "Alice", 123, { phonebuf })
print(protobuf.unpack("tutorial.Person name id phone", buffer))
]]--
