# Failure JSONL merge crashes when default encoding is US-ASCII

## Participants

Andrei

## Decisions

Read failure fragments as UTF-8 in FailureMerge, matching the coverage HTML source-line path. Keep locale LANG and LC_ALL as a host workaround, not as the gem contract.

## Effects

run-shards --merge-failures raised Encoding::CompatibilityError in String#strip when File.readlines tagged UTF-8 JSONL as US-ASCII. RSpec JSON File.read then JSON.parse raised Encoding::InvalidByteSequenceError on the same locale. Coverage merge still completed because those fragments stay ASCII-heavy. Worker Playwright or Capybara dumps with box-drawing bytes are valid UTF-8 on disk.

## Next

UTF-8 read is on main. Version 2.2.3 is prepared; publish so consumers leave 2.2.2.

## Source

Reproduced with LANG=C LC_ALL=C: Encoding.default_external is US-ASCII, default_internal is nil, File.readlines then strip raises Encoding::CompatibilityError invalid byte sequence in US-ASCII. Same class of fix as CHANGELOG 2.1.1 for HTML coverage source files.
