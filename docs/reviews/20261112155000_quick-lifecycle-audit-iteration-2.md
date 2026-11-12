# Engineering audit iteration 2: Quick DSL and timing

## Decisions

After lifecycle hooks landed: confirm predicates, `with`/`subject`, reporter slowest list, `add_load_path`, and fail-closed around without `run.call`. Align with suite teardown always running after `before_suite` (ensure).

## Effects

| Field | Content |
|-------|---------|
| Severity | Medium |
| Confidence | High |
| Location | `ExampleRunner#invoke_arounds` |
| Why it matters | Around that skips continuation silently skips the example |
| Kind | Observed fact (mitigated) |
| Smallest credible fix | Fail the example when `run.call` was not invoked |

| Field | Content |
|-------|---------|
| Severity | Low |
| Confidence | High |
| Location | `Reporter#print_slowest!` |
| Why it matters | Slow examples invisible in default summary |
| Kind | Observed fact (mitigated) |
| Smallest credible fix | Print up to 5 examples >= 0.05s |

Deferred: before_all/after_all per group; YAML suite config under `polyrun.yml`; Covered persist import for Quick.

## Next

Changelog + RFC index; broader Quick/CLI specs green.

## Source

- `rfcs/0009-quick-lifecycle-and-dsl.md`
- `docs/reviews/20261112154600_quick-lifecycle-engineering-audit.md`
