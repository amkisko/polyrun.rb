#!/usr/bin/env bash
# Compare partition strategies from this directory (no Rails). Run: chmod +x demo_plan.sh && ./demo_plan.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
POLYRUN="$(cd "$ROOT/../.." && pwd)/bin/polyrun"

echo "=== round_robin — sorted paths, index mod N ==="
for s in 0 1; do
  echo "--- shard $s ---"
  "$POLYRUN" plan --total 2 --shard "$s" --strategy round_robin --paths-file spec_paths.txt | ruby -rjson -e 'j=JSON.parse(STDIN.read); puts j["paths"].inspect'
done

echo ""
echo "=== random_round_robin — shuffled then mod (seed=42) ==="
for s in 0 1; do
  echo "--- shard $s ---"
  "$POLYRUN" plan --total 2 --shard "$s" --strategy random_round_robin --seed 42 --paths-file spec_paths.txt | ruby -rjson -e 'j=JSON.parse(STDIN.read); puts j["paths"].inspect'
done

echo ""
echo "=== cost_binpack — balance estimated seconds (polyrun_timing.json) ==="
for s in 0 1; do
  echo "--- shard $s ---"
  "$POLYRUN" plan --total 2 --shard "$s" --strategy cost_binpack --timing polyrun_timing.json --paths-file spec_paths.txt | ruby -rjson -e 'j=JSON.parse(STDIN.read); puts "paths=#{j["paths"].inspect} shard_seconds=#{j["shard_seconds"].inspect}"'
done

echo ""
echo "=== hrw (rendezvous) — hash-based shard per path ==="
for s in 0 1; do
  echo "--- shard $s ---"
  "$POLYRUN" plan --total 2 --shard "$s" --strategy hrw --seed demo-salt --timing polyrun_timing.json --paths-file spec_paths.txt | ruby -rjson -e 'j=JSON.parse(STDIN.read); puts "paths=#{j["paths"].inspect} strategy=#{j["strategy"]}"'
done

echo ""
echo "=== Sample configs (use as polyrun.yml or polyrun -c FILE) ==="
ls -1 "$ROOT"/*.yml
