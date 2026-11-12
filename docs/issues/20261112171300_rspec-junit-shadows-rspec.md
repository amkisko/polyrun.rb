# Polyrun RspecJunit.install! shadows ::RSpec

## Participants

Andrei Makarov (@amkisko)

## Decisions

Treat this as a first-party bug in `Polyrun::Reporting::RspecJunit`, not a third-party dependency defect. Bare `RSpec` inside `module Polyrun` resolves to `Polyrun::RSpec` after `require "polyrun/rspec"`. Qualify with `::RSpec` and `::RSpec::Core::Formatters::JsonFormatter`, matching `lib/polyrun/rspec.rb`.

Do not file this under `docs/dependencies/`: the failing constant is this gem. Consumer workarounds are unnecessary once the fix ships.

Correct a false load-order claim about this repository: `spec/spec_helper.rb` requires `support/junit_formatter` before `polyrun/rspec`, so this repo's own CI path often avoids the failure. The failure is still real for any process that loads `polyrun/rspec` before `RspecJunit.install!` (the documented consumer order).

## Effects

Reproduced on polyrun 2.2.9 / main: `require "polyrun/rspec"` then `Polyrun::Reporting::RspecJunit.install!` with `CI=1` raises `NoMethodError: undefined method 'configure' for module Polyrun::RSpec` at bare `RSpec.configure` in `lib/polyrun/reporting/rspec_junit.rb`.

Fixed by qualifying `::RSpec` in `install!`. Regression example in `spec/polyrun/reporting/rspec_junit_spec.rb` fails before the qualification and passes after.

## Next

Ship `::RSpec` qualification and the RFC-0007 rename (`Polyrun::RSpecSupport` / `Polyrun::MinitestSupport`, hard cut) in the next release after 2.2.9.

## Source

- `lib/polyrun/reporting/rspec_junit.rb`
- `rfcs/0007-rspec-support-rename.md`
- `spec/polyrun/reporting/rspec_junit_spec.rb`
- `spec/support/junit_formatter.rb`, `spec/spec_helper.rb`
