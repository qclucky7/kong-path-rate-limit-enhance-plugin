local typedefs = require "kong.db.schema.typedefs"

return {
    rate_limit_path_config = {
        name                = "rate_limit_path_config",
        primary_key         = { "id" },
        cache_key           = { "tenant_id", "route_id" ,"service_id", "path", "method" },
        fields = {
            {
                id = typedefs.uuid
            },
            {
                tenant_id = {
                    type = "string",
                    required = true,
                }
            },
            {
                service_id = {
                    type = "string",
                    required = true,
                }
            },
            {
                route_id = {
                    type = "string",
                    required = true,
                }
            },
            {
                method  = {
                    type = "string",
                    required = true,
                }
            },
            {
                path = {
                    type = "string",
                    required = true,
                }
            },
            {
                rate = {
                    type = "integer",
                    required = true,
                }
            },
            {
                capacity = {
                    type = "integer",
                    required = true,
                }
            },
            { created_at = typedefs.auto_timestamp_s },
        },
    },
}