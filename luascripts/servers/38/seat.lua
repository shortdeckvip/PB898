-- serverdev\luascripts\servers\38\seat.lua

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
    self.table = t -- 桌子对象(房间对象)
    self.sid = sid -- 座位ID
    self.uid = nil -- 坐在该位置的玩家ID
    self.isplaying = false -- 是否在玩状态

    self.handcards = {} -- 手牌 初始化时为2张牌
    self.cardtype = 0 -- 手牌类型

    self.chips = 0 -- 剩余筹码数
    self.last_chips = 0 -- 剩余筹码数
    self.roundmoney = 0 -- 一轮下注筹码值
    self.money = 0 -- 一局总消耗筹码数
    self.chipinnum = 0 -- 上一轮下注筹码值
    self.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_NULL") -- 下注操作类型
    self.lastchiptype = self.chiptype
    self.bettingtime = 0 -- 下注时刻
    self.show = false -- 是否需要亮牌


    self.score = 0

    self.gamecount = 0  --局数 

    self.autobuy = 0 -- 普通场玩法自动买入
    self.buyinToMoney = 0 -- 普通场玩法自动买入多少钱
    self.totalbuyin = 0 --总共买入
    self.currentbuyin = 0 --非 0：此次已买入但未加到筹码 0：没有买入要换成筹码
    self.isbuyining = false --正在买入
    self.autoBuyinToMoney = 0 --普通场勾选了自动买入后手动补币数

    self.room_delta = 0
    self.thirdCardOperate = 0 -- 补牌操作(0:未操作  1：double  2:补牌  3:不补牌)
    self.profit = 0
end

-- 玩家坐下
function Seat:sit(uid, init_money, autobuy, totalbuyin, isplaying)
    if self.uid ~= nil then
        log.info("dfr 8 uid=%s, self.uid=%s", uid, self.uid)
        return false
    end

    self:reset()
    self.uid = uid -- 坐下的玩家ID
    if uid == 0 then
        self.isplaying = true
    else
        self.isplaying = isplaying or self.isplaying
    end

    self.chips = init_money
    self.last_chips = self.chips
    self.autobuy = autobuy
    self.buyinToMoney = init_money
    self.totalbuyin = totalbuyin
    self.currentbuyin = 0

    self.gamecount = 0

    self.intots = global.ctsec()
    self.room_delta = 0
    self.tostandup = false
    return true
end

function Seat:totalBuyin()
    return self.totalbuyin
end

function Seat:setIsBuyining(state)
    self.isbuyining = state
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

    self.room_delta = 0 -- 纯收益，初始时为0
    self.tostandup = false

    return true
end

-- 重置座位
function Seat:reset()
    self.cardtype = 0 -- 手牌类型
    self.handcards = {} -- 手牌数据

    self.money = 0
    self.roundmoney = 0
    self.chipinnum = 0
    self.chiptype = pb.enum_id("network.cmd.PBPokDengChipinType", "PBPokDengChipinType_NULL")
    self.lastchiptype = self.chiptype
    self.isplaying = false
    self.bettingtime = 0 -- 下注阶段开始时刻
    self.show = false
    self.last_chips = self.chips

    self.score = 0
    self.thirdCardOperate = 0 --补牌操作值(1:double  2:补牌  3:不补牌)
    self.profit = 0
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


    self.lastchiptype = self.chiptype -- 上一轮是何动作(出牌或过牌)
    self.table.lastchipintype = self.chiptype
    self.table.lastchipinpos = self.sid
end
