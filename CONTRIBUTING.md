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

Native extension (optional; compiles via `bundle install` or `cd ext/polyrun_coverage_merge && ruby extconf.rb && make`):

After pulling changes under `ext/**/*.c` or `ext/**/extconf.rb`, rebuild the extension before running specs or benchmarks:

```bash
make native-extension
# or: bundle exec rake native_extension
```

If merge specs segfault or native acceleration behaves oddly after a pull, run `make clean` in `ext/polyrun_coverage_merge` and `make native-extension` again (or `bundle install` to trigger a full compile).

CI compiles the extension on Linux and macOS (`.github/workflows/native-extension.yml`).

```bash
bundle exec rake bench_merge
# or: ruby benchmark/merge_coverage.rb
```

RSpec performance benchmarks (coverage merge + spec-quality peek; writes `tmp/benchmarks/profile_<sha>.log`):

```bash
bundle exec rake bench_performance
# optional: STACKPROF=1 or BENCHMARK_IPS=1 for spec/performance/profiling_spec.rb
# optional: BENCH_MEMORY=1 bundle exec rspec spec/performance/benchmark_merge_spec.rb spec/performance/benchmark_spec.rb --tag benchmark
# optional env: BENCH_LINE_COUNT_REPS, BENCH_MEMORY_REPS
```

Run the suite under alternate Ruby constraints (see `Appraisals` and `gemfiles/`):

```bash
bundle exec appraisal ruby32 rspec
bundle exec appraisal ruby34 rspec
bundle exec appraisal ruby40 rspec
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
