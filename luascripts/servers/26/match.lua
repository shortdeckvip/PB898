local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

MatchMgr:init(TABLECONF)