# Polyrun in this project

This repo uses [Polyrun](https://github.com/amkisko/polyrun.rb) for parallel RSpec, merged coverage, and optional CI report formats.

## Setup profile

Fill in and keep updated: dimensions are summarized in Polyrun’s [SETUP_PROFILE checklist](https://github.com/amkisko/polyrun.rb/blob/main/docs/SETUP_PROFILE.md) (project type, DB, prepare, CI model).

## Canonical commands

```bash
bundle exec polyrun build-paths -c polyrun.yml
bundle exec polyrun parallel-rspec --workers 5 -c polyrun.yml
```

Adjust `--workers` or use `bin/rspec_parallel` if your repo provides a wrapper.

## CI model (choose one and match your workflows)

### Model A — single CI job, N worker processes on one runner

- Run `polyrun parallel-rspec --workers N -c polyrun.yml` (or `polyrun start`).
- Merge coverage in the same job (or a follow-up step) from `coverage/polyrun-fragment-*.json`.

### Model B — matrix: one shard per job

- Matrix sets `POLYRUN_SHARD_INDEX` and `POLYRUN_SHARD_TOTAL` explicitly (e.g. GitHub Actions does not set `CI_NODE_*` by default).
- Each job runs `polyrun build-paths`, `polyrun plan`, then `bundle exec rspec` for that shard only (see `bin/polyrun-rspec` or `bin/rspec_ci_shard` patterns).
- Upload `coverage/polyrun-fragment-<shard>.json` per job; a `merge-coverage` job downloads all fragments and merges.

Do not combine Model A and Model B in one workflow without a documented reason (nested parallelism and duplicate merges).

## Configuration contract

- `polyrun.yml` — partition, optional `prepare`, optional `databases`. This file is the source of truth for shard indices and paths.
- Adapters — thin scripts (`bin/rspec_parallel`, `bin/polyrun-rspec`, `database.yml` ERB, prepare scripts) must match `polyrun.yml`.

## Coverage

- `spec/spec_helper.rb`: `require "polyrun"` and collector or Rails helper as appropriate.
- Fragments: `coverage/polyrun-fragment-<shard>.json` → `polyrun merge-coverage` → `polyrun report-coverage` / `report-junit` for CI.

## Further reading

- Polyrun README: partition, prepare, databases, merge-coverage, `Polyrun::Env::Ci`
