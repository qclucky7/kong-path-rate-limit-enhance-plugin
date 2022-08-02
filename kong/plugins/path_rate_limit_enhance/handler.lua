local BasePlugin    = require "kong.plugins.base_plugin"
local LimitSelector = require "kong.plugins.path_rate_limit_enhance.policies.rate_limiter_selector"
local Router        = require "kong.plugins.path_rate_limit_enhance.route.router_api"
local RouterTree    = require "kong.plugins.path_rate_limit_enhance.route.trie_tree"
local Tools         = require "kong.plugins.path_rate_limit_enhance.tools"

local path_rate_limit_enhance = BasePlugin:extend()

local ngx               = ngx
local kong              = kong
local pairs             = pairs
local toString          = tostring
local pcall             = pcall

path_rate_limit_enhance.VERSION  = "1.0.0"
path_rate_limit_enhance.PRIORITY = 1500

local EMPTY = {}

local function load_service_rate_limit_path_config(key)
    local rate_limit_path_config, err = kong.db.rate_limit_path_config:select_by_cache_key(key)
    if not rate_limit_path_config then
        return nil, err
    end
    return rate_limit_path_config
end

function path_rate_limit_enhance:access(plugin_conf)

    local kong_route = kong.router.get_route()

    local router_id = (kong_route or EMPTY).id
    if not router_id then
        kong.log.err("[path_rate_limit_enhance] router not found")
        return
    end

    local service_id = (kong_route.service or EMPTY).id
    if not service_id then
        kong.log.err("[path_rate_limit_enhance] service not found")
        return
    end

    local path = kong.request.get_path()
    if not path then
        kong.log.err("[path_rate_limit_enhance] path not found")
        return
    end

    local route_paths = (kong_route or EMPTY).paths

    if not route_paths then
        kong.log.err("[path_rate_limit_enhance] route_paths is empty!")
        return
    end

    for _, path_prefix in pairs(route_paths) do
        local match, sub_path = Tools.start_with_and_sub(path, path_prefix)
        if match then
            path = sub_path
        end
    end


    local method = kong.request.get_method()

    local tenant_id = "default"
    local tenant_id_header = plugin_conf.tenant_id_header
    if tenant_id_header then
        local request_tenant_id = kong.request.get_header(tenant_id_header)
        if request_tenant_id then
            tenant_id = request_tenant_id
        end
    end

    local success, route = pcall(function() return Router:new() end)

    if not success or not route then
        kong.log.err("[path_rate_limit_enhance] shared dict routeTree not found " .. toString(route))
        return
    end

    local route_tree, err = route:fetch(route:buildKey(router_id, tenant_id))
    if not route_tree then
        kong.log("[path_rate_limit_enhance] route_tree not found router_id: " .. router_id .. "tenant_id: " .. tenant_id)
        if err then
            kong.log("[path_rate_limit_enhance] route_tree not found router_id: " .. router_id .. "tenant_id:" .. tenant_id .."error: " .. toString(err))
        end
        return
    end

    local _, match_path, _, hit = RouterTree:replace(route_tree):match(path, method)

    kong.log("[path_rate_limit_enhance] router match result ->  path :" .. path .. " method: " .. method .. " match_path: " .. (match_path and {match_path} or {''})[1] .. " hit: " .. toString(hit))

    if not hit then
        return
    end

    local cache = kong.cache

    local limit_rate_path_config_cache_key = kong.db.rate_limit_path_config:cache_key(tenant_id, router_id, service_id, match_path, method)
    local path_config, err = cache:get(limit_rate_path_config_cache_key, nil, load_service_rate_limit_path_config,
            limit_rate_path_config_cache_key)

    if err then
        kong.log.err("[path_rate_limit_enhance] service select redis config error:" .. err)
        return
    end
    if not path_config then
        kong.log("[path_rate_limit_enhance] service path_config not found service:" .. service_id .. " path:" .. path)
        return
    end

    local ngx_time = ngx.time()
    local result, err = LimitSelector[plugin_conf.algorithm].allowed(plugin_conf, path_config, ngx_time)
    if err then
        kong.log("[path_rate_limit_enhance] service rate_limit_selector error:" .. err)
        return
    end

    kong.log("[path_rate_limit_enhance] result : " .. result .. "time: " .. ngx_time)

    -- no tokens
    if result == 0 then
        ngx.header["Content-Type"] = "application/json; charset=utf-8"
        ngx.status = plugin_conf.response.code
        ngx.say(plugin_conf.response.message)
        return
    end

end

return path_rate_limit_enhance