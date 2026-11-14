# Native quality pressure binding

The local workload performs native Polyrun graph indexing, actual mutation generation and test execution, and Ruby call observation. It requires only the checkout and Ruby. Load L creates L source files and performs L times 1,000 observed calls; mutation selection stays fixed at one method. This is a mixed load ladder, not an isolated graph or mutation scalability claim.

- Calibrate before baseline: `ruby benchmarks/quality.rb self-test`.
- Baseline: `LOAD=5 SAMPLES=3 ruby benchmarks/quality.rb measure`.
- Stress and proposal: `LOAD=50 SAMPLES=3 ruby benchmarks/quality.rb propose`.
- Gate: `LOAD=50 SAMPLES=3 ruby benchmarks/quality.rb gate benchmarks/quality-ceilings.json`.
- Replay ten temporary optimize/prove candidates, then gate production separately: `ruby benchmarks/quality_trials.rb`.
- Full edit and mutation smoke: `ruby benchmarks/quality_smoke.rb`.

The meter self-test checks distinct known medians and p95 values for every named series, a direct command wall comparison, and the RSS probe. Three samples per load are mandatory for measure, propose, and gate; minimum episode length is ten source-change cycles. The per-series proposal basis is maximum times 1.15. Promote a proposal by explicitly updating benchmarks/quality-ceilings.json only after calibration and review. The trials never change that file. The observation primary tightens from the initial experimental recorder's measured stress envelope to the fixed production ceiling before the ten trials. Other series keep their fixed proposal limits. A failed primary remains primary until its next proof.

Series are wall_s, cpu_s, peak_rss_bytes, storage_bytes, graph_wall_s, mutation_wall_s, and observe_wall_s. CPU includes the probe's own CPU and reaped child counters. RSS uses the OS time utility around one complete workload subprocess: memory_probe_class is process_lifetime. It is not a sum of concurrent subprocess RSS and does not isolate stage memory. Storage includes fixture source, index, and observation bytes; gem package bytes are reported separately. Network is not_in_scope. No physical energy measurement is made.

Run samples without a concurrent test suite. Other host activity remains uncontrolled; the episode cannot establish a universal performance bound or small timing gain. Calibration, baseline, raw samples, proposals, cycle failures, source hashes, and final production gate are retained in benchmarks/quality-episode.json. The earlier native episode remains historical evidence for its recorded source digest. Configuration follow-up samples belong in benchmarks/quality-configuration-episode.json. Rejected alternatives run only in a temporary checkout. QUALITY_EPISODE_OUTPUT can select a separate report path. The checked-in native ceilings start a new workload episode and are not performance comparisons with earlier prototypes.
