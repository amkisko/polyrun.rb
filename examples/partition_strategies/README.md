# Partition strategies (load balancing)

Polyrun assigns spec files to **shards** (worker processes) using a **strategy** from `polyrun.yml` (`partition.strategy`) or **`bin/polyrun plan` / `run-shards --strategy`**.

This folder holds **minimal files** so you can compare strategies without booting Rails:

| Strategy | Meaning | Needs timing JSON? | Typical use |
|----------|---------|-------------------|-------------|
| **`round_robin`** (default) | Sort paths, assign by index mod shard count | No | Predictable splits, simplest |
| **`random_round_robin`** | Fisher–Yates shuffle (optional `seed`), then mod | No | Jitter order to reduce ordering bias |
| **`cost_binpack`** / **`binpack`** / **`timing`** | Longest-processing-time greedy binpack using per-file seconds | **Yes** | Balance wall time across workers |
| **`hrw`** / **`rendezvous`** | Rendezvous hashing: stable assignment when shard count changes | Optional (weights in manifest) | Minimize reshuffle when `N` workers changes |

Aliases: `cost`, `cost_binpack`, `binpack`, `timing` are equivalent cost strategies; `rendezvous` is the same as `hrw`.

## Files here

- **`spec_paths.txt`** — example paths (same shape as a real `paths_file`).
- **`polyrun_timing.json`** — path → seconds (for cost strategies).
- **`round_robin.yml`**, **`random_round_robin.yml`**, **`cost_binpack.yml`**, **`hrw.yml`** — copy into a demo app as `polyrun.yml` or pass **`-c`** to `polyrun`.

## Try it (plan only)

From this directory:

```bash
chmod +x demo_plan.sh
./demo_plan.sh
```

Or manually:

```bash
POLYRUN=../../bin/polyrun   # from repo root: examples/partition_strategies → ../../bin/polyrun

# Round-robin (default if you omit --strategy)
$POLYRUN plan --total 2 --shard 0 --strategy round_robin --paths-file spec_paths.txt

# Random round-robin (deterministic with --seed)
$POLYRUN plan --total 2 --shard 0 --strategy random_round_robin --seed 42 --paths-file spec_paths.txt

# Cost binpack (needs --timing)
$POLYRUN plan --total 2 --shard 0 --strategy cost_binpack --timing polyrun_timing.json --paths-file spec_paths.txt

# HRW / rendezvous (optional --timing for shard_seconds in manifest)
$POLYRUN plan --total 2 --shard 0 --strategy hrw --seed my-salt --paths-file spec_paths.txt
$POLYRUN plan --total 2 --shard 0 --strategy hrw --timing polyrun_timing.json --paths-file spec_paths.txt
```

With a config file, global `-c` must come **before** the subcommand — e.g. **`polyrun -c hrw.yml plan --shard 0 --total 2`**, not `polyrun plan … -c hrw.yml`.

## Rails demos using different strategies

| App | Default in `polyrun.yml` | Where to see cost-based / timing |
|-----|--------------------------|----------------------------------|
| **simple/simple_demo** | `round_robin` (no `strategy` key → default) | Add `strategy` + `timing_file` in `polyrun.yml` |
| **multi_database/multi_demo** | `round_robin` | Comment points to **cost_balancing/polyrun_rails.yml** |
| **examples/cost_balancing** | **`cost_binpack`** in `polyrun.yml` / `polyrun_rails.yml` | **`demo.sh`**, **`demo_rails.sh`**, **`polyrun_timing.json`** |

Constraints (pins / serial globs) require **`cost_binpack` + timing** or **`hrw`** — see **`examples/cost_balancing/partition_constraints.example.yml`** and **[cost_balancing/README.md](../cost_balancing/README.md)**.
