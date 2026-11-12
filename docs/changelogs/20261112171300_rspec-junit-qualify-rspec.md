# Qualify ::RSpec in RspecJunit.install!

## Decisions

`Polyrun::Reporting::RspecJunit.install!` must call `::RSpec.configure` and register `::RSpec::Core::Formatters::JsonFormatter`. Nested constant lookup otherwise binds bare `RSpec` to `Polyrun::RSpec` after `require "polyrun/rspec"`.

## Effects

`install!` no longer raises `NoMethodError` for `configure` when `Polyrun::RSpec` is already defined. Spec covers that order.

## Next

Include in the next CHANGELOG.md release section when cutting past 2.2.9.

## Source

- `docs/issues/20261112171300_rspec-junit-shadows-rspec.md`
- `lib/polyrun/reporting/rspec_junit.rb`
- `spec/polyrun/reporting/rspec_junit_spec.rb`
