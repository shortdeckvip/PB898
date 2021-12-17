local log = require(CLIBS["c_log"])
local g = require("luascripts/common/g")

local msgparser = {}
local forward_msgparser = {}

function msgparser.register(maincmd, subcmd, cb)
    local msg = wh.msg
    msg[maincmd] = msg[maincmd] or {}
    msg[maincmd][subcmd] = msg[maincmd][subcmd] or {}
    msg[maincmd][subcmd].cb = cb
end

function msgparser.hasmsg(maincmd, subcmd)
    local msg = wh.msg
    if msg[maincmd] == nil then
        log.error("%s", string.format("maincmd is nil 0x%x 0x%x", maincmd, subcmd))
        return false
    end
    if msg[maincmd][subcmd] == nil then
        log.error("%s", string.format("subcmd is nil 0x%x 0x%x", maincmd, subcmd))
        return false
    end
    return true
end

function msgparser.dispatch(uid, linkid, maincmd, subcmd, msg)
    wh.msg[maincmd][subcmd].cb(uid, linkid, msg)
end

function Register(maincmd, subcmd, name, cb)
    wh.mp.register(maincmd, subcmd, cb)
end

function Dispatch(uid, linkid, maincmd, subcmd, msg)
    local function doRun()
        if wh.mp.hasmsg(maincmd, subcmd) == false then
            return
        end
        wh.mp.dispatch(uid, linkid, maincmd, subcmd, msg)
    end

	g.call(doRun)
end

-----------------------------forward msg----------------------------
function forward_msgparser.register(maincmd, subcmd, cb)
    local msg = wh.forward_msg
    msg[maincmd] = msg[maincmd] or {}
    msg[maincmd][subcmd] = msg[maincmd][subcmd] or {}

    msg[maincmd][subcmd].cb = cb
end

function forward_msgparser.hasmsg(maincmd, subcmd)
    local msg = wh.forward_msg
    if msg[maincmd] == nil then
        log.error("%s", string.format("forward maincmd is nil 0x%x 0x%x", maincmd, subcmd))
        return false
    end
    if msg[maincmd][subcmd] == nil then
        log.error("%s", string.format("forward subcmd is nil 0x%x 0x%x", maincmd, subcmd))
        return false
    end
    return true
end

function forward_msgparser.dispatch(uid, linkid, maincmd, subcmd, msg)
    if not wh.forward_msg[maincmd][subcmd].cb then
        log.error("no callback %s %s", maincmd, subcmd)
    end
    wh.forward_msg[maincmd][subcmd].cb(uid, linkid, msg)
end

function Forward_Register(maincmd, subcmd, name, cb)
    wh.forward_mp.register(maincmd, subcmd, cb)
end

function Forward_Dispatch(uid, linkid, maincmd, subcmd, msg)
    local function doRun()
        if wh.forward_mp.hasmsg(maincmd, subcmd) == false then
            return
        end
        wh.forward_mp.dispatch(uid, linkid, maincmd, subcmd, msg)
    end

	g.call(doRun)
end
-----------------------------forward msg----------------------------

local function init()
    wh.mp = wh.mp or msgparser
    wh.msg = wh.msg or {}
    wh.forward_mp = wh.forward_mp or forward_msgparser
    wh.forward_msg = wh.forward_msg or {}
end
init()
