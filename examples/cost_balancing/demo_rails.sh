#!/usr/bin/env bash
# Parallel RSpec with cost-balanced shards + merged coverage (Polyrun run-shards + merge-coverage).
# Requires: `cd` targets the shared Rails demo (multi_database/multi_demo) via `rails_demo` symlink.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
POLYRUN_BIN="$REPO_ROOT/bin/polyrun"
cd "$ROOT/rails_demo"
export RAILS_ENV=test

echo "== db:prepare (primary + cache) =="
bin/rails db:prepare

echo "== polyrun run-shards (workers inherit POLYRUN_SHARD_INDEX; coverage fragments per shard) =="
"$POLYRUN_BIN" -c "$ROOT/polyrun_rails.yml" run-shards --workers 4 --timing "$ROOT/polyrun_timing.json" -- bundle exec rspec

echo "== merge-coverage =="
shopt -s nullglob
fragments=(coverage/polyrun-fragment-*.json)
if ((${#fragments[@]} == 0)); then
  echo "No coverage/polyrun-fragment-*.json (set POLYRUN_COVERAGE_DISABLE!=1 in spec_helper or run rspec with coverage enabled)."
  exit 0
fi
args=()
for f in "${fragments[@]}"; do
  args+=(-i "$f")
done
"$POLYRUN_BIN" merge-coverage "${args[@]}" -o coverage/merged.json --format json,console
echo "Wrote coverage/merged.json"
