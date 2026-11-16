# Preserve exact native coverage counts

## Participants

Current human operator: name requested in the session, awaiting confirmation.

## Decisions

Keep native coverage arithmetic equivalent to the existing Ruby fallback at integer representation and conversion boundaries. Runtime-owned arithmetic is preferable to maintaining a second bounded-number parser.

## Effects

Promote sums that exceed immediate-integer range. Reuse Ruby line-count conversion and preserve the branch-count to_i contract. Read array entries through the host API after conversions that can invoke Ruby. Add regression specs before the fixes and clarify that graph --prove accepts command status rather than establishing a mathematical proof.

Reproduction, exact test commands, results and resource measurements have one home in the live-work note. No release or version change was made.

## Source

- [Live work and validation](../issues/20261116152529_verification-arithmetic-contract.md).
- [Native arithmetic review](../reviews/20261116152529_coverage-integer-contract.md).
