# DEBUG_SQL subscriber uses ExampleDebug helpers

## Participants

Andrei Makarov

## Decisions

Qualify loggable_sql? and sql_with_interpolated_binds as ExampleDebug methods inside the sql.active_record subscriber. Match the 2.2.0 Rails logging receiver pattern. Cut version 2.2.4 on main.

## Effects

The around hook no longer resolves those helpers on the RSpec example-group instance. Mutating SQL prints with interpolated binds. SELECT prefixes stay skipped. SpecQuality::SqlCounter notification arity is unchanged.

## Next

CHANGELOG.md 2.2.4 records the DEBUG_SQL subscriber receiver. Publish the gem after this release commit lands on main.

## Source

usr/docs/issues/20260904152800_debug-sql-example-instrumentation.md
lib/polyrun/rspec/example_debug_instrumentation.rb
spec/polyrun/rspec/example_debug_instrumentation_spec.rb
CHANGELOG.md 2.2.4
