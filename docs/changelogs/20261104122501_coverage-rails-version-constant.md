# Coverage rails entry loads VERSION

## Decisions

`polyrun/coverage/collector.rb` and `polyrun/coverage/merge/formatters.rb` require `polyrun/version` so `Polyrun::VERSION` is defined when a consumer starts coverage with only `require "polyrun/coverage/rails"` (or `require "polyrun/coverage/collector"`), without `require "polyrun"` or `require "polyrun/rspec"`.

## Effects

Finish no longer raises `uninitialized constant Polyrun::VERSION` after a green example run. Fragment meta still records `polyrun_version`. Cut into 2.2.7. Consumers can drop a temporary `require "polyrun/version"` after upgrading to 2.2.7 or later.

## Next

Run `make release` after the 2.2.7 prep commit is on `main`.

## Source

- `lib/polyrun/coverage/collector.rb`
- `lib/polyrun/coverage/merge/formatters.rb`
- `spec/polyrun/coverage/collector_finish_spec.rb`
- `docs/changelogs/20261104122723_release-2-2-7.md`
- `CHANGELOG.md` section 2.2.7
