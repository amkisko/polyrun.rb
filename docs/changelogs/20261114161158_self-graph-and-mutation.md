# Self graph, mutation, and quality exercise

## Participants

Andrei Makarov (@amkisko).

## Decisions

Run Polyrun graph indexing, a curated mutation gate, observe, and measure against this repository. Keep root mutation, observe, and measure inactive; enable them only through the self suite.

## Effects

Add make graph, make mutate, make observe, make measure, and make quality-self. Wire quality-self into the quality CI job. Ship curated subjects plus suite settings. Stage project-root coverage reports by path so nested library coverage sources remain available during mutation copies.

## Next

Undetected cases assessed in ../reviews/20261114182832_undetected-mutation-and-consumer-assessment.md. Promotion off Experimental still needs a hosted consuming app CI run.

## Source

- ../reviews/20261114161158_self-graph-and-mutation.md.
- ../reviews/20261114182832_undetected-mutation-and-consumer-assessment.md.
- ../../CHANGELOG.md.
