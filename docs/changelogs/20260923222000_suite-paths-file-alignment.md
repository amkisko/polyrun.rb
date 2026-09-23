# Suite selection vs paths_file

## Decisions

Bare `polyrun` resolves the parallel runner from `partition.suite` when set, else from `partition.paths_file` contents, else filesystem auto-detect (`spec/**/*_spec.rb` before `test/**/*_test.rb`, then Quick). `run-shards` exits 2 when path list and a recognizable RSpec/Minitest/Quick command disagree. `parallel-minitest` and `parallel-quick` are registered CLI subcommands.

## Effects

Repos with both trees and a Minitest `paths_file` no longer default to `bundle exec rspec` while sharding Minitest files. Explicit suite vs paths_file mismatch fails closed.

## Next

None.

## Source

Implementation: `lib/polyrun/partition/suite.rb`, `lib/polyrun/cli/default_run.rb`, `lib/polyrun/cli/run_shards_planning.rb`, `lib/polyrun/cli.rb`.
