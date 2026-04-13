# Polyrepo complex demo (`polyrepo_demo`)

Runnable **Rails 8** app under **`examples/complex/`** — the **most complex Polyrun example**:

- **Three SQLite databases**: `primary`, `cache`, `warehouse` (separate files + migration paths).
- **Three Vite client bundles**: `admin/`, `store/`, `portal/` → `public/admin`, `public/store`, `public/portal` (production builds once via **`script/ci_prepare`**).
- **Capybara + Playwright** system specs with **named sessions** (`:admin`, `:store`, `:portal`, `:platform`) — end-to-end coverage lives **only in RSpec** (no separate Playwright/JS test runner).
- **REST**, **GraphQL**, and **gRPC** on the same catalog (see `spec/integration/` and `proto/`).
- **Lattice:** 120 `Demo::Lattice::CellNNN` units under `lib/demo/lattice/` (gitignored; `spec/spec_helper.rb` runs `examples/script/generate_lattice_spec_suite.rb`).

Polyrun path in **`Gemfile`**: `path: "../../.."` (repo root).

```bash
cd examples/complex/polyrepo_demo
bundle install
./script/ci_prepare
RAILS_ENV=test bin/rails db:prepare
bundle exec rspec
```

See **`../README.md`** (complex example overview) and **`../../TESTING_REQUIREMENTS.md`**.
