# Self graph, mutation, and quality exercise

## Participants

Andrei Makarov (@amkisko).

## Decisions

Enable graph indexing against this checkout in the root polyrun.yml. Keep mutation, observe, and measure disabled at the root so nested quality CLI specs do not inherit a self workload. Activate them through the self suite with a shared focused quality-spec command. Mutation keeps curated subjects and the operator family as the current green gate. Observe writes tmp/observed-self.json. Measure writes tmp/measurement-self.json with a wall_s ceiling of 60.

Move the default staging exclusion for coverage reports from a basename match to exclude_paths coverage so nested library directories named coverage still stage. Without that change, lib/polyrun/coverage was pruned and the staged baseline could not load Polyrun.

## Effects

make graph indexes lib with 11887 nodes. make mutate with the self suite detected 8 operator mutations and recorded zero undetected cases. An earlier full-operator run on the same subjects produced 87 mutations, 65 detected, and 22 literal or body undetected cases; those cases were assessed later. make observe recorded 140 non-truncated calls. make measure passed with wall_s about 8.7 under the 60 second ceiling. Staging now copies lib/polyrun/coverage/merge.rb while excluding the project-root coverage report tree. make quality-self runs graph, mutate, observe, and measure. The quality CI job runs make quality-self.

### Validation

- bundle exec rspec spec/polyrun/quality/tool_limits_spec.rb: exit 0; 9 examples, zero failures, including the nested coverage staging regression.
- bundle exec rspec spec/polyrun/quality/tool_limits_spec.rb spec/polyrun/quality/configuration_spec.rb spec/polyrun/config/root_defaults_spec.rb spec/polyrun/quality/subjects_spec.rb: exit 0; 26 examples, zero failures.
- bundle exec polyrun validate: exit 0.
- make graph: exit 0; snapshot present, nodes 11887, reused true on the second run.
- make mutate: exit 0; 8 mutations, 8 detected (`killed`), 0 undetected (`survived`); report at tmp/mutation-self.json.
- make observe: exit 0; tmp/observed-self.json truncated false, 140 calls.
- make measure: exit 0; label self-quality, failures empty, wall_s about 8.7.

## Next

Undetected-mutation assessment and consumer evaluation are recorded in 20261114182832_undetected-mutation-and-consumer-assessment.md. Hosted consuming-app CI remains the Experimental promotion gate.

## Source

- ../QUALITY.md.
- ../QUALITY_CONFIGURATION.md.
- ../issues/20261114090000_graph-and-mutation-adoption.md.
- ../reviews/20261114182832_undetected-mutation-and-consumer-assessment.md.
- ../../polyrun.yml.
- ../../config/mutation_subjects.txt.
