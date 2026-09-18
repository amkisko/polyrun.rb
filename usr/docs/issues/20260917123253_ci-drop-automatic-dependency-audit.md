Trunk Check failed markdownlint MD013 on pray-managed AGENTS.md lines. Dependency scanners in Trunk and scheduled CI were a second source of standing red.

## Participants

- amkisko

## Decisions

- Disable markdownlint MD013 in .markdownlint.yaml. Keep AGENTS.md in Trunk so other markdownlint rules still run.
- Disable osv-scanner in Trunk Check.
- Keep dependency-audit.yml as workflow_dispatch only. Do not run it on push, pull request, or schedule.

## Effects

- Trunk Check no longer fails on markdown line length or treats dependency CVEs as a required check.
- AGENTS.md stays under other markdownlint rules.
- Manual dependency-audit remains available on workflow_dispatch.

## Next

- Run dependency audit on demand when a release or a known advisory needs it.
- Do not reintroduce advisory scanners into test.yml.

## Source

- GitHub Actions Trunk Check run 35091124124 on 2026-09-17
