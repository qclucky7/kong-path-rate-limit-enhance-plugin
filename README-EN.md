## [Kong](https://github.com/Kong/kong) rate-limit-enhance

kong version : 2x

#### Provides flow limiting based on Path and Method, supports complete matching, parameter matching, Path fuzzy matching。

Traffic limiting algorithm: `Token bucket algorithm based on redis`

Routing algorithm: `Prefix tree`

1. Priority Complete Matching > Parameter Matching > Fuzzy Matching。

`Advantage`: 

1. You can dynamically add or delete routes and configure traffic limiting。
2. The tenant can customize traffic limiting rules。
3. Distributed Support

`Enhancement point not implemented`:

1. The routing tree cache needs to be obtained from the nginx cache and serialized and deserialized each time, which can be optimized into VM memory to improve efficiency。
2. The Redis script is executed using eval, and the Redis register script is called using SHA1, reducing network transmission。

## Getting Started

### Modify kong.conf
1. add plugin: `plugins="bundled,path_rate_limit_enhance"`
2. Configure the nginx cache: `nginx_http_lua_shared_dict=router_shared_cache 128m` Store the API routing tree, size as defined by the project. If the cache size is exceeded, the new traffic limiting API will not take effect。

### Database table Create
1. Database execute [SQL Script](https://github.com/GravityMatrix/kong-path-rate-limit-enhance-plugin/blob/main/kong/plugins/path_rate_limit_enhance/migrations/init.lua)
2. [Kong migration](https://docs.konghq.com/gateway/2.8.x/install-and-run/upgrade-enterprise/)

### Enable plugin
   1. API enabled, of course, also can be seen in the Kong management interface custom plugin start。
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
Parameters

| parameters       | required | default                                                    | description                                |
|------------------|----------|------------------------------------------------------------|--------------------------------------------|
 | algorithm        | N        | token_buckets                                              | only token buckets supported               |
 | host             | Y        | nothing                                                    | redis host                                 |
| port             | N        | 6379                                                       | redis port                                 |
| database         | N        | 0                                                          | redis database                             |
| username         | N        | nothing                                                    | redis username                             |
| password         | N        | nothing                                                    | redis password                             |
| timeout          | N        | 1000                                                       | redis connect timeout (millisecond)        |
| response.code    | N        | 429                                                        | rate limit response status code (429, 503) |
| response.message | N        | { message = "The system is busy. Please try again later" } | rate limit response body (JSON)            |
  | tenant_id_header | N        | nothing                                                    | tenant header                              |

  
### Plugin API
#### The corresponding service API interface needs to be imported, and the route matching takes effect by refreshing the cache。

#### Parameters:  
route_id: route id  
service_id: service id  
tenant_id: tenant id(The default value is default)

#### API import rules:
1. complete matching: /api/v1/orders
2. parameter matching: /api/v1/orders/{variable} The parameter placeholder is fixed as `{variable}`
3. fuzzy matching: /api/v1/orders/** Input API request method Write `ANY` (ANY type, although filling in other types does not affect the effect of fuzzy matching rules, for better discrimination)

---

The following API calls dynamically refresh the routing cache。You are advised to import routes in batches first. Then refresh. Prevent frequent update of the route cache。

POST `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config`

Request: 
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 1, //Number of fills per second
            "capacity": 1 //Token bucket capacity
        },
        {
            //Parameter matches a fixed format -> {variable}。
            "path": "/api/v1/orders/{variable}/users/{variable}",
            "method": "GET",
            "rate": 1, //Number of fills per second
            "capacity": 1 //Token bucket capacity
        },
        {
            //Fuzzy matches Request method is ANY。
            "path": "/api/v1/orders/**",
            "method": "ANY",
            "rate": 1, //Number of fills per second
            "capacity": 1 //Token bucket capacity
        }
    ]
}
```

PUT `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/path_config`

Only the rate and capacity parameters are modified。

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
search: /api/v1 (Path Search)

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
            "cache_key": "", //Kong cache key。
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

fetch the current routing tree。

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

This import interface does not refresh the cache route. This interface is suitable for many API imports and then flushes the cache at once。

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 1,
            "capacity": 1
        },
        {
            "path": "/api/v1/orders/{variable}/users/{variable}",
            "method": "GET",
            "rate": 1,
            "capacity": 1
        },
        {
            "path": "/api/v1/orders/**",
            "method": "ANY",
            "rate": 1,
            "capacity": 1
        }
    ]
}
```

PUT `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/refresh`

route cache is fully refreshed。


POST  `http://localhost:8001/path_rate_limit_enhance/router/:route_id/service/:service_id/tenant/:tenant_id/import_path_config_and_refresh`

Integration of the above two interface functions, import and refresh cache routes。

Request:
```
{
    "path_configs":[
        {
            "path": "/api/v1/orders",
            "method": "GET",
            "rate": 1,
            "capacity": 1
        },
        {
            "path": "/api/v1/orders/{variable}/users/{variable}",
            "method": "GET",
            "rate": 1,
            "capacity": 1
        },
        {
            "path": "/api/v1/orders/**",
            "method": "ANY",
            "rate": 1,
            "capacity": 1
        }
    ]
}
```