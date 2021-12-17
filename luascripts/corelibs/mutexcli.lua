local log = require(CLIBS["c_log"])
local g = require("luascripts/common/g")

local mutexcli = {}

function mutexcli.register(maincmd, subcmd, cb)
	local msg = wh.mutexcli_msg
	msg[maincmd] = msg[maincmd] or {}
	msg[maincmd][subcmd] = msg[maincmd][subcmd] or {}

	msg[maincmd][subcmd].cb = cb
end

function mutexcli.hasmsg(maincmd, subcmd)
	local msg = wh.mutexcli_msg
	if msg[maincmd] == nil then
		log.info("%s", string.format("mutex maincmd is nil 0x%x", maincmd))
		return false
	end
	if msg[maincmd][subcmd] == nil then
		log.info("%s", string.format("mutex subcmd is nil 0x%x", subcmd))
		return false
	end
	return true
end

function mutexcli.dispatch(linkid, maincmd, subcmd, msg)
	wh.mutexcli_msg[maincmd][subcmd].cb(linkid, msg)
end

function Mutexcli_Register(maincmd, subcmd, name, cb)
	wh.mutexcli_mp.register(maincmd, subcmd, cb)
end

function Mutexcli_Dispatch(linkid, maincmd, subcmd, msg)
    local function doRun()
        if wh.mutexcli_mp.hasmsg(maincmd, subcmd) == false then
            return
        end
        wh.mutexcli_mp.dispatch(linkid, maincmd, subcmd, msg)
    end
	g.call(doRun)
end

local function init()
	wh.mutexcli_mp = wh.mutexcli_mp or mutexcli
	wh.mutexcli_msg = wh.mutexcli_msg or {}
end
init()
