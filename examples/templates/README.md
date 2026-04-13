# Polyrun template pack (for `polyrun init`)

Source files ship in the gem under `lib/polyrun/templates/` so `polyrun init` works from a RubyGems install, not only from a git checkout.

| Profile | `--profile` | Output file (default) | Use case |
|---------|-------------|------------------------|----------|
| Minimal gem | `gem` | `polyrun.yml` | Library / no Rails `prepare` / optional coverage collector only |
| Rails + prepare | `rails` | `polyrun.yml` | `prepare.recipe: shell` + placeholder `prepare.command`; optional `databases:` commented |
| CI matrix | `ci-matrix` | `polyrun.yml` | Partition-only YAML; document matrix and `merge-coverage` job separately |
| Host doc | `doc` | `POLYRUN.md` | Starter doc with Model A vs Model B CI and canonical commands |

## Commands

```bash
polyrun init --list
polyrun init --profile gem -o polyrun.yml
polyrun init --profile rails -o polyrun.yml
polyrun init --profile ci-matrix -o polyrun.yml
polyrun init --profile doc -o POLYRUN.md
polyrun init --profile gem --dry-run   # print template; no write
```

Full checklist (project type, DB, prepare, coverage): [../../docs/SETUP_PROFILE.md](../../docs/SETUP_PROFILE.md).
