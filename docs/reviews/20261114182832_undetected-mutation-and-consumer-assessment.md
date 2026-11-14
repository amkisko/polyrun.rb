# Undetected-mutation and consuming-project assessment

## Participants

Andrei Makarov (@amkisko).

## Decisions

Treat the curated self-mutation Next item as an assessment, not an open-ended detection pass. Classify each full-operator undetected case as a detectable suite gap, a redundant production check, or an accepted behavioral equivalent. Keep the CI self gate on the operator family after the assessment. Do not promote RFC-0010 off Experimental yet.

Consumer readiness for Experimental retention requires: self-checkout exercise, a standalone packaged-gem path, and at least one external-shaped project indexing without host-path mistakes. Rails demo bundles are not required for graph index evaluation.

Use detected and undetected in prose. Keep report field names and codes `killed`, `survived`, `KILLED`, and `SURVIVED` as identifiers only. Do not apply organism or life metaphors to programs or hosts in durable notes.

## Effects

Full-operator inventory against the curated subjects started at 87 mutations, 65 detected, 22 undetected. Strengthening the self-suite command and contracts reduced that to 84 detected and 3 undetected, then 2 accepted equivalents after removing a redundant master.key equality that end_with?(".key") already covered.

Detectable suite gaps closed in specs: invalid subject messages, unknown selectors, max_subjects ceiling, observation size and invalid provenance, non-mapping tool settings, multi-error join separators, hidden and key-file staging, and exact invalid or unknown setting text.

Accepted equivalents that remain under full operators:

- emptying the ceilings key name still fails closed through generic nested validation
- emptying the "*" wildcard guard still matches through File.fnmatch on selectors that contain *
- both keep fail-closed or same observable selection under the current contracts

Consuming-project checks:

- temporary one-file project with graph.enabled indexed successfully
- examples/simple/simple_demo indexed 5 nodes via relative --root from the repository root after fixing root expansion
- package specs remain the packaged-gem consumer proof
- simple_demo Rails bundle was not installed here; partition and Rails runtime evaluation stay out of scope for this episode

Bug found and fixed during consumer evaluation: a relative --root was re-expanded against the already selected root and produced a doubled path. CLI now absolute-expands --root only when the flag is present, and does not inject Dir.pwd over a configured root.

Self CI gate: make mutate with operators [operator] remains green (7 detected, 0 undetected).

Prose audit on the quality docs set replaced organism and life wording (lives, fresh copy, contaminated, reaped, process-lifetime, dogfood, kill/survive in running text) with instrument wording. Report identifiers stay quoted. Stale Next text in the self-exercise review now points here.

### Validation

- bundle exec rspec spec/polyrun/quality/configuration_spec.rb spec/polyrun/quality/adoption_cli_spec.rb: exit 0; 16 examples, zero failures.
- bundle exec rspec spec/polyrun/quality/tool_limits_spec.rb spec/polyrun/quality/mutation_spec.rb spec/polyrun/quality/subjects_spec.rb: covered in the earlier focused runs with zero failures after the contract asserts.
- full-operator run after hardening: 87 mutations, 84 detected (`killed`), 3 then 2 accepted-equivalent undetected (`survived`).
- make mutate: exit 0; 7 mutations, 7 detected, 0 undetected.
- bundle exec polyrun graph --enable index --root examples/simple/simple_demo --json: exit 0; ok true, nodes 5.

## Next

Keep RFC-0010 Experimental until a hosted consuming app runs graph check or mutate in its own CI with its ordinary test command. Optional later: assert ceilings-specific diagnostics if that distinction becomes a published contract.

## Source

- ../issues/20261114090000_graph-and-mutation-adoption.md.
- ../QUALITY.md.
- ../QUALITY_CONFIGURATION.md.
- ../../rfcs/0010-graph-and-quality-orchestration.md.
- ../../config/mutation_subjects.txt.
- ../../polyrun.yml.
- ../reviews/20261114161158_self-graph-and-mutation.md.
