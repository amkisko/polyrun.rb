# Polyrun template pack (for `polyrun init`)

Source files ship in the gem under `lib/polyrun/templates/` so `polyrun init` works from a RubyGems install, not only from a git checkout.

| Profile | `--profile` | Output file (default) | Use case |
|---------|-------------|------------------------|----------|
| Minimal gem | `gem` | `polyrun.yml` | Library / no Rails `prepare` / optional coverage collector only |
| Rails + prepare | `rails` | `polyrun.yml` | `prepare.recipe: shell` + placeholder `prepare.command`; optional `databases:` commented |
| Rails prepare rake | `rails-prepare-task` | `lib/tasks/polyrun_prepare.rake` | Thin rake wrapper around `polyrun prepare`; honors `POLYRUN_SKIP_PREPARE` |
| CI matrix | `ci-matrix` | `polyrun.yml` | Partition-only YAML; document matrix and `merge-coverage` job separately |
| Host doc | `doc` | `POLYRUN.md` | Starter doc with Model A vs Model B CI and canonical commands |

## Commands

```bash
polyrun init --list
polyrun init --profile gem -o polyrun.yml
polyrun init --profile rails -o polyrun.yml
polyrun init --profile rails-prepare-task
polyrun init --profile ci-matrix -o polyrun.yml
polyrun init --profile doc -o POLYRUN.md
polyrun init --profile gem --dry-run   # print template; no write
```

Named suites in one `polyrun.yml`:

```yaml
suites:
  unit:
    workers: 4
    partition:
      paths_build:
        all_glob: spec/unit/**/*_spec.rb
```

Select with `polyrun --suite unit start` or `POLYRUN_SUITE=unit`. Inspect with `polyrun doctor`.

Full checklist (project type, DB, prepare, coverage): [../../docs/SETUP_PROFILE.md](../../docs/SETUP_PROFILE.md).
