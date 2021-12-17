local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

TEEMPATTICONF = {
    max_blind_cnt = 4,      --盲下次数上限
    max_chaal_limit = 128,  --看牌后最高倍数
    max_pot_limit = 1024,   --底池达到上限强制结束
}

MatchMgr:init(TABLECONF)