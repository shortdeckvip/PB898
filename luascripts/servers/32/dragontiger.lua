local rand = require(CLIBS["c_rand"])
local cjson = require("cjson")
local texas = require(CLIBS["c_texas"])
local redis = require(CLIBS["c_hiredis"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/poker")

local DRAGON_TIGER_WINTYPE = {
    DRAGON_TIGER_WINTYPE_DRAGON = 1,
    DRAGON_TIGER_WINTYPE_TIGER = 2,
    DRAGON_TIGER_WINTYPE_DRAW = 3
}

DragonTiger = DragonTiger or {}
setmetatable(DragonTiger, {__index = Poker})

function DragonTiger:new(o)
    o = o or {}
    setmetatable(o, {__index = self})

    o:init()
    return o
end

function DragonTiger:getWinType(dragonCard, tigerCard)
    local dragon_value = self:cardValue(dragonCard) % 0x0E
    local tiger_value = self:cardValue(tigerCard) % 0x0E
    if dragon_value > tiger_value then
        return DRAGON_TIGER_WINTYPE.DRAGON_TIGER_WINTYPE_DRAGON
    elseif dragon_value < tiger_value then
        return DRAGON_TIGER_WINTYPE.DRAGON_TIGER_WINTYPE_TIGER
    else
        return DRAGON_TIGER_WINTYPE.DRAGON_TIGER_WINTYPE_DRAW
    end
end
