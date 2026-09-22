# Read failure merge JSON as UTF-8

## Participants

Andrei

## Decisions

Pass encoding Encoding::UTF_8 to File.readlines for JSONL fragments and File.read for RSpec JSON. Specs merge a non-ASCII message while Encoding.default_external is US-ASCII.

## Effects

Failure merge no longer depends on process locale for Unicode exception dumps. Coverage HTML already used this encoding argument; failure merge now matches.

## Next

CHANGELOG.md 2.2.3 records the UTF-8 failure merge read. Publish the gem after this release commit lands on main.

## Source

usr/docs/issues/20260816192354_utf8-failure-jsonl-merge.md
lib/polyrun/reporting/failure_merge.rb
spec/polyrun/reporting/failure_merge_spec.rb
