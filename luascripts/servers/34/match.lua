local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/room", global.stype()))

RUMMYCONF = {
    --最高分数
    MAX_SCORE_VALUE = 80,
    NOT_DRAW_SCORE = 20,
    HAS_DRAWED_SCORE = 40,
    CONFCARDS = {
        --[[
        magiccard = 0x106,
        groupcards = {
            {
                {
                    cards = {
                        1770242,
                        3540240,
                        3474703
                    }
                },
                {
                    cards = {
                        1901316,
                        1966853,
                        4719110,
                        2884614
                    }
                },
                {
                    cards = {
                        196868,
                        1049092,
                        2753540
                    }
                },
                {
                    cards = {
                        5243406,
                        852238,
                        3408910
                    }
                }
            }
        }
        --]]
    }
}

MatchMgr:init(TABLECONF)
