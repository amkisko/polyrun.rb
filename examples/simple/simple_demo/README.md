# simple_demo

Rails **Polyrun** example app (see **[../../README.md](../../README.md)** for all examples and **[../README.md](../README.md)** for this track).

## Setup

```bash
bundle install
./script/ci_prepare
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec
```

## Parallel run + merged coverage

Use **`polyrun` global options before the subcommand** (so `-c polyrun.yml` is applied):

```bash
bundle exec polyrun -c polyrun.yml parallel-rspec --workers 4
# or: ./bin/rspec_parallel
```

Configuration: **`polyrun.yml`** (`partition`, `prepare`, `databases`).
