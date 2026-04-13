# Mandatory parallel / CI testing practices (examples + Polyrun)

These practices are **required** for stable, fast parallel suites. Polyrun APIs support them; your app must wire them correctly.

## 1. Shared assets: pre-build once, never per example

**Goal:** Parallel workers must not each run `vite build`, `rails assets:precompile`, or digest-heavy steps before every group or example.

**Pattern:**

- Run **`script/ci_prepare`** (or `examples/bin/ci_prepare` at the repo root) **once** before the test matrix: compile Vite bundles, Propshaft digest, etc.
- Use **`Polyrun::Prepare::Assets`** (`digest_sources`, `stale?`, `write_marker!`, optional `precompile!`) so a **marker file** records the digest of source trees. Workers skip work when `stale?` is false.
- In CI, **cache** the Polyrun assets **digest marker** (`Polyrun::Prepare::Assets`), `public/assets`, `node_modules/.cache`, and build outputs keyed by lockfiles.

**Anti-pattern:** `before(:each)` that shells out to `rails assets:precompile` or `npm run build`.

## 2. Shared fixtures and factories: deterministic, cheap, process-scoped

**Goal:** Load YAML / seed data **once per process** (or once per suite in a controlled hook), not per example. Avoid redundant factory work.

**Pattern:**

- **`Polyrun::Data::Fixtures`**: `load_directory` / `each_table_in_directory` — read-only YAML; safe to call multiple times in one process (same result). Prefer loading **once** in `before(:suite)` or a support file and reuse structures in memory. For Rails, optional **`apply_insert_all!`** bulk-inserts rows per table via `ActiveRecord::ConnectionAdapters#insert_all`.
- **`Polyrun::Data::CachedFixtures`**: memoize expensive setup (`register` / `fetch`) once per **process** (parallel workers each get their own cache). Use **`reset!`** between suites if you reuse the same process.
- **`Polyrun::Data::ParallelProvisioning`**: assign **`serial`** vs **`parallel_worker`** callbacks (your `truncate` / `load_seed` logic); call **`run_suite_hooks!`** once per process or use **`Polyrun::RSpec.install_parallel_provisioning!`**. Aligns with empty per-worker DBs vs a single shared DB.
- **`Polyrun::Data::FactoryInstrumentation`**: after `require "factory_bot"`, call **`instrument_factory_bot!`** so **`FactoryCounts`** records every factory run.
- **`Polyrun::Data::FactoryCounts`**: uses **class-level** storage; intended for **single-process** serial suites or **one counter per process** in parallel **process** runners. For parallel **threads** in one process, counts can race — use **process-based** parallelism (`parallel_tests`, matrix jobs) or wrap recording in a **Mutex** if you must use threads.
- Prefer **database_cleaner** / transactional tests with **shared connection** discipline; batch-insert fixtures where possible.

**Anti-pattern:** Re-parsing large YAML in every `before(:each)` when data is identical.

## 3. Databases: avoid deadlocks under parallel load

**Goal:** Multiple processes must not contend on the **same** rows or **same** migration locks in conflicting order.

**Pattern:**

- **Separate database per shard** (naming via **`Polyrun::Database::Shard`** / `TEST_ENV_NUMBER` / `POLYRUN_TEST_DATABASE`). Each parallel worker gets a distinct `DATABASE_URL` — no cross-worker row locks.
- Keep **lock acquisition order** consistent if multiple tables are updated (same order in every spec).
- Use **transactional fixtures** (`use_transactional_fixtures = true`) for **unit** tests; integration tests that need **truncation** should still avoid **advisory** deadlocks by not holding locks across **network** calls.
- **Migrations:** run **once** before fan-out; do not run `db:migrate` inside parallel workers concurrently on the **same** DB.

**Anti-pattern:** All workers sharing one `test` database and hammering the same rows.

**Docker:** **`examples/docker-compose.yml`** provisions Postgres with empty template DBs matching each demo’s **`polyrun.yml`**. Use **`examples/script/docker_up.sh`**, set **`PGPORT`** (default mapped port **5433**), then **`examples/script/docker_polyrun_provision_demo.sh`** with a path such as **`simple/simple_demo`** before **`bin/polyrun run-shards`**. **`run-shards`** injects per-shard **`DATABASE_URL`** from **`polyrun.yml`** when **`databases:`** is configured.

## 4. Ruby GVL (global VM lock)

**Goal:** CPU-bound Ruby in one process does **not** scale with **threads**. I/O (DB, HTTP, Playwright) can overlap, but **merge**, **digest**, and pure Ruby hot loops stay on one core per process.

**Pattern:**

- Use **multiple processes** for parallel RSpec (Polyrun **`plan`** splits file lists; each process runs a subset). That sidesteps GVL for **throughput**.
- For **coverage merge**, `Polyrun::Coverage::Merge` is **pure** (no mutable globals); you can merge **disjoint** shard JSON files in **parallel threads** safely if needed, then merge results — but default **`merge_fragments`** is single-threaded and fast enough for most CI.
- **Capybara + Puma:** one app server per process; avoid dozens of **threads** all doing heavy Ruby in the same process for **CPU** work.

**Anti-pattern:** Expecting `Thread.new` × N to speed up **pure Ruby** coverage merging or **digest_sources** on huge trees.

## 5. Capybara system specs and Playwright

**Goal:** Examples use **capybara-playwright-driver** for **system** specs when the **Playwright CLI** is available (`npx playwright --version`, `node_modules/.bin/playwright`, or `PLAYWRIGHT_CLI_EXECUTABLE_PATH`). Install browsers with **`npx playwright install chromium`** (the multi_capybara demo runs this from **`script/ci_prepare`** after `npm install`). There is **no** supported env flag to swap in `rack_test` instead; missing CLI causes system examples to **skip** with an install message.

**Anti-pattern:** Documenting or relying on `SKIP_PLAYWRIGHT=1` to avoid installing Playwright for real browser coverage.

## 6. Multi-protocol apps and partition-friendly specs

**Goal:** Real services expose **REST**, **GraphQL**, and **gRPC** (and browsers via **Capybara**). Example apps should include enough **shared domain code** (e.g. one catalog) so integration specs can assert **parity** across protocols. That gives meaningful **coverage** on each layer and clean **`partition.paths_file`** splits (`spec/grpc` vs `spec/requests` vs `spec/system`) while **`merge-coverage`** still tells one story.

**Pattern:** See **`examples/multi_capybara/multi_demo`** — `spec/integration/catalog_protocol_parity_spec.rb`, named **`using_session`** examples, and **`script/ci_prepare`** for shared Vite + Playwright setup.

## Verification

- **Examples:** Each demo under `examples/*/` should ship a **`script/ci_prepare`** where assets or Vite apply.
- **Polyrun gem:** `spec/polyrun/mandatory_parallel_support_spec.rb` encodes contracts for assets markers, fixture idempotence, shard env separation, and merge purity.
