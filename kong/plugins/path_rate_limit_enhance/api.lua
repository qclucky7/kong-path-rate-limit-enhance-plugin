local Json                = require "cjson.safe"
local Utils               = require "kong.plugins.path_rate_limit_enhance.tools"
local Router              = require "kong.plugins.path_rate_limit_enhance.route.router_api"
local RouterTree          = require "kong.plugins.path_rate_limit_enhance.route.trie_tree"
local SQLTemplate         = require "kong.plugins.path_rate_limit_enhance.migrations.sql_template"

local kong              = kong
local services_dao      = kong.db.services
local routes_dao        = kong.db.routes
local path_config_dao   = kong.db.rate_limit_path_config
local pairs             = pairs
local insert            = table.insert
local toString          = tostring
local pcall             = pcall
local setmetatable      = setmetatable
local type              = type
local methods           = {"GET", "POST", "DELETE", "PUT", "OPTIONS", "HEAD", "ANY"}


local PageResult = {}

function PageResult:new()
    return setmetatable({
        results = {},
        num  = 0,
        page = 1,
        size = 10,
        total = 0
    },
            { __index = PageResult })
end

local function valid(self, db, helpers)
    local route_id = self.params.route_id
    local service_id = self.params.service_id
    local path_configs = self.params.path_configs
    if not route_id then
        kong.response.error(404, "route_id not found")
        return
    end
    if not service_id then
        kong.response.error(404, "service not found")
        return
    end
    local route, err = routes_dao:select({
        id = route_id
    })
    if err then
        kong.response.error(500, err)
    end
    if not route then
        kong.response.error(404, "route not found id: " .. route_id)
        return
    end
    local service, err = services_dao:select({
        id = service_id
    })
    if err then
        return kong.response.error(500, err)
    end
    if not service then
        kong.response.error(404, "service not found id: " .. service_id)
        return
    end
    if not path_configs then
        kong.response.error(400, "path_configs not found")
        return
    end
    if type(path_configs) ~= "table" then
        kong.response.error(400, "path_configs must be table")
        return
    end
end

local function get_tenant_id(self)
    local tenant_id = "default"
    local request_tenant_id = self.params.tenant_id
    if request_tenant_id then
        tenant_id = request_tenant_id
    end
    return tenant_id
end


local function page_rate_limit_path_configs(db, tenant_id, route_id, service_id, page, size, path_search)
    if not tenant_id and not route_id and not service_id then
        kong.response.error(400, "tenant_id, route_id, service_id is must be exist")
    end
    local _page, _size, query_sql, count_query_sql = SQLTemplate.page_rate_limit_path_configs_query_sql(tenant_id, route_id, service_id, page, size, path_search)
    kong.log("page_rate_limit_path_configs query sql : " .. query_sql)
    kong.log("page_rate_limit_path_configs query count sql : " .. count_query_sql)
    local err
    local rows, err, _, _ = path_config_dao.db.connector:query(query_sql)
    local count_rows, err, _, _ = path_config_dao.db.connector:query(count_query_sql)
    local pageResult = PageResult:new()
    if err then
        kong.log.err("page_rate_limit_path_configs err: " .. err)
        return Json.encode(pageResult)
    end
    pageResult.page = _page
    pageResult.size = _size
    pageResult.num  = #rows
    pageResult.total = count_rows[1].count
    pageResult.results = rows
    return Json.encode(pageResult)
end


local function save_or_update_rate_limit_path_config(dao, tenant_id, route_id, service_id, path_configs, update_router)
    local insert_paths = {}
    for index, path_config in pairs(path_configs) do
        local path = path_config.path
        local method = path_config.method
        local rate = path_config.rate
        local capacity = path_config.capacity
        kong.log("tenant_id: " .. tenant_id .. " route_id: " .. route_id .. " service_id: " .. service_id .. " path: " .. path .. " method: " .. method)
        if not path or not Utils.is_all_number(rate, capacity) or not Utils.in_array(method, methods) then
            goto skip
        end
        local key = dao:cache_key(tenant_id, route_id, service_id, path, method)
        local db_path_config, err = dao:select_by_cache_key(key)
        if err then
            kong.log.err("api save_rate_limit_path_config select err: " .. err)
        end
        if not db_path_config then
            local response, err = dao:insert({
                tenant_id  = tenant_id,
                route_id   = route_id,
                service_id = service_id,
                path       = path,
                method     = method,
                rate       = rate,
                capacity   = capacity
            })
            if err then
                kong.log.err("api save_rate_limit_path_config insert err: " .. err)
            end
            insert(insert_paths, { path, method })
        else
            local _, err = dao:update({ id  = db_path_config.id },
                    {
                        tenant_id  = db_path_config.tenant_id,
                        route_id   = db_path_config.route_id,
                        service_id = db_path_config.service_id,
                        path       = db_path_config.path,
                        method     = db_path_config.method,
                        rate       = rate,
                        capacity   = capacity
                    })
            if err then
                kong.log.err("api save_rate_limit_path_config update err: " .. err)
            end
        end
        ::skip::
    end

    if update_router then
        local success, route = pcall(function() return Router:new() end)
        if not success or not route then
            kong.response.error(500, "shared dict routeTree not found " .. toString(route))
            return
        end

        local key = route:buildKey(route_id, tenant_id)
        local route_tree, err = route:fetch(key)
        if err then
            kong.log.err("route:fetch err: " .. err)
        end
        if not route_tree then
            kong.log("route:fetch route_tree not exist! : ")
            local tree = RouterTree:new()
            if insert_paths then
                for _, path_method in pairs(insert_paths) do
                    local path = path_method[1]
                    local method = path_method[2]
                    tree:insert(path, method)
                end
            end
            local success, err = route:store(key, tree)
            if err then
                kong.log("save shared dict success : " .. success .. " err: " .. err)
            end
        else
            if insert_paths then
                local new_route_tree = RouterTree:replace(route_tree)
                for _, path_method in pairs(insert_paths) do
                    local path = path_method[1]
                    local method = path_method[2]
                    new_route_tree:insert(path, method)
                end
                local exist, err = route:cover(key, new_route_tree)
                if err then
                    kong.log("cover shared dict exist : " .. exist .. " err: " .. err)
                end
            end
        end
    end
end

-- 删除不去更新路由树, 查不到限流规则就行。
local function delete_rate_limit_path_config(dao, tenant_id, route_id, service_id, path_configs)
    for index, path_config in pairs(path_configs) do
        local path = path_config.path
        local method = path_config.method
        if not path then
            goto skip
        end
        local key = dao:cache_key(tenant_id, route_id, service_id, path, method)
        local db_path_config, err = dao:select_by_cache_key(key)
        if err then
            kong.log.err("api delete_rate_limit_path_config select err: " .. err)
            goto skip
        end
        local result, err = dao:delete({
            id = db_path_config.id
        }, {
            tenant_id  = db_path_config.tenant_id,
            route_id   = db_path_config.route_id,
            service_id = db_path_config.service_id,
            path       = db_path_config.path,
            method     = db_path_config.method
        })
        local cache = kong.cache
        cache:invalidate(key)
        if err then
            kong.log.err("api delete_rate_limit_path_config delete err: " .. err)
            return kong.response.error(500, err)
        end
        ::skip::
    end
end


local function router_init(dao, tenant_id, route_id, service_id)
    local success, route = pcall(function() return Router:new() end)
    if not success or not route then
        kong.response.error(500, "shared dict routeTree not found " .. toString(route))
        return
    end
    local key = route:buildKey(route_id, tenant_id)
    local tree = RouterTree:new()
    for path_config, err in dao:each(1000) do
        if err then
            kong.log.err("Error when iterating over router: " .. err)
            goto skip
        end
        tree:insert(path_config.path, path_config.method)
        ::skip::
    end
    local success, err = route:cover(key, tree)
    -- 不存在当前缓存
    if not success then
        local success, err = route:store(key, tree)
        if not success then
            if err then
                kong.log.err("router_init store err:" .. err)
            end
        end
    end
end


return {
    ["/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config"] = {
        before = valid,
        POST = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local path_configs = self.params.path_configs
            save_or_update_rate_limit_path_config(path_config_dao, tenant_id, route_id, service_id, path_configs, true)
            return kong.response.exit(200)
        end,
        PUT = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local path_configs = self.params.path_configs
            save_or_update_rate_limit_path_config(path_config_dao, tenant_id, route_id, service_id, path_configs, false)
            return kong.response.exit(200)
        end,
        DELETE = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local path_configs = self.params.path_configs
            delete_rate_limit_path_config(path_config_dao, tenant_id, route_id, service_id, path_configs)
            return kong.response.exit(200)
        end,
        GET = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local page = self.params.page
            local size = self.params.size
            local search = self.params.search
            return kong.response.exit(200, page_rate_limit_path_configs(db, tenant_id, route_id, service_id, page, size, search))
        end
    },
    ["/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/fetch_router_tree"] = {
        GET = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local success, route = pcall(function() return Router:new() end)
            if not success or not route then
                kong.response.error(500, "shared dict routeTree not found " .. toString(route))
                return
            end
            local result, err = route:fetch_json(route:buildKey(route_id, tenant_id))
            if err then
                return kong.response.exit(200, err)
            end
            return kong.response.exit(200, result)
        end
    },
    ["/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/import_path_config"] = {
        before = valid,
        POST = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local path_configs = self.params.path_configs
            save_or_update_rate_limit_path_config(path_config_dao, tenant_id, route_id, service_id, path_configs, false)
            return kong.response.exit(200)
        end
    },
    ["/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/refresh"] = {
        PUT = function(self, db, helpers)
            local tenant_id = self.params.tenant_id
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            router_init(path_config_dao, tenant_id, route_id, service_id)
            return kong.response.exit(200)
        end
    },
    ["/path_rate_limit_enhance/router/:route_id/service/:service_id/import_path_config_and_refresh"] = {
        before = valid,
        POST = function(self, db, helpers)
            local tenant_id = get_tenant_id(self)
            local route_id = self.params.route_id
            local service_id = self.params.service_id
            local path_configs = self.params.path_configs
            save_or_update_rate_limit_path_config(path_config_dao, tenant_id, route_id, service_id, path_configs, false)
            router_init(path_config_dao, tenant_id, route_id, service_id)
            return kong.response.exit(200)
        end
    }
}