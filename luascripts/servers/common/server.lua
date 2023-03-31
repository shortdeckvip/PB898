local log = require(CLIBS["c_log"])
local pb = require("protobuf")
local global = require(CLIBS["c_global"])
local mutex = require(CLIBS["c_mutex"])
local g = require("luascripts/common/g")
require("luascripts/servers/common/uploadplayercount")

function OnServerStartUp()
    local function doRun()
        if
            global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Texas") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_TShort") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_TeemPatti") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Joker") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_QiuQiu") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Rummy") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Slot") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_SlotFarm") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_SlotSea") or
                global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_SlotShip")
         then
            JackpotMgr:init()
        end
        if global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Slot") then
            Utils:unSerializeMiniGame(SLOT_INFO, nil, global.stype()) -- 获取该玩家最近几天的所有押注信息
            log.debug("dqw Utils:unSerializeMiniGame(SLOT_INFO)")
        elseif global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_SlotFarm") then
            Utils:unSerializeMiniGame(SLOT_FARM_INFO, nil, global.stype()) -- 获取该玩家最近几天的所有押注信息
        elseif global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_SlotSea") then
            Utils:unSerializeMiniGame(SLOT_SEA_INFO, nil, global.stype()) -- 获取该玩家最近几天的所有押注信息
        elseif global.stype() == pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_SlotShip") then
            Utils:unSerializeMiniGame(SLOT_SHIP_INFO, nil, global.stype()) -- 获取该玩家最近几天的所有押注信息
        end
        UploadPlayerModule.enableUploadPlayerCount()
    end
    g.call(doRun)
end

function OnServerStop()
    log.debug("on server stopping %s", global.sid())
    local function doRun()
        MatchMgr:kickout()
    end
    g.call(doRun)
end

function OnServerRegister()
end

function OnAccessServerCrash(srvid)
    local function doRun()
        MatchMgr:clearRoomUsersBySrvId(srvid)
    end
    g.call(doRun)
end

function OnPlayerLogout(uid, mid, rid)
    log.debug("user logout:%s,%s", tostring(uid), tostring(rid))
    local function doRun()
        local r = MatchMgr:getRoomById(mid, rid)
        if r ~= nil then
            r:logout(uid)
        else
            for id, _ in pairs(MatchMgr:getMatchMgr()) do
                for _, room in pairs(MatchMgr:getMatchById(id):getRoomMgr()) do
                    room:logout(uid)
                end
            end
        end
    end
    g.call(doRun)
end

function OnMutexServerCrash(srvid)
    log.debug("OnMutexServerCrash:%s", srvid)
end

function OnMutexServerRegister()
    local function doRun()
        local t = {
            srvid = global.sid(),
            data = {}
        }
        MatchMgr:getAllUsers(t)
        mutex.request(
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
            pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexSynchronize"),
            pb.encode("network.cmd.PBMutexDataSynchronize", t)
        )
    end
    g.call(doRun)
end
