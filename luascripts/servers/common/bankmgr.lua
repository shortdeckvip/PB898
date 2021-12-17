local log = require(CLIBS["c_log"])

BankMgr = BankMgr or {}

local BANK_ADDTO_FAIL_REASON = {
    BANK_ADDTO_FAIL_REASON_SUCCESS = 0,
    BANK_ADDTO_FAIL_REASON_LISTSIZE = 1,
    BANK_ADDTO_FAIL_REASON_MONEYCNT = 2,
    BANK_ADDTO_FAIL_REASON_HASONBANKList = 3,
    BANK_ADDTO_FAIL_REASON_HASONBANK = 4,
}

function BankMgr:new(o)
    o = o or {mgr = {}, current = {uid = 0, successive = 0, goingdown = true},}
    setmetatable(o, {__index = self})
	return o
end

-- 申请上庄
function BankMgr:add(uid)
    -- make sure unique
    for _,v in ipairs(self.mgr) do
        if v == uid then
            return BANK_ADDTO_FAIL_REASON.BANK_ADDTO_FAIL_REASON_HASONBANKList
        end
    end

    if self.current and self.current.uid == uid then
        return BANK_ADDTO_FAIL_REASON.BANK_ADDTO_FAIL_REASON_HASONBANK
    end

    table.insert(self.mgr, uid)
    log.info("===========add %s", uid)
    return BANK_ADDTO_FAIL_REASON.BANK_ADDTO_FAIL_REASON_SUCCESS
end

-- 取消申请
function BankMgr:remove(uid)
    for k,v in ipairs(self.mgr) do
        if v == uid then
            table.remove(self.mgr, k)
            log.info("===========remove %s", uid)
            return true
        end
    end
    return false
end

-- 上庄
function BankMgr:pop()
    self.current = {uid = 0, successive = 0, goingdown = true,}
    if #self.mgr > 0 then
        self.current.uid = table.remove(self.mgr, 1)
        log.info("===========pop %s", self.current.uid)
        self.current.goingdown = false
    end
    return self.current
end

-- 下庄
function BankMgr:down(uid)
    if self.current and self.current.uid == uid then
        self.current.goingdown = true
        return true
    end
    return false
end

-- 庄家
function BankMgr:banker()
    return self.current.uid
end

-- 申请人数
function BankMgr:count()
    return #self.mgr
end

-- 连庄次数
function BankMgr:successiveCnt()
    return self.current.successive + 1
end

-- 连庄+1
function BankMgr:successive()
    self.current.successive = self.current.successive + 1
    return self.current.successive
end

-- 换庄检查
-- max_cnt连庄最大次数
function BankMgr:checkSwitch(max_cnt, isonline, ismoneyok)
    if not max_cnt then return nil end
    self:successive()
    log.info("===========successive %s %s %s %s", self:successiveCnt(), max_cnt, tostring(isonline), tostring(ismoneyok))
    if self.current.successive >= max_cnt or (not isonline) or (not ismoneyok) then
        self.current.goingdown = true
    end
    if self.current.goingdown then
        return self:pop()
    end
    return nil
end

-- 申请上庄列表
function BankMgr:getBankList()
    local res = {}
    for _,v in ipairs(self.mgr) do
        table.insert(res, v)
    end
    return res
end

-- 庄位是否将要下庄
function BankMgr:isGoingDown()
    return self.current.goingdown
end