local pb = require('protobuf')
local log = require(CLIBS['c_log'])
local timer = require(CLIBS['c_timer'])
local cjson = require('cjson')
local net = require(CLIBS['c_net'])
local global = require(CLIBS['c_global'])
local redis = require(CLIBS['c_hiredis'])

local TimerID = {
    TimerID_Once = {1, 3 * 1000}, --id, interval(ms), timestamp(ms)
    TimerID_StopServer = {2, 6 * 1000} --id, interval(ms), timestamp(ms)
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
    2752513
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
        pb.enum_id('network.inter.ServerMainCmdID', 'ServerMainCmdID_Game2Game'),
        pb.enum_id('network.inter.Game2GameSubCmdID', 'Game2GameSubCmdID_ToolsForward'),
        pb.encode('network.inter.PBGame2GameToolsForward', msg)
    )
end

local function onTaskOnce(tm)
    local msg = {
        matchid = 1,
        roomid = 65536,
        jdata = cjson.encode({a = 1, b = 'str'})
    }
    log.info('sendto msg===> %s', cjson.encode(msg))
    forwardToGame(2031617, msg)

    timer.cancel(tm, TimerID.TimerID_Once[1])
end

local function onNotiyStopServer(tm)
    local msg = {
        matchid = 0,
        roomid = 0,
        jdata = cjson.encode({api = 'kickout'})
    }
    log.info('sendto msg===> %s', cjson.encode(msg))

    for _, v in ipairs(ServerID) do
        forwardToGame(v, msg)
    end

    timer.cancel(tm, TimerID.TimerID_StopServer[1])
end

local function onMiniGameProfit(tm)
    for _, v in ipairs(ServerID) do
        local room = {total_bets = {}, total_profit = {}, id = 65536}
        local gameid = v >> 16
        if gameid == 31 or gameid == 32 or gameid == 35 or gameid == 42 then
            if gameid == 32 then
                room.robottotal_bets = {}
                room.robottotal_profit = {}
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
                        '%s profit_rate=%s banker_profit_rate=%s',
                        gameid,
                        1 - totalprofit / totalbet,
                        bankertotalprofit / bankertotalbet
                    )
                else
                    log.info('%s profit_rate=%s', gameid, 1 - totalprofit / totalbet)
                end
            end
        end
    end

    timer.cancel(tm, TimerID.TimerID_Once[1])
end

local function onUserKVData(tm)
    local uid = 1001
    local op = 0
    local v = {gameid = 43, bv = 100000, win = {{type = 1, cnt = 10}, {type = 2, cnt = 5}}}
    local updata = {k = '1001|43', v = cjson.encode(v)}
    Utils:updateUserInfo({uid = uid, op = op, data = {updata}})
    timer.cancel(tm, TimerID.TimerID_Once[1])
end

local function StartTask()
    local tm = timer.create()
    if global.lowsid() == 0 then --1179648
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onTaskOnce, tm)
    elseif global.lowsid() == 1 then --1179649
        timer.tick(tm, TimerID.TimerID_StopServer[1], TimerID.TimerID_StopServer[2], onNotiyStopServer, tm)
    elseif global.lowsid() == 2 then --1179650
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onMiniGameProfit, tm)
    elseif global.lowsid() == 3 then --1179651
        timer.tick(tm, TimerID.TimerID_Once[1], TimerID.TimerID_Once[2], onUserKVData, tm)
    end
end

StartTask()
