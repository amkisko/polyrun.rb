# Cost-balanced partitioning + Rails demo

This folder combines:

1. **Standalone `polyrun plan` demos** (no application boot) — compare **round-robin** vs **cost binpack** using **`polyrun_timing.json`**.
2. **Rails + Polyrun** via **`rails_demo/`** — a symlink to **`../multi_database/multi_demo`** (same multi-DB **`primary` + `cache`** app). From **`rails_demo`**, **`./bin/rspec_parallel`** runs **`run-shards`** + **`merge-coverage`** with default **`polyrun.yml`**. For **cost-balanced** assignment, use **`polyrun_rails.yml`** + **`demo_rails.sh`** (**`run-shards --timing …`** + **`merge-coverage`**).

## Polyrun features

| Feature | Demo |
|--------|------|
| **All partition strategies** (`round_robin`, `random_round_robin`, `cost_binpack`, `hrw`) | **[../partition_strategies/README.md](../partition_strategies/README.md)** — `demo_plan.sh` (no Rails) |
| **`plan`** + **`--timing`** | `demo.sh` — `shard_seconds` in JSON manifest |
| **`partition_constraints`** | `partition_constraints.example.yml` + `--constraints` |
| **`run-shards`** + **`POLYRUN_SHARD_INDEX`** | `demo_rails.sh` — parallel RSpec, coverage fragments |
| **`merge-coverage`** | `demo_rails.sh` — merges `coverage/polyrun-fragment-*.json` |
| **Queue** (optional) | `polyrun queue init|claim|ack` — see `polyrun queue --help` and `Polyrun::Queue::FileStore` |

## Try plan-only (no Rails)

```bash
cd examples/cost_balancing
chmod +x demo.sh
./demo.sh
```

## Try Rails + parallel + merged coverage

Requires the shared demo app (multi-database). From this directory:

```bash
chmod +x demo_rails.sh
./demo_rails.sh
```

This runs **`db:prepare`** (primary + cache), then **`bin/polyrun -c polyrun_rails.yml run-shards --workers 4 --timing polyrun_timing.json -- bundle exec rspec`**, then **`merge-coverage`** into **`coverage/merged.json`**.

## Workflow in a real repo

1. Run parallel RSpec shards and record per-file times (e.g. **`polyrun merge-timing`** from shard timing files).
2. **`polyrun merge-timing -i … -o polyrun_timing.json`**
3. Next CI run: **`polyrun plan --timing polyrun_timing.json`** or **`partition.timing_file`** + **`strategy: cost_binpack`** in **`polyrun.yml`**.
4. **`polyrun run-shards --timing polyrun_timing.json --workers N -- bundle exec rspec`**
5. **`polyrun merge-coverage`** on all **`coverage/polyrun-fragment-*.json`** files.

Unknown spec paths get the **mean** of all weights in the timing file (paths are normalized with `File.expand_path` relative to the current working directory).

## Constraints (pins / serial globs)

YAML example (`partition_constraints.example.yml`):

```yaml
pin:
  "spec/models/heavy_spec.rb": 0
serial_glob:
  - "spec/system/**"
```

```bash
polyrun plan --total 2 --shard 0 --timing polyrun_timing.json \
  --paths-file spec_paths.txt --constraints partition_constraints.example.yml
```

Use strategy **`cost_binpack`** (with `--timing`) or **`hrw`** / **`rendezvous`** when using constraints.

## File-backed queue (dynamic batches)

For pull-based workers (queue-backed batching):

```bash
polyrun queue init --paths-file spec_paths.txt --timing polyrun_timing.json --dir .polyrun-queue
polyrun queue claim --dir .polyrun-queue --worker ci-1 --batch 5
polyrun queue ack --lease <uuid> --worker ci-1 --dir .polyrun-queue
polyrun queue status --dir .polyrun-queue
```

Initial ordering is **LPT** when `--timing` is set (longest estimated jobs first in the pending list). Claims move work into **leases** until **`ack`**; there is no lease TTL—recover stuck paths manually if a worker dies mid-lease.

