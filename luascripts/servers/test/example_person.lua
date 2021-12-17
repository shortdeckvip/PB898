-- load lua-pb first.
require "pb"

-- now you can use require to load person.proto
require "pb_person"
local pbs = require "pb_person"
function encode()
	local msg = pbs.Person()
	msg.name = "John Doe"
	msg.id = 1234
	msg.email = "jdoe@example.com"

	local phone_work = pbs.Person.PhoneNumber()
	phone_work.type = pbs.Person.PhoneType.WORK
	phone_work.number = "123-456-7890"
	msg.phone = {phone_work}

	msg.ages = {1,2,3,4,5}
	msg.tel = {"123"}

	--pb.print(msg)

	--print("Encode person message to binary.")
	local bin = assert(msg:Serialize())
	--msgpush(bin, #bin)
	--print("bytes =", #bin)
end

function dispatch(maincmd, subcmd, bin)
	--local msg2 = pbs.Person():Parse(bin)
	--pb.print(msg2)
	--print("======================")
	for i=1,100000 do
		encode()
	end
end
