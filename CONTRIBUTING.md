# Contributing to Polyrun

## Development setup

```bash
bundle install
bundle exec appraisal install
```

## Tests

```bash
bundle exec rspec
# or
bundle exec rake spec
```

Coverage merge performance (large synthetic payloads):

```bash
bundle exec rake bench_merge
# or: ruby benchmark/merge_coverage.rb
```

Run the suite under alternate Ruby constraints (see `Appraisals` and `gemfiles/`):

```bash
bundle exec appraisal ruby32 rspec
bundle exec appraisal ruby34 rspec
```

## Linting

[RuboCop](https://rubocop.org/) with [Standard](https://github.com/standardrb/standard) style, plus `rubocop-rspec` and `rubocop-thread_safety`. Project-specific cop tweaks and metric `Exclude` lists live in `.rubocop.yml`.

```bash
bundle exec rubocop
bundle exec rubocop -a   # safe autocorrect
bundle exec rake rubocop
```

## RBS

Type signatures live under `sig/` and ship with the gem. Validate them after changes:

```bash
bundle exec rake rbs
# equivalent: bundle exec rbs -I sig validate
```

Keep `require "polyrun"` free of RSpec/Minitest: optional wiring stays in `polyrun/rspec`, `polyrun/minitest`, and `polyrun/reporting/rspec_junit` (see README).

[Trunk](https://trunk.io/) aggregates RuboCop, YAML, Markdown, shellcheck, and more (see `.trunk/trunk.yaml`):

```bash
trunk check
trunk fmt
```

CI runs `rake ci` (RSpec + RuboCop). Optional Trunk workflow: `.github/workflows/trunk.yml`.

## Adopting Polyrun in other repos

- [docs/SETUP_PROFILE.md](docs/SETUP_PROFILE.md) — agent or human checklist (CI model A vs B, database, prepare).
- `bundle exec polyrun init --list` — lists starter `polyrun.yml` and `POLYRUN.md` templates (see `examples/templates/README.md`).

## Examples

Runnable demos live under `examples/`. After changing the gem, smoke them:

```bash
cd examples && ./bin/ci_prepare
cd examples/simple/simple_demo && RAILS_ENV=test bundle exec rspec
# optional: complex polyrepo demo (multi-DB + three Vite clients + RSpec E2E)
# cd examples/complex/polyrepo_demo && RAILS_ENV=test bin/rails db:prepare && bundle exec rspec
```

See `examples/README.md`.

## Pull requests

- One logical change per PR when possible.
- Add or update specs for behavior changes.
- Run `bundle exec rake ci` before pushing.
