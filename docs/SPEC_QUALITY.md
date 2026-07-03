# Spec quality (experimental)

Per-example signals for hollow specs, redundant line churn, and resource-heavy examples. Opt-in only.

## Enable

```bash
export POLYRUN_SPEC_QUALITY=1
export POLYRUN_COVERAGE=1   # stdlib Coverage must be running for line deltas
```

In `spec/spec_helper.rb` (after coverage starts):

```ruby
require "polyrun/rspec"
Polyrun::RSpec.install_spec_quality!
```

Optional config: `config/polyrun_spec_quality.yml` (see `lib/polyrun/templates/polyrun_spec_quality.yml`).

## Parallel runs

```bash
polyrun run-shards --workers 4 --merge-spec-quality -- bundle exec rspec
```

Workers receive `POLYRUN_SPEC_QUALITY_FRAGMENTS=1`. Each writes `coverage/polyrun-spec-quality-fragment-<shard>.jsonl`. Parent merges to `coverage/polyrun-spec-quality.json` and prints a summary.

Manual merge / report:

```bash
polyrun merge-spec-quality -o coverage/polyrun-spec-quality.json
polyrun report-spec-quality -i coverage/polyrun-spec-quality.json --top 20
polyrun report-spec-quality -i coverage/polyrun-spec-quality.json --profile cpu,mem,io
```

## Cost

`Coverage.peek_result` runs before and after every example. This adds overhead on large suites. Reduce with:

```bash
export POLYRUN_SPEC_QUALITY_SAMPLE=0.1   # instrument ~10% of examples
```

## Environment

| Variable | Meaning |
|----------|---------|
| `POLYRUN_SPEC_QUALITY` | Master opt-in |
| `POLYRUN_SPEC_QUALITY_DISABLE` | Force off |
| `POLYRUN_SPEC_QUALITY_FRAGMENTS` | Set in workers by `--merge-spec-quality` |
| `POLYRUN_SPEC_QUALITY_SAMPLE` | `0.0`–`1.0` (default `1.0`) |
| `POLYRUN_SPEC_QUALITY_STRICT` | Exit non-zero when gate thresholds fail |
| `POLYRUN_SPEC_QUALITY_SQL_COUNTER` | Count SQL via ActiveSupport when loaded |
| `POLYRUN_SPEC_QUALITY_PROFILE` | Comma list: `cpu`, `mem`, `io`, `wall` |
| `POLYRUN_MERGE_SPEC_QUALITY` | Merge after `run-shards` (like `POLYRUN_MERGE_FAILURES`) |

## Profiling notes

- **CPU**: `Process.times` user + system delta per example (all platforms).
- **Memory**: `GC.stat` allocation / heap live slots (proxy, not RSS).
- **IO**: Linux `/proc/self/io` read/write bytes; omitted elsewhere.

## Pause / resume

Skip attribution for inline jobs or shared setup:

```ruby
Polyrun::SpecQuality.pause do
  # code not attributed to the current example
end
```

## Sampling

`POLYRUN_SPEC_QUALITY_SAMPLE=0.1` instruments roughly 10% of examples (reduces `peek_result` overhead). See `benchmark/spec_quality_peek.rb` for a local cost estimate.

## CI gates

Set in `config/polyrun_spec_quality.yml`:

- `minimum_unique_lines_per_example`
- `max_zero_hit_examples`
- `max_hot_line_overlap`

Enable `strict: true` or `POLYRUN_SPEC_QUALITY_STRICT=1`.
