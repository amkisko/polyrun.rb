# Non-Postgres CloneShards gate on start

## Decisions

Gate CloneShards and start database bootstrap on ConnectionInfer postgresql?. Auto start skips and warns for other adapters. Explicit start.databases true fails closed. Explicit db:clone-shards and db:setup-shard fail closed before psql. Provision accepts password and merges PGPASSWORD into a full child env (never an empty env hash that would replace PATH).

## Effects

polyrun start with mysql2 nested block and template_db no longer invokes psql. db:clone-shards with mysql2 exits 1 with PostgreSQL-only message. postgresql host port username password from polyrun.yml reach psql.

## Source

docs/issues/20260928121826_non-postgres-clone-shards-on-start.md
