local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

DUMMYCONF = {
    CONFCARDS = {
        {
            0x106,
            0x206,
            0x105,
            0x205,
            0x305,
            0x405,
            0x107
        },
        {
            0x207,
            0x307,
            0x108,
            0x208,
            0x308,
            0x408,
            0x306
        }
    }
}

MatchMgr:init(TABLECONF)
