# Pressure benchmarking binding (polyrun)

- measure command: `env -u BUNDLE_PATH SCENARIO=measure bundle exec ruby benchmarks/cooker.rb`
- self-test command: `env -u BUNDLE_PATH SCENARIO=calibrate bundle exec ruby benchmarks/cooker.rb`
- ceilings file: `benchmarks/ceilings.json`
- load axis: coverage fragment count × files × lines (`MERGE_FRAGMENTS`, `MERGE_FILES`, `MERGE_LINES`)
- samples-per-load default: 3 (`SAMPLES`)
- min episode iterations: 10 (`COOKER_N`)
- propose-basis: median × headroom 1.15 for `wall_s`, `cpu_s`, `allocated_objects`, `storage_delta_bytes`
- Memory probe class: `process_lifetime`
- network: `not_in_scope` (local disk fixtures only)
- primary series default: `allocated_objects` (hot-path merge cost)
- gate / propose / write: `SCENARIO=gate|propose|write` on `benchmarks/cooker.rb`
