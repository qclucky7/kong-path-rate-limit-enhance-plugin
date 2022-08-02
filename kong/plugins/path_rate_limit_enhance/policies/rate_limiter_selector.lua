local Script = require "kong.plugins.path_rate_limit_enhance.policies.script"
local Redis  = require "resty.redis"
local Utils  = require "kong.plugins.path_rate_limit_enhance.tools"

local kong = kong

local function build_hit_key(tenant_id, route_id, service_id, path, method)
    local hit_key = "path_rate_limit_enhance:" .. tenant_id .. ":" .. service_id .. ":" .. route_id .. ":" .. method .. ":" .. path
    local hit_key_timestamp = hit_key .. ":" .. "_timestamp"
    return hit_key, hit_key_timestamp
end


local function get_connection(plugin_config)

    local red = Redis:new()
    red:set_timeout(plugin_config.timeout)

    local ok, err = red:connect(plugin_config.host, plugin_config.port)
    if not ok then
        kong.log.err("[path_rate_limit_enhance] failed to connect to Redis: " .. err)
        return nil, err
    end

    local times, err = red:get_reused_times()
    if err then
        kong.log.err("[path_rate_limit_enhance] failed to get connect reused times: " .. err)
        return nil, err
    end

    if times == 0 then
        if Utils:is_not_empty(plugin_config.password) then
            local ok, err
            if Utils:is_not_empty(plugin_config.username) then
                ok, err = red:auth(plugin_config.username, plugin_config.password)
            else
                ok, err = red:auth(plugin_config.password)
            end
            if not ok then
                kong.log.err("[path_rate_limit_enhance] failed to auth Redis: " .. err)
                return nil, err
            end
        end
        if plugin_config.database ~= 0 then
            local ok, err = red:select(plugin_config.database)
            if not ok then
                kong.log.err("[path_rate_limit_enhance] failed to change Redis database: " .. err)
                return nil, err
            end
        end
    end
    return red
end

return {
    ["token_buckets"] = {
        allowed = function(plugin_config, rate_limit_path_config, timestamp)
            local red, err = get_connection(plugin_config)
            if not red then
                if err then
                    kong.log.err("[path_rate_limit_enhance] get_connection err: " .. err)
                end
                return 0, err
            end

            local tenant_id = rate_limit_path_config.tenant_id
            local service_id = rate_limit_path_config.service_id
            local route_id = rate_limit_path_config.route_id
            local path = rate_limit_path_config.path
            local method = rate_limit_path_config.method
            local rate = rate_limit_path_config.rate
            local capacity = rate_limit_path_config.capacity

            local hit_key, hit_key_timestamp  = build_hit_key(tenant_id, route_id, service_id, path, method)
            -- 这应该改造把脚本缓存在redis。EVALSHA命令。
            local result, err = red:eval(Script.token_buckets, 2, hit_key, hit_key_timestamp, rate, capacity, timestamp, 1)
            if err then
                kong.log.err("[path_rate_limit_enhance] red:eval err: " .. err)
                return 0, err
            end

            local ok, err = red:set_keepalive(10000, 100)
            if not ok then
                kong.log.err("[path_rate_limit_enhance] failed to set Redis keepalive: " .. err)
            end

            return result[1]
        end
    }

}






