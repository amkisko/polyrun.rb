# DEBUG_SQL subscriber resolves helpers on the example group

## Participants

Andrei Makarov

## Decisions

Stay on main. Qualify loggable_sql? and sql_with_interpolated_binds as ExampleDebug methods inside the sql.active_record subscriber, matching the 2.2.0 Rails logging receiver. Cut 2.2.4 on main; do not create a branch. Consumers stay on ActiveSupport::Notifications counters until 2.2.4 is published.

## Effects

RubyGems latest is 2.2.3 (created 2026-08-16). lib/polyrun/version.rb is 2.2.3. CHANGELOG Unreleased has no instrumentation fix. GitHub issue search for loggable_sql and DEBUG_SQL returned no results.

lib/polyrun/rspec/example_debug_instrumentation.rb:12-16 registers an sql.active_record subscriber inside rspec_config.around. RSpec runs that block with self as the example-group instance. Bare loggable_sql? and sql_with_interpolated_binds therefore miss the module_function methods. Line 14 is the first failure: NoMethodError undefined method loggable_sql?. sql_with_interpolated_binds has the same binding and is not reached.

The same file defines those helpers on ExampleDebug. spec/polyrun/rspec/example_debug_spec.rb tests loggable_sql? on described_class and only asserts that install! does not raise while registering. spec/polyrun/rspec/example_debug_instrumentation_spec.rb tests bind interpolation only. The 2.2.0 rails-logging spec already instance_execs the hook on a plain Object; the SQL hook has no equivalent.

DEBUG_SQL / POLYRUN_DEBUG_SQL are standalone since 2.2.1. POLYRUN_EXAMPLE_DEBUG=1 is not required for the crash. Combining both is valid and still hits the subscriber.

SpecQuality::SqlCounter already qualifies the module and uses |*args| plus Event.new. The debug subscriber uses |event|. The reported stack reached event.payload then loggable_sql?, so that Rails build passed an Event. That arity is not the reported crash.

A later pass added spec/polyrun/rspec/example_debug_instrumentation_spec.rb coverage that instance_execs the around hook on Object and instruments UPDATE versus SELECT. The subscriber now calls ExampleDebug.loggable_sql? and ExampleDebug.sql_with_interpolated_binds.

A later pass cut version 2.2.4 on main. CHANGELOG.md 2.2.4 records the user-facing fix. Path gem version in Gemfile.lock, gemfiles/ruby34.gemfile.lock, and gemfiles/ruby40.gemfile.lock is 2.2.4.

## Next

Version 2.2.4 is prepared. Commit, then publish so consumers leave 2.2.3. Reproduce the original job example with DEBUG_SQL=1 after the gem is released.

## Source

Consumer report: POLYRUN_EXAMPLE_DEBUG=1 DEBUG_SQL=1 bin/rspec spec/jobs/generate_excel_job_spec.rb:123, NoMethodError loggable_sql? at polyrun-2.2.3/lib/polyrun/rspec/example_debug_instrumentation.rb:14. Same example passed without DEBUG_SQL; ActiveSupport::Notifications query counters used as the local workaround.

https://rubygems.org/gems/polyrun/versions/2.2.3
https://rubygems.org/api/v1/versions/polyrun.json
lib/polyrun/rspec/example_debug_instrumentation.rb
lib/polyrun/rspec/example_debug.rb (ExampleDebug.log_level in the before hook)
lib/polyrun/spec_quality/sql_counter.rb
CHANGELOG.md 2.2.0, 2.2.1, 2.2.3, 2.2.4
docs/SETUP_PROFILE.md DEBUG_SQL row
commit 3e344dc (2.1.3 helpers), 930ba69 (rails logging NameError), 530561c (2.2.1 standalone flags)
