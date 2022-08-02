return {
    postgres = {
        up = [[

          CREATE TABLE IF NOT EXISTS "rate_limit_path_config" (
            "id"           UUID                         PRIMARY KEY,
            "tenant_id"    TEXT                         NOT NULL,
            "service_id"   TEXT                         NOT NULL,
            "route_id"     TEXT                         NOT NULL,
            "path"         TEXT                         NOT NULL,
            "method"       TEXT                         NOT NULL,
            "rate"         INTEGER                      NOT NULL,
            "capacity"     INTEGER                      NOT NULL,
            "cache_key"    TEXT                         NOT NULL,
            "created_at"   TIMESTAMP WITH TIME ZONE     DEFAULT (CURRENT_TIMESTAMP(0) AT TIME ZONE 'CCT')
          );

          DO $$
          BEGIN

          CREATE UNIQUE INDEX IF NOT EXISTS rate_limit_path_config_unique_index ON rate_limit_path_config (tenant_id, route_id, service_id, path, method);

          CREATE INDEX IF NOT EXISTS rate_limit_path_config_index ON rate_limit_path_config (tenant_id, route_id, service_id, path, method);

          END$$;

        ]],
    },
    cassandra = {
        up = [[]],
    },
}