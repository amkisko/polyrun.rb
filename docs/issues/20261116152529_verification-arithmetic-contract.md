# Native coverage arithmetic contract

## Participants

Current human operator: name requested in the session, awaiting confirmation.

## Decisions

Correct the observed native/fallback arithmetic disagreement within the existing contract. Preserve zero runtime gem dependencies, Ruby ownership, and current CLI fields. Polyrun fully implements absorbed capabilities. Keep product documentation focused on Polyrun's own behavior; external product comparisons and shared review guidance belong outside this repository.

## Effects

The [review](../reviews/20261116152529_coverage-integer-contract.md) owns the arithmetic findings. The [ownership plan](../plans/20261116152529_formal-verification-extension.md) owns the boundary for future checking capabilities.

Native coverage sums now promote beyond immediate-integer range. Non-integer line counts use the existing Ruby conversion helper. Branch counts preserve the fallback's to_i conversion semantics. The expanded conversion path exposed cached array pointers surviving a Ruby callback: replacing the input during to_int returned [3, 1, 1, 1] rather than [3, 4, 5, 6]. Array entries are now read through the host API on each iteration. A failing regression spec preceded this correction too.

The command guide explains the meaning of --prove, the limits of receipts, and the selected command's responsibility to reject failed or incomplete checks. This clarifies the existing subprocess contract.

### Observed validation

Environment: arm64-darwin24, Ruby 4.0.2, existing native extension. Baseline revision: da71b60599ebb0c8680c3a487d49f65800546487. No dependency install was performed.

- bundle exec rspec spec/polyrun/coverage/native_integer_contract_spec.rb before the fix: exit 1, 3 examples, 3 failures, seed 34522.
- bundle exec rspec spec/polyrun/coverage/native_integer_contract_spec.rb:36 before correcting callback array access: exit 1, 1 example, 1 failure, seed 20523.
- make native-extension: exit 0; compiled and loaded the extension after each C edit.
- bundle exec rspec spec/polyrun/coverage/native_integer_contract_spec.rb spec/polyrun/coverage/merge_native_spec.rb spec/polyrun/coverage/merge_spec.rb after the final C edit: exit 0, 35 examples, 0 failures, seed 30247.
- RUBOCOP_CACHE_ROOT set to a writable temporary cache, bundle exec rubocop: exit 0, 368 files inspected, no offenses.
- bundle exec rbs -I sig validate: exit 0, no diagnostics.
- bundle exec rspec --format progress --out "$test_log", with test_log pointing to a temporary file: exit 0, seed 38000, no failure markers. The suite's sharded-formatter specs install a global text-summary silencer, so this run did not print an example-count summary; no whole-suite count is claimed.
- git diff --check: exit 0, no whitespace errors.

An initial RuboCop invocation could not create its default cache outside the workspace; the writable temporary-cache invocation completed. One missing ternary-expression parenthesis was corrected before the final lint run. An initial temporary extension build selected system Ruby outside the checkout; rebuilding with the checkout's Ruby executable succeeded. Neither was treated as an upstream dependency defect.

### Resource comparison

Expensive unit: coverage merging at 110 files, 310 lines per file, 8 fragments, 5 repetitions per benchmark row. Preserve exact arithmetic at boundary values; do not trade correctness for fixed-width wraparound. This work does not set or change a continuous delivery ceiling.

The [measurement artifact](../../benchmarks/coverage-integer-contract.json) freezes eight runs in before/after/after/before/before/after/after/before order, including raw benchmark output, process counters, row CPU/wall medians, process peak RSS, binary sizes, source hashes and driver hash. Both versions used the same Ruby executable and driver, preloading either the baseline extension built in a temporary directory or the final extension. The whole-suite test process had exited before this comparison. Network traffic and electricity were not instrumented; CPU time is an energy proxy.

The measured inner command was /usr/bin/time -lp "$ruby" -r "$extension" benchmarks/merge_coverage.rb, with MERGE_FILES=110, MERGE_LINES=310, MERGE_FRAGMENTS=8 and MERGE_REPS=5 in its environment. ruby identified the checkout's Ruby executable and extension identified one of the two separately built binaries. A temporary Ruby driver invoked that command with argument arrays, alternated the revisions, parsed its output and wrote the artifact. Rows include fixture construction, and peak RSS covers the whole benchmark process. Small mixed timing changes on one host do not establish a speed improvement or regression.

The sandbox blocked macOS time -l resource counters. The same local measurements completed with authorized sandbox escalation. No automatic approval rejection occurred.

## Next

Confirm the human operator name. Keep the corrected arithmetic and regression tests in Polyrun. The scoped correction and validation are complete. No commit, release, publication, package install, or new verification CLI was performed.

## Source

- [Native arithmetic review](../reviews/20261116152529_coverage-integer-contract.md).
- [Design-only plan](../plans/20261116152529_formal-verification-extension.md).
- [Regression specs](../../spec/polyrun/coverage/native_integer_contract_spec.rb).
- [Coverage merge benchmark](../../benchmarks/merge_coverage.rb).
- [Frozen before/after measurements](../../benchmarks/coverage-integer-contract.json).
