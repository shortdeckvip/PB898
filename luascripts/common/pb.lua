local pb = require("protobuf")
local utils = require(CLIBS["c_utils"])

--preload dependency proto
local protodir = "luascripts/proto/"
pb.register_file(protodir .. "cmdid.pb")
pb.register_file(protodir .. "common.pb")
pb.register_file(protodir .. "cmd.pb")
pb.register_file(protodir .. "server.pb")
pb.register_file(protodir .. "userinfo.pb")

for fname in utils.dir(protodir) do
	if string.find(fname, "[%d%w].pb") ~= nil then
		pb.register_file("luascripts/proto/" .. fname)
	end
end
