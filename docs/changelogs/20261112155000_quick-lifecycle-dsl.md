# Quick lifecycle and DSL

## Decisions

Ship RFC-0009: suite config, around, error-aware after, with/subject, predicates, slowest summary.

## Effects

- `config/polyrun_quick.rb` with `before_suite`, `after_suite`, `add_load_path`
- Per-example `around { |run| run.call }` (fail closed if skipped)
- `after { |error| }` receives failure or nil; always runs after the example attempt
- `with`, `subject`, `be` / `be_a` / `raise_exception`
- Reporter lists slowest examples >= 0.05s

## Next

- before_all/after_all per group only with host demand
- Optional YAML suite hooks under `polyrun.yml`

## Source

- `rfcs/0009-quick-lifecycle-and-dsl.md`
- `docs/reviews/20261112154600_quick-lifecycle-engineering-audit.md`
