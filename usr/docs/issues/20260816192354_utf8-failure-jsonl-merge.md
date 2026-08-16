# Failure JSONL merge crashes when default encoding is US-ASCII

## Participants

Andrei

## Decisions

Read failure fragments as UTF-8 in FailureMerge, matching the coverage HTML source-line path. Keep locale LANG and LC_ALL as a host workaround, not as the gem contract.

## Effects

run-shards --merge-failures raised Encoding::CompatibilityError in String#strip when File.readlines tagged UTF-8 JSONL as US-ASCII. RSpec JSON File.read then JSON.parse raised Encoding::InvalidByteSequenceError on the same locale. Coverage merge still completed because those fragments stay ASCII-heavy. Worker Playwright or Capybara dumps with box-drawing bytes are valid UTF-8 on disk.

## Next

Ship the UTF-8 read in FailureMerge.rows_from_jsonl_file and rows_from_path. Cut a gem release after merge so consumers on 2.2.2 pick it up.

## Source

Reproduced with LANG=C LC_ALL=C: Encoding.default_external is US-ASCII, default_internal is nil, File.readlines then strip raises Encoding::CompatibilityError invalid byte sequence in US-ASCII. Same class of fix as CHANGELOG 2.1.1 for HTML coverage source files.
