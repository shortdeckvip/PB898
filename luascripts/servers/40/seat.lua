local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local global = require(CLIBS["c_global"])

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
    self.handcards = {} -- 手牌
    self.drawcard = 0 --摸上来的牌
    self.isplaying = false -- 是否在玩状态
    self.chips = 0 -- 剩余筹码数
    self.last_chips = 0 -- 剩余筹码数
    self.roundmoney = 0 -- 一轮下注筹码值
    self.money = 0 -- 一局总消耗筹码数
    self.chipinnum = 0 -- 上一轮下注筹码值
    self.chiptype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_NULL") -- 下注操作类型
    self.lastchiptype = self.chiptype
    self.bettingtime = 0 -- 下注时刻
    self.show = false -- 是否需要亮牌
    self.total_time = self.table.bettingtime
    self.addon_time = 0
    self.addon_count = 0
    self.is_drawcard = false

    self.gamecount = 0

    self.autobuy = 0 -- 普通场玩法自动买入
    self.buyinToMoney = 0 -- 普通场玩法自动买入多少钱
    self.totalbuyin = 0 --总共买入
    self.currentbuyin = 0 --非 0：此次已买入但未加到筹码 0：没有买入要换成筹码
    self.isbuyining = false --正在买入
    self.autoBuyinToMoney = 0 --普通场勾选了自动买入后手动补币数

    self.preop = 0
    self.bet_timeout_count = 0
    self.room_delta = 0
    self.zone = {}
    self.profit = 0
    self.additional = {}
end

function Seat:sit(uid, init_money, autobuy, totalbuyin)
    if self.uid ~= nil then
        return false
    end

    self:reset()
    self.uid = uid
    self.chips = init_money
    self.last_chips = self.chips
    self.autobuy = autobuy
    self.buyinToMoney = init_money
    self.totalbuyin = totalbuyin
    self.currentbuyin = 0
    self.addon_time = 0
    self.addon_count = 0

    self.gamecount = 0

    self.preop = 0
    self.intots = global.ctsec()
    self.room_delta = 0
    return true
end

function Seat:getIdxByCardValue(card)
    for k, v in ipairs(self.handcards) do
        if card == v then
            return k
        end
    end
    return 0
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

    self.gamecount = 0

    self.preop = 0
    self.room_delta = 0

    return true
end

function Seat:reset()
    self.handtype = 0
    self.handcards = {} -- 手牌
    self.drawcard = 0 --摸上来的牌
    self.money = 0
    self.roundmoney = 0
    self.chipinnum = 0
    self.chiptype = pb.enum_id("network.cmd.PBDummyChipinType", "PBDummyChipinType_NULL")
    self.lastchiptype = self.chiptype
    self.isplaying = false
    self.bettingtime = 0
    self.show = false
    self.last_chips = self.chips
    self.total_time = self.table.bettingtime
    self.is_drawcard = false
    self.bet_timeout_count = 0
    self.zone = {}
    self.lastfoldcard = 0
    self.oneshotflag = 0
    self.profit = 0
    self.room_delta = 0
    self.additional = {}
    self.show2q = false
    self.canshow2q = false
    self.iscreate = false
    self.handcreate = false
end

function Seat:getZone()
    local zone = {holes = {}}
    for _, v in ipairs(self.zone) do
        table.insert(zone.holes, {cards = v})
    end
    return zone
end

function Seat:chipin(type, value)
    log.debug(
        "Seat:chipin UID:%s pos:%s type:%s lasttype:%s money:%s chips:%s, state:%s, isplaying:%s",
        tostring(self.uid),
        self.sid,
        type,
        self.lastchiptype,
        value,
        self.chips,
        self.table.state,
        tostring(self.isplaying)
    )
    if not self.isplaying then
        return
    end
    self.chiptype = type
    self.chipinnum = value
    self.addon_time = 0
    self.total_time = self.table.bettingtime

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

function Seat:isInHandCard(card)
    for _, vv in ipairs(self.handcards) do
        if card == vv then
            return true
        end
    end
    return false
end
