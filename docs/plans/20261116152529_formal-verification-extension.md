# Quality capability ownership

## Participants

Current human operator: name requested in the session, awaiting confirmation.

## Decisions

Polyrun is Ruby-core first and fully implements the capabilities it absorbs. Keep product documentation focused on Polyrun's own behavior and contracts. Shared review procedures and comparisons with external products belong outside this repository.

### Executable behavior

Keep test execution, coverage, mutation, graph staging and generic checking commands under their existing contracts. Add independently specified boundary, algebraic, differential and state-transition tests where observed defects or missing contracts justify them. Prefer the existing test framework and runtime before introducing another abstraction.

Candidate properties include exact coverage arithmetic, partition multiset preservation, pinned-shard behavior, interleaved heap operations and recovery after interrupted writes. Turn confirmed executable counterexamples into ordinary regression specs. These checks must run with the project's existing dependencies.

A consumer can supply a checking command through the existing generic command workflow. Polyrun runs that command and reports its status. This does not make the command's implementation part of Polyrun.

### Scope of future checks

Consider a narrowly scoped first-party checker only for a demonstrated Polyrun need. Define its supported input domain, complete published contract, resource limits and refusal behavior before implementation. Implement and test the whole declared contract.

Keep evidence precise: a finite test domain remains finite, a source fingerprint binds bytes, and a successful command establishes only the checks it actually performed. Do not describe those results as general program verification.

## Next

Keep the arithmetic correction and regression specs in this repository. Require a focused product decision before adding another checking capability. Keep RFC-0010 Experimental under its existing adoption requirement.

## Source

- [Native arithmetic review](../reviews/20261116152529_coverage-integer-contract.md).
- [Current graph and quality contract](../../rfcs/0010-graph-and-quality-orchestration.md).
