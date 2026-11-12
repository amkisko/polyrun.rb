# RFC 0007: Rename RSpec and Minitest wiring to *Support

- Feature Name: test-framework-support
- Type: Standards Track
- Status: Stable
- Created: 2026-11-12
- Author: Andrei Makarov
- Relates: RFC 0002

## Summary

Rename `Polyrun::RSpec` to `Polyrun::RSpecSupport` and `Polyrun::Minitest` to `Polyrun::MinitestSupport`. Move opt-in requires to `polyrun/rspec_support` and `polyrun/minitest_support`. Nested RSpec helpers move under `RSpecSupport`. Hard cut: no aliases, no deprecation stubs for the old constants or require paths.

## Motivation

`module Polyrun; module RSpec` shadows `::RSpec` for nested constant lookup. Bare `RSpec.configure` under `Polyrun` binds to `Polyrun::RSpec` and raises `NoMethodError` for `configure` (seen in `RspecJunit.install!`). Qualifying `::RSpec` patches one site; the name keeps the trap. The modules are installer and support surfaces, not the gems. The same naming pattern applies to `Polyrun::Minitest` versus `::Minitest`.

## Guide-level explanation

Before:

```ruby
require "polyrun/rspec"
Polyrun::RSpec.install_worker_ping!

require "polyrun/minitest"
Polyrun::Minitest.install_worker_ping!
```

After:

```ruby
require "polyrun/rspec_support"
Polyrun::RSpecSupport.install_worker_ping!

require "polyrun/minitest_support"
Polyrun::MinitestSupport.install_worker_ping!
```

Nested RSpec types:

- `Polyrun::RSpec::ExampleDebug` -> `Polyrun::RSpecSupport::ExampleDebug`
- `Polyrun::RSpec::ShardedFormatterCompat` -> `Polyrun::RSpecSupport::ShardedFormatterCompat`
- `Polyrun::RSpec::ActiveRecordTimeoutRecovery` -> `Polyrun::RSpecSupport::ActiveRecordTimeoutRecovery`

Installer method names and behavior stay the same.

## Reference-level explanation

Public contract after this RFC:

- Require paths: `polyrun/rspec_support`, `polyrun/minitest_support`
- Constants: `Polyrun::RSpecSupport`, `Polyrun::MinitestSupport`
- Nested modules under `Polyrun::RSpecSupport` as listed above
- Source: `lib/polyrun/rspec_support.rb`, `lib/polyrun/rspec_support/*.rb`, `lib/polyrun/minitest_support.rb`
- Signatures: `sig/polyrun/rspec_support.rbs`, `sig/polyrun/minitest_support.rbs`

Removed from the public contract:

- `Polyrun::RSpec`, `Polyrun::Minitest`
- Require paths `polyrun/rspec`, `polyrun/minitest`
- Nested constants under `Polyrun::RSpec`

Fail mode: old requires and constants raise `LoadError` / `NameError`. No soft alias and no deprecation stub that keeps the old name working.

Library code that means the gem keeps using `::RSpec` and `::Minitest`.

## Registrar

- `Polyrun::RSpecSupport` and its `install_*` methods
- `Polyrun::MinitestSupport` and its `install_*` methods
- Requires: `polyrun/rspec_support`, `polyrun/minitest_support`
- Nested under RSpecSupport: `ExampleDebug`, `ShardedFormatterCompat`, `ActiveRecordTimeoutRecovery`

Retired: `Polyrun::RSpec`, `Polyrun::Minitest`, requires `polyrun/rspec`, `polyrun/minitest`.

## Drawbacks

Breaking change for every host on the old constants or require paths. Docs, examples, templates, and RBS move in the same release. Wide mechanical replace.

## Rationale and alternatives

- Keep old names and only qualify `::RSpec` / `::Minitest`: cheap, leaves the shadow.
- `*Compat`: clear but reads as a temporary shim.
- `*Support`: states the role without claiming to be the gem.
- Alias for one release: rejected; hard cut only.
- Rename only RSpec: rejected; keep RSpec and Minitest naming symmetric.

## Prior art

This repository already qualifies `::RSpec` and `::Minitest` in installer code. `ShardedFormatterCompat` already signals support wiring. Other gems avoid nesting the gem's own top-level constant under their namespace when the gem is a peer dependency.

## Unresolved questions

None.

## Future possibilities

Audit other `Polyrun::*` names that collide with popular gem tops and rename only when nested lookup has bitten or is likely.
