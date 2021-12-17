-- dqw 多米诺房间配置
local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

MatchMgr:init(TABLECONF)
