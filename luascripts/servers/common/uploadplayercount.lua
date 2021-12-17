local timer = require(CLIBS["c_timer"])
local global = require(CLIBS["c_global"])
local net = require(CLIBS["c_net"])
local pb = require("protobuf")
local cjson = require("cjson")
local log = require(CLIBS["c_log"])
local g = require("luascripts/common/g")

local checkcount = 0

-- 上传房间列表? 
local function uploadRoomList()
    local tpu = {tpentry = {}}
    for mid, mmgr in pairs(MatchMgr:getMatchMgr()) do
        local conf = MatchMgr:getConfByMid(mid)
        for rid, r in pairs(mmgr:getRoomMgr()) do
            local players = r:count()
            table.insert(
                tpu.tpentry,
                {
                    gameid = global.stype(),
                    roomtype = conf and conf.roomtype or 0,  -- 房间类型(金币/豆子)
                    tag = conf and conf.tag or 0,
                    serverid = global.sid(),
                    matchid = mid,
                    roomid = rid,
                    players = players
                }
            )
        end
    end
    --log.debug('PBTablePlayersUpdate %s', cjson.encode(t))
    --print('PBTablePlayersUpdate %s', cjson.encode(tpu))
    net.forward(
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_TList") << 16,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2TList"),
        pb.enum_id("network.inter.Game2TListSubCmd", "Game2TListSubCmd_TablePlayersUpdate"),
        pb.encode("network.inter.PBTablePlayersUpdate", tpu)
    )
end

local function onUploadCheck()
    --print('******************* UploadPlayerCount onUploadCheck *******************')
    uploadRoomList()

    --print('---------------', checkcount % 24, '---------------')
    if checkcount == 0 then -- 60 * 1 = 60 (1 min)
        local pa = {
            serverid = global.sid(),
            apis = {}
        }
        local t = {}
        for _, mmgr in pairs(MatchMgr:getMatchMgr()) do
            for _, r in pairs(mmgr:getRoomMgr()) do
                local tmp = r:getApiUserNum()
                for api, t1 in pairs(tmp) do
                    if type(t1) == "table" then
                        for roomtype, t2 in pairs(t1) do
                            t[api] = t[api] or {}
                            t[api][roomtype] =
                                t[api][roomtype] or {api = api, roomtype = roomtype, players = 0, viewplayers = 0}
                            if t[api] and t[api][roomtype] then
                                t[api][roomtype].players = (t[api][roomtype].players or 0) + (t2.players or 0)
                                t[api][roomtype].viewplayers =
                                    (t[api][roomtype].viewplayers or 0) + (t2.viewplayers or 0)
                            end
                        end
                    end
                end
            end
        end
        for _, v in pairs(t) do
            for _, vv in pairs(v) do
                table.insert(pa.apis, vv)
            end
        end
        if #pa.apis > 0 then
            net.forward(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Notify") << 16,
                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Servers2Notify"),
                pb.enum_id("network.inter.Servers2NotifySubCmdID", "Servers2NotifySubCmdID_PlayerApi"),
                pb.encode("network.inter.PBPlayerApi", pa)
            )
        end
    end
    checkcount = (checkcount + 1) % 10
end

local TimerID = {
    -- id, interval
    TimerID_Default = {10001, 1000}
}
UploadPlayerModule = UploadPlayerModule or {UploadPlayerCount_Timer = timer.create()}
function UploadPlayerModule.enableUploadPlayerCount()
    timer.tick(
        UploadPlayerModule.UploadPlayerCount_Timer,
        TimerID.TimerID_Default[1],
        TimerID.TimerID_Default[2],
        onUploadCheck,
        nil
    )
end

function UploadPlayerModule.onRoomChange()
    uploadRoomList()
end
