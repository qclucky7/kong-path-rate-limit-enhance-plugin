-- spring-cloud-gateway限流lua脚本
-- https://github.com/spring-cloud/spring-cloud-gateway/blob/e61028a8b79f66a3a907b8f199454f49a10fea80/spring-cloud-gateway-core/src/main/resources/META-INF/scripts/request_rate_limiter.lua

--[[
    tokens_key 限流key
    rate 令牌桶填充频率
    capacity 令牌桶容量
]]

-- 当前限流key
local tokens_key = KEYS[1]
-- 当前限流key对应的时间戳key。
local timestamp_key = KEYS[2]
-- 填充频率
local rate = tonumber(ARGV[1])
-- 桶容量
local capacity = tonumber(ARGV[2])
-- 当前时间戳。
local now = tonumber(ARGV[3])
-- 一次请求数量消耗令牌数量 固定为1。
local requested = tonumber(ARGV[4])
-- 计算多少单位时间填充一个令牌。
local fill_time = capacity / rate
-- redis key 过期时间。清理低频访问限流key。
-- 这里面把限流key过期时间都延长下。
local ttl = math.floor(fill_time * 60)

--redis.log(redis.LOG_WARNING, "rate " .. ARGV[1])
--redis.log(redis.LOG_WARNING, "capacity " .. ARGV[2])
--redis.log(redis.LOG_WARNING, "now " .. ARGV[3])
--redis.log(redis.LOG_WARNING, "requested " .. ARGV[4])
--redis.log(redis.LOG_WARNING, "fill_time " .. fill_time)
--redis.log(redis.LOG_WARNING, "ttl " .. ttl)

-- 限流key初始化
local last_tokens = tonumber(redis.call("get", tokens_key))
if last_tokens == nil then
    last_tokens = capacity
end
--redis.log(redis.LOG_WARNING, "last_tokens " .. last_tokens)

-- 限流key时间戳key初始化
local last_refreshed = tonumber(redis.call("get", timestamp_key))
if last_refreshed == nil then
    last_refreshed = 0
end
--redis.log(redis.LOG_WARNING, "last_refreshed " .. last_refreshed)

-- 获取当前访问距上一次最后一次访问时间间隔
local delta = math.max(0, now - last_refreshed)

-- 获取桶中的令牌数量。 第一次访问初始化最小容量。 当令牌数越来越小。
local filled_tokens = math.min(capacity, last_tokens + (delta * rate))

-- 比较桶中令牌数量和当前请求的令牌数量。
local allowed = filled_tokens >= requested

--[[

        把桶中令牌数量再次赋值给限流key桶数量。 这里面如果限流了new_tokens就是减去请求消耗的令牌数。
        不断填充的令牌数量这段代码 比如1秒填充1个, 当当前访问时间减去最后一次访问时间等于一秒的时候, 才能允许访问, 因为在一秒以内填充令牌数量不够。
        如果一直没有请求。当第一次请求的时候, 访问时间减去最后一次访问时间, 远远大于一秒, 则不断在填充桶, 直到大于等于桶容量
        核心: 访问减去桶令牌数量
                new_tokens = filled_tokens - requested
             按时间去填充令牌数量
                local delta = math.max(0, now - last_refreshed)
                local filled_tokens = math.min(capacity, last_tokens + ( delta * rate))
--]]

local new_tokens = filled_tokens

-- 0为桶中无令牌了, 被限流
local allowed_num = 0

-- 允许访问 用桶中剩余令牌减去当前请求消耗的令牌数
if allowed then
    new_tokens = filled_tokens - requested
    allowed_num = 1
end

--redis.log(redis.LOG_WARNING, "delta " .. delta)
--redis.log(redis.LOG_WARNING, "filled_tokens " .. filled_tokens)
--redis.log(redis.LOG_WARNING, "allowed_num " .. allowed_num)
--redis.log(redis.LOG_WARNING, "new_tokens " .. new_tokens)

if ttl > 0 then
    -- 填充限流key桶剩余令牌
    redis.call("setex", tokens_key, ttl, new_tokens)
    -- 填充限流key时间戳key桶最后一次访问时间
    redis.call("setex", timestamp_key, ttl, now)
end

-- return { allowed_num, new_tokens, capacity, filled_tokens, requested, new_tokens }
return allowed_num
