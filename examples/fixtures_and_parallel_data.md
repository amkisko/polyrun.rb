# Fixtures, factories, and parallel DB setup (Polyrun::Data)

Polyrun ships optional helpers for **parallel test processes** (same model as `run-shards`: one Ruby process per shard, not threads alone).

| Module | Purpose |
|--------|---------|
| **`Polyrun::Data::CachedFixtures`** | Process-local memoization for expensive setup (`fetch` / `register`); same idea as TestProf AnyFixture. |
| **`Polyrun::Data::ParallelProvisioning`** | **`serial`** vs **`parallel_worker`** hooks for DB seeds / truncate (Oaken + parallel_tests style). |
| **`Polyrun::Data::FactoryInstrumentation`** | Opt-in FactoryBot hook → **`FactoryCounts`** (needs **`factory_bot`** gem). |
| **`Polyrun::Data::Fixtures`** | Load YAML fixture batches and `insert_all`-style apply (optional ActiveRecord). |
| **`Polyrun::Data::SqlSnapshot`** | `pg_dump` / `psql` snapshots without the `pg` gem. |

## Runnable demo

**[simple/simple_demo](simple/simple_demo/README.md)** wires:

- **`spec/support/polyrun_parallel_data.rb`** — `ParallelProvisioning.configure` (empty hooks you can fill).
- **`spec/rails_helper.rb`** — `require "polyrun/rspec"` + **`Polyrun::RSpec.install_parallel_provisioning!(config)`** so hooks run in **`before(:suite)`**.
- **`spec/polyrun/polyrun_data_optimizations_spec.rb`** — **`CachedFixtures`** memoization example.

Run:

```bash
cd examples/simple/simple_demo
bundle exec rspec spec/polyrun/polyrun_data_optimizations_spec.rb
```

## FactoryBot + FactoryCounts

If you add **`factory_bot`** to the Gemfile:

```ruby
require "factory_bot"
Polyrun::Data::FactoryInstrumentation.instrument_factory_bot!
```

Then inspect **`Polyrun::Data::FactoryCounts.counts`** (per-factory run counts). Use **process isolation** for parallel runners — counts are per process.

## Related

- **[TESTING_REQUIREMENTS.md](TESTING_REQUIREMENTS.md)** — shared builds, DB contention, GVL.
- **`Polyrun::Database::Shard`** — env vars for per-worker DB names (`polyrun env`).
