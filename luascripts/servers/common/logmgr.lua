local cjson = require("cjson")
local redis = require(CLIBS["c_hiredis"])

LogMgr = LogMgr or {}

-- 创建日志管理器
function LogMgr:new(limit, filename)
    local o = {
        limit = limit, -- 限制条数
        logs = {}
    }
    setmetatable(o, self)
    self.__index = self

    if filename then -- 如果文件名存在
        o.filename = tostring(filename) -- 文件名
        local val = redis.get(5001, o.filename)
        if val then
            val = cjson.decode(val) -- 解码
            if val then
                o.logs = val -- 保存日志数据
            end
        end
    end

    return o
end

-- 存放日志
function LogMgr:push(log)
    table.insert(self.logs, log) -- 插入新记录到最后
    while #self.logs > self.limit do -- 如果超出日志条数限制，则移除最前面的
        table.remove(self.logs, 1) -- 移除最前面的一条记录
    end
    if self.filename then
        redis.set(5001, self.filename, cjson.encode(self.logs), true) -- 保存日志数据到redis中
    end
end

-- 获取最后的日志(最新的日志)
function LogMgr:back()
    return self.logs[#self.logs]
end

-- 获取日志列表
function LogMgr:getLogs()
    return self.logs
end

-- 获取日志条数
function LogMgr:size()
    return #self.logs
end
