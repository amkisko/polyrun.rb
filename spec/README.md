# Polyrun gem specs

Canonical test command for this repository:

    bundle exec rspec

Focused run (one file or example):

    bundle exec rspec spec/polyrun/cli_ci_shard_run_spec.rb
    bundle exec rspec spec/polyrun/cli_ci_shard_run_spec.rb:38

## What to test

Test executable behavior and user-visible contracts: CLI exit codes, stderr messages, files written, env passed to child processes, and public module APIs.

Do not test private methods with `send`. Prefer subprocess CLI specs (`polyrun(...)` from `spec/support/polyrun_cli_helpers.rb`) over in-process `CLI.new` unless coverage measurement requires in-process (`POLYRUN_COVERAGE=1`).

Do not assert source file contents, README wording, or hook execution order unless order is the published contract.

## Coverage

Non-trivial lib behavior needs specs before behavior changes ship. Trivial one-liners need no new spec.

When fixing a bug: add or update a spec that fails before the fix, then implement, then run focused and full suites.

## Layout

- `spec/polyrun/cli_*_spec.rb` — CLI integration (subprocess or in-process per helper)
- `spec/polyrun/<module>/` — unit specs for lib modules
- `spec/spec_paths.txt` — path list used by partition / queue examples in the suite

## Environment

`spec_helper.rb` clears shard and CI env vars before each example. Examples that need `POLYRUN_*` flags should set and restore them in the example or an `around` block.
