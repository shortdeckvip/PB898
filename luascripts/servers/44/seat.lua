local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local global = require(CLIBS["c_global"])
require(string.format("luascripts/servers/%d/reservation", global.stype()))

-- seat start
Seat = {}

function Seat:new(t, sid)
    local s = {}
    setmetatable(s, self)
    self.__index = self

    s:init(t, sid)

    return s
end

local SeatState = { -- 低位标识是否参与游戏，高位标识是否坐下
    NotPlayNotSit = 0, -- 未参与游戏，没玩家坐下
    PlayNotSit = 1, -- 参与游戏，没玩家坐下
    NotPlaySit = 2, -- 未参与游戏，有玩家坐下
    PlaySit = 3 -- 参与游戏，有玩家坐下
}


-- 座位初始化
-- 参数 t: 房间对象
-- 参数 sid: 座位ID
function Seat:init(t, sid)
    --self.uid = nil  -- 坐下的玩家ID
    self.table = t
    self.sid = sid
    self.cardsType = 0 -- 手牌类型
    self.handcards = { 0, 0, 0 } -- 手牌
    self.cardsNum = 0 -- 已发牌张数
    self.besthand = { 0, 0, 0 } -- 最大组合牌数据
    self.replayCards = { 0, 0 } -- 重赛前发的牌(seotda3中必定为3张, seotda中为2张)
    self.roundNum = 0 -- 参与的轮数  >=3 则表示重赛了
    self.roundchipintypes = { 0, 0, 0, 0 } -- 第一轮、第二轮、重赛下注类型
    self.roundchipinmoneys = { 0, 0, 0, 0 } -- 手牌、翻牌前、转牌、河牌下注筹码数
    self.isplaying = false -- 是否在玩状态  是否参与游戏
    self.chips = 0 -- 剩余筹码数
    self.last_chips = 0 -- 剩余筹码数
    self.roundmoney = 0 -- 一轮下注筹码值
    self.operateTypesRound = 0 -- 该轮所有操作类型(位)
    self.operateTypes = 0 -- 该局所有操作类型(位)
    self.money = 0 -- 一局总消耗筹码数
    self.betmoney = 0 -- 下注金额(计算时使用)
    self.winmoney = 0 -- 该局赢取到的金额
    self.chipinnum = 0 -- 上一轮下注筹码值
    self.chiptype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_NULL") -- 下注操作类型
    self.lastchiptype = self.chiptype -- 最近一次操作类型

    self.bettingtime = 0 -- 下注时刻
    self.show = false -- 是否需要亮牌

    self.addon_time = 0
    self.addon_count = 0 -- 本轮已增加思考时间次数
    self.total_time = self.table.bettingtime

    self.gamecount = 0

    --self.rv = Reservation:new(self.table, self) -- 留座发生器

    self.autobuy = 0 -- 普通场玩法自动买入
    self.buyinToMoney = 0 -- 普通场玩法自动买入多少钱
    self.totalbuyin = 0 --总共买入
    self.currentbuyin = 0 --非 0：此次已买入但未加到筹码 0：没有买入要换成筹码
    self.isbuyining = false --正在买入
    self.autoBuyinToMoney = 0 --普通场勾选了自动买入后手动补币数
    self.escapebb = 0 -- 1: 坐下立刻交大盲，然后玩牌    0：分配到小盲或庄位要等1轮

    self.preop = 0
    self.total_bets = 0 -- 该局总下注金额
    self.playerState = 0 -- 该座位玩家状态 1-等待补码重赛 2-确定重赛 3-确定不重赛
    self.firstShowCard = 0 -- 三张中第一张要公开显示的牌
    self.secondCard = 0
    --self.state = SeatState.NotPlayNotSit -- 座位状态  0-不参与游戏且未坐下 1-参与游戏但未坐下  2-不参与游戏但已坐下  3-参与游戏且坐下
    self.hasLeave = true  -- 是否已经离开(默认已经离开)
end

-- 玩家坐下
-- 返回值: 成功坐下则返回true,否则返回false
function Seat:sit(uid, init_money, autobuy, escapebb, totalbuyin)
    if not uid then
        return false
    end

    -- if self.uid == uid then
    --     if self.isplaying then -- 如果该座位参与游戏
    --         self.state = SeatState.PlaySit -- 参与游戏且已坐下
    --     end
    -- end

    if self.uid ~= nil and self.uid ~= uid then -- 如果已经有玩家坐下 且 不是当前玩家
        return false
    end
    
    if not self.isplaying and not self.uid then  -- 未参与游戏，未坐下
    -- if self.state == SeatState.NotPlayNotSit then -- 未参与游戏，未坐下
        --self.state = SeatState.NotPlaySit
        self:reset()
        self.uid = uid
        self.chips = init_money
        self.last_chips = self.chips
        --self.rv:reset()
        self.autobuy = autobuy
        self.buyinToMoney = init_money
        self.totalbuyin = totalbuyin
        self.currentbuyin = 0
        self.escapebb = escapebb or 0
        self.addon_time = 0
        self.addon_count = 0

        self.gamecount = 0

        self.preop = 0
    -- elseif self.state == SeatState.PlayNotSit then
    --     self.state = SeatState.PlaySit
    end
    self.uid = uid

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

-- 买入筹码
function Seat:buyin(money)
    self.totalbuyin = self.totalbuyin + money
    self.currentbuyin = self.currentbuyin + money
end

-- 将要买入的筹码转换为筹码
function Seat:buyinToChips()
    self.chips = self.chips + self.currentbuyin
    self.last_chips = self.chips
    self.currentbuyin = 0
end

-- 判断是否正要买入筹码
function Seat:hasBuyin()
    return self.currentbuyin > 0
end

function Seat:setPreOP(preop)
    self.preop = preop
end

function Seat:getPreOP()
    return self.preop
end

-- 玩家站起
function Seat:stand(uid)
    if not uid then
        return false
    end
    if self.uid == nil then
        return false
    end
    if self.uid ~= uid then
        return false
    end

    self.hasLeave = true
    self.uid = nil
    -- if self.state == SeatState.NotPlaySit then -- 未参与游戏但坐下
    --     self.state = SeatState.NotPlayNotSit
    --     self.uid = nil
    -- elseif self.state == SeatState.PlaySit then  -- 参与游戏且坐下
    --     self.state = SeatState.PlayNotSit
    -- end

    self.chips = 0
    self.roundmoney = 0
    self.autobuy = 0
    self.buyinToMoney = 0
    self.totalbuyin = 0
    self.currentbuyin = 0
    self.isbuyining = false
    self.preop = 0

    --[[
    self.isplaying = false  --??
    
    self.autoBuyinToMoney = 0
    self.escapebb = 0

    self.gamecount = 0

    --self.rv.is_set_rvtimer = false
    --]]

    return true
end

-- 重置该座位
function Seat:reset()
    self.cardsType = 0 -- 最大牌牌型
    self.handcards = { 0, 0, 0 } -- 牌数据
    self.cardsNum = 0 -- 已发牌张数

    self.betmoney = 0 -- 下注金额(计算时使用)
    self.besthand = { 0, 0 } -- 最优手牌组合
    self.roundchipintypes = { 0, 0, 0, 0 } -- 各轮操作类型
    self.roundchipinmoneys = { 0, 0, 0, 0 } -- 各轮操作金额
    self.money = 0 -- 一局总消耗筹码数
    self.operateTypesRound = 0 -- 该轮操作类型(位)
    self.operateTypes = 0 -- 该局所有操作类型(位)
    self.winmoney = 0 -- 该局赢取到的金额
    self.roundmoney = 0 -- 一轮下注金额(一轮结束后会置0)
    self.total_bets = 0
    self.chipinnum = 0
    self.chiptype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_NULL") -- 操作类型
    self.lastchiptype = self.chiptype
    self.isplaying = false -- 未参与游戏
    --self.state = self.state & 2
    self.bettingtime = 0
    self.show = false
    self.last_chips = self.chips
    self.total_time = self.table.bettingtime
    self.playerState = 0
    self.firstShowCard = 0 -- 要公开显示的牌
    self.secondCard = 0 -- 第二张牌
    self.replayCards = { 0, 0 } -- 重赛前发的牌(seotda3张中必定为3张 seotda为2张)
    self.roundNum = 0 -- 参与的轮数  >=3 则表示重赛了
end

-- 玩家操作
-- 参数 type: 操作类型
-- 参数 money: 操作涉及到的金额
function Seat:chipin(type, money)
    log.debug(
        "idx(%s,%s,%s) Seat:chipin() uid=%s,sid=%s,type=%s,lasttype=%s,money=%s",
        self.table.id,
        self.table.mid,
        self.table.logid,
        self.uid,
        self.sid,
        type,
        self.lastchiptype,
        money
    )
    log.debug(
        "idx(%s,%s,%s) Seat:chipin() uid=%s,chips=%s,state=%s,isplaying=%s",
        self.table.id,
        self.table.mid,
        self.table.logid,
        self.uid,
        self.chips,
        self.table.state,
        tostring(self.isplaying)
    )
    if not self.isplaying then -- 如果未参与游戏
        return
    end
    self.operateTypesRound = self.operateTypesRound | (1 << type) -- 本轮该座位所有操作类型
    self.operateTypes = self.operateTypes | (1 << type) -- 该局该座位所有操作类型
    self.chiptype = type -- 操作类型
    self.chipinnum = self.roundmoney
    self.roundmoney = money
    self.addon_time = 0
    self.total_time = self.table.bettingtime

    if money >= self.chips and type ~= pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_FOLD") then
        self.chiptype = pb.enum_id("network.cmd.PBSeotdaChipinType", "PBSeotdaChipinType_ALL_IN")
        self.roundmoney = self.chips
        money = self.chips
        self.operateTypesRound = self.operateTypesRound | (1 << self.chiptype) -- 本轮该座位所有操作类型
        self.operateTypes = self.operateTypes | (1 << self.chiptype) -- 该局该座位所有操作类型
    end

    if self.table.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting1") then -- 第一轮下注
        self.roundchipintypes[1] = self.chiptype
        self.roundchipinmoneys[1] = self.roundmoney
    elseif self.table.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting2") then -- 第二轮下注
        self.roundchipintypes[2] = self.chiptype
        self.roundchipinmoneys[2] = self.roundmoney
    elseif self.table.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_Betting3") then -- 第三轮下注
        self.roundchipintypes[3] = self.chiptype
        self.roundchipinmoneys[3] = self.roundmoney
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
    local bet = { uid = self.uid, bv = self.roundmoney - self.chipinnum, bt = self.chiptype }

    if self.table.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_None") or
        self.table.state == pb.enum_id("network.cmd.PBSeotdaTableState", "PBSeotdaTableState_PreChips")
    then
        self.table.sdata.users[self.uid].ugameinfo.texas.pre_bets = self.table.sdata.users[self.uid].ugameinfo.texas.pre_bets
            or {}
        table.insert(self.table.sdata.users[self.uid].ugameinfo.texas.pre_bets, bet)
    end
    log.info("idx(%s,%s,%s) Seat:chipin(),state=%s,chiptype=%s,lastchiptype=%s", self.table.id, self.table.mid,
        self.table.logid, self.table.state, self.chiptype, self.lastchiptype)


    self.lastchiptype = self.chiptype -- 最近一次操作类型
    self.table.lastchipintype = self.chiptype
    self.table.lastchipinpos = self.sid -- 刚操作过的座位ID
end

function Seat:getChipinTotalTime()
    return self.total_time
end

-- 是否操作超时
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

-- 刷新座位状态
function Seat:flush()
    -- if self.state == SeatState.PlayNotSit or self.state == SeatState.NotPlayNotSit then -- 参与游戏但未坐下
    --     self.state = SeatState.NotPlayNotSit
    --     self.isplaying = false
    --     self.uid = nil
    --     self.hasLeave = true
    -- end
    if not self.uid then
        self.isplaying = false
        self.hasLeave = true
    end
    if self.hasLeave then
        self:reset()
    end
end
