# Multi-Capybara / dual Vite example

**`multi_demo`** — Rails app with **multiple databases** (**`primary`** + **`cache`**, same SQLite layout as **`examples/multi_database`**) plus **two separate front-end build pipelines** and a **super-platform** demo hub (**`/platform`**) with business verticals (banking, clinic, library, ledger, blog, forum, assistant, analytics) for realistic coverage stories.

- **`/admin`** and **`/store`** namespaces with compiled bundles under `public/admin` and `public/store`.
- **Two Vite projects**: `admin/vite.config.ts` and `store/vite.config.ts` (TypeScript entrypoints — client components as TS bundles; add `react` npm deps in a real app).
- **npm** scripts: `npm run build` builds both; checked-in `public/` assets let `bundle exec rspec` pass without Node.
- **Capybara** named sessions `using_session(:admin)` / `:store` / `:platform` (**multiple Capybara sessions** on one Puma server; requires Playwright — see below).

For an **Angular** + **Vite** polyrepo (separate CLI, AoT, `angular.json`), see **`../complex/README.md`** (`apps/ops-console` sketch).

## Spec volume

`lib/demo/lattice/` — 120 paired lattice specs (gitignored; generated from `spec/spec_helper.rb`) plus REST/GraphQL/gRPC/system specs for realistic `partition.paths_file` lists.

## Polyrun features

- **`polyrun.yml`**: `partition`, `prepare`, `databases` (shard naming for Postgres CI).
- **`script/ci_prepare`**: runs **`npm install` / `npm run build`** when needed, **`npx playwright install chromium`**, then asset digest marker — **once** before **`run-shards`**.
- **Coverage**: `Polyrun::Coverage::Rails` in `spec_helper` → **`merge-coverage`** after parallel workers (see **`../README.md`**).

## Commands

```bash
cd multi_demo
bundle install
./script/ci_prepare   # once: npm build + digest marker — do not repeat per parallel worker
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec
```

### Parallel + merged coverage

```bash
bundle exec polyrun -c polyrun.yml parallel-rspec --workers 4
# or: ./bin/rspec_parallel
```

## Why two Vite roots?

Each frontend can have its own dependencies, env, and build pipeline (e.g. admin vs storefront). Rails serves compiled assets from `public/`; `bin/dev` can run `vite` in watch mode per app if you add a Procfile.

## Multi-Capybara + Playwright (production wiring)

Large apps typically wire Playwright with optional browser types, **suite-level** asset/Playwright prep, and **URL options** for mailers. This demo mirrors those patterns:

| Mechanism | Where |
|-----------|--------|
| Registered `Playwright` driver with `BROWSER`, `HEADFUL`, `CAPYBARA_MAX_WAIT`, `CAPYBARA_ARTIFACTS`, `PLAYWRIGHT_CLI_EXECUTABLE_PATH` | `spec/support/capybara_playwright.rb` |
| `PlaywrightEnv` CLI detection + skip message when missing | `spec/support/playwright_env.rb` |
| `rails_helper` sets `default_url_options[:host]` from `Capybara.server_host` around system examples | `spec/rails_helper.rb` |
| `DemoTestEnv.before_system_suite` hook for per-process setup (extend like `TestEnv.before_suite` if you add digests) | `spec/support/demo_test_env.rb` |
| Named sessions **admin / store / platform** | `spec/system/multi_frontends_spec.rb` |

`using_session` is **Capybara’s** API for isolated browser sessions (separate cookies/storage) while sharing one Rails app — useful for admin vs storefront vs platform hub without spinning up extra processes.

## REST, GraphQL, gRPC, and multi-client coverage

The app exposes the **same catalog** and **platform verticals** over several transports so you can split specs by directory (`spec/requests`, `spec/grpc`, `spec/integration`, `spec/system`) and still merge **Polyrun** coverage JSON fragments (`coverage/polyrun-fragment-*.json` → **`merge-coverage`**) after **`run-shards`**:

| Transport | Demo surface |
|-----------|----------------|
| `REST` | `GET /api/v1/health`, `GET /api/v1/catalog`, `GET /api/v1/items`, `GET /api/v1/items/:slug` |
| GraphQL | `POST /graphql` — `health`, `verticals`, `items`, `item(slug:)` |
| gRPC | In-process `demo.v1.Demo` — `Health`, `ListItems`, `GetItem` (`proto/demo/v1/demo.proto`, `./script/grpc_codegen`) |

Integration examples: **`spec/integration/catalog_protocol_parity_spec.rb`**, **`spec/integration/multi_client_flow_spec.rb`**. They exercise **multi-client** flows in one process (typical for a single shard’s coverage), while Polyrun splits **files** across workers for wall-clock time and **merges** coverage JSON for a single report.

## Polyrun: performance and developer experience

- **Throughput:** `partition.paths_file` + `run-shards` runs disjoint spec groups in parallel; each shard still runs **Capybara + Puma + Playwright** in one process, which matches how teams usually parallelize.
- **Coverage:** `Polyrun::Coverage::Rails` writes **`coverage/polyrun-fragment-<shard>.json` → `merge-coverage`** so REST + GraphQL + gRPC + system lines all contribute to one merged view.
- **Prepare once:** `script/ci_prepare` builds Vite bundles and installs Chromium **once** per CI job (see **`../TESTING_REQUIREMENTS.md`**), not per worker.
