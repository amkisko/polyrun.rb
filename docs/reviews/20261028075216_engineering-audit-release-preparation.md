# Engineering audit and release preparation

## Decisions

- Continue on main while preserving the pre-existing uncommitted changes. Do not commit, tag, push, or publish.
- Retain release version 2.2.6. Reconcile root and appraisal PATH metadata without updating third-party dependency versions.
- Review correctness, executable coverage, workflow triggers and permissions, package boundaries, resource cost, and trace/identity boundaries. Re-audit the changed paths after corrections.

## Effects

- Restore the required lint gate by extracting implicit argument splitting, shard-pattern resolution, and minimum-unique-line checks without changing their behavior. Move repeated timing set construction outside its conditional.
- Move the existing queue recovery and quarantine examples unchanged into file_store_recovery_spec.rb to meet the executable file-length gate. Preserve both cases in the generated suite path list.
- Correct the shard-output notice so it does not promise a per-worker text summary that the sharded formatter suppresses.
- Build and load the optional native merge extension; exercise the native contracts and the existing coverage-merge benchmark at 100 files x 200 lines x 8 fragments, 2 repetitions. Disk merge: 0.066623 CPU seconds and 0.066942 real seconds for both repetitions.
- Fix the release confirmation guard in usr/bin/release.rb so EOF refuses publication. An explicit Enter still selects the displayed default. The process-boundary regression test executes the release script with command execution replaced at the operating-system boundary; no publication command runs against a real service. The shared regression was observed first in Favorites: 2 examples, 1 failure before correction and 2 examples, 0 failures after correction. The release specs pass in every repository.
- Final serial JSON report: 749 examples, 0 failures, 7 pending. Five pending examples require opt-in memory/IPS/StackProf profiling; two require optional ActiveSupport integration. Native contracts: 21 examples, 0 failures.
- Required project checks passed: make test. Environment: Ruby 4.0.2, BUNDLE_PATH=vendor/bundle; the installed native extensions require that Ruby build.
- Build the gem, verify it with Gem::Package#verify, and check that the changelog heading matches the gem version. Compressed package: 157696 bytes; source payload: 581703 bytes across 181 packaged paths. These are compressed versus uncompressed sizes, not interchangeable quantities.
- Cold process measurement on macOS arm64 with /usr/bin/time -l and bundle exec ruby -Ilib: 0.36 CPU seconds, 0.48 elapsed seconds, 33636352 peak RSS bytes. Favorites loads Rails before the engine. Local smoke ceilings: 1 MiB compressed gem, 128 MiB RSS, 2 CPU seconds. All measured values fit those ceilings. CPU seconds are the energy proxy; electricity use was not measured.
- Parse every workflow YAML, verify lockfile own-gem versions, and run git diff --check. All passed. All six assigned repositories remain on main.

## Next

- Push `main` and run `make release` for 2.2.6 (gem push, tag, GitHub release). See `docs/changelogs/20261029102014_release-2-2-6.md`.
- Hosted GitHub Actions and the complete supported Ruby/framework matrix were not executed locally in this review.
- Scope limits: production traffic, production database size and query plans, external service retention, and co-located resource interference were not measured. The local byte/RSS/CPU results do not establish those properties.
- Trace review follows local file/log and protocol emissions. No live customer identities or credentials were used. Data retention and deletion in embedding applications remain host contracts.
- Learned-system training/evaluation and cloud deployment modes do not apply to these library trees. Native memory-boundary mode applies to Polyrun's extension; browser presentation applies to Favorites; HTTP/identity and message companions apply only to repositories that expose those boundaries. Libraries have no independent production health endpoint to assess.

## Source

- AGENTS.md
- .agents/skills/engineering-audit/SKILL.md
- .agents/skills/changelog-update/SKILL.md
- CHANGELOG.md
- Makefile
- spec/README.md
