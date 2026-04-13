#!/usr/bin/env bash
# Run from this directory. Compares round-robin vs cost-based binpack using polyrun_timing.json.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
POLYRUN_BIN="$(cd "$ROOT/../.." && pwd)/bin/polyrun"

echo "=== Round-robin (2 shards) — ignores wall times ==="
for s in 0 1; do
  echo "--- shard $s ---"
  "$POLYRUN_BIN" plan --total 2 --shard "$s" --strategy round_robin --paths-file spec_paths.txt
done

echo ""
echo "=== Cost binpack (2 shards) — balances estimated seconds across shards ==="
for s in 0 1; do
  echo "--- shard $s ---"
  "$POLYRUN_BIN" plan --total 2 --shard "$s" --timing polyrun_timing.json --paths-file spec_paths.txt
done

echo ""
echo "=== shard_seconds totals (same manifest field for every shard index) ==="
"$POLYRUN_BIN" plan --total 2 --shard 0 --timing polyrun_timing.json --paths-file spec_paths.txt | ruby -rjson -e 'j=JSON.parse(STDIN.read); p j["shard_seconds"]'

echo ""
echo "=== Using polyrun.yml (strategy + timing_file) ==="
"$POLYRUN_BIN" -c polyrun.yml plan --shard 1 --total 3
