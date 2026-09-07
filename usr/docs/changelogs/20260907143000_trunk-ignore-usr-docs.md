## Participants

- amkisko

## Decisions

- Add usr/docs/** to the Trunk lint ignore list in .trunk/trunk.yaml.
- usr/docs is durable engineering trace in plain prose. markdownlint MD013 and MD034 on that tree are the wrong check for this layout.
- Do not wrap every live-work note to satisfy line length. The ignore is the product contract.

## Effects

- Trunk no longer lints files under usr/docs/.

## Source

- usr/docs/issues/20260907141000_engineering-and-dependency-audit.md
- GitHub Actions run 33874689956
