local XML = require(CLIBS["c_xml"])
local global = require(CLIBS["c_global"])
local g = require("luascripts/common/g")
local cjson = require("cjson")
local log = require(CLIBS["c_log"])

--load serverlist.xml
SERVERLIST_CONF = {}
local function loadServerListXml()
    local doc = XML.createdoc()
    if XML.load(doc, "Config/Server/serverlist.xml") then
        local root = XML.rootelement(doc, "SERVER")
        local game = XML.firstchild(root, "other")
        while game do
            local tb = XML.firstchild(game, "srv")
            while tb do
                SERVERLIST_CONF[XML.intattribute(tb, "id")] = XML.attribute(tb, "addr")
                local oldtb = tb
                tb = XML.nextsibling(tb)
                XML.destroyelement(oldtb)
            end
            local oldgame = game
            game = XML.nextsibling(game)
            XML.destroyelement(oldgame)
        end
    end
    XML.destroydoc(doc)
end
loadServerListXml()

-- load control.xml
CONTROL_CONF = {}
local function loadControlXml()
    local doc = XML.createdoc()
    if XML.load(doc, "Config/Game/control.xml") then
        local root = XML.rootelement(doc, "CONTROL")
        local game = XML.firstchild(root, "info")
        while game do
            CONTROL_CONF.control_type = XML.attribute(game, "control_type")
            local oldgame = game
            game = XML.nextsibling(game)
            XML.destroyelement(oldgame)
        end
    end
    XML.destroydoc(doc)
end
loadControlXml()
log.info("load control.xml: %s", cjson.encode(CONTROL_CONF))

--load robotai.xml
ROBOTAI_CONF = {}
local function loadRobotAiXml()
    local doc = XML.createdoc()
    if XML.load(doc, "Config/Game/robotai.xml") then
        local root = XML.rootelement(doc, "ROBOT")
        local tb = XML.firstchild(root, "ai")
        while tb do
            if XML.attribute(tb, "id") then
                ROBOTAI_CONF[XML.intattribute(tb, "id")] = {
                    id = XML.intattribute(tb, "id"),
                    name = XML.attribute(tb, "name"),
                    firerate = XML.intattribute(tb, "fire-rate"),
                    mincarry = XML.intattribute(tb, "min-carry"),
                    maxcarry = XML.intattribute(tb, "max-carry"),
                    carrymultiple = XML.intattribute(tb, "carry-multiple")
                }

            --local gameid = XML.intattribute(tb, "gameid")
            --if gameid == 33 and ROBOTAI_CONF[XML.intattribute(tb, "id")].firerate < 3000 then
            --    ROBOTAI_CONF[XML.intattribute(tb, "id")].firerate = 3000
            --elseif gameid ~= 33 and ROBOTAI_CONF[XML.intattribute(tb, "id")].firerate < 5000 then
            --    ROBOTAI_CONF[XML.intattribute(tb, "id")].firerate = 5000
            --end
            end
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end
    end
    XML.destroydoc(doc)
end
loadRobotAiXml()
--log.info("load robotai.xml: %s", cjson.encode(ROBOTAI_CONF))

--load jp.xml
JACKPOT_CONF = {}
local function loadJackpotXml()
    local doc = XML.createdoc()
    if XML.load(doc, "Config/Game/jp.xml") then
        local root = XML.rootelement(doc, "XGAME")
        local tb = XML.firstchild(root, "table")
        while tb do
            table.insert(
                JACKPOT_CONF,
                {
                    id = XML.intattribute(tb, "id"),
                    roomtype = XML.intattribute(tb, "roomtype"),
                    name = XML.attribute(tb, "name"),
                    initmoney = XML.intattribute(tb, "initmoney"),
                    deltabb = XML.doubleattribute(tb, "deltabb"),
                    profitbb = XML.intattribute(tb, "profitbb"),
                    percent = {
                        [1] = XML.doubleattribute(tb, "fourkind"),
                        [2] = XML.doubleattribute(tb, "straightflush"),
                        [3] = XML.doubleattribute(tb, "royalflush")
                    }
                }
            )
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end
    end
    XML.destroydoc(doc)
end
loadJackpotXml()
log.info("load jp.xml: %s", cjson.encode(JACKPOT_CONF))

--load tablelist.xml
TABLECONF = {}
local function loadTableListXml()
    local doc = XML.createdoc()
    if XML.load(doc, "Config/Game/tablelist.xml") then
        local root = XML.rootelement(doc, "TLIST")
        local game = XML.firstchild(root, "game")
        while game do
            if XML.intattribute(game, "gameid") == global.stype() then  -- 获取游戏ID，并与当前游戏ID比较
                local tb = XML.firstchild(game, "table")  
                while tb do
                    table.insert(
                        TABLECONF,
                        {
                            mid = XML.intattribute(tb, "matchid"),
                            name = XML.attribute(tb, "name"),
                            zhname = XML.attribute(tb, "zhname"),
                            gameid = XML.intattribute(game, "gameid"),
                            serverid = XML.intattribute(game, "serverid"),
                            mintable = XML.intattribute(tb, "mintable"),
                            maxtable = XML.intattribute(tb, "maxtable"),
                            tag = XML.intattribute(tb, "tag"),  -- (房间等级标志：1-低级场 2-中级场 3-高级场)
                            sb = XML.intattribute(tb, "sb"),
                            ante = XML.intattribute(tb, "ante"),
                            minchip = XML.intattribute(tb, "minchips"),
                            fee = XML.doubleattribute(tb, "fee"),
                            toolcost = math.floor(0.1 * 2 * XML.intattribute(tb, "sb")), --XML.intattribute(tb, 'toolcost'),
                            addtime = XML.intattribute(tb, "addtime"),
                            --addtimecost       = g.at2it(g.split(XML.attribute(tb, 'addtimecost'), ';')),
                            maxuser = XML.intattribute(tb, "maxuser"),   -- 每桌最大玩家数
                            referrerbb = XML.intattribute(tb, "referrerbb"),
                            minbuyinbb = XML.intattribute(tb, "minbuyinbb"),
                            maxbuyinbb = XML.intattribute(tb, "maxbuyinbb"),
                            bettime = XML.intattribute(tb, "bettime"),
                            roomtype = XML.intattribute(tb, "roomtype"),
                            matchtype = XML.intattribute(tb, "matchtype"),
                            buyin = XML.intattribute(tb, "buyin"),
                            buyintime = XML.intattribute(tb, "buyintime"),
                            peekwinnerhandcardcost = math.floor(2 * 2 * XML.intattribute(tb, "sb")), --XML.intattribute(tb, 'peekwinnerhandcardcost'),
                            peekwinnerhandcardearn = XML.doubleattribute(tb, "peekwinnerhandcardearn"),
                            peekpubcardcost = math.floor(0.2 * 2 * XML.intattribute(tb, "sb")), --=XML.intattribute(tb, 'peekpubcardcost'),
                            jpid = XML.intattribute(tb, "jpid") or 0,
                            minipotrate = XML.intattribute(tb, "minipotrate"),
                            rebate = XML.doubleattribute(tb, "rebate"),
                            feerate = XML.doubleattribute(tb, "feerate"),
                            feehandupper = XML.intattribute(tb, "feehandupper") < 0 and 0xFFFFFFFFFF or
                                XML.intattribute(tb, "feehandupper"),
                            checkip = XML.intattribute(tb, "checkip"),
                            maxinto = XML.intattribute(tb, "maxinto") <= 0 and 0xFFFFFFFFFF or
                                XML.intattribute(tb, "maxinto"),
                            special = XML.intattribute(tb, "special") or 0  -- 新手专场
                        }
                    )
                    assert(TABLECONF[#TABLECONF].sb >= TABLECONF[#TABLECONF].minchip)
                    local sb = TABLECONF[#TABLECONF].sb
                    TABLECONF[#TABLECONF].addtimecost = {
                        math.floor(0.5 * 2 * sb),
                        math.floor(1 * 2 * sb),
                        math.floor(1.5 * 2 * sb)
                    }
                    local jp = JACKPOT_CONF[TABLECONF[#TABLECONF].jpid]
                    if jp and jp.roomtype ~= TABLECONF[#TABLECONF].roomtype then
                        assert(false, "jpid is invalid in tablelist.xml, please check!!")
                    end
                    if XML.attribute(tb, "robotid") then
                        TABLECONF[#TABLECONF].robotid = XML.intattribute(tb, "robotid")
                    end
                    if XML.attribute(tb, "bigcardsrate") then
                        TABLECONF[#TABLECONF].bigcardsrate = XML.intattribute(tb, "bigcardsrate") -- 发大牌比例 [1,10000]
                    end
                    if XML.attribute(tb, "single_profit_switch") then
                        TABLECONF[#TABLECONF].single_profit_switch = true
                    end
                    if CONTROL_CONF and CONTROL_CONF.control_type then
                        log.debug("CONTROL_CONF.control_type=%s", CONTROL_CONF.control_type)
                        if tonumber(CONTROL_CONF.control_type) == 1 then -- 单人控制
                            TABLECONF[#TABLECONF].single_profit_switch = true
                            TABLECONF[#TABLECONF].global_profit_switch = false
                        elseif tonumber(CONTROL_CONF.control_type) == 2 then -- 全局控制
                            TABLECONF[#TABLECONF].single_profit_switch = false
                            TABLECONF[#TABLECONF].global_profit_switch = true
                        end
                    end

                    TABLECONF[#TABLECONF].fee = math.floor(TABLECONF[#TABLECONF].fee * TABLECONF[#TABLECONF].sb)
                    TABLECONF[#TABLECONF].maxinto = math.floor(TABLECONF[#TABLECONF].maxinto * TABLECONF[#TABLECONF].sb)

                    local oldtb = tb
                    tb = XML.nextsibling(tb)
                    XML.destroyelement(oldtb)
                end
            end
            local oldgame = game
            game = XML.nextsibling(game)
            XML.destroyelement(oldgame)
        end
    end
    XML.destroydoc(doc)
end
loadTableListXml()
log.info("load tablelist.xml:%s", cjson.encode(TABLECONF))

--load minigame servertype.xml
MINIGAME_CONF = {}
local function loadMiniGameXml()
    local doc = XML.createdoc()
    local minigame_conf_file = string.format("Config/Game/%s.xml", global.stype())
    if XML.load(doc, minigame_conf_file) then
        local root = XML.rootelement(doc, "XGAME")
        local tb = XML.firstchild(root, "table")
        while tb do
            local betarea_str = g.split(XML.attribute(tb, "betarea"), ";")
            local betarea = {}
            for _, v in ipairs(betarea_str) do
                table.insert(betarea, g.at2it(g.split(v, "-")))
            end
            local chips = {}
            if XML.attribute(tb, "chips") then
                local chips_str = g.split(XML.attribute(tb, "chips"), ",")
                for _, v in ipairs(chips_str) do
                    table.insert(chips, tonumber(v))
                end
            end
            local carrybound = {}
            if XML.attribute(tb, "carrybound") then
                local carrybound_str = g.split(XML.attribute(tb, "carrybound"), ",")
                for _, v in ipairs(carrybound_str) do
                    table.insert(carrybound, tonumber(v))
                end
            end
            table.insert(MINIGAME_CONF, {})
            if XML.attribute(tb, "id") then
                MINIGAME_CONF[#MINIGAME_CONF].id = XML.intattribute(tb, "id")
            end
            if XML.attribute(tb, "jpid") then
                MINIGAME_CONF[#MINIGAME_CONF].jpid = XML.intattribute(tb, "jpid")
            end
            if XML.attribute(tb, "max_bank_successive_cnt") then
                MINIGAME_CONF[#MINIGAME_CONF].max_bank_successive_cnt = XML.intattribute(tb, "max_bank_successive_cnt")
            end
            if XML.attribute(tb, "addbetmin") then
                MINIGAME_CONF[#MINIGAME_CONF].addbetmin = XML.intattribute(tb, "addbetmin")
            end
            if XML.attribute(tb, "addbetmax") then
                MINIGAME_CONF[#MINIGAME_CONF].addbetmax = XML.intattribute(tb, "addbetmax")
            end
            if #betarea > 0 then
                MINIGAME_CONF[#MINIGAME_CONF].betarea = betarea
            end
            if XML.attribute(tb, "roomtype") then
                MINIGAME_CONF[#MINIGAME_CONF].roomtype = XML.intattribute(tb, "roomtype")
            end
            if XML.attribute(tb, "fee") then
                MINIGAME_CONF[#MINIGAME_CONF].fee = XML.doubleattribute(tb, "fee")
            end
            if XML.attribute(tb, "profitrate_threshold_minilimit") then
                MINIGAME_CONF[#MINIGAME_CONF].profitrate_threshold_minilimit =
                    XML.doubleattribute(tb, "profitrate_threshold_minilimit")
            end
            if XML.attribute(tb, "profitrate_threshold_lowerlimit") then
                MINIGAME_CONF[#MINIGAME_CONF].profitrate_threshold_lowerlimit =
                    XML.doubleattribute(tb, "profitrate_threshold_lowerlimit")
            end
            if XML.attribute(tb, "min_onbank_moneycnt") then
                MINIGAME_CONF[#MINIGAME_CONF].min_onbank_moneycnt = XML.intattribute(tb, "min_onbank_moneycnt")
            end
            if XML.attribute(tb, "min_outbank_moneycnt") then
                MINIGAME_CONF[#MINIGAME_CONF].min_outbank_moneycnt = XML.intattribute(tb, "min_outbank_moneycnt")
            end
            if XML.attribute(tb, "isib") then
                MINIGAME_CONF[#MINIGAME_CONF].isib = true
            end
            if XML.attribute(tb, "global_profit_switch") then
                MINIGAME_CONF[#MINIGAME_CONF].global_profit_switch = true
                MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch = false
            end
            if XML.attribute(tb, "single_profit_switch") then
                MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch = true
                MINIGAME_CONF[#MINIGAME_CONF].global_profit_switch = false
            end
            -- 2022-4-12 暂时注释
            if CONTROL_CONF and CONTROL_CONF.control_type then
                if tonumber(CONTROL_CONF.control_type) == 1 then  -- 单人控制
                    MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch = true
                    MINIGAME_CONF[#MINIGAME_CONF].global_profit_switch = false                    
                elseif tonumber( CONTROL_CONF.control_type) == 2 then
                    MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch = false
                    MINIGAME_CONF[#MINIGAME_CONF].global_profit_switch = true
                else
                    MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch = false
                    MINIGAME_CONF[#MINIGAME_CONF].global_profit_switch = false
                end
                log.debug("load loadMiniGameXml:MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch=%s,global_profit_switch=%s,control_type=%s", tostring(MINIGAME_CONF[#MINIGAME_CONF].single_profit_switch),tostring(MINIGAME_CONF[#MINIGAME_CONF].global_profit_switch), CONTROL_CONF.control_type)
            end

            if XML.attribute(tb, "min_player_num") then
                MINIGAME_CONF[#MINIGAME_CONF].min_player_num = XML.intattribute(tb, "min_player_num")
            end
            if XML.attribute(tb, "max_player_num") then
                MINIGAME_CONF[#MINIGAME_CONF].max_player_num = XML.intattribute(tb, "max_player_num")
            end
            if XML.attribute(tb, "update_interval") then
                MINIGAME_CONF[#MINIGAME_CONF].update_interval = XML.intattribute(tb, "update_interval")
            end
            if XML.attribute(tb, "mintable") then
                MINIGAME_CONF[#MINIGAME_CONF].mintable = XML.intattribute(tb, "mintable")
            end
            if XML.attribute(tb, "rebate") then
                MINIGAME_CONF[#MINIGAME_CONF].rebate = XML.doubleattribute(tb, "rebate")
            end

            if #carrybound > 0 then
                MINIGAME_CONF[#MINIGAME_CONF].carrybound = carrybound
            end
            if #chips > 0 then
                MINIGAME_CONF[#MINIGAME_CONF].chips = chips
            end
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end
    end
    XML.destroydoc(doc)
end

local MINI_GAME_STYPE = {31, 32, 35, 38, 42, 43, 45}
if g.isInTable(MINI_GAME_STYPE, global.stype()) then
    loadMiniGameXml()
    log.info(cjson.encode(MINIGAME_CONF))
end

function CheckMiniGameConfig(conf)
    for _, vv in ipairs(conf) do
        for _, v in ipairs(MINIGAME_CONF) do
            if v.id == vv.mid then
                for k, vvv in pairs(v) do
                    vv[tostring(k)] = vvv
                end
                break
            end
        end
    end
end

-- 2021-11-4
-- load slot game config file  slot.xml
SLOT_CONF = {simple = {}, normal = {}, hard = {}, freeSpin = {}, lineInfo = {}, lineNum = 0, lineCol = 0, lineRow = 0}

local function loadSlotGameXml()
    local doc = XML.createdoc()
    if XML.load(doc, "Config/Game/slot.xml") then
        local root = XML.rootelement(doc, "XGAME")

        local tb = XML.firstchild(root, "Simple") -- 新手级别
        if tb then
            tb = XML.firstchild(tb, "elem")
        end
        while tb do
            table.insert(
                SLOT_CONF.simple,
                {
                    id = XML.intattribute(tb, "id"),
                    name = XML.attribute(tb, "name"),
                    first = XML.intattribute(tb, "first"),
                    second = XML.intattribute(tb, "second"),
                    third = XML.intattribute(tb, "third"),
                    fourth = XML.intattribute(tb, "fourth"),
                    fifth = XML.intattribute(tb, "fifth"),
                    times2 = XML.intattribute(tb, "times2"),
                    times3 = XML.intattribute(tb, "times3"),
                    times4 = XML.intattribute(tb, "times4"),
                    times5 = XML.intattribute(tb, "times5")
                }
            )
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end

        tb = XML.firstchild(root, "Normal") -- 正常级别
        if tb then
            tb = XML.firstchild(tb, "elem")
        end
        while tb do
            table.insert(
                SLOT_CONF.normal,
                {
                    id = XML.intattribute(tb, "id"),
                    name = XML.attribute(tb, "name"),
                    first = XML.intattribute(tb, "first"),
                    second = XML.intattribute(tb, "second"),
                    third = XML.intattribute(tb, "third"),
                    fourth = XML.intattribute(tb, "fourth"),
                    fifth = XML.intattribute(tb, "fifth"),
                    times2 = XML.intattribute(tb, "times2"),
                    times3 = XML.intattribute(tb, "times3"),
                    times4 = XML.intattribute(tb, "times4"),
                    times5 = XML.intattribute(tb, "times5")
                }
            )
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end

        tb = XML.firstchild(root, "Hard") -- 困难级别
        if tb then
            tb = XML.firstchild(tb, "elem")
        end
        while tb do
            table.insert(
                SLOT_CONF.hard,
                {
                    id = XML.intattribute(tb, "id"),
                    name = XML.attribute(tb, "name"),
                    first = XML.intattribute(tb, "first"),
                    second = XML.intattribute(tb, "second"),
                    third = XML.intattribute(tb, "third"),
                    fourth = XML.intattribute(tb, "fourth"),
                    fifth = XML.intattribute(tb, "fifth"),
                    times2 = XML.intattribute(tb, "times2"),
                    times3 = XML.intattribute(tb, "times3"),
                    times4 = XML.intattribute(tb, "times4"),
                    times5 = XML.intattribute(tb, "times5")
                }
            )
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end

        tb = XML.firstchild(root, "FreeSpin") -- 免费旋转
        if tb then
            tb = XML.firstchild(tb, "elem")
        end
        while tb do
            table.insert(
                SLOT_CONF.freeSpin,
                {
                    id = XML.intattribute(tb, "id"),
                    name = XML.attribute(tb, "name"),
                    first = XML.intattribute(tb, "first"),
                    second = XML.intattribute(tb, "second"),
                    third = XML.intattribute(tb, "third"),
                    fourth = XML.intattribute(tb, "fourth"),
                    fifth = XML.intattribute(tb, "fifth"),
                    times2 = XML.intattribute(tb, "times2"),
                    times3 = XML.intattribute(tb, "times3"),
                    times4 = XML.intattribute(tb, "times4"),
                    times5 = XML.intattribute(tb, "times5")
                }
            )
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end

        tb = XML.firstchild(root, "LineInfo") -- 线条信息
        if tb then
            tb = XML.firstchild(tb, "elem")
        end
        while tb do
            local i = 1
            local lineData = {id = 0, name = XML.attribute(tb, "name"), col = {}}
            lineData.id = XML.intattribute(tb, "id")
            if lineData.id > SLOT_CONF.lineNum then
                SLOT_CONF.lineNum = lineData.id -- 线条总数
            end

            lineData.col[1] = XML.intattribute(tb, "col1")
            if lineData.col[1] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[1]
            end
            lineData.col[2] = XML.intattribute(tb, "col2")
            if lineData.col[2] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[2]
            end
            lineData.col[3] = XML.intattribute(tb, "col3")
            if lineData.col[3] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[3]
            end
            lineData.col[4] = XML.intattribute(tb, "col4")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[4] then
                SLOT_CONF.lineCol = 3 -- 线条列数
            end
            if lineData.col[4] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[4]
            end
            lineData.col[5] = XML.intattribute(tb, "col5")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[5] then
                SLOT_CONF.lineCol = 4
            end
            if lineData.col[5] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[5]
            end
            lineData.col[6] = XML.intattribute(tb, "col6")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[6] then
                SLOT_CONF.lineCol = 5
            end
            if lineData.col[6] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[6]
            end
            lineData.col[7] = XML.intattribute(tb, "col7")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[7] then
                SLOT_CONF.lineCol = 6
            end
            if lineData.col[7] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[7]
            end
            lineData.col[8] = XML.intattribute(tb, "col8")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[8] then
                SLOT_CONF.lineCol = 7
            end
            if lineData.col[8] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[8]
            end
            lineData.col[9] = XML.intattribute(tb, "col9")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[9] then
                SLOT_CONF.lineCol = 8
            end
            if lineData.col[9] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[9]
            end
            lineData.col[10] = XML.intattribute(tb, "col10")
            if 0 == SLOT_CONF.lineCol and 0 == lineData.col[10] then
                SLOT_CONF.lineCol = 9
            end
            if lineData.col[10] > SLOT_CONF.lineRow then
                SLOT_CONF.lineRow = lineData.col[10]
            end
            if 0 == SLOT_CONF.lineCol then
                SLOT_CONF.lineCol = 10 -- 最大10列
            end

            table.insert(SLOT_CONF.lineInfo, lineData)
            local oldtb = tb
            tb = XML.nextsibling(tb)
            XML.destroyelement(oldtb)
        end
    end
    XML.destroydoc(doc)
end
loadSlotGameXml()
log.info("load slot.xml: %s", cjson.encode(SLOT_CONF))
