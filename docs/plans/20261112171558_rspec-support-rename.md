# Plan: RSpecSupport and MinitestSupport rename

## Decisions

- Names: `Polyrun::RSpecSupport`, `Polyrun::MinitestSupport`.
- Requires: `polyrun/rspec_support`, `polyrun/minitest_support`.
- Hard cut: no aliases, no deprecation stubs for `Polyrun::RSpecSupport`, `Polyrun::MinitestSupport`, `polyrun/rspec_support`, or `polyrun/minitest_support`.
- Design: RFC 0007 (Draft).

## Next

- Merge release prep, then `make release` for gem push and tag `3.0.0`.

## Source

- `rfcs/0007-rspec-support-rename.md`
- `docs/issues/20261112171300_rspec-junit-shadows-rspec.md`
