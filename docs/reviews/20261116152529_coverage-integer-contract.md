# Native coverage integer contract review

## Participants

Current human operator: name requested in the session, awaiting confirmation.

## Decisions

Preserve exact native coverage arithmetic and the existing Ruby fallback contract. Keep the implementation within Polyrun and use runtime-owned integer operations. Keep product documentation focused on Polyrun's behavior, limits and executable evidence.

## Effects

Severity: medium. Confidence: high. Stage: coverage input and aggregation. Location: ext/polyrun_coverage_merge/coverage_merge.c, line_hit_to_i, merge_line_hits and merge_line_arrays. Evidence kind: observed.

On the observed 64-bit host, merging two arrays each containing 4611686018427387903 returned [-2] natively and [9223372036854775806] in the Ruby fallback. Converting a decimal count representing 10**100 and adding one returned [0] natively. These extreme inputs exposed silent disagreement with the existing contract.

The correction promotes sums beyond immediate-integer range and reuses the existing line-count conversion helper. Branch counts retain their distinct to_i conversion contract. A further regression test exposed cached array pointers surviving a conversion callback that replaced the input. Array entries are now read through the host API on each iteration.

Failing regression specs preceded the corrections. The final focused run passed 35 examples with no failures. Exact commands, earlier failures, whole-suite status and resource comparisons are recorded in the linked live-work note.

The comparison measurements contain small timing differences in both directions on one host. They do not establish a performance improvement. No new runtime dependency or public command was added.

The person-facing surface is docs/QUALITY.md. Its checking description now distinguishes command success, tested executions and the staged-byte receipt. No interactive surface changed; rendered document layout was not assessed.

## Next

Confirm the human operator name. Keep future checking capabilities within a complete, explicitly bounded product contract.

## Source

- [Live work and validation](../issues/20261116152529_verification-arithmetic-contract.md).
- [Ownership plan](../plans/20261116152529_formal-verification-extension.md).
- [Regression specs](../../spec/polyrun/coverage/native_integer_contract_spec.rb).
- [Before/after measurements](../../benchmarks/coverage-integer-contract.json).
