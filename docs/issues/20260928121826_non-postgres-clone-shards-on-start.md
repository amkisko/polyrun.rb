# Non-Postgres databases: CloneShards on start

## Decisions

Skip auto CloneShards on polyrun start when the inferred databases adapter is not PostgreSQL, and warn that apps must provision shards themselves. Exit 1 when start.databases is explicitly true with a non-Postgres adapter. Fail db:clone-shards and db:setup-shard before psql with an explicit PostgreSQL-only error. Pass postgresql connection fields from polyrun.yml into Provision psql calls.

UrlBuilder continues to emit mysql2 and other schemes for worker env from template_db and shard_db_pattern.

## Effects

Reproduced the reported failure mode: start_run_database_provision? previously returned true whenever template_db was set, regardless of adapter, and Provision always shelled out to psql with PG defaults.

Fixed path covered by specs in cli_start_prepare_spec, clone_shards_spec, cli_database_spec, and provision_spec.

## Next

None for this defect. Optional later: MySQL/MariaDB clone automation if a product need appears.

## Source

Issue report: start runs Postgres CloneShards when databases is mysql2 / non-Postgres (observed polyrun 2.2.5).
