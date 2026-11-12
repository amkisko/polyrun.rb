# Engineering audit: Quick lifecycle and DSL

## Decisions

Improve `Polyrun::Quick` using Sus/Covered lessons and cross-language teardown practices: suite config hooks, `around`, error-aware `after`, richer predicates, `with`/`subject`, timing summary. Keep stdlib-only runtime.

## Effects

Findings for iteration 1 (lifecycle) and iteration 2 (DSL/reporting).

## Next

Implement with specs first; re-audit after each tranche.

## Source

- Sus: `around`, `after { |error| }`, `config/sus.rb` before/after_tests, Covered `COVERAGE` gate
- Pytest: yield fixtures / finalizers; teardown even on failure; setup failure skips that fixture's teardown
- Jest: `afterEach` runs after failures
- Go: `t.Cleanup` registered at acquire time
- Spectator / behave-style DSLs: around must invoke continuation; `subject` / nested context

## Findings

### F1 No suite config surface

| Field | Content |
|-------|---------|
| Severity | Medium |
| Confidence | High |
| Location | `lib/polyrun/quick/runner.rb` |
| Why it matters | Hosts cannot register suite-level setup/teardown or load-path fixtures without patching Polyrun |
| Kind | Observed fact |
| Smallest credible fix | Load `config/polyrun_quick.rb` with `before_suite` / `after_suite` / `add_load_path` |

### F2 No `around`; `after` ignores error

| Field | Content |
|-------|---------|
| Severity | High for resource leaks |
| Confidence | High |
| Location | `ExampleGroup`, `ExampleRunner` |
| Why it matters | Cleanup that needs failure vs success (kill vs term) cannot branch; no wrap for transactions/timing |
| Kind | Observed fact |
| Smallest credible fix | `around { \|run\| ... run.call }`; `after` via `instance_exec(error, &hook)` |

### F3 Thin matchers / no `subject` / no `with`

| Field | Content |
|-------|---------|
| Severity | Medium (DX) |
| Confidence | High |
| Location | `matchers.rb`, `example_group.rb` |
| Why it matters | Sus-style predicates and subject one-liners are missing; nested context spelling is only `describe` |
| Kind | Observed fact |
| Smallest credible fix | `be` / `be_a` / `raise_exception`; `subject`; `with` alias |

### F4 Reporter has no per-example timing

| Field | Content |
|-------|---------|
| Severity | Low |
| Confidence | High |
| Location | `reporter.rb` |
| Why it matters | Slow examples are invisible without SpecQuality/timing JSON |
| Kind | Observed fact |
| Smallest credible fix | Record duration; print slowest N in summary |

## Pipeline map

```text
ingress (paths / config/polyrun_quick.rb)
  -> before_suite
  -> load files
  -> per example: before -> around* -> body -> after(error)
  -> after_suite(status)
  -> reporter egress
```

## Modes

- Core eight: yes
- Boundary: process/env only; skip physical actuators
- Resource/budget: no new hot-path claim without bench
