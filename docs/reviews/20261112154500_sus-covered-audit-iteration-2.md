# Engineering audit iteration 2: Sus and Covered

## Decisions

After landing RFC-0008 code: tighten Covered::Sus conflict skip in `SusSupport.install_coverage!`, refresh help/docs, assert CLI help lists `parallel-sus` / `ci-shard-sus` / `COVERAGE`.

## Effects

| Field | Content |
|-------|---------|
| Severity | Medium |
| Confidence | High |
| Location | `SusSupport.install_coverage!` |
| Why it matters | Dual `Coverage.start` when Covered::Sus and Collector both run |
| Kind | Observed fact (mitigated) |
| Smallest credible fix | Skip Collector start when Covered::Sus is already an ancestor of Sus::Config; warn |

Deferred (unchanged from iteration 1 F4 / RFC unresolved):

| Field | Content |
|-------|---------|
| Severity | Low until a host asks |
| Confidence | High |
| Location | Coverage merge ingress |
| Why it matters | `.covered.db` MessagePack is not a Polyrun fragment |
| Kind | Observed fact |
| Smallest credible fix | Defer import; keep JSON fragments as shard merge contract |

| Field | Content |
|-------|---------|
| Severity | Low |
| Confidence | Medium |
| Location | SpecQuality / Sus |
| Why it matters | No per-example Sus SpecQuality installer yet |
| Kind | Inference (no host request in this episode) |
| Smallest credible fix | Later installer mirroring MinitestHook when demand appears |

## Next

- SpecQuality Sus hooks only with a concrete host need
- `.covered.db` import only with a stdlib or vendored unpacker plan

## Source

- `docs/reviews/20261112153400_sus-covered-engineering-audit.md`
- `rfcs/0008-sus-suite-and-covered-coverage-bridge.md`
