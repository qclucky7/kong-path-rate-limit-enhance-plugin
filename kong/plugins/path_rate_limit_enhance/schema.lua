local typedefs = require "kong.db.schema.typedefs"

return {
    name = "path-rate-limit-enhance",
    fields = {
        {
            consumer = typedefs.no_consumer
        },
        {
            protocols = typedefs.protocols_http
        },
        {
            config = {
                type = "record",
                fields = {
                    {
                        algorithm = {
                            type = "string",
                            default = "token_buckets",
                            one_of = {
                                "token_buckets",
                            }
                        }
                    },
                    {
                        tenant_id_header = {
                            type = "string",
                        }
                    },
                    {
                        host = {
                            type = "string",
                            required = true
                        }
                    },
                    {
                        port = {
                            type = "number",
                            default = 6379,
                            between = { 0, 65535 }
                        }
                    },
                    {
                        database = {
                            type = "number",
                            default = 0,
                        }
                    },
                    {
                        username = {
                            type = "string",
                            required = false
                        }
                    },
                    {
                        password = {
                            type = "string",
                            required = false
                        }
                    },
                    {
                        timeout = {
                            type = "number",
                            required = false,
                            default = 1000
                        }
                    },
                    {
                        response = {
                            type = "record",
                            fields = {
                                {
                                    code = {
                                        type = "number",
                                        default = 429,
                                        one_of = {
                                            429, 503
                                        }
                                    }
                                },
                                {
                                    message = {
                                        type = "string",
                                        default = [[{ message = "The system is busy. Please try again later" }]]
                                    }
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}