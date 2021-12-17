package.path = package.path .. ";luascripts/libs/?.lua;"
package.cpath = package.cpath .. ";luascripts/libs/?.so;"

--eg: c_global-v1
CLIBS = {
    c_global = "c_global",
    c_hiredis = "c_hiredis",
    c_http = "c_http",
    c_log = "c_log",
    c_mutex = "c_mutex",
    c_net = "c_net",
    c_rand = "c_rand",
    c_texas = "c_texas",
    c_timer = "c_timer",
    c_utils = "c_utils",
    c_xml = "c_xml"
}

------------------------preload necessary directory begin----------------------------
local rand = require(CLIBS["c_rand"])
local utils = require(CLIBS["c_utils"])
local global = require(CLIBS["c_global"])

local function init()
    local ldir = {
        "luascripts/libs/",
        "luascripts/corelibs/",
        "luascripts/common/",
        "luascripts/servers/common/"
    }
    rand.seed()
    --overwrite
    _G.wh = {}
    for _, v in ipairs(ldir) do
        for fname in utils.dir(v) do
            if global.binary() then
                if string.find(fname, "[%d%w].lc$") ~= nil then
                    dofile(v .. fname)
                end
            elseif string.find(fname, "[%d%w].lua$") ~= nil then
                dofile(v .. fname)
            end
        end
    end
end

collectgarbage("collect")
init()

local function init_service()
    local stype = global.stype()
    local server = string.format("luascripts/servers/%d/", stype)
    for s in utils.dir(server) do
        if global.binary() then
            if string.find(s, "^[%w]+[%w_]*%.lc$") ~= nil then
                dofile(server .. s)
            end
        elseif string.find(s, "^[%w]+[%w_]*%.lua$") ~= nil then
            dofile(server .. s)
        end
    end
end

init_service()
------------------------preload necessary directory end----------------------------

--do profile test
--dofile("luascripts/servers/test/test.lua")

--do clibs test
--dofile("luascripts/servers/test/clibs.lua")

--do 3rdparty test
--dofile("luascripts/servers/test/3rdparty.lua")
