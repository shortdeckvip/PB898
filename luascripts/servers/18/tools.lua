local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local timer = require(CLIBS["c_timer"])
local cjson = require("cjson")
local util = require("util")
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local redis = require(CLIBS["c_hiredis"])

local TimerID = {
    TimerID_Once = { 1, 2 * 1000 },      --id, interval(ms), timestamp(ms)
    TimerID_StopServer = { 2, 6 * 1000 } --id, interval(ms), timestamp(ms)
}

local ServerID = {
    -- 31 Cowboy
    2031617,
    -- 32 DT
    2097153,
    -- 35 AB
    2293761,
    -- 34 Rummy
    2228225,
    2228226,
    2228227,
    -- 33 TeenPatti
    2162689,
    2162690,
    2162691,
    -- 41 TeenPattiJoker
    2686977,
    2686978,
    2686979,
    -- 42 TeenPattiBet
    2752513,
    -- 43 Slots
    2818049
    --[[
    --26 texas
    1703937,
    1703938,
    1703939,
    --28 6+
    1835009,
    1835010,
    1835011,
    -- 36 domino
    2359297,
    -- 37 qiuqiu
    2424833,
    -- 38 pokdeng
    2490369,
    -- 39 samgong
    2555905,
    -- 40 dummy
    2621441
    --]]
}

local function forwardToGame(serverid, msg)
    return net.forward(
        serverid,
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Game"),
        pb.enum_id("network.inter.Game2GameSubCmdID", "Game2GameSubCmdID_ToolsForward"),
        pb.encode("network.inter.PBGame2GameToolsForward", msg)
    )
end

local function onTaskOnce(tm)
    local msg = {
        matchid = 1,
        roomid = 65536,
        jdata = cjson.encode({ a = 1, b = "str" })
    }
    log.info("sendto msg===> %s", cjson.encode(msg))
    forwardToGame(2031617, msg)

    timer.cancel(tm, TimerID.TimerID_Once[1])
end

local function onNotiyStopServer(tm)
    local msg = {
        matchid = 0,
        roomid = 0,
        jdata = cjson.encode({ api = "kickout" })
    }
    log.info("sendto msg===> %s", cjson.encode(msg))

    for _, v in ipairs(ServerID) do
        forwardToGame(v, msg)
    end

    timer.cancel(tm, TimerID.TimerID_StopServer[1])
end

local function onMiniGameProfit(tm)
    for _, v in ipairs(ServerID) do
        local room = { total_bets = {}, total_profit = {}, id = 65536 }
        local gameid = v >> 16
        if gameid == 31 or gameid == 32 or gameid == 35 or gameid == 42 or gameid == 43 then
            if gameid == 32 then
                room.robottotal_bets = {}
                room.robottotal_profit = {}
            end
            if gameid == 43 then
                room.id = gameid
            end

            Utils:unSerializeMiniGame(room, v)
            local totalbet, totalprofit, bankertotalbet, bankertotalprofit = 0, 0, 0, 0
            for _, vv in pairs(room.total_bets) do
                totalbet = totalbet + vv
            end
            for _, vv in pairs(room.total_profit) do
                totalprofit = totalprofit + vv
            end
            if gameid == 32 then
                for _, vv in pairs(room.robottotal_bets) do
                    bankertotalbet = bankertotalbet + vv
                end
                for _, vv in pairs(room.robottotal_profit) do
                    bankertotalprofit = bankertotalprofit + vv
                end
            end
            if totalbet > 0 then
                if gameid == 32 and bankertotalbet > 0 then
                    log.info(
                        "%s profit_rate=%s banker_profit_rate=%s",
                        gameid,
                        1 - totalprofit / totalbet,
                        bankertotalprofit / bankertotalbet
                    )
                else
                    log.info("%s profit_rate=%s", gameid, 1 - totalprofit / totalbet)
                end
            end
        end
    end

    timer.cancel(tm, TimerID.TimerID_Once[1])
end

local function onUserKVData(tm)
    local uid = 1001
    local op = 0
    local v = { gameid = 43, bv = 100000, win = { { type = 1, cnt = 10 }, { type = 2, cnt = 5 } } }
    local updata = { k = "1001|43", v = cjson.encode(v) }
    Utils:updateUserInfo({ uid = uid, op = op, data = { updata } })
    timer.cancel(tm, TimerID.TimerID_Once[1])
end

--补偿牌局
local function onStatisticLog(tm)
    local json_text = util.file_load("gamelog.json")
    local sdata = cjson.decode(json_text)
    local statistic = Statistic:new(sdata["roomid"], sdata["matchid"])
    statistic:appendLogs(sdata["data"], sdata["logid"])
    timer.cancel(tm, TimerID.TimerID_Once[1])
end

--补偿金币
local function onMoneyLog(tm)
    local json_text = util.file_load("moneylog.json")
    local sdata = cjson.decode(json_text)
    local timestamp = tonumber(sdata["timestamp"])*1000
    local balance = tonumber(sdata["balance"])
    local data = sdata["data"]
    local from = (balance + 0.001) * 100 - tonumber(data["data"][1].coin)
    local msg = {
        mcs = {
            {
                uid = data["data"][1].uid,
                time = timestamp,
                type = 2,
                reason = data["data"][1].reason,
                gameid = data["srvid"] >> 16,
                extrainfo = data["data"][1].extrainfo,
                from = from,
                cto = (balance + 0.001) * 100,
                changed = data["data"][1].coin,
                api = data["data"][1].api,
                ip = data["data"][1].ip,
            }
        }
    }
    log.info("moneylog %s", cjson.encode(msg))
    Utils:reportMoneyLog(msg)
    timer.cancel(tm, TimerID.TimerID_Once[1])
end


local function StartTask()
    local tm = timer.create()
    if global.lowsid() == 0 then     --1179648
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onTaskOnce, tm)
    elseif global.lowsid() == 1 then --1179649
        timer.tick(tm, TimerID.TimerID_StopServer[1], TimerID.TimerID_StopServer[2], onNotiyStopServer, tm)
    elseif global.lowsid() == 2 then --1179650
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onMiniGameProfit, tm)
    elseif global.lowsid() == 3 then --1179651
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onUserKVData, tm)
    elseif global.lowsid() == 4 then --1179652
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onStatisticLog, tm)
    elseif global.lowsid() == 5 then --1179653
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onMoneyLog, tm)
    end
end

StartTask()
