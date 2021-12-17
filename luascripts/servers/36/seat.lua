-- serverdev\luascripts\servers\36\seat.lua

local pb = require("protobuf")
local log = require(CLIBS["c_log"])
local cjson = require("cjson")
local global = require(CLIBS["c_global"])
local g = require("luascripts/common/g")

-- seat start
Seat = {}

-- 创建一个座位
function Seat:new(t, sid)
    local s = {}
    setmetatable(s, self)
    self.__index = self

    s:init(t, sid) -- 初始化创建好的座位

    return s
end

-- 初始化座位
function Seat:init(t, sid)
    --self.uid = 0
    self.table = t -- 桌子对象(房间对象)
    self.sid = sid -- 座位ID
    self.uid = nil -- 坐在该位置的玩家ID
    self.isplaying = false -- 是否在玩状态
    self.handcards = {} -- 手牌 初始化时为7张牌

    self.handtype = 0 -- 手牌类型查看enum CardWinType
    -- self.handcards = {0, 0, 0, 0, 0, 0, 0} -- 手牌
    self.drawcard = 0 --摸上来的牌

    self.chips = 0 -- 剩余筹码数
    self.last_chips = 0 -- 剩余筹码数
    self.roundmoney = 0 -- 一轮下注筹码值
    self.money = 0 -- 一局总消耗筹码数
    self.chipinnum = 0 -- 上一轮下注筹码值
    self.chiptype = pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_NULL") -- 下注操作类型
    self.lastchiptype = self.chiptype
    self.bettingtime = 0 -- 下注时刻
    self.show = false -- 是否需要亮牌
    self.total_time = self.table.bettingtime
    self.addon_time = 0
    self.addon_count = 0
    self.score = 0
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
    self.profit = 0 -- 当前局纯收益
    self.passcnt = 0
end

-- 玩家坐下
function Seat:sit(uid, init_money, autobuy, totalbuyin)
    if self.uid ~= nil then
        return false
    end

    self:reset()
    self.uid = uid -- 坐下的玩家ID

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
    -- self.intots = global.ctsec()
    self.room_delta = 0
    return true
end

-- 获取牌索引值  若打出的牌值为0x0000 ?
function Seat:getIdxByCardValue(card)
    for k, v in ipairs(self.handcards) do
        if (v > 0) and ((card & 0xFFFF) == (v & 0xFFFF)) then
            return k
        end
    end
    return 0
end

-- 判断手上是否有空牌  点数为0
function Seat:isEmptyCard()
    for _, v in ipairs(self.handcards) do
        if v ~= 0 then
            return false
        end
    end
    return true
end

function Seat:getLeftPoint()
    local sum = 0
    for _, v in ipairs(self.handcards) do
        sum = sum + self.table.poker:getPointSum(v)
    end
    return sum
end

-- 查找可出的牌
function Seat:findDiscardCard()
    for k, v in ipairs(self.handcards) do -- 遍历手上的牌
        if v > 0 then
            local jointype = self.table.poker:checkJoinable(v)
            if jointype > 0 then
                if jointype == 1 then
                    return -v -- 可出在左边
                elseif jointype == 2 then
                    return v -- 可出在右边
                else
                    return v -- 默认出右边
                end
            end
        end
    end
    return 0
end

function Seat:totalBuyin()
    return self.totalbuyin
end

-- 设置买入状态 
-- 参数 state: 买入状态  ture-正在买入  false-买入结束 
function Seat:setIsBuyining(state)
    self.isbuyining = state
    if self.isbuyining then
        self.buyin_start_time = global.ctsec()
    end
end

function Seat:getIsBuyining()
    return self.isbuyining
end

-- 参数 money: 本次买入金额 
function Seat:buyin(money)
    self.totalbuyin = self.totalbuyin + money
    self.currentbuyin = self.currentbuyin + money
end

-- 将当前买入金额换成筹码 
function Seat:buyinToChips()
    self.chips = self.chips + self.currentbuyin
    self.last_chips = self.chips
    self.currentbuyin = 0
end

-- 判断是否有买入(还未转换为筹码)
function Seat:hasBuyin()
    return self.currentbuyin > 0
end

function Seat:setPreOP(preop)
    self.preop = preop
end

function Seat:getPreOP()
    return self.preop
end

-- 玩家起立
function Seat:stand(uid)
    if self.uid == nil then
        return false
    end

    self.uid = nil -- 起立之后，将玩家ID设置为空
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

    return true
end

-- 重置座位
function Seat:reset()
    self.handtype = 0
    self.handcards = {}
    -- self.handcards = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0} -- 手牌
    self.drawcard = 0 --摸上来的牌
    self.money = 0
    self.roundmoney = 0
    self.chipinnum = 0
    self.chiptype = pb.enum_id("network.cmd.PBDominoChipinType", "PBDominoChipinType_NULL")
    self.lastchiptype = self.chiptype
    self.isplaying = false
    self.bettingtime = 0 -- 下注阶段开始时刻
    self.show = false
    self.last_chips = self.chips
    self.total_time = self.table.bettingtime
    self.score = 0
    self.is_drawcard = false
    self.bet_timeout_count = 0
    self.profit = 0 -- 当前局纯收益
    self.passcnt = 0
end

-- 出一张牌
-- 参数 type: 出牌或过牌
-- 参数 value: 待出的牌(可以为负数)
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
    if not self.isplaying then --玩家未参与游戏
        return
    end
    self.chiptype = type --本次做出什么操作 (过牌、出牌)
    self.chipinnum = value -- 牌值
    self.addon_time = 0
    self.total_time = self.table.bettingtime

    self.lastchiptype = self.chiptype -- 上一轮是何动作(出牌或过牌)
    self.table.lastchipintype = self.chiptype
    self.table.lastchipinpos = self.sid
end

function Seat:getChipinTotalTime()
    return self.total_time
end

-- 判断出牌是否超时
function Seat:isChipinTimeout()
    local elapse = global.ctsec() - self.bettingtime -- 从准备出牌到现在经过时长
    if elapse >= self.table.bettingtime + self.addon_time - 1 then --
        return true
    else
        return false
    end
end

--
function Seat:getChipinLeftTime()
    local now = global.ctsec() --
    local elapse = now - self.bettingtime -- 出牌经过时长 = 当前时刻 - 该座位出牌开始时刻
    if elapse > self.table.bettingtime + self.addon_time then
        return 0
    else
        return (self.table.bettingtime + self.addon_time) - elapse
    end
end
