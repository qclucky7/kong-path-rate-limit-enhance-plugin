## [Kong](https://github.com/Kong/kong) 限流插件扩展

[English Documentation](https://github.com/GravityMatrix/kong-path-rate-limit-enhance/README-EN.md)

kong版本: 2x

#### 提供基于Path和Method的限流, 支持完整匹配, 带参数匹配, 路径模糊匹配。

限流算法: 基于redis的令牌桶算法。

路由算法: 前缀树。
1. 优先级 完整匹配 > 参数匹配 > 模糊匹配。

`优点`:

1. 可动态添加删除路由, 限流配置。
2. 提供租户自定义限流规则。
3. 支持分布式

`未实现可增强点`:

1. 路由树缓存每次需要从nginx缓存获取并进行序列化反序列化, 可优化为本地内存, 提高效率。
2. redis脚本执行使用eval, 在redis注册脚本使用sha1调用, 降低网络传输。

## 快速开始

### 修改kong.conf
1. 添加插件: `plugins="bundled,path_rate_limit_enhance"`
2. 配置nginx缓存: `nginx_http_lua_shared_dict=router_shared_cache 128m` 存储api的路由树, 大小根据项目定义。超过缓存大小新的限流api则不会生效。

### 数据库创建
1. 直接在数据库执行[SQL脚本](https://github.com/GravityMatrix/kong-path-rate-limit-enhance/kong/plugins/path_rate_limit_enhance/migrations)
2. [Kong迁移](https://docs.konghq.com/gateway/2.8.x/install-and-run/upgrade-enterprise/)

### 启用插件
1. api方式启用, 当然也在可以在kong管理界面看到自定义插件启动。
   ```
    curl -X POST http://localhost:8001/routes/{route_id}/plugins \
        --data "name=path_rate_limit_enhance" \
        --data "config.algorithm=token_buckets" \
        --data "config.host=redis_host" \
        --data "config.port=redis_port" \
        --data "config.database=redis.database" \
        --data "config.username=redis.username" \
        --data "config.password=redis.password" \
        --data "config.timeout=redis.timeout" \
        --data "config.response.code=429" \
        --data "config.response.message={json}" \
        
   ```
参数描述

| 参数名              | 必填  | 默认值                                                        | 描述                |
|------------------|-----|------------------------------------------------------------|-------------------|
| algorithm        | 否   | token_buckets                                              | 只支持令牌桶算法          |
| host             | 是   | 无                                                          | redis host地址      |
| port             | 否   | 6379                                                       | redis 端口号         |
| database         | 否   | 0                                                          | redis 数据库         |
| username         | 否   | 无                                                          | redis用户名          |
| password         | 否   | 无                                                          | redis密码           |
| timeout          | 否   | 1000                                                       | redis连接超时(毫秒)     |
| response.code    | 否   | 429                                                        | 限流响应状态码(429, 503) |
| response.message | 否   | { message = "The system is busy. Please try again later" } | 限流响应JSON体         |
| tenant_id_header | 否   | 无                                                          | 多租户定制请求头          |


### 插件api接口
#### 使用需要把对应的服务api接口导入进来, 在通过刷新缓存使路由匹配生效。

参数:  
route_id: 路由id  
service_id: 服务id  
tenant_id: 租户id(默认为default)

api导入规则:
1. 完整匹配: /api/v1/orders
2. 参数匹配: /api/v1/orders/{variable} 参数占位符固定为`{variable}`
3. 模糊匹配: /api/v1/orders/** 录入api请求方式写入`ANY`(任意类型, 虽然填写其他的类型不影响模糊匹配规则生效, 为了更好区分)

---

以下api调用的时候会动态刷新路由缓存。批量导入的时候建议先导入, 在手动刷新路由缓存防止频繁更新路由缓存。

POST `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config`

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        },
        {
            //参数变量固定填入{variable}。
            "path": "/api/v1/orders/{variable}/users/{variable}",
            "method": "GET",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        },
        {
            //模糊匹配 请求方式传入ANY任意类型。
            "path": "/api/v1/orders/**",
            "method": "ANY",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        }
    ]
}
```

PUT `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config`

更新只会修改rate和capacity参数。

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 10, //修改每秒填充个数为10
            "capacity": 10 //令牌桶容量
        }
    ]
}
```


DELETE `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config`

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 10, 
            "capacity": 10
        }
    ]
}
```

GET `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config`

Params:

page: 1   
size: 10  
search: /api/v1 (路径搜索)

Response:
```
{
    "results": [
        {
            "tenant_id": "default",
            "created_at": "2022-07-27 01:49:46+00",
            "capacity": 10,
            "method": "GET",
            "service_id": "",
            "path": "/api/v1/orders",
            "route_id": "",
            "rate": 10,
            "cache_key": "", //此字段是kong缓存需要。
            "id": "a3863399-2b3f-4e85-b87d-4318bc803257"
        },
        {
            "tenant_id": "default",
            "created_at": "2022-07-29 02:57:36+00",
            "capacity": 10,
            "method": "GET",
            "service_id": "",
            "path": "/api/v1/orders/{variable}/user/{variable}",
            "route_id": "",
            "rate": 10,
            "cache_key": "",
            "id": "db77af2c-9e5a-468c-9aa8-21dd412e5b3c"
        }
    ],
    "page": 1,
    "size": 10, 
    "num": 2, 
    "total": 2 
}
```

---

GET `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/fetch_router_tree`

获取当前生效的路由树。

Response:
```
{
    "root": {
        "is_wildcard": false,
        "is_end": false,
        "next_nodes": {
            "api": {
                "is_wildcard": false,
                "is_end": false,
                "fragment": "api",
                "next_nodes": {
                    "v1": {
                        "is_wildcard": false,
                        "is_end": false,
                        "fragment": "v1",
                        "next_nodes": {
                            "ping": {
                                "is_wildcard": false,
                                "is_end": false,
                                "fragment": "orders",
                                "next_nodes": {
                                    "GET": {
                                        "is_wildcard": false,
                                        "is_end": true,
                                        "fragment": "GET",
                                        "next_nodes": {}
                                    }
                                }
                            }     
                        }
                    }
                }
            }
        }
    }
}
```

POST  `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/import_path_config`

此导入接口不会刷新缓存路由。此接口适合很多api导入, 然后在一次性刷新缓存。

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        },
        {
            //参数变量固定填入{variable}。
            "path": "/api/v1/orders/{variable}/users/{variable}",
            "method": "GET",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        },
        {
            //模糊匹配 请求方式传入ANY任意类型。
            "path": "/api/v1/orders/**",
            "method": "ANY",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        }
    ]
}
```

PUT `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/refresh`

全量刷新路由缓存。


POST  `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/import_path_config_and_refresh`

上两个接口功能的集成, 导入并且刷新缓存路由。

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        },
        {
            //参数变量固定填入{variable}。
            "path": "/api/v1/orders/{variable}/users/{variable}",
            "method": "GET",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        },
        {
            //模糊匹配 请求方式传入ANY任意类型。
            "path": "/api/v1/orders/**",
            "method": "ANY",
            "rate": 1, //每秒填充个数
            "capacity": 1 //令牌桶容量
        }
    ]
}
```