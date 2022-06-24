local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local global = require(CLIBS["c_global"])
require("luascripts/servers/28/reservation")

-- seat start
Seat = {}

function Seat:new(t, sid)
    local s = {}
    setmetatable(s, self)
    self.__index = self

    s:init(t, sid)

    return s
end

function Seat:init(t, sid)
    --self.uid = 0
    self.table = t
    self.sid = sid
    self.handtype = 0 -- 手牌类型查看enum CardWinType
    self.handcards = {0, 0} -- 手牌
    self.besthand = {0, 0, 0, 0, 0} -- 结算后的5张牌
    self.roundchipintypes = {0, 0, 0, 0} -- 手牌、翻牌前、转牌、河牌下注类型
    self.roundchipinmoneys = {0, 0, 0, 0} -- 手牌、翻牌前、转牌、河牌下注筹码数
    self.isplaying = false -- 是否在玩状态
    self.chips = 0 -- 剩余筹码数
    self.last_chips = 0 -- 剩余筹码数
    self.roundmoney = 0 -- 一轮下注筹码值
    self.money = 0 -- 一局总消耗筹码数
    self.chipinnum = 0 -- 上一轮下注筹码值
    self.chiptype = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_NULL") -- 下注操作类型
    self.lastchiptype = self.chiptype
    self.isdelayplay = false -- 是否延迟进入比赛
    self.reraise = false -- 是否起reraise
    self.bettingtime = 0 -- 下注时刻
    self.show = false -- 是否需要亮牌
    self.bigblind_betting = false
    self.cgcoins = 0 -- 筹码变化
    self.save = 0 -- 牌局是否收藏
    self.isputin = 0 -- 是否入局
    self.escape_bb_count = 0 -- 防逃盲次数
    self.addon_time = 0
    self.addon_count = 0
    self.total_time = self.table.bettingtime

    self.gamecount = 0

    self.rv = Reservation:new(self.table, self) -- 留座发生器

    self.autobuy = 0 -- 普通场玩法自动买入
    self.buyinToMoney = 0 -- 普通场玩法自动买入多少钱
    self.totalbuyin = 0 --总共买入
    self.currentbuyin = 0 --非 0：此次已买入但未加到筹码 0：没有买入要换成筹码
    self.isbuyining = false --正在买入
    self.autoBuyinToMoney = 0 --普通场勾选了自动买入后手动补币数
    self.escapebb = 0 -- 1: 坐下立刻交大盲，然后玩牌    0：分配到小盲或庄位要等1轮

    self.preop = 0
    self.total_bets = 0
end

function Seat:sit(uid, init_money, autobuy, escapebb, totalbuyin)
    if self.uid ~= nil then
        return false
    end

    self:reset()
    self.uid = uid
    self.chips = init_money
    self.last_chips = self.chips
    self.rv:reset()
    self.autobuy = autobuy
    self.buyinToMoney = init_money
    self.totalbuyin = totalbuyin
    self.currentbuyin = 0
    self.escapebb = escapebb or 0
    self.addon_time = 0
    self.addon_count = 0

    --if self.autobuy == 0 then
    --self.buyinToMoney = 0
    --self.totalbuyin = 0
    --end

    self.escape_bb_count = 0
    self.gamecount = 0

    self.preop = 0
    return true
end

function Seat:totalBuyin()
    return self.totalbuyin
end

function Seat:setIsBuyining(state)
    self.isbuyining = state
    if self.isbuyining then
        self.buyin_start_time = global.ctsec()
    end
end

function Seat:getIsBuyining()
    return self.isbuyining
end

function Seat:buyin(money)
    self.totalbuyin = self.totalbuyin + money
    self.currentbuyin = self.currentbuyin + money
end

function Seat:buyinToChips()
    self.chips = self.chips + self.currentbuyin
    self.last_chips = self.chips
    self.currentbuyin = 0
end

function Seat:hasBuyin()
    return self.currentbuyin > 0
end

function Seat:setPreOP(preop)
    self.preop = preop
end

function Seat:getPreOP()
    return self.preop
end

function Seat:stand(uid)
    if self.uid == nil then
        return false
    end

    self.uid = nil
    self.isplaying = false
    self.chips = 0

    self.autobuy = 0
    self.buyinToMoney = 0
    self.totalbuyin = 0
    self.currentbuyin = 0
    self.isbuyining = false

    self.autoBuyinToMoney = 0
    self.escapebb = 0

    self.escape_bb_count = 0
    self.gamecount = 0

    self.rv.is_set_rvtimer = false

    self.preop = 0

    return true
end

function Seat:reset()
    self.handtype = 0
    self.handcards = {0, 0}
    self.besthand = {0, 0, 0, 0, 0}
    self.roundchipintypes = {0, 0, 0, 0}
    self.roundchipinmoneys = {0, 0, 0, 0}
    self.money = 0
    self.roundmoney = 0
    self.chipinnum = 0
    self.chiptype = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_NULL")
    self.lastchiptype = self.chiptype
    self.isplaying = false
    self.reraise = false
    self.bettingtime = 0
    self.show = false
    self.bigblind_betting = false
    self.cgcoins = 0
    self.save = 0
    self.isputin = 0
    self.last_chips = self.chips
    self.total_time = self.table.bettingtime
    self.odds = nil
    self.total_bets = 0
end

function Seat:chipin(type, money)
    log.info(
        "Seat:chipin UID:%s pos:%s type:%s lasttype:%s money:%s chips:%s, state:%s, isplaying:%s",
        self.uid,
        self.sid,
        type,
        self.lastchiptype,
        money,
        self.chips,
        self.table.state,
        tostring(self.isplaying)
    )
    if not self.isplaying then
        return
    end
    self.chiptype = type
    self.chipinnum = self.roundmoney
    self.roundmoney = money or 0
    self.addon_time = 0
    self.total_time = self.table.bettingtime

    if money >= self.chips and type ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") then
        self.chiptype = pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN")
        self.roundmoney = self.chips
        money = self.chips
    end

    -- 留座
    if
        type ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") and
            type ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BIGBLIND") and
            type ~= pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_SMALLBLIND")
     then
        self.rv:resetBySys()
    end

    -- 每一轮操作记录
    if self.table.state > pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Start") then
        local round = self.table.state - pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreChips")
        self.roundchipintypes[round] = self.chiptype
        self.roundchipinmoneys[round] = self.roundmoney
    end

    -- 统计
    self.table.sdata.users = self.table.sdata.users or {}
    self.table.sdata.users[self.uid] = self.table.sdata.users[self.uid] or {}
    self.table.sdata.users[self.uid].betype = self.table.sdata.users[self.uid].betype or {}
    self.table.sdata.users[self.uid].betvalue = self.table.sdata.users[self.uid].betvalue or {}
    table.insert(self.table.sdata.users[self.uid].betype, self.chiptype)
    table.insert(self.table.sdata.users[self.uid].betvalue, self.roundmoney - self.chipinnum)

    self.table.sdata.users[self.uid].ugameinfo = self.table.sdata.users[self.uid].ugameinfo or {}
    self.table.sdata.users[self.uid].ugameinfo.texas = self.table.sdata.users[self.uid].ugameinfo.texas or {}
    local bet = {uid = self.uid, bv = self.roundmoney - self.chipinnum, bt = self.chiptype}
    if
        self.table.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_None") or
            self.table.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreChips") or
            self.table.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_PreFlop")
     then
        self.table.sdata.users[self.uid].ugameinfo.texas.pre_bets =
            self.table.sdata.users[self.uid].ugameinfo.texas.pre_bets or {}
        table.insert(self.table.sdata.users[self.uid].ugameinfo.texas.pre_bets, bet)
    elseif self.table.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Flop") then
        self.table.sdata.users[self.uid].ugameinfo.texas.flop_bets =
            self.table.sdata.users[self.uid].ugameinfo.texas.flop_bets or {}
        table.insert(self.table.sdata.users[self.uid].ugameinfo.texas.flop_bets, bet)
    elseif self.table.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Turn") then
        self.table.sdata.users[self.uid].ugameinfo.texas.turn_bets =
            self.table.sdata.users[self.uid].ugameinfo.texas.turn_bets or {}
        table.insert(self.table.sdata.users[self.uid].ugameinfo.texas.turn_bets, bet)
    elseif self.table.state == pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_River") then
        self.table.sdata.users[self.uid].ugameinfo.texas.river_bets =
            self.table.sdata.users[self.uid].ugameinfo.texas.river_bets or {}
        table.insert(self.table.sdata.users[self.uid].ugameinfo.texas.river_bets, bet)
    end
    log.info("%s %s %s", self.table.state, self.chiptype, self.lastchiptype)
    if self.table.state < pb.enum_id("network.cmd.PBTexasTableState", "PBTexasTableState_Flop") then --翻牌前
        if
            pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_FOLD") == self.chiptype and
                (pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_NULL") == self.lastchiptype or
                    pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_SMALLBLIND") == self.lastchiptype or
                    pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BIGBLIND") == self.lastchiptype or
                    pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_PRECHIPS") == self.lastchiptype)
         then
            self.table.sdata.users[self.uid].ugameinfo.texas.incpreflopfoldhands = 1
        end
        if
            pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_RAISE") == self.chiptype or
                pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_ALL_IN") == self.chiptype
         then
            self.table.sdata.users[self.uid].ugameinfo.texas.incpreflopraisehands = 1
        end
        if
            pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_CHECK") == self.chiptype and
                (pb.enum_id("network.cmd.PBTexasChipinType", "PBTexasChipinType_BIGBLIND") == self.lastchiptype)
         then
            self.table.sdata.users[self.uid].ugameinfo.texas.incpreflopcheckhands = 1
        end
    end

    self.lastchiptype = self.chiptype
    self.table.lastchipintype = self.chiptype
    self.table.lastchipinpos = self.sid
end

function Seat:getChipinTotalTime()
    return self.total_time
end

function Seat:isChipinTimeout()
    local elapse = global.ctsec() - self.bettingtime
    if elapse >= self.table.bettingtime + self.addon_time then
        return true
    else
        return false
    end
end

function Seat:getChipinLeftTime()
    local now = global.ctsec()
    local elapse = now - self.bettingtime
    if elapse > self.table.bettingtime + self.addon_time then
        return 0
    else
        return (self.table.bettingtime + self.addon_time) - elapse
    end
end
