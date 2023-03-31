local pb = require("protobuf")
local timer = require(CLIBS["c_timer"])
local log = require(CLIBS["c_log"])
local net = require(CLIBS["c_net"])
local global = require(CLIBS["c_global"])
local cjson = require("cjson")
local mutex = require(CLIBS["c_mutex"])
local rand = require(CLIBS["c_rand"])
local g = require("luascripts/common/g")
local cfgcard = require("luascripts/servers/common/cfgcard")
require("luascripts/servers/common/uniqueid")
require("luascripts/servers/common/statistic")

Room = Room or {}

-- 定时器信息
local TimerID = {
    TimerID_Check = { 1, 1000 }, --id, interval(ms), timestamp(ms)
    TimerID_Timeout = { 2, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_MutexTo = { 3, 5 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_FreeSpinTimes = { 4, 3 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Result = { 5, 3 * 1000, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_Wallet = { 6, 200, 0 }, --id, interval(ms), timestamp(ms)
    TimerID_WaitJackpotResult = { 7, 1500, 0 },
    TimerID_BroadCastMsg = { 8, 7000, 0 } -- 延迟广播
}


-- 房间状态
local EnumRoomState = {
    Check = 1,
    Start = 2,
    Betting = 3, -- 下注状态
    Show = 4,
    Finish = 5
}


-- 玩家状态
local EnumUserState = {
    Intoing = 1, -- 进入
    Playing = 2, -- 正在玩
    Logout = 3, -- 退出
    Leave = 4 -- 离开
}

-- 牌型
local EnumCardType = {
    Pic_1_Banana = 1, --香蕉
    Pic_2_Cherry = 2, --樱桃
    Pic_3_Lemon = 3, --柠檬
    Pic_4_Fraise = 4, --草莓
    Pic_5_Grape = 5, --葡萄
    Pic_6_Watermelon = 6, --西瓜
    Pic_7_Mango = 7, --芒果
    Pic_8_Bar_One = 8,
    Pic_9_Bar_Two = 9,
    Pic_10_Bar_Three = 10,
    Pic_11_Wild = 11, --帽子
    Pic_12_Free_Spins = 12, --免费旋转
    Pic_13_Scatter = 13 --红7  中JackPot用
}


-- 获取该游戏线条条数
-- 参数 gameid: 游戏ID = global.stype() -- 游戏ID
local function GetLineNum()
    local gameid = global.stype() -- 游戏ID
    if gameid == 43 then
        return 10
    elseif gameid == 49 then
        log.debug("GetLineNum(), #SLOT_CONF.lineInfoFarm = %s", #SLOT_CONF.lineInfoFarm)
        return #SLOT_CONF.lineInfoFarm
    elseif gameid == 50 then
        return #SLOT_CONF.lineInfoSea
    elseif gameid == 51 then
        return #SLOT_CONF.lineInfoShip
    end
    return 10 -- 默认是10条线
end

-- 获取该游戏线条信息
-- 参数 gameid: 游戏ID = global.stype() -- 游戏ID
local function GetLineInfo(gameid)
    --local gameid = global.stype() -- 游戏ID
    if gameid == 43 then
        return SLOT_CONF.lineInfo
    elseif gameid == 49 then
        return SLOT_CONF.lineInfoFarm
    elseif gameid == 50 then
        return SLOT_CONF.lineInfoSea
    elseif gameid == 51 then
        return SLOT_CONF.lineInfoShip
    end
    return SLOT_CONF.lineInfo
end

-- 获取行数(3行5列，共15张图)
local function GetRowNum()
    return 3
end

-- 获取列数(3行5列，共15张图)
local function GetColNum()
    return 5
end

-- 根据某列中各图标的权重随机获取一个图标
-- 参数 conf: 配置信息
-- 参数 colIndex: 列号 [1,5]
-- 参数 totalValue: 该列总的权重
-- 返回值: 返回随机分配的牌
local function GetRandId(conf, colIndex, totalValue)
    local val = rand.rand_between(0, totalValue)
    if 1 == colIndex then
        for k, v in ipairs(conf) do
            if val <= v.first then
                return v.id
            end
            val = val - v.first
        end
    elseif 2 == colIndex then
        for k, v in ipairs(conf) do
            if val <= v.second then
                return v.id
            end
            val = val - v.second
        end
    elseif 3 == colIndex then
        for k, v in ipairs(conf) do
            if val <= v.third then
                return v.id
            end
            val = val - v.third
        end
    elseif 4 == colIndex then
        for k, v in ipairs(conf) do
            if val <= v.fourth then
                return v.id -- 返回随机获取到的图标[1,13]
            end
            val = val - v.fourth
        end
    else -- 第5列
        for k, v in ipairs(conf) do
            if val <= v.fifth then
                return v.id
            end
            val = val - v.fifth
        end
    end
    return conf[#conf].id
end

-- 随机获取牌数据(共15张牌)
-- 参数 slotConf: 游戏配置信息
-- 参数 type: 难度级别 1-简单  2-正常  3-困难  4-免费旋转
local function GetCards(slotConf, type)
    local firstCol = 0 -- 第1列总权值
    local secondCol = 0 -- 第2列总权重
    local thirdCol = 0
    local fourthCol = 0
    local fifthCol = 0 -- 第5列总的权值
    local cards = {} -- 待返回的牌数据 15张牌(从左到右，从上到下)
    if not slotConf then
        return nil
    end
    if 1 == type then -- 简单
        for k, v in pairs(slotConf.simple) do
            if v then
                firstCol = firstCol + v.first
                secondCol = secondCol + v.second
                thirdCol = thirdCol + v.third
                fourthCol = fourthCol + v.fourth
                fifthCol = fifthCol + v.fifth
            end
        end

        local id = 1
        -- for i = 1, 3, 1 do
        for i = 1, slotConf.lineRow, 1 do
            id = GetRandId(slotConf.simple, 1, firstCol) -- 获取第一列值
            table.insert(cards, id)
            id = GetRandId(slotConf.simple, 2, secondCol) -- 获取第二列值
            table.insert(cards, id)
            id = GetRandId(slotConf.simple, 3, thirdCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.simple, 4, fourthCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.simple, 5, fifthCol) --获取第五列值
            table.insert(cards, id)
        end
    elseif 2 == type then -- 正常
        for k, v in pairs(slotConf.normal) do
            if v then
                firstCol = firstCol + v.first
                secondCol = secondCol + v.second
                thirdCol = thirdCol + v.third
                fourthCol = fourthCol + v.fourth
                fifthCol = fifthCol + v.fifth
            end
        end
        local id = 1
        for i = 1, slotConf.lineRow, 1 do
            id = GetRandId(slotConf.normal, 1, firstCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.normal, 2, secondCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.normal, 3, thirdCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.normal, 4, fourthCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.normal, 5, fifthCol)
            table.insert(cards, id)
        end
    elseif 3 == type then -- 困难级别
        for k, v in pairs(slotConf.hard) do
            if v then
                firstCol = firstCol + v.first
                secondCol = secondCol + v.second
                thirdCol = thirdCol + v.third
                fourthCol = fourthCol + v.fourth
                fifthCol = fifthCol + v.fifth
            end
        end
        local id = 1
        for i = 1, slotConf.lineRow, 1 do
            id = GetRandId(slotConf.hard, 1, firstCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.hard, 2, secondCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.hard, 3, thirdCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.hard, 4, fourthCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.hard, 5, fifthCol)
            table.insert(cards, id)
        end
    else -- freeSpin
        for k, v in pairs(slotConf.freeSpin) do
            if v then
                firstCol = firstCol + v.first
                secondCol = secondCol + v.second
                thirdCol = thirdCol + v.third
                fourthCol = fourthCol + v.fourth
                fifthCol = fifthCol + v.fifth
            end
        end
        local id = 1
        for i = 1, slotConf.lineRow, 1 do
            id = GetRandId(slotConf.freeSpin, 1, firstCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.freeSpin, 2, secondCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.freeSpin, 3, thirdCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.freeSpin, 4, fourthCol)
            table.insert(cards, id)
            id = GetRandId(slotConf.freeSpin, 5, fifthCol)
            table.insert(cards, id)
        end
    end
    return cards
end

--
-- 1  2  3  4  5
-- 6  7  8  9  10
-- 11 12 13 14 15
--
-- 根据牌数据获取某条线上的牌数据(5张牌)
-- 参数 lineNo: 线号[1,50]
-- 参数 cards: 牌数据15张(从左到右，从上到下)
-- 参数 slotConf: slot配置信息
local function GetLineData(lineNo, cards, slotConf)
    local lineData = {}
    local lineInfo = GetLineInfo(global.stype())
    -- lineData[1] = cards[(lineInfo[lineNo].col[1] - 1) * GetColNum() + 1]
    -- lineData[2] = cards[(lineInfo[lineNo].col[2] - 1) * GetColNum() + 2]
    -- lineData[3] = cards[(lineInfo[lineNo].col[3] - 1) * GetColNum() + 3]
    -- lineData[4] = cards[(lineInfo[lineNo].col[4] - 1) * GetColNum() + 4]
    -- lineData[5] = cards[(lineInfo[lineNo].col[5] - 1) * GetColNum() + 5]

    lineData[1] = cards[(3 - lineInfo[lineNo].col[1]) * GetColNum() + 1]
    lineData[2] = cards[(3 - lineInfo[lineNo].col[2]) * GetColNum() + 2]
    lineData[3] = cards[(3 - lineInfo[lineNo].col[3]) * GetColNum() + 3]
    lineData[4] = cards[(3 - lineInfo[lineNo].col[4]) * GetColNum() + 4]
    lineData[5] = cards[(3 - lineInfo[lineNo].col[5]) * GetColNum() + 5]
    log.debug("GetLineData(),lineData=%s", cjson.encode(lineData))
    return lineData
end

-- 获取Jackpot元素个数
local function GetScatterNum(cards)
    local num = 0
    for k, v in ipairs(cards) do
        if v == 13 then
            num = num + 1
        end
    end
    return num
end

-- 获取FreeSpins元素个数
local function GetFreeSpinsNum(cards)
    local num = 0
    for k, v in ipairs(cards) do
        if v == 12 then
            num = num + 1
        end
    end
    return num
end

-- 根据线条数据(该线上的5张图)计算赢的倍数
-- 参数 LineData: 这条线数据(5张)
-- 参数 slotConf: 配置信息(赔率) SLOT_CONF
-- 参数 type: 困难度  1-简单  2-正常  3-困难  4-免费旋转
-- 返回值: 返回该线中奖倍率+几连
local function GetWinType(lineData, slotConf, type)
    --计算连续的图片张数
    local iNum = 1 -- 连续的牌张数
    local first = lineData[1] -- 第一张数据
    if (lineData[1] > 11) then
        return 0, 1
    end

    for i = 2, 5, 1 do
        if lineData[i] == first then
            iNum = iNum + 1
        elseif lineData[i] == 11 and first <= 11 then -- Wild
            iNum = iNum + 1
        elseif first == 11 and lineData[i] <= 11 then
            first = lineData[i]
            iNum = iNum + 1
        else
            break
        end
    end

    if iNum < 2 then
        return 0, 1
    end

    --SLOT_CONF
    if type == 1 then -- 简单
        if iNum == 2 then -- 2连
            return slotConf.simple[first].times2, iNum -- 返回中奖倍数, 几连
        elseif iNum == 3 then -- 3连
            return slotConf.simple[first].times3, iNum
        elseif iNum == 4 then
            return slotConf.simple[first].times4, iNum
        elseif iNum == 5 then
            return slotConf.simple[first].times5, iNum
        end
    elseif type == 2 then --正常
        if iNum == 2 then -- 2连
            return slotConf.normal[first].times2, iNum -- 返回中奖倍数, 几连
        elseif iNum == 3 then -- 3连
            return slotConf.normal[first].times3, iNum
        elseif iNum == 4 then
            return slotConf.normal[first].times4, iNum
        elseif iNum == 5 then
            return slotConf.normal[first].times5, iNum
        end
    elseif type == 3 then -- 困难
        if iNum == 2 then -- 2连
            return slotConf.hard[first].times2, iNum -- 返回中奖倍数, 几连
        elseif iNum == 3 then -- 3连
            return slotConf.hard[first].times3, iNum
        elseif iNum == 4 then
            return slotConf.hard[first].times4, iNum
        elseif iNum == 5 then
            return slotConf.hard[first].times5, iNum
        end
    elseif type == 4 then -- 免费旋转
        if iNum == 2 then -- 2连
            return slotConf.freeSpin[first].times2, iNum -- 返回中奖倍数, 几连
        elseif iNum == 3 then -- 3连
            return slotConf.freeSpin[first].times3, iNum
        elseif iNum == 4 then
            return slotConf.freeSpin[first].times4, iNum
        elseif iNum == 5 then
            return slotConf.freeSpin[first].times5, iNum
        end
    end
end

-- 根据15张牌数据计算本次所有线条赢取的倍数
-- 参数 cards: 15张牌数据(从左到右，从上到下)
-- 参数 slotConf: 配置信息(赔率) SLOT_CONF
-- 参数 type: 困难度  1-简单  2-正常  3-困难
-- 参数 lineNum: 该游戏线条总条数
-- 返回值: 返回本局所有线条赢得的倍数
local function GetAllLineWinTimes(cards, slotConf, type, lineNum)
    local lineCards = {}
    local winLineTimes = 0
    for i = 1, lineNum do -- 遍历每条线
        log.debug("GetAllLineWinTimes(),i=%s", i)
        lineCards = GetLineData(i, cards, slotConf)
        winLineTimes = winLineTimes + GetWinType(lineCards, slotConf, type)
    end
    return winLineTimes
end

-- 根据15张牌数据计算本次赢取的免费次数
-- 参数 cards: 15张牌数据(从左到右，从上到下)
-- 参数 slotConf: 配置信息(赔率) SLOT_CONF
-- 参数 type: 困难度  1-简单  2-正常  3-困难
-- 返回值: 返回本局赢得的免费旋转次数
local function GetWinFreeSpinTimes(cards, slotConf, type)
    local iNum = GetFreeSpinsNum(cards)
    if iNum < 3 then
        return 0
    end
    --SLOT_CONF
    if type == 1 then -- 简单
        if iNum == 2 then -- 2连
            return slotConf.simple[12].times2 -- 返回中免费旋转次数
        elseif iNum == 3 then -- 3连
            return slotConf.simple[12].times3
        elseif iNum == 4 then
            return slotConf.simple[12].times4
        elseif iNum == 5 then
            return slotConf.simple[12].times5
        end
    elseif type == 2 then --正常
        if iNum == 2 then -- 2连
            return slotConf.normal[12].times2 --  返回中免费旋转次数
        elseif iNum == 3 then -- 3连
            return slotConf.normal[12].times3
        elseif iNum == 4 then
            return slotConf.normal[12].times4
        elseif iNum == 5 then
            return slotConf.normal[12].times5
        end
    elseif type == 3 then -- 困难
        if iNum == 2 then -- 2连
            return slotConf.hard[12].times2 --  返回中免费旋转次数
        elseif iNum == 3 then -- 3连
            return slotConf.hard[12].times3
        elseif iNum == 4 then
            return slotConf.hard[12].times4
        elseif iNum == 5 then
            return slotConf.hard[12].times5
        end
    end
    return 0
end

-- 查询结果超时处理
local function onResultTimeout(arg)
    arg[1]:queryUserResult(false, nil)
end

function Room:queryUserResult(ok, ud)
    if self.timer and self.confInfo.single_profit_switch then
        timer.cancel(self.timer, TimerID.TimerID_Result[1])
        log.info("idx(%s,%s) query userresult ok:%s", self.id, self.mid, tostring(ok))
        coroutine.resume(self.result_co, ok, ud)
    end
end

local function onWalletTimeout(arg)
    local self = arg[1]
    local t = arg[2]
    local linkid = arg[3]
    if self.timer then
        timer.cancel(self.timer, TimerID.TimerID_Wallet[1])
        log.info("idx(%s,%s) wait for %s ms", self.id, self.mid, TimerID.TimerID_Wallet[2])
        self:doResult(t, linkid)
    end
end

--
local function onWaitJackpotResult(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_WaitJackpotResult[1]) -- 关闭定时器
        if self.needJackPotResult then
            self.needJackPotResult = false

            self.state = EnumRoomState.Check
            log.debug("uid=%s, state=%s,onWaitJackpotResult() 1", self.uid, self.state)
            self.stateBeginTime = global.ctsec() -- 该状态开始时刻

            if not self.users[self.uid].isdebiting and self.freeSpinTimes <= 0 and not self.needJackPotResult then -- 如果未中免费旋转且未中jackpot
                Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SLOTSHIP_SETTLE")) -- 增加金额(输赢都更新金额)
                log.debug("Utils:credit(),uid=%s,self.winMoney=%s,userMoney=%s,onWaitJackpotResult()", self.uid,
                    self.winMoney, self:getUserMoney(self.uid))
                log.debug("uid=%s,self.sdata.jp=%s", self.uid, cjson.encode(self.sdata.jp))
                self.statistic:appendLogs(self.sdata, self.logid) -- 统计信息
                self:reset()

                self.winMoney = 0
                self.sdata.jp = {}
                Utils:serializeMiniGame(SLOT_SHIP_INFO, nil, global.stype())
            end
        end
    end

    g.call(doRun)
end

local function onBroadcastMsg(self)
    local function doRun()
        timer.cancel(self.timer, TimerID.TimerID_BroadCastMsg[1])
        -- 延迟广播中jackpot消息
        Utils:broadcastSysChatMsgToAllUsers(self.notify_jackpot_msg)
        log.debug("self.notify_jackpot_msg=%s", cjson.encode(self.notify_jackpot_msg))
        self.notify_jackpot_msg = nil
    end

    g.call(doRun)
end

-- 获取玩家身上金额
function Room:getUserMoney(uid)
    local user = self.users[uid]

    if self.confInfo and user then
        if not self.confInfo.roomtype or
            self.confInfo.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
            return user.money
        elseif self.confInfo.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
            return user.coin
        end
    end
    return 0
end

-- 减少玩家身上金额
function Room:subUserMoney(uid, subMoney)
    local user = self.users[uid]

    if self.confInfo and user then
        if not self.confInfo.roomtype or
            self.confInfo.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
            user.money = user.money - subMoney
            user.playerinfo = user.playerinfo or {}
            user.playerinfo.balance = user.money
        elseif self.confInfo.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
            user.coin = user.coin - subMoney
            user.playerinfo = user.playerinfo or {}
            user.playerinfo.balance = user.coin
        end
    end
end

--room start
function Room:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    o:init()
    o:check()
    return o
end

local function onCheck(self)
    local function doRun()
        if self.isStopping then
            Utils:onStopServer(self)
            timer.cancel(self.timer, TimerID.TimerID_Check[1])
            return
        end

        for uid, user in pairs(self.users) do
            local linkid = user.linkid
            -- clear logout users after 10 mins
            if user.state == EnumUserState.Logout and global.ctsec() >= user.logoutts + MYCONF.logout_to_kickout_secs then
                log.info(
                    "idx(%s,%s,%s) onCheck user logouttime=%s, currentTime=%s, uid=%s",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    user.logoutts,
                    global.ctsec(),
                    uid
                )
                self:userLeave(uid, linkid)
            end
        end

        self:start()

        -- 定时检测，若玩家太长时间不操作，则让玩家离开房间
    end

    g.call(doRun)
end

-- 房间初始化
function Room:init()
    self.confInfo = MatchMgr:getConfByMid(self.mid) -- 加载配置信息
    if not self.confInfo then
        log.error("idx(%s,%s) self.confInfo == nil", self.id, self.mid)
        return
    end
    self.confInfo.jpminbet = self.confInfo.jpminbet or 10000

    log.info(
        "idx(%s,%s,%s) init() profitrate_threshold_maxdays=%s,profitrate_threshold_minilimit=%s,profitrate_threshold_lowerlimit=%s"
        ,
        self.id,
        self.mid,
        tostring(self.logid),
        tostring(self.confInfo.profitrate_threshold_maxdays),
        tostring(self.confInfo.profitrate_threshold_minilimit),
        tostring(self.confInfo.profitrate_threshold_lowerlimit)
    )

    self.users = {} -- 当前玩家信息
    self.uid = 0 -- 当前玩家ID

    self.bet = 0 -- 当前下注金额
    self.freeSpinTimes = 0 -- 当前剩余免费旋转次数
    self.pot = 0 -- 奖池
    self.lastWin = 0 -- 上一局中奖金额


    self.beginMoney = 0 -- 一局游戏开始前身上金额
    self.winMoney = 0 -- 当前这一局赢得的金额
    self.currentIsFreeSpin = false -- 当前这一局是否为免费旋转
    self.index = 1

    self.lastSpinIsFree = false -- 上一局是否是免费旋转
    self.totalFreeSpinTimes = 0 -- 最近总的免费旋转次数
    self.beginFreeSpinMoney = 0 -- 开始免费旋转时玩家身上金额
    self.totalFreeSpinWin = 0 -- 最近连续免费赢得的金额
    self.timer = timer.create()

    self.gameId = 0
    self.gameid = global.stype() -- 游戏ID  43-slot

    self.start_time = global.ctms()
    self.starttime = self.start_time / 1000 -- 最近一局牌局开始时刻(秒) global.ctsec()
    self.tabletype = self.confInfo.matchtype

    self.statistic = Statistic:new(self.id, self.confInfo.mid) -- 统计信息
    self.sdata = {
        roomtype = self.confInfo.roomtype, -- 房间类型
        tag = self.confInfo.tag
    }
    self.gamelog = {
        logid = self.logid or 0,
        stime = self.starttime,
        etime = global.ctms() / 1000,
        gameid = global.stype(),
        serverid = global.sid(),
        matchid = self.mid,
        roomid = self.id,
        roomtype = self.confInfo.roomtype, -- 房间类型
        tag = self.confInfo.tag or 0,
        jp = {},
        cards = { { cards = {} } },
        cardstype = {},
        gameinfo = {},
        wintypes = { 1 },
        winpokertype = 0,
        totalbet = self.bet or 0,
        totalprofit = self.winMoney or 0, -- 该局总收益
        areas = {},
        extrainfo = ""

    }

    self.state = EnumRoomState.Check -- 房间状态
    --self.state = 0 --pb.enum_id("network.cmd.PBTeemPattiTableState", "PBTeemPattiTableState_None") -- 桌子状态 0-未开始  1-开始还未结束
    self.stateBeginTime = 0 -- 该状态开始时刻  global.ctsec()
    self.reviewlogs = LogMgr:new(5)

    --实时牌局
    self.reviewlogitems = {} --暂存站起玩家牌局

    -- 配牌
    self.cfgcard_switch = false
    self.cfgcard =
    cfgcard:new(
        {
            handcards = {
                -- 15张手牌（从左到右，从上到下 [1,13]）
                0x06,
                0x0c,
                0x0B,
                0x02,
                0x02,
                0x03,
                0x09,
                0x0d,
                0x0d,
                0x02,
                0x0b,
                0x02,
                0x02,
                0x03,
                0x01
            }
        }
    )
    self.cards = { 0x06, 0x0c, 0x0B, 0x02, 0x02, 0x03, 0x09, 0x0d, 0x01, 0x02, 0x03, 0x02, 0x02, 0x03, 0x01 }
    self.tableStartCount = 0
    self.logid = self.statistic:genLogId() -- 日志ID
    self.calcChipsTime = 0           -- 计算筹码时刻(秒)
end

function Room:check()
    if global.stopping() then
        return
    end

    log.debug("idx(%s,%s,%s) Room:check()", self.id, self.mid, tostring(self.logid))

    timer.tick(self.timer, TimerID.TimerID_Check[1], TimerID.TimerID_Check[2], onCheck, self) -- 启动定时器定时检测
end

-- 销毁房间
function Room:destroy()
    timer.destroy(self.timer)
end

-- 获取游戏ID
function Room:getGameId()
    return self.gameId + 1
end

-- 获取某玩家的免费旋转次数
-- 参数 uid: 玩家ID
local function GetUserKVData(uid, mid, id)
    log.debug("GetUserKVData(),uid=%s", uid)
    --local uid = 1001
    local op = 0 -- 0-读取  1-写入
    local v = { gameid = global.stype(), bv = 100000, win = { { type = 1, cnt = 10 }, { type = 2, cnt = 5 } } } -- type =1 freespin剩余次数   =2 其它
    --local updata = {k = '1001|43', v = cjson.encode(v)}
    local updata = { k = uid .. "|" .. tostring(global.stype()), v = cjson.encode(v) }
    Utils:updateUserInfo({ uid = uid, matchid = mid, roomid = id, op = op, data = { updata } })
end

-- 保存某玩家的剩余免费旋转次数及下注金额
-- 参数 uid: 玩家ID
-- 参数 bet: 下注金额
-- 参数 freeSpinTimes: 剩余的免费旋转次数
-- 参数 freeSpinTotalTimes: 最近总的免费旋转次数
-- 参数 winMoney: 免费旋转赢取到的金额总和
-- 参数 totalWin: 总共赢取到的金额总和
local function SetUserKVData(uid, bet, freeSpinTimes, mid, id, freeSpinTotalTimes, winMoney, totalWin)
    log.debug(
        "SetUserKVData(), uid=%s,bet=%s, freeSpinTimes=%s, freeSpinTotalTimes=%s, winMoney=%s, totalWin=%s",
        uid,
        bet,
        freeSpinTimes,
        freeSpinTotalTimes,
        winMoney,
        totalWin
    )
    local op = 1 -- 0-读取  1-写入
    local v = {
        gameid = global.stype(),
        bv = bet,
        win = { { type = 1, cnt = freeSpinTimes }, { type = 2, cnt = freeSpinTotalTimes }, { type = 3, cnt = winMoney },
            { type = 4, cnt = totalWin } }
    } -- type =1 freespin剩余次数   =2 freespin总次数  =3 freespin赢得的金额  4 free+free前总赢得的金额(包括jackpot)
    local updata = { k = tostring(uid) .. "|" .. tostring(global.stype()), v = cjson.encode(v) }
    Utils:updateUserInfo({ uid = uid, matchid = mid, roomid = id, op = op, data = { updata } })
end

-- 解析获取到的玩家剩余免费旋转次数
function Room:kvdata(data)
    log.debug("Room:kvdata() ")
    for k, v in ipairs(data) do
        if v then
            log.debug("id=%s,mid=%s, kvdata(), v.k=%s,v.v=%s", self.id, self.mid, v.k, v.v)
            if v.k == (self.uid .. "|" .. tostring(global.stype())) then
                -- 解析 v.v
                if v.v then
                    self.freeSpinTimes = 0
                    self.totalFreeSpinTimes = 0
                    self.totalFreeSpinWin = 0
                    self.lastSpinIsFree = false -- 默认上次是自费旋转

                    local info = cjson.decode(v.v)
                    self.bet = info.bv
                    for _, value in ipairs(info.win) do
                        if value then
                            if value.type == 1 then -- 剩余免费旋转次数
                                self.freeSpinTimes = value.cnt or 0
                            elseif value.type == 2 then
                                self.totalFreeSpinTimes = value.cnt or 0 -- 最近总的免费旋转次数
                            elseif value.type == 3 then
                                self.totalFreeSpinWin = value.cnt or 0 --已赢得的金额
                                self.lastWin = self.totalFreeSpinWin
                            elseif value.type == 4 then
                                self.winMoney = value.cnt or 0 -- 总共赢取到的金额
                            end
                        end
                    end
                    if self.totalFreeSpinTimes > self.freeSpinTimes then
                        self.lastSpinIsFree = true -- 默认上次是自费旋转
                        --self.beginFreeSpinMoney = self:getUserMoney(self.uid) - self.totalFreeSpinWin -- 第一次免费旋转时才保存开始免费旋转时的金额
                        self.beginFreeSpinMoney = self:getUserMoney(self.uid) -- 第一次免费旋转时才保存开始免费旋转时的金额
                    elseif self.totalFreeSpinTimes < self.freeSpinTimes then
                        self.totalFreeSpinTimes = self.freeSpinTimes
                    end
                end

                local user = self.users[self.uid] -- 根据玩家ID获取玩家对象
                if user then
                    timer.cancel(user.TimerID_FreeSpinTimes, TimerID.TimerID_FreeSpinTimes[1])
                    log.debug(
                        "idx(%s,%s,%s) kvdata(), uid=%s ",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        tostring(self.uid)
                    )
                    coroutine.resume(user.co2, 2)
                end
            end
        end
    end
end

-- 重新加载配置信息
function Room:reload()
    self.confInfo = MatchMgr:getConfByMid(self.mid) -- 获取配置信息
    self.confInfo.jpminbet = self.confInfo.jpminbet or 10000
    self.cfgcard_switch = false
end

-- 房间人数[0,1]
function Room:count()
    self.user_count = 0
    for k, v in pairs(self.users) do
        self.user_count = self.user_count + 1
    end
    return self.user_count, 0
end

-- 给正在玩的玩家广播消息
function Room:sendCmdToPlayingUsers(maincmd, subcmd, msg, msglen)
    self.links = self.links or {}
    if not self.user_cached then
        self.links = {}
        local linkidstr = nil
        for k, v in pairs(self.users) do
            if v.state == EnumUserState.Playing then
                linkidstr = tostring(v.linkid)
                self.links[linkidstr] = self.links[linkidstr] or {}
                table.insert(self.links[linkidstr], k)
            end
        end
        self.user_cached = true
        --log.debug("idx:%s,%s is not cached", self.id,self.mid)
    end

    net.send_users(cjson.encode(self.links), maincmd, subcmd, msg, msglen)
end

function Room:getApiUserNum()
    local t = {}
    for k, v in pairs(self.users) do
        if v.api and self.confInfo and self.confInfo.roomtype then
            t[v.api] = t[v.api] or {}
            t[v.api][self.confInfo.roomtype] = t[v.api][self.confInfo.roomtype] or {}
            if v.state == EnumUserState.Playing then
                t[v.api][self.confInfo.roomtype].players = (t[v.api][self.confInfo.roomtype].players or 0) + 1
            end
        end
    end

    return t
end

function Room:lock()
    return self.islock
end

function Room:roomtype()
    return self.confInfo.roomtype
end

-- 玩家退出
function Room:logout(uid)
    local user = self.users[uid]
    if user then
        user.state = EnumUserState.Logout -- 玩家准备退出
        user.logoutts = global.ctsec()
        log.info(
            "idx(%s,%s,%s) room logout uid:%s, logouttime=%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            user and user.logoutts or 0
        )
    end
end

function Room:clearUsersBySrvId(srvid)
    for k, v in pairs(self.users) do
        if v.linkid == srvid then
            self:logout(k)
        end
    end
end

-- 查询玩家信息
-- 参数 ok: 是否成功获取到用户信息
-- 参数 ud: 用户信息
function Room:userQueryUserInfo(uid, ok, ud)
    local user = self.users[uid]
    if user and user.TimerID_Timeout then
        timer.cancel(user.TimerID_Timeout, TimerID.TimerID_Timeout[1]) -- 关闭超时定时器
        log.debug(
            "idx(%s,%s,%s) query userinfo:%s ok:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(uid),
            tostring(ok)
        )
        coroutine.resume(user.co, ok, ud)
    end
end

-- 获取免费旋转次数
function Room:userFreeSpinTimes(uid, data)
    local user = self.users[uid]
    if user then
        timer.cancel(user.TimerID_FreeSpinTimes, TimerID.TimerID_FreeSpinTimes[1])
        log.debug(
            "idx(%s,%s,%s) userFreeSpinTimes(), uid=%s data:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(uid),
            tostring(data)
        )
        coroutine.resume(user.co2, data > 0)
    end
end

-- 互斥检测
function Room:userMutexCheck(uid, code)
    local user = self.users[uid]
    if user then
        timer.cancel(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1])
        log.debug(
            "idx(%s,%s,%s) mutex check:%s code:%s",
            self.id,
            self.mid,
            tostring(self.logid),
            tostring(uid),
            tostring(code)
        )
        coroutine.resume(user.mutex, code > 0)
    end
end

-- 互斥检测超时处理
local function onMutexTo(arg)
    arg[2]:userMutexCheck(arg[1], -1)
end

-- 查询用户信息超时处理
local function onTimeout(arg)
    arg[2]:userQueryUserInfo(arg[1], false, nil)
end

-- 获取免费旋转次数超时处理
local function onGetFreeSpinTimes(arg)
    arg[2]:userFreeSpinTimes(arg[1], 1)
end

-- 玩家进入房间
-- 参数 uid: 要进入的玩家ID
function Room:userInto(uid, linkid, rev)
    if not linkid then
        return
    end
    local t = {
        -- 对应 PBSlotIntoRoomResp_S 消息
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameSuccess"),
        gameid = global.stype(), -- 游戏ID  43-Slot
        idx = {
            srvid = global.sid(), -- 服务器ID ?
            roomid = self.id, -- 房间ID
            matchid = self.mid, -- 房间级别 (1：初级场  2：中级场  3：高级场)
            roomtype = self:conf().roomtype or 0
        },
        data = {
            state = self.state, -- 当前房间状态
            betList = self.confInfo.chips or { 10, 100, 500, 1000, 10000 }, -- 下注列表
            jackPot = JackpotMgr:getJackpotById(self.confInfo.jpid) or 0, -- 奖池
            playerinfo = {}, -- 玩家信息
            lastWin = self.lastWin or 0, -- 最后一次摇奖中奖信息
            autoSpinTimes = 0, -- 自动旋转次数
            freeSpinTimes = self.freeSpinTimes or 0, -- 剩余免费旋转次数
            currentBet = self.bet or 0,
            cards = self.cards or {}, -- 牌数据(共15张)
            autoSpinList = self.confInfo.autoSPinList or { 2, 5, 10, 20 }, -- 自动旋转次数
            jpid = self.confInfo.jpid or 31,
            lineNum = GetLineNum() or 10, -- 线条总数
            totalFreeSpinTimes = self.totalFreeSpinTimes or 0, -- 总的免费旋转次数
            allLineInfo = g.copy(SLOT_CONF.lineInfoShip) -- 线条信息
        } --data
    } --t


    local function handleFail(code)
        t.code = code
        t.data = nil
        if linkid then
            net.send(
                linkid,
                uid,
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
            )
        end
        log.info(
            "idx(%s,%s,%s) player:%s ip %s code %s into room failed",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            tostring(rev.ip),
            code
        )
    end

    log.debug("idx(%s,%s) userInto(), uid=%s", self.id, self.mid, uid)
    if self.isStopping then
        handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")) -- 正要停服，不能进入
        return
    end

    self.needGetFreeSpinTimes = true
    if self.uid and self.uid ~= 0 then -- 如果该桌已有玩家
        if self.uid ~= uid then
            handleFail(pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail"))
        else
            if self.users[uid] then
                self.needGetFreeSpinTimes = false
                -- self.users[uid].state = EnumUserState.Playing
                -- self:userTableInfo(uid, linkid, rev)
                -- return
            end
        end
    end

    self.users[uid] =
    self.users[uid] or
        { TimerID_MutexTo = timer.create(), TimerID_Timeout = timer.create(), TimerID_FreeSpinTimes = timer.create() }
    local user = self.users[uid]
    user.money = 0
    user.diamond = 0 --
    user.linkid = linkid
    user.ip = rev.ip or ""
    user.state = EnumUserState.Intoing

    user.mutex =
    coroutine.create(
        function(user)
            mutex.request(
                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
                pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexCheck"),
                pb.encode(
                    "network.cmd.PBMutexCheck", -- 互斥检测
                    {
                        uid = uid,
                        srvid = global.sid(),
                        matchid = self.mid,
                        roomid = self.id,
                        roomtype = self.confInfo and self.confInfo.roomtype
                    }
                )
            )
            local ok = coroutine.yield()
            if not ok then
                if self.users[uid] ~= nil then
                    if user and user.TimerID_MutexTo then
                        timer.destroy(user.TimerID_MutexTo)
                    end
                    if user and user.TimerID_Timeout then
                        timer.destroy(user.TimerID_Timeout)
                    end
                    if user and user.TimerID_FreeSpinTimes then
                        timer.destroy(user.TimerID_FreeSpinTimes)
                    end

                    self.users[uid] = nil
                    t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入房间失败
                    t.data = nil
                    net.send(
                        linkid,
                        uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                        pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                    )
                    --Utils:sendTipsToMe(linkid, uid, global.lang(37), 0)
                end
                log.info(
                    "idx(%s,%s,%s) player: uid=%s has been in another room",
                    self.id,
                    self.mid,
                    tostring(self.logid),
                    uid
                )
                return
            end

            user.co =
            coroutine.create(
                function(user)
                    Utils:queryUserInfo(
                        {
                            uid = uid,
                            roomid = self.id,
                            matchid = self.mid,
                            jpid = self.confInfo.jpid, --
                            carrybound = self:conf().carrybound --???
                        }
                    )
                    --print("start coroutine", self, user, uid)
                    local ok, ud = coroutine.yield()
                    --print('ok', ok, 'ud', ud)
                    if ud then
                        -- userinfo
                        user.uid = uid
                        user.money = ud.money or 0
                        user.coin = ud.coin or 0
                        user.diamond = ud.diamond or 0
                        user.nickurl = ud.nickurl or ""
                        user.username = ud.name or ""
                        user.viplv = ud.viplv or 0
                        --user.tomato = 0
                        --user.kiss = 0
                        user.sex = ud.sex or 0
                        user.api = ud.api or ""
                        user.ip = rev.ip or ""

                        -- 携带数据
                        user.linkid = linkid
                        user.intots = user.intots or global.ctsec()
                        user.sid = ud.sid
                        user.userId = ud.userId
                        -- user.roundId = user.roundId or self.statistic:genLogId()  -- pve游戏中不需要该值?
                        user.playerinfo = user.playerinfo or {}
                        if self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
                            user.playerinfo.balance = user.money
                        elseif self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
                            user.playerinfo.balance = user.coin
                        end
                        log.debug("userInto(), uid=%s, money=%s, coin=%s, userMoney=%s", uid, user.money, user.coin,
                            user.playerinfo.balance)
                    end

                    -- 防止协程返回时，玩家实质上已离线
                    if ok and user.state ~= EnumUserState.Intoing then
                        ok = false
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail") -- 进入游戏失败
                        log.info("idx(%s,%s,%s) user %s logout or leave", self.id, self.mid, tostring(self.logid), uid)
                    end

                    if not ok then
                        t.code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_IntoGameFail")
                        t.data = nil
                        if self.users[uid] ~= nil then
                            timer.destroy(user.TimerID_MutexTo)
                            timer.destroy(user.TimerID_Timeout)
                            timer.destroy(user.TimerID_FreeSpinTimes)
                            self.users[uid] = nil
                            net.send(
                                linkid,
                                uid,
                                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_IntoGameRoomResp"),
                                pb.encode("network.cmd.PBIntoGameRoomResp_S", t)
                            )
                            mutex.request(
                                pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
                                pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
                                pb.encode(
                                    "network.cmd.PBMutexRemove",
                                    { uid = uid, srvid = global.sid(), roomid = self.id }
                                )
                            )
                        end
                        log.info(
                            "idx(%s,%s,%s) not enough money:%s,%s,%s",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            uid,
                            ud.money,
                            t.code
                        )
                        return
                    end

                    self.user_cached = false
                    user.state = EnumUserState.Playing

                    log.debug(
                        "idx(%s,%s,%s) into room: uid=%s, linkid=%s, state=%s,money=%s",
                        self.id,
                        self.mid,
                        tostring(self.logid),
                        uid,
                        linkid,
                        self.state,
                        self:getUserMoney(uid)
                    )

                    if self.needGetFreeSpinTimes then
                        -- 获取玩家其它信息(免费旋转次数)
                        user.co2 =
                        coroutine.create(
                            function(user)
                                -- 查询剩余免费旋转次数
                                GetUserKVData(user.uid, self.mid, self.id)
                                local ret = coroutine.yield() -- 挂起协程，等待结果

                                if ret then
                                    --关闭定时器
                                    timer.cancel(user.TimerID_FreeSpinTimes, TimerID.TimerID_FreeSpinTimes[1]) -- 关闭定时器
                                end

                                t.data.playerinfo.uid = user.uid
                                t.data.playerinfo.nickurl = user.nickurl
                                t.data.playerinfo.username = user.username
                                t.data.playerinfo.balance = self:getUserMoney(uid)

                                t.data.playerinfo.viplv = user.viplv
                                t.data.playerinfo.extra = {}
                                t.data.playerinfo.extra.ip = user.ip or ""
                                t.data.playerinfo.extra.api = user.api or ""

                                t.data.currentBet = self.bet or 0

                                if self.freeSpinTimes == 0 or self.freeSpinTimes == self.totalFreeSpinTimes then
                                    t.data.lastWin = self.lastWin or 0
                                end

                                self.uid = user.uid
                                local resp = pb.encode("network.cmd.PBSlotIntoRoomResp_S", t)
                                local to = {
                                    uid = uid,
                                    srvid = global.sid(),
                                    roomid = self.id,
                                    matchid = self.mid,
                                    maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                                    subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotIntoRoomResp"),
                                    data = resp
                                }

                                log.debug(
                                    "idx(%s,%s,%s) userInto(),uid=%s,intoRoom success! t=%s ",
                                    self.id,
                                    self.mid,
                                    tostring(self.logid),
                                    uid,
                                    cjson.encode(t)
                                )
                                local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)

                                net.shared(
                                    linkid,
                                    pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                                    pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                                    synto
                                )
                            end
                        )
                        --设置定时器
                        timer.tick(
                            user.TimerID_FreeSpinTimes,
                            TimerID.TimerID_FreeSpinTimes[1],
                            TimerID.TimerID_FreeSpinTimes[2],
                            onGetFreeSpinTimes,
                            { uid, self }
                        )
                        -- 执行协程
                        coroutine.resume(user.co2, user)

                    else

                        t.data.playerinfo.uid = user.uid
                        t.data.playerinfo.nickurl = user.nickurl
                        t.data.playerinfo.username = user.username
                        t.data.playerinfo.balance = self:getUserMoney(uid)

                        t.data.playerinfo.viplv = user.viplv
                        t.data.playerinfo.extra = {}
                        t.data.playerinfo.extra.ip = user.ip or ""
                        t.data.playerinfo.extra.api = user.api or ""

                        t.data.currentBet = self.bet or 0

                        if self.freeSpinTimes == 0 or self.freeSpinTimes == self.totalFreeSpinTimes then
                            t.data.lastWin = self.lastWin or 0
                        end

                        self.uid = user.uid
                        local resp = pb.encode("network.cmd.PBSlotIntoRoomResp_S", t)
                        local to = {
                            uid = uid,
                            srvid = global.sid(),
                            roomid = self.id,
                            matchid = self.mid,
                            maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                            subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotIntoRoomResp"),
                            data = resp
                        }

                        log.debug(
                            "idx(%s,%s,%s) userInto(),uid=%s intoRoom success!! t=%s ",
                            self.id,
                            self.mid,
                            tostring(self.logid),
                            uid,
                            cjson.encode(t)
                        )
                        local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)

                        net.shared(
                            linkid,
                            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
                            pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
                            synto
                        )
                    end
                end
            )
            timer.tick(
                user.TimerID_Timeout,
                TimerID.TimerID_Timeout[1],
                TimerID.TimerID_Timeout[2],
                onTimeout,
                { uid, self }
            )
            coroutine.resume(user.co, user)
        end
    )
    timer.tick(user.TimerID_MutexTo, TimerID.TimerID_MutexTo[1], TimerID.TimerID_MutexTo[2], onMutexTo, { uid, self })
    coroutine.resume(user.mutex, user)
end

-- 玩家离开房间
function Room:userLeave(uid, linkid)
    local t = {
        code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess")
    }
    log.info("idx(%s,%s,%s) userLeave(), uid=%s", self.id, self.mid, tostring(self.logid), uid)
    if not linkid then
        return
    end

    local function handleFailed()
        local resp =
        pb.encode(
            "network.cmd.PBLeaveGameRoomResp_S",
            {
                code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameFailed") -- 离开失败
            }
        )
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
            resp
        )
    end

    local user = self.users[uid]
    if not user then
        log.info("idx(%s,%s,%s) user:%s is not in room", self.id, self.mid, tostring(self.logid), uid)
        handleFailed() -- 玩家不在房间，离开失败
        return
    end

    if user.state == EnumUserState.Leave then -- 如果玩家已经处于离开状态
        log.info("idx(%s,%s) has leaveed: uid=%s", self.id, self.mid, uid)
        return
    end

    user.state = EnumUserState.Leave

    -- if user.gamecount and user.gamecount > 0 then -- 该玩家玩的局数
    --     Statistic:appendRoomLogs( --
    --         {
    --             uid = uid,
    --             time = global.ctsec(), -- 当前时刻
    --             roomtype = self.confInfo.roomtype,
    --             gameid = global.stype(),
    --             serverid = global.sid(),
    --             roomid = self.id,
    --             smallblind = self.confInfo.ante,
    --             seconds = global.ctsec() - (user.intots or 0),
    --             changed = 0,
    --             roomname = self.confInfo.name,
    --             gamecount = user.gamecount,
    --             matchid = self.mid,
    --             api = tonumber(user.api) or 0
    --         }
    --     )
    -- end

    mutex.request(
        pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2Mutex"),
        pb.enum_id("network.inter.Game2MutexSubCmd", "Game2MutexSubCmd_MutexRemove"),
        pb.encode("network.cmd.PBMutexRemove", { uid = uid, srvid = global.sid(), roomid = self.id })
    )
    -- 如果和进入时的免费旋转次数不同或押注金额不同时才更新  待优化
    SetUserKVData(
        self.uid,
        self.bet,
        self.freeSpinTimes,
        self.mid,
        self.id,
        self.totalFreeSpinTimes,
        self.totalFreeSpinWin,
        self.winMoney
    )
    self.lastWin = 0
    local resp = pb.encode("network.cmd.PBLeaveGameRoomResp_S", t)

    local to = {
        uid = uid,
        srvid = 0,
        roomid = 0,
        matchid = 0,
        maincmd = pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        subcmd = pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
        data = resp
    }
    local synto = pb.encode("network.cmd.PBServerSynGame2ASAssignRoom", to)
    if linkid then        
        net.shared(
            linkid,
            pb.enum_id("network.inter.ServerMainCmdID", "ServerMainCmdID_Game2AS"),
            pb.enum_id("network.inter.Game2ASSubCmd", "Game2ASSubCmd_SysAssignRoom"),
            synto
        )
    end

    if user.TimerID_Timeout then
        timer.destroy(user.TimerID_Timeout)
    end
    if user.TimerID_MutexTo then
        timer.destroy(user.TimerID_MutexTo)
    end
    if user.TimerID_FreeSpinTimes then
        timer.destroy(user.TimerID_FreeSpinTimes)
    end

    -- local resp =
    --     pb.encode(
    --     "network.cmd.PBLeaveGameRoomResp_S",
    --     {
    --         code = pb.enum_id("network.cmd.PBLoginCommonErrorCode", "PBLoginErrorCode_LeaveGameSuccess"), -- 成功离开房间
    --         hands = user.gamecount or 0, --从进入到离开玩的局数
    --         profits = 0, -- 总收益
    --         roomtype = self.confInfo.roomtype -- 房间类型
    --     }
    -- )
    -- net.send(
    --     linkid,
    --     uid,
    --     pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
    --     pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_LeaveGameRoomResp"),
    --     resp
    -- )
    -- log.info(
    --     "idx(%s,%s,%s) userLeave() success: uid=%s, gamecount=%s",
    --     self.id,
    --     self.mid,
    --     tostring(self.logid),
    --     uid,
    --     user.gamecount or 0
    -- )

    self.uid = 0
    self.users[uid] = nil
    self.user_cached = false
    self:reset()

    -- MatchMgr:getMatchById(self.confInfo.mid):shrinkRoom()
end

function Room:userTableInfo(uid, linkid, rev)
    log.info("idx(%s,%s) userTableInfo(), uid:%s", self.id, self.mid, uid)
    local intoRev = { gameid = global.stype(), matchid = rev.idx.matchid, roomid = rev.idx.roomid, serverid = rev.idx.srvid }
    return self:userInto(uid, linkid, intoRev)
end

function Room:reset()
    self.sdata = {
        --moneytype = self.confInfo.moneytype,
        roomtype = self:conf().roomtype,
        tag = self.confInfo.tag,
        cards = { { cards = {} } }
    }
    self.reviewlogitems = {}
end

function Room:start()
    --self:reset()
end

-- 检测是否可操作
function Room:checkCanChipin()
    local currentTime = global.ctsec() -- 当前时刻(秒)
    if currentTime - self.stateBeginTime > 30 then
        self.state = EnumRoomState.Check -- 房间状态
        log.debug("uid=%s, state=%s,checkCanChipin() 1", self.uid, self.state)
        self.stateBeginTime = currentTime
    end
    return self.state == EnumRoomState.Check
end

-- 旋转操作
-- 参数 type: 未使用该参数
-- 参数 money: 押注金额
-- 参数 linkid:
function Room:userchipin(uid, type, money, linkid)
    if not self.total_bets then
        self.total_bets = SLOT_SHIP_INFO.total_bets -- {} -- 存放各天的总下注额
        self.total_profit = SLOT_SHIP_INFO.total_profit -- {} -- 存放各天的总收益
    end

    log.info(
        "idx(%s,%s,%s) userchipin(): uid=%s, type=%s, money=%s, freeSpinTimes=%s,state=%s",
        self.id,
        self.mid,
        tostring(self.logid),
        tostring(uid),
        tostring(type),
        tostring(money),
        tostring(self.freeSpinTimes),
        self.state
    )


    self.t = {
        -- 待返回的结构  PBSlotSpinResp_S
        code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_Succ"), -- 默认成功
        bet = money, --本轮下注金额(底注) 免费下注也需要填
        balance = 10000, --玩家此时身上金额
        isFreeSpin = true, --本局是否是免费旋转
        freeSpinTimes = 0, --剩余免费旋转次数(之前剩余的+这一局赢取的)
        cards = {}, --牌数据(共15张牌，从左到右，从上到下)
        jackPot = 0, --当前奖池金额
        winMoney = 0, --这一局玩家赢得的金额(线条金额+奖池金额)
        winLines = {}, --各条线的中奖情况
        winFreeSpinTimes = 10, --本局赢得的免费旋转次数
        uid = self.uid,
        totalFreeSpinTimes = 0,
        totalFreeSpinWin = 0,
        winJackPot = false
    }

    uid = uid or 0
    type = type or 0
    money = money or 0

    if uid ~= self.uid then
        self.t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidUser") -- 玩家无效

        local resp = pb.encode("network.cmd.PBSlotSpinResp_S", self.t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotSpinResp"), -- 旋转回应
            resp
        )
        log.debug("idx(%s,%s) userchipin(),uid=%s, PBSlotSpinResp_S=%s", self.id, self.mid, uid, cjson.encode(self.t))
        return
    end

    if not self:checkCanChipin() then
        self.t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_InvalidGameState") -- 状态不对

        local resp = pb.encode("network.cmd.PBSlotSpinResp_S", self.t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotSpinResp"), -- 旋转回应
            resp
        )
        log.debug("idx(%s,%s) userchipin(),uid=%s, PBSlotSpinResp_S 00: %s ", self.id, self.mid, uid,
            cjson.encode(self.t))
        return
    end
    self.linkid = linkid

    if self.freeSpinTimes <= 0 then -- 如果当前不是免费旋转
        self.currentIsFreeSpin = false -- 当前这一局不是免费旋转局
        self.index = 1
        self.winMoney = 0
        self.logid = self.statistic:genLogId(self.starttime) or self.logid
        self.beginMoney = self:getUserMoney(uid)

        self.start_time = global.ctms()
        self.starttime = self.start_time / 1000 -- 开始时刻(秒)
        self.gamelog.stime = self.starttime
        -- self.statis
    else
        self.currentIsFreeSpin = true -- 当前这一局是免费旋转
        self.index = self.index + 1
    end

    local user = self.users[uid] -- 根据玩家ID获取玩家对象


    --self.state = EnumRoomState.Betting   --1   -- 正在下注
    self.state = EnumRoomState.Show
    log.debug("uid=%s, state=%s,userchipin() 4", self.uid, self.state)
    self.stateBeginTime = global.ctsec() -- 该状态开始时刻

    -- 判断玩家身上筹码是否足够下注
    if 0 == self.freeSpinTimes and self:getUserMoney(uid) < money then
        self.t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_OverBalance") -- 金额不足

        local resp = pb.encode("network.cmd.PBSlotSpinResp_S", self.t)
        net.send(
            linkid,
            uid,
            pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
            pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotSpinResp"), -- 旋转回应
            resp
        )
        log.info("idx(%s,%s) userchipin(),uid=%s, PBSlotSpinResp_S: %s", self.id, self.mid, uid, cjson.encode(self.t))
        self.state = EnumRoomState.Check
        log.debug("uid=%s, state=%s,userchipin() 1", self.uid, self.state)
        self.stateBeginTime = global.ctsec() -- 该状态开始时刻
        return
    end

    -- 下面是可以下注旋转的情况
    local curday = global.cdsec() -- 当天标志

    -- 打印该局游戏前身上金额
    log.debug("userchipin(),uid=%s,userMoney=%s,self.winMoney=%s", self.uid, self:getUserMoney(self.uid), self.winMoney)

    if self.freeSpinTimes > 0 then -- 如果当前是免费旋转
        -- 免费玩
        self.freeSpinTimes = self.freeSpinTimes - 1
        self.t.isFreeSpin = true
        if not self.lastSpinIsFree then -- 如果上一局是自费旋转，这一局才是免费旋转
            self.beginFreeSpinMoney = self:getUserMoney(self.uid) -- 第一次免费旋转时才保存开始免费旋转时的金额
            self.totalFreeSpinWin = 0
            log.debug("userchipin(), beginFreeSpinMoney = %s", self.beginFreeSpinMoney)
            self.lastSpinIsFree = true
        end
        money = self.bet or money
        self.users[self.uid] = self.users[self.uid] or {}
        self.users[self.uid].totalbet = self.bet
    else
        -- 自费玩
        self.t.isFreeSpin = false
        self.bet = money -- 下注金额
        self.lastSpinIsFree = false
        self.total_bets[curday] = (self.total_bets[curday] or 0) + money -- 增加下注金额
        log.debug(
            "uid=%s, curday=%s, total_bets=%s, bet=%s",
            uid,
            tostring(curday),
            tostring(self.total_bets[curday]),
            self.bet
        )
        self.users[self.uid] = self.users[self.uid] or {}
        self.users[self.uid].totalbet = money

        -- 扣除费用
        self:subUserMoney(self.uid, self.bet)

        self.beginMoney = self:getUserMoney(uid) -- 下注后，玩家身上金额
        --self.endMoney = self.beginMoney -- 当前玩家身上金额

        -- 下注后身上金额
        log.debug("userchipin(),uid=%s,userMoney=%s,bet=%s,self.winMoney=%s", self.uid, self:getUserMoney(self.uid),
            self.bet, self.winMoney)

        if not self:conf().isib then -- 如果不是indibet版本
            log.debug("idx(%s,%s) userchipin(),uid=%s,isib=false,self.bet=%s", self.id, self.mid, self.uid or 0, self.bet)
            Utils:walletRpc(
                uid,
                user.api,
                user.ip,
                -1 * self.bet,
                pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SLOTSHIP_BET"),
                linkid,
                self.confInfo.roomtype,
                self.id,
                self.mid,
                {
                    api = "debit",
                    sid = user.sid or 1,
                    userId = user.userId,
                    transactionId = g.uuid(),
                    roundId = user.roundId,
                    gameId = tostring(global.stype())
                }
            )
        else
            log.debug("idx(%s,%s) userchipin(),uid=%s,isib=true", self.id, self.mid, self.uid or 0)
            -- 减少身上金额
            Utils:debit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SLOTSHIP_BET"))
            Utils:balance(self, EnumUserState.Playing)
            for uid, user in pairs(self.users) do
                if user and Utils:isRobot(user.api) then
                    user.isdebiting = false
                end
            end
        end
    end

    --随机生成结果
    if self.lastSpinIsFree then -- 如果上一局是免费旋转
        self.cards = GetCards(SLOT_CONF, 4)
    else
        --self.cards = GetCards(SLOT_CONF, self.confInfo.mid)
        self:getFinalCards()
    end

    if self.currentIsFreeSpin then
        self:doResult(self.t, self.linkid)
    else
        self.needSendCards = true
    end
    --timer.tick(self.timer, TimerID.TimerID_Wallet[1], TimerID.TimerID_Wallet[2], onWalletTimeout, { self, t, linkid })

    return true
end

-- 处理游戏结果
function Room:doResult(t, linkid)
    local needSendResult = true
    if not self.confInfo.single_profit_switch then -- 如果不是单人控制
        local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {} }
        table.insert(msg.data, { uid = self.uid, chips = self.bet or 0, betchips = self.bet or 0 })
        log.debug("idx(%s,%s) start result request %s", self.id, self.mid, cjson.encode(msg))
        Utils:queryProfitResult(msg)
    end
    if self.confInfo.single_profit_switch then -- 如果是单人控制
        log.debug("uid=%s, single_profit_switch==true", self.uid)
        needSendResult = false
        self.result_co =
        coroutine.create(
            function()
                local msg = { ctx = 0, matchid = self.mid, roomid = self.id, data = {} }
                table.insert(
                    msg.data,
                    { uid = self.uid, chips = self.bet or 0, betchips = self.bet or 0 }
                )
                log.debug("idx(%s,%s) start result request %s", self.id, self.mid, cjson.encode(msg))
                Utils:queryProfitResult(msg)
                local ok, res = coroutine.yield() -- 等待查询结果
                if ok and res then
                    for _, v in ipairs(res) do
                        local uid, r, maxwin = v.uid, v.res, v.maxwin
                        local user = self.users[uid]
                        if user then
                            user.maxwin = r * maxwin
                        end
                        log.debug("uid=%s, r=%s, maxwin=%s", tostring(uid), tostring(r), tostring(maxwin))
                        if uid and uid == self.uid and r then
                            log.debug("uid=%s,uid == self.uid", self.uid or 0)
                            local realPlayerWinMin = 0x7FFFFFFF
                            local minCards = self.cards -- 记录玩家输的牌
                            local hasFind = false
                            for i = 0, 10, 1 do
                                -- 根据牌数据计算真实玩家的输赢值
                                local realPlayerWin = self:GetRealPlayerWin()
                                log.debug(
                                    "idx(%s,%s) redeal  i=%s, realPlayerWin=%s",
                                    self.id,
                                    self.mid,
                                    tostring(i),
                                    tostring(realPlayerWin)
                                )
                                if realPlayerWin < realPlayerWinMin then
                                    realPlayerWinMin = realPlayerWin
                                    minCards = self.cards
                                end
                                if r > 0 and maxwin then
                                    if maxwin >= realPlayerWin and realPlayerWin > 0 then
                                        hasFind = true
                                        break
                                    end
                                elseif r < 0 then -- 真实玩家输
                                    if realPlayerWin < 0 then
                                        hasFind = true
                                        break
                                    end
                                elseif r == 0 and maxwin then
                                    if maxwin >= realPlayerWin then
                                        hasFind = true
                                        break
                                    end
                                else
                                    if realPlayerWin < 0x7FFF0000 then
                                        break
                                    end
                                end
                                -- 未满足条件，重新发牌
                                if self.lastSpinIsFree then
                                    self.cards = GetCards(SLOT_CONF, 4)
                                else
                                    --self:getFinalCards()
                                    self.cards = GetCards(SLOT_CONF, self.confInfo.mid)
                                end
                            end -- for
                            if not hasFind then -- 如果未找出匹配的牌
                                self.cards = minCards
                            end
                        end
                    end
                    log.info("idx(%s,%s) result success", self.id, self.mid)
                end
                log.debug("uid=%s,ssssss", self.uid or 0)
                t.cards = g.copy(self.cards)

                self:sendResult(self.uid, t, linkid)
            end
        )
        timer.tick(self.timer, TimerID.TimerID_Result[1], TimerID.TimerID_Result[2], onResultTimeout, { self })
        coroutine.resume(self.result_co)
    end

    if needSendResult then
        self:sendResult(self.uid, t, linkid)
    end
end

--通知玩家中奖jackpot
function Room:userJackPotResp(uid, rev)
    local roomtype, value, jackpot = rev.roomtype or 0, rev.value or 0, rev.jp or 0
    self.notify_jackpot_msg = {
        type = pb.enum_id("network.cmd.PBChatChannelType", "PBChatChannelType_Jackpot"),
        msg = cjson.encode(
            {
                nickname = rev.nickname, --玩家名称
                bonus = rev.value, -- 奖金
                roomtype = rev.roomtype,
                sb = self.ante,
                ante = self.confInfo.ante,
                pokertype = rev.wintype,
                gameid = global.stype()
            }
        )
    }
    local user = self.users[uid]
    if not user then
        return true
    end

    log.debug(
        "idx(%s,%s,%s) userJackPotResp(),uid=%s,roomtype=%s,value=%s,jackpot=%s",
        self.id,
        self.mid,
        tostring(self.logid),
        uid,
        roomtype,
        value,
        jackpot
    )

    if self.gamelog.jp and self.gamelog.jp.uid and self.gamelog.jp.uid == uid and self.jackpot_and_showcard_flags then
        self.jackpot_and_showcard_flags = false
        pb.encode(
            "network.cmd.PBGameJackpotAnimation_N", -- 通知播放中jackpot奖励动画
            { data = { sid = 0, uid = uid, delta = value, wintype = 0 } },
            function(pointer, length)
                self:sendCmdToPlayingUsers(
                    pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                    pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyJackPotAnimation"),
                    pointer,
                    length
                )
            end
        )
        log.info(
            "idx(%s,%s,%s) jackpot animation is to be playing %s,%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            value,
            0
        )
    else
        log.debug("uid=%s,jackpot_and_showcard_flags=%s", self.uid, tostring(self.jackpot_and_showcard_flags))
    end

    if uid == self.uid then -- 2021-11-29
        self.lastWin = self.lastWin + value
        if self.lastSpinIsFree then
            self.totalFreeSpinWin = self.totalFreeSpinWin + value
        end

        -- 直接更新玩家身上金额
        if value > 0 then
            self.winMoney = self.winMoney + value -- 本局赢取到的金额
            local curday = global.cdsec() -- 当天标志
            self.total_profit[curday] = (self.total_profit[curday] or 0) + value
            log.debug("userJackPotResp(),uid=%s,userMoney=%s,jackpotValue=%s,self.winMoney=%s", self.uid,
                self:getUserMoney(self.uid), value, self.winMoney)
        end

        if self.needJackPotResult then
            self.needJackPotResult = false
            timer.cancel(self.timer, TimerID.TimerID_WaitJackpotResult[1]) -- 关闭定时器
            self.state = EnumRoomState.Check
            log.debug("uid=%s, state=%s,userJackPotResp() 1", self.uid, self.state)
            self.stateBeginTime = global.ctsec() -- 该状态开始时刻

            -- 检测是否需要更新金额
            if not self.users[self.uid].isdebiting and self.freeSpinTimes <= 0 and not self.needJackPotResult then -- 如果下一局不是免费旋转且未中jackpot
                self.users[uid] = self.users[uid] or {}
                self.users[uid].totalprofit = self.winMoney
                Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SLOTSHIP_SETTLE")) -- 增加金额(输赢都更新金额)
                log.debug("Utils:credit(),uid=%s,self.winMoney=%s,userMoney=%s,jackpot ret", uid, self.winMoney,
                    self:getUserMoney(uid))

                log.debug("uid=%s,self.sdata.jp=%s", self.uid, cjson.encode(self.sdata.jp))

                self.sdata.users = self.sdata.users or {}
                self.sdata.users[uid] = self.sdata.users[uid] or {}
                self.sdata.users[uid].totalprofit = self.winMoney
                self.sdata.users[uid].totalpureprofit = self.winMoney - self.bet

                self.statistic:appendLogs(self.sdata, self.logid) -- 统计信息
                self:reset()

                self.winMoney = 0
                self.sdata.jp = {}
                Utils:serializeMiniGame(SLOT_SHIP_INFO, nil, global.stype())
            end
        end
    end


    timer.tick(self.timer, TimerID.TimerID_BroadCastMsg[1], TimerID.TimerID_BroadCastMsg[2], onBroadcastMsg, self)
    -- -- 延迟广播中jackpot消息
    --  Utils:broadcastSysChatMsgToAllUsers(self.notify_jackpot_msg)
    --  self.notify_jackpot_msg = nil

    return true
end

-- 根据jackpot id获取对应房间
function Room:getJackpotId(id)
    return id == self.confInfo.jpid and self or nil
end

-- 通知所有玩家当前Jackpot值
function Room:onJackpotUpdate(jackpot)
    log.debug("(%s,%s,%s)notify client for jackpot change %s", self.id, self.mid, tostring(self.logid), jackpot)
    pb.encode(
        "network.cmd.PBGameNotifyJackPot_N",
        { jackpot = jackpot },
        function(pointer, length)
            self:sendCmdToPlayingUsers(
                pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_GameNotifyJackPot"),
                pointer,
                length
            )
        end
    )
end

-- 踢出所有玩家
function Room:kickout()
    for k, v in pairs(self.users) do
        self:userLeave(k, v.linkid)
    end
end

-- 金额更新
function Room:phpMoneyUpdate(uid, rev)
    log.info("(%s,%s,%s)phpMoneyUpdate %s", self.id, self.mid, tostring(self.logid), uid)
    local user = self.users[uid]
    if user then
        user.money = user.money + rev.money
        user.coin = user.coin + rev.coin
        log.info(
            "(%s,%s,%s)phpMoneyUpdate %s,%s,%s",
            self.id,
            self.mid,
            tostring(self.logid),
            uid,
            tostring(rev.money),
            tostring(rev.coin)
        )
        user.playerinfo = user.playerinfo or {}
        if self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
            user.playerinfo.balance = user.money
        elseif self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
            user.playerinfo.balance = user.coin
        end
    end
end

function Room:needLog()
    return self.has_player_inplay or (self.sdata and self.sdata.jp and self.sdata.jp.id)
end

function Room:getUserIp(uid)
    local user = self.users[uid]
    if user then
        return user.ip
    end
    return ""
end

function Room:tools(jdata)
    log.info("(%s,%s) tools>>>>>>>> %s", self.id, self.mid, jdata)
    local data = cjson.decode(jdata)
    if data then
        log.info("(%s,%s) handle tools %s", self.id, self.mid, cjson.encode(data))
        if data["api"] == "kickout" then
            self.isStopping = true
        end
    end
end

-- function Room:userWalletResp(rev)
--     if not rev.data or #rev.data == 0 then
--         return
--     end
--     for _, v in ipairs(rev.data) do
--         local user = self.users[v.uid]
--         log.info("(%s,%s,%s) userWalletResp %s", self.id, self.mid, tostring(self.logid), cjson.encode(rev))
--         if user then
--             if v.code > 0 then
--                 if
--                     not self.confInfo.roomtype or
--                         self.confInfo.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money")
--                  then
--                     user.money = v.money
--                 elseif self.confInfo.roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
--                     user.coin = v.coin
--                 end
--             end
--         else
--             Utils:transferRepay(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_RETURNCHIPS"), v)
--         end
--     end
-- end


function Room:userWalletResp(rev)
    if not rev.data or #rev.data == 0 then
        return
    end
    for _, v in ipairs(rev.data) do
        local user = self.users[v.uid]
        if user and not Utils:isRobot(user.api) then
            log.info("(%s,%s) userWalletResp() rev=%s", self.id, self.mid, cjson.encode(rev))
        end
        if v.code >= 0 then
            if user then
                if not Utils:isRobot(user.api) then
                    user.playerinfo = user.playerinfo or {}
                    if self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Money") then
                        user.playerinfo.balance = v.money
                        user.money = v.money
                    elseif self:conf().roomtype == pb.enum_id("network.cmd.PBRoomType", "PBRoomType_Coin") then
                        user.playerinfo.balance = v.coin
                        user.coin = v.coin
                    end
                end
                if type(v) == "table" and rawget(v, "extrainfo") and v.extrainfo and v.extrainfo ~= "" then
                    local extrainfo = rawget(v, "extrainfo") and cjson.decode(v.extrainfo) or nil
                    if extrainfo and extrainfo["api"] == "debit" then
                        user.isdebiting = false
                        if self.needSendCards and v.uid == self.uid then
                            self.needSendCards = false
                            self:doResult(self.t, self.linkid)
                        end
                    end
                end
            end

            -- --该局结算后才debit成功、需要补回
            -- Utils:debitRepay(
            --     self,
            --     pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SLOTSHIP_SETTLE"),
            --     v,
            --     user,
            --     EnumRoomState.Show
            -- )
            log.info("(%s,%s) userWalletResp(),uid=%s,userMoney=%s", self.id, self.mid, self.uid or 0,
                self:getUserMoney(self.uid))
        else
            if type(v) == "table" and rawget(v, "extrainfo") and v.extrainfo and v.extrainfo ~= "" then
                local extrainfo = rawget(v, "extrainfo") and cjson.decode(v.extrainfo) or nil
                if user and extrainfo and extrainfo["api"] == "debit" and v.uid == self.uid then
                    user.isdebiting = false
                    self.t.code = pb.enum_id("network.cmd.EnumBetErrorCode", "EnumBetErrorCode_Fail") -- 下注失败

                    local resp = pb.encode("network.cmd.PBSlotSpinResp_S", self.t)
                    net.send(
                        self.linkid,
                        self.uid,
                        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
                        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotSpinResp"), -- 旋转回应
                        resp
                    )
                    log.debug("idx(%s,%s) userchipin(),uid=%s, PBSlotSpinResp_S 11: %s", self.id, self.mid, self.uid,
                        cjson.encode(self.t))
                    self.state = EnumRoomState.Check
                    log.debug("uid=%s, state=%s,userWalletResp() 1  1", self.uid, self.state)

                end
            end
        end
    end
end

-- 玩家请求获取房间配置信息
function Room:userSlotConfInfo(uid, linkid, rev)
    local t = {
        -- 待返回的结构  PBSlotConfResp_S
        aIcon = {},
        minBetForJackpot = self.confInfo.jpminbet or 10000
    }

    local i = 1

    for _, v in ipairs(SLOT_CONF.simple) do
        local icon = {
            iconType = v.id,
            twoWinTimes = v.times2,
            threeWinTimes = v.times3,
            fourWinTimes = v.times4,
            fiveWinTimes = v.times5
        }
        table.insert(t.aIcon, icon)
    end

    local resp = pb.encode("network.cmd.PBSlotConfResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotConfResp"), -- 旋转回应
        resp
    )
    log.debug("idx(%s,%s) uid=%s, PBSlotConfResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
end

-- 获取最终的牌数据
function Room:getFinalCards()
    local times = 0
    local randCards
    local last_profit_rate = nil
    local minwin = nil
    local profit_rate, usertotalbet_inhand, usertotalprofit_inhand = 0, self.bet, 0
    -- if self.currentIsFreeSpin then
    --     usertotalbet_inhand = 0
    -- end

    while true do
        randCards = GetCards(SLOT_CONF, self.confInfo.mid)
        if self.confInfo.single_profit_switch then -- 如果是单人控制
            self.cards = g.copy(randCards)
            return self.cards
        end
        usertotalprofit_inhand = GetAllLineWinTimes(randCards, SLOT_CONF, self.confInfo.mid, GetLineNum()) *
            self.bet / GetLineNum()
        if not minwin or usertotalprofit_inhand < minwin then
            minwin = usertotalprofit_inhand
            self.cards = g.copy(randCards)
        end

        profit_rate = self:getTotalProfitRate(usertotalbet_inhand, usertotalprofit_inhand)
        if profit_rate < self.confInfo.profitrate_threshold_minilimit then -- 盈利阈值触发收紧策略
            -- 百分之百会重新发牌
        elseif profit_rate < self.confInfo.profitrate_threshold_lowerlimit then
            local rnd = rand.rand_between(1, 10000)
            if rnd <= 5000 then -- 一半的概率不需要重新发牌
                break
            end
        else
            break -- 不需要重新发牌  跳出while循环
        end
        log.debug("getFinalCards() times=%s,uid=%s", times, self.uid)
        times = times + 1
        if times > 5 then
            break
        end
    end
    profit_rate = self:getTotalProfitRate(usertotalbet_inhand, minwin, true)
    log.debug("getFinalCards() profit_rate=%s, bet=%s,winMoney=%s", tostring(profit_rate), self.bet, minwin)

    -- if rand.rand_between(0, 100) < 10 then   -- 2022-2-18
    --     self.cards = {0x06, 0x0a, 0x0B, 0x0c, 0x0c, 0x0c, 0x09, 0x0d, 0x0d, 0x0d, 0x0d, 0x02, 0x0C, 0x03, 0x01}
    -- end

    return self.cards
end

-- 获取系统盈利比例
-- 参数 wintype: 玩家是否赢
-- 参数 currentBet: 当前这一局玩家下注金额(免费旋转时为0)
-- 参数 currentWin: 当前这一局玩家线条中奖金额
function Room:getTotalProfitRate(currentBet, currentWin, isResult)
    local totalbets, totalprofit = 0, 0 -- 总下注额,总收益
    local sn = 0

    for k, v in g.pairsByKeys(
        self.total_bets,
        function(arg1, arg2)
            return arg1 > arg2
        end
    ) do
        if sn >= self.confInfo.profitrate_threshold_maxdays then -- 如果前面已有3个元素
            sn = k
            break
        end
        totalbets = totalbets + v -- 累计玩家总下注额
        sn = sn + 1
    end

    totalbets = totalbets + currentBet -- 增加本局下注金额 2022-8-19 19:26:33

    self.total_bets[sn] = nil -- 将最前那个移除掉  防止超过 profitrate_threshold_maxdays 天
    sn = 0

    for k, v in g.pairsByKeys(
        self.total_profit,
        function(arg1, arg2)
            return arg1 > arg2
        end
    ) do
        if sn >= self.confInfo.profitrate_threshold_maxdays then
            sn = k
            break
        end
        totalprofit = totalprofit + v -- 累计玩家总盈利
        sn = sn + 1
    end
    self.total_profit[sn] = nil

    -- 玩家当前这一局总盈利
    totalprofit = totalprofit + currentWin

    --盈利率 = (投注总额*(1-投注进入jackpot比例) -  非jackpot中奖总额 ) / 投注总额*(1-投注进入jackpot比例)
    local percent = JACKPOT_CONF[self.confInfo.jpid].deltabb / 100.0
    local profit_rate = totalbets > 0 and (totalbets * (1 - percent) - totalprofit) / (totalbets * (1 - percent)) or 0
    if isResult then
        log.debug(
            "getTotalProfitRate() currentBet=%s,currentWin=%s, percent=%s, totalbets=%s, totalprofit=%s,profit_rate=%s",
            currentBet,
            currentWin,
            tostring(percent),
            totalbets,
            totalprofit,
            tostring(profit_rate)
        )
    end
    return profit_rate
end

function Room:conf()
    return MatchMgr:getConfByMid(self.mid) -- 根据房间类型(房间级别)获取该类房间配置
end

-- 根据牌数据及下注金额获取玩家赢取到的金额
function Room:GetRealPlayerWin()
    -- self.cards
    -- self.bet

    log.debug("uid=%s,GetRealPlayerWin()", self.uid or 0)
    local winMoney = 0

    -- 计算所有线条赢得的倍数
    local lineWinTimes = GetAllLineWinTimes(self.cards, SLOT_CONF, self.confInfo.mid, GetLineNum())
    log.debug("uid=%s,GetRealPlayerWin() 2", self.uid or 0)
    if lineWinTimes > 0 then
        winMoney = lineWinTimes * self.bet / GetLineNum()
    end
    log.debug("uid=%s,GetRealPlayerWin() 3", self.uid or 0)
    local scatterNum = 0
    -- 旋转金额大于等于10000才有机会赢得jackpot
    if self.bet >= self.confInfo.jpminbet then
        -- 计算这一局赢得的jackpot
        scatterNum = GetScatterNum(self.cards)
        if scatterNum >= 3 then
            log.debug("uid=%s,GetRealPlayerWin() 4", self.uid or 0)
            return 0x7FFFFFFF
        end
    end
    winMoney = winMoney - self.bet
    log.debug("uid=%s,GetRealPlayerWin() 5", self.uid or 0)
    return winMoney
end

-- 发送游戏结果
function Room:sendResult(uid, t, linkid)
    local user = self.users[uid] or {} -- 根据玩家ID获取玩家对象
    local curday = global.cdsec() -- 当天标志
    self.state = EnumRoomState.Show -- 4 -- 结算状态
    log.debug("uid=%s, state=%s,sendResult() 4", self.uid, self.state)
    self.stateBeginTime = global.ctsec() -- 该状态开始时刻

    if self.cfgcard_switch and not self.lastSpinIsFree then
        if rand.rand_between(0, 100) < 20 then
            self.cards = { 0x06, 0x0a, 0x0B, 0x0c, 0x0c, 0x0c, 0x09, 0x0d, 0x0d, 0x0d, 0x0d, 0x02, 0x02, 0x03, 0x01 }
        end
    end
    -- if not self.currentIsFreeSpin then
    --     local randV = rand.rand_between(1, 100)
    --     if randV < 30 then
    --         --self.cards = { 0x06, 0x0a, 0x0B, 0x0c, 0x0c, 0x0c, 0x09, 0x0d, 0x0d, 0x0d, 0x0d, 0x02, 0x02, 0x03, 0x01 } -- 同时存在jackpot和free
    --         self.cards = { 0x06, 0x0a, 0x0B, 0x03, 0x03, 0x02, 0x09, 0x0d, 0x0d, 0x0d, 0x04, 0x02, 0x02, 0x03, 0x01 } -- 只中jackpot
    --     elseif randV < 60 then
    --         self.cards = { 0x06, 0x0a, 0x0B, 0x03, 0x03, 0x02, 0x09, 0x0d, 0x0d, 0x0d, 0x0d, 0x02, 0x02, 0x03, 0x01 } -- 只中jackpot
    --     elseif randV < 90 then
    --         --self.cards = { 0x06, 0x0a, 0x0B, 0x0c, 0x0c, 0x0c, 0x09, 0x02, 0x03, 0x04, 0x05, 0x02, 0x02, 0x03, 0x01 } -- 只中free
    --         self.cards = { 0x06, 0x0a, 0x0B, 0x03, 0x03, 0x02, 0x09, 0x0d, 0x0d, 0x0d, 0x0d, 0x0d, 0x02, 0x03, 0x01 } -- 只中jackpot
    --     end
    -- end
    t.cards = g.copy(self.cards) -- 该局牌数据

    local winMoney = 0 -- 该局赢取到的金额
    self.lastWin = 0

    -- 计算所有线条赢得的倍数
    local lineWinTimes = GetAllLineWinTimes(self.cards, SLOT_CONF, self.confInfo.mid, GetLineNum())
    if lineWinTimes > 0 then
        log.debug("sendResult(),uid=%s,lineWinTimes=%s,bet=%s", self.uid, lineWinTimes, self.bet)
        winMoney = lineWinTimes * self.bet / GetLineNum()
        self.lastWin = winMoney
        local lineCards = {}
        local winLineTimes = 0
        for i = 1, GetLineNum() do -- 遍历每一条线
            lineCards = GetLineData(i, self.cards, SLOT_CONF)
            local lineTimes, num = GetWinType(lineCards, SLOT_CONF, self.confInfo.mid)
            if lineTimes > 0 then
                table.insert(
                    t.winLines,
                    {
                        lineNo = i,
                        picNum = num,
                        winTimes = lineTimes,
                        winMoney = lineTimes * self.bet / GetLineNum()
                    }
                )
            end
        end
    end

    --盈利扣水
    local totalpureprofit = 0
    if t.isFreeSpin then -- 如果是免费旋转
        winMoney = math.floor(winMoney * (1 - (self.confInfo.rebate or 0)))
        totalpureprofit = winMoney
        user.totalpureprofit = totalpureprofit
    else -- 如果不是免费旋转
        local rebate = math.floor((winMoney - self.bet) * (self.confInfo.rebate or 0))
        if rebate > 0 then
            winMoney = winMoney - rebate
        end
        totalpureprofit = winMoney - self.bet -- 纯盈利
        user.totalpureprofit = totalpureprofit
    end
    self.winMoney = self.winMoney + winMoney -- 本次赢取到的金额总和(如果有免费旋转，则有多局)

    log.debug("sendResult(),uid=%s,userMoney=%s,winMoney=%s,self.winMoney=%s", self.uid, self:getUserMoney(self.uid),
        winMoney, self.winMoney)

    -- 计算这一局赢取的免费旋转次数
    local winFreeSpinTimes = GetWinFreeSpinTimes(self.cards, SLOT_CONF, self.confInfo.mid)
    if winFreeSpinTimes > 0 then
        if self.cfgcard_switch then
            winFreeSpinTimes = 3 -- 暂时测试用 待修改DQW
        end
        self.freeSpinTimes = self.freeSpinTimes + winFreeSpinTimes
        self.totalFreeSpinTimes = self.totalFreeSpinTimes + winFreeSpinTimes
    end

    local scatterNum = 0
    -- 旋转金额大于等于10000才有机会赢得jackpot
    if self.bet >= self.confInfo.jpminbet then
        -- 计算这一局赢得的jackpot
        scatterNum = GetScatterNum(self.cards)
    end
    if t.isFreeSpin then
        -- t.balance = self:getUserMoney(self.uid) + winMoney -- 玩家身上金额
        t.balance = self.beginMoney + self.winMoney
        self.totalFreeSpinWin = self.totalFreeSpinWin + winMoney
        self.lastWin = self.totalFreeSpinWin
    else
        self.lastWin = winMoney
        --t.balance = self:getUserMoney(self.uid) + winMoney - self.bet -- 玩家身上金额
        -- t.balance = self:getUserMoney(self.uid) + winMoney -- 玩家身上金额
        t.balance = self.beginMoney + self.winMoney -- 玩家身上金额
    end
    t.winMoney = winMoney -- 该局赢取到的金额
    t.winFreeSpinTimes = winFreeSpinTimes
    t.freeSpinTimes = self.freeSpinTimes
    t.totalFreeSpinWin = self.totalFreeSpinWin

    if winMoney > 0 then
        self.total_profit[curday] = (self.total_profit[curday] or 0) + winMoney -- 线条中奖总金额
        self.users[self.uid] = self.users[self.uid] or {}
        self.users[self.uid].totalprofit = self.winMoney
        self.users[self.uid].totalfee = 0
    else
        self.users[self.uid] = self.users[self.uid] or {}
        self.users[self.uid].totalprofit = self.winMoney
        self.users[self.uid].totalfee = 0
    end

    self.sdata = self.sdata or { roomtype = self.confInfo.roomtype, tag = self.confInfo.tag or 1 } -- 清空统计数据

    self.sdata.stime = self.starttime -- 开始时刻(秒)
    self.sdata.etime = global.ctms() / 1000 -- 结束时刻(秒) DQW
    self.sdata.totalbet = self.bet -- 该局总下注额
    self.sdata.totalprofit = self.winMoney -- 该局总收益

    self.sdata.jp = self.sdata.jp or {}
    self.sdata.jp.id = self.confInfo.jpid

    log.debug("uid=%s,jpid=%s,self.bet=%s,jpminbet=%s,scatterNum=%s", self.uid, self.confInfo.jpid, self.bet,
        self.confInfo.jpminbet, scatterNum)
    --JackPot抽水
    if JACKPOT_CONF[self.confInfo.jpid] then
        if t.isFreeSpin then
            self.sdata.jp.delta_add = self.sdata.jp.delta_add or 0
        else
            local delta_add = JACKPOT_CONF[self.confInfo.jpid].deltabb * self.bet / 100
            self.sdata.jp.delta_add = (self.sdata.jp.delta_add or 0) + delta_add
        end

        if scatterNum > 5 then
            t.winJackPot = true
            self.jackpot_and_showcard_flags = true
            -- self.sdata.jp.delta_sub = JACKPOT_CONF[self.confInfo.jpid].percent[3]
            -- self.sdata.jp.uid = self.uid
            -- self.sdata.jp.username = self.users[self.uid] and self.users[self.uid].username or ""
            -- self.sdata.winpokertype = 5
            self.needJackPotResult = true

            self.gamelog.jp = {}
            self.gamelog.jp.delta_sub = JACKPOT_CONF[self.confInfo.jpid].percent[3]
            self.gamelog.jp.uid = self.uid
            self.gamelog.jp.username = self.users[self.uid] and self.users[self.uid].username or ""
            self.gamelog.winpokertype = 5
            log.debug("uid=%s,jpid=%s,self.gamelog=%s", self.uid, self.confInfo.jpid, cjson.encode(self.gamelog))
            self:getJackpot()
            -- 增加定时器，等待jackpot结果
            timer.tick(self.timer, TimerID.TimerID_WaitJackpotResult[1], TimerID.TimerID_WaitJackpotResult[2],
                onWaitJackpotResult, self)
        elseif scatterNum >= 3 then
            t.winJackPot = true
            self.jackpot_and_showcard_flags = true
            -- self.sdata.jp.delta_sub = JACKPOT_CONF[self.confInfo.jpid].percent[scatterNum - 2]
            -- self.sdata.jp.uid = self.uid
            -- self.sdata.jp.username = self.users[self.uid] and self.users[self.uid].username or ""
            -- self.sdata.winpokertype = scatterNum
            self.needJackPotResult = true


            self.gamelog.jp = {}
            self.gamelog.jp.delta_sub = JACKPOT_CONF[self.confInfo.jpid].percent[scatterNum - 2]
            self.gamelog.jp.uid = self.uid
            self.gamelog.jp.username = self.users[self.uid] and self.users[self.uid].username or ""
            self.gamelog.winpokertype = scatterNum
            log.debug("uid=%s,jpid=%s,self.gamelog=%s", self.uid, self.confInfo.jpid, cjson.encode(self.gamelog))
            self:getJackpot()
            -- 增加定时器，等待jackpot结果
            timer.tick(self.timer, TimerID.TimerID_WaitJackpotResult[1], TimerID.TimerID_WaitJackpotResult[2],
                onWaitJackpotResult, self)
        end
    end

    -- 牌局统计数据上报
    self.sdata.areas = {}
    self.sdata.cards = self.sdata.cards or { { cards = {} } }
    self.sdata.cards[self.index] = { cards = {} }
    self.sdata.cards[self.index].cards = g.copy(self.cards)
    self.sdata.wintypes = { 1 }
    self.sdata.totalbet = self.bet
    self.sdata.totalprofit = self.winMoney
    self.sdata.extrainfo = cjson.encode({ playercount = self.index, playerbet = self.bet, playerprofit = self.winMoney })

    -- 统计
    self.sdata.users = self.sdata.users or {}
    self.sdata.users[uid] = self.sdata.users[uid] or {}
    self.sdata.users[uid].stime = self.starttime
    self.sdata.users[uid].etime = global.ctms() / 1000
    self.sdata.users[uid].username = user.username
    self.sdata.users[uid].nickurl = user.nickurl
    self.sdata.users[uid].totalbet = self.bet
    self.sdata.users[uid].totalprofit = self.winMoney
    self.sdata.users[uid].totalpureprofit = self.winMoney - self.bet

    self.sdata.users[uid].cards = g.copy(self.cards)

    if not Utils:isRobot(user.api) then
        self.sdata.users[uid].ugameinfo = { texas = { inctotalhands = 1 } } -- 增加该玩家已玩局数
    end
    if t.isFreeSpin then -- 如果是免费旋转
        self.sdata.users[uid].extrainfo =
        cjson.encode(
            {
                ip = user and user.ip or "",
                api = user and user.api or "",
                roomtype = self.confInfo.roomtype,
                roundid = user.roundId,
                jp = {
                    id = self.sdata.jp.id,
                    delta_sub = self.sdata.jp.delta_sub or 0,
                    delta_add = self.sdata.jp.delta_add or 0
                },
                playchips = self.bet, -- 2022-1-11
                maxwin = user.maxwin or 0, -- 2022-3-21
                money = self:getUserMoney(uid) or 0,
                totalmoney = self:getUserMoney(uid) or 0 -- 总金额
            }
        )
    else
        self.sdata.users[uid].extrainfo =
        cjson.encode(
            {
                ip = user and user.ip or "",
                api = user and user.api or "",
                roomtype = self.confInfo.roomtype,
                roundid = user.roundId,
                jp = {
                    id = self.sdata.jp.id,
                    delta_sub = self.sdata.jp.delta_sub or 0,
                    delta_add = self.sdata.jp.delta_add or 0
                },
                playchips = self.bet, -- 2022-1-11
                maxwin = user.maxwin or 0, -- 2022-3-21
                money = self:getUserMoney(uid) or 0,
                totalmoney = self:getUserMoney(uid) or 0 -- 总金额
            }
        )
    end

    t.totalFreeSpinTimes = self.totalFreeSpinTimes -- 总共免费旋转次数
    if t.isFreeSpin and 0 == self.freeSpinTimes then -- 如果免费旋转次数已用完
        -- t.totalFreeSpinTimes = self.totalFreeSpinTimes -- 总共免费旋转次数
        -- t.totalFreeSpinWin = self:getUserMoney(self.uid) + self.winMoney - self.beginFreeSpinMoney --免费旋转总盈利
        -- if t.totalFreeSpinWin < self.totalFreeSpinWin then
        --     t.totalFreeSpinWin = self.totalFreeSpinWin
        -- end
        self.totalFreeSpinTimes = 0
    end

    if not self.users[self.uid].isdebiting and self.freeSpinTimes <= 0 and not self.needJackPotResult then -- 如果未中免费旋转且未中jackpot
        Utils:credit(self, pb.enum_id("network.inter.MONEY_CHANGE_REASON", "MONEY_CHANGE_SLOTSHIP_SETTLE")) -- 增加金额(输赢都更新金额)
        log.debug("Utils:credit(),uid=%s,self.winMoney=%s,userMoney=%s,sendResult()", self.uid, self.winMoney,
            self:getUserMoney(self.uid))

        log.debug("uid=%s,self.sdata.jp=%s", self.uid, cjson.encode(self.sdata.jp))

        self.sdata.users = self.sdata.users or {}
        self.sdata.users[uid] = self.sdata.users[uid] or {}
        self.sdata.users[uid].totalprofit = self.winMoney
        self.sdata.users[uid].totalpureprofit = self.winMoney - self.bet

        self.statistic:appendLogs(self.sdata, self.logid) -- 统计信息
        self:reset()

        self.winMoney = 0
        self.sdata.jp = {}
        Utils:serializeMiniGame(SLOT_SHIP_INFO, nil, global.stype())
    end
    -- if self.needJackPotResult and self.freeSpinTimes <= 0 then
    --     t.winJackPot = true
    -- end

    local resp = pb.encode("network.cmd.PBSlotSpinResp_S", t)
    net.send(
        linkid,
        uid,
        pb.enum_id("network.cmd.PBMainCmdID", "PBMainCmdID_Game"),
        pb.enum_id("network.cmd.PBGameSubCmdID", "PBGameSubCmdID_SlotSpinResp"), -- 旋转回应
        resp
    )
    log.info("idx(%s,%s) uid=%s, PBSlotSpinResp_S: %s", self.id, self.mid, uid, cjson.encode(t))
    if not self.needJackPotResult then -- 如果不需要等待jackpot结果
        self.state = EnumRoomState.Check
        log.debug("uid=%s, state=%s,sendResult() 1", self.uid, self.state)
        self.stateBeginTime = global.ctsec() -- 该状态开始时刻
    end
end

-- 获取未中任何奖的牌数据(输的牌)
function Room:getLoseCards()
    for i = 1, 1000, 1 do
        local cards = { rand.rand_between(1, 10), rand.rand_between(1, 11), rand.rand_between(1, 13),
            rand.rand_between(1, 10),
            rand.rand_between(1, 13), rand.rand_between(1, 10), rand.rand_between(1, 10), rand.rand_between(1, 10),
            rand.rand_between(1, 11),
            rand.rand_between(1, 13), rand.rand_between(1, 10), rand.rand_between(1, 11), rand.rand_between(1, 10),
            rand.rand_between(1, 10), rand.rand_between(1, 10) }

        local scatterNum = GetScatterNum(cards)
        local freeSpinsNum = GetFreeSpinsNum(cards)
        local lineWinTimes = GetAllLineWinTimes(cards, SLOT_CONF, self.confInfo.mid, GetLineNum())

        if scatterNum < 3 and freeSpinsNum < 3 and lineWinTimes <= 0 then
            return cards
        end
    end
end

-- 增加消息请求获取中jackpot金额
function Room:getJackpot()
    -- network.inter.PBGameLog

    self.gamelog.logid = self.logid
    self.gamelog.stime = self.starttime
    self.gamelog.etime = global.ctms() / 1000
    self.gamelog.cards[1].cards = self.cards or {}
    self.gamelog.totalbet = self.bet or 0

    self.gamelog.jp.id = self.confInfo.jpid


    Utils:requestJackpotChange(self.gamelog)
end


