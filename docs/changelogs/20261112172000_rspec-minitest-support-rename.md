# Rename RSpec and Minitest wiring to *Support

## Decisions

Ship RFC-0007: `Polyrun::RSpecSupport` / `Polyrun::MinitestSupport`, requires `polyrun/rspec_support` / `polyrun/minitest_support`, hard cut with no aliases.

## Effects

Old constants and require paths raise `NameError` / `LoadError`. Nested helpers live under `Polyrun::RSpecSupport`. `RspecJunit.install!` keeps `::RSpec` qualification.

## Next

Include in the next CHANGELOG.md release section when cutting past 2.2.9. Mark RFC 0007 Stable with the release that ships the rename.

## Source

- `rfcs/0007-rspec-support-rename.md`
- `docs/issues/20261112171300_rspec-junit-shadows-rspec.md`
