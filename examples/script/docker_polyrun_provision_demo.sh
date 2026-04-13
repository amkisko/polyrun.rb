#!/usr/bin/env bash
# Migrate polyrun.yml template DB + CREATE shard DBs from template (parallel-safe isolation).
# Prerequisites: examples/script/docker_up.sh, PGPORT/PGPASSWORD set, demo ./script/ci_prepare + bundle install.
#
# Usage:  ./script/docker_polyrun_provision_demo.sh simple/simple_demo
#         ./script/docker_polyrun_provision_demo.sh multi_database/multi_demo
set -euo pipefail
EXAMPLES="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$EXAMPLES/.." && pwd)"
POLYRUN="${POLYRUN_BIN:-$REPO/bin/polyrun}"
DEMO_REL="${1:?usage: $0 <path under examples/, e.g. simple/simple_demo>}"
DEMO="$EXAMPLES/$DEMO_REL"
if [[ ! -d "$DEMO" || ! -f "$DEMO/polyrun.yml" ]]; then
  echo "Not a demo with polyrun.yml: $DEMO" >&2
  exit 1
fi

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-${POLYRUN_PG_PORT:-5433}}"
export PGUSER="${PGUSER:-postgres}"
export PGPASSWORD="${PGPASSWORD:-postgres}"
export RAILS_ENV="${RAILS_ENV:-test}"

cd "$DEMO"
SHARD_TOTAL="$(ruby -ryaml -e 'y=YAML.load_file("polyrun.yml"); p=(y["partition"]||{}); puts (p["shard_total"]||p[:shard_total]||4).to_i')"
echo "== polyrun db:setup-template ($DEMO_REL) =="
bundle exec "$POLYRUN" -c polyrun.yml db:setup-template --rails-root .

echo "== polyrun db:setup-shard × $SHARD_TOTAL =="
for i in $(seq 0 $((SHARD_TOTAL - 1))); do
  POLYRUN_SHARD_INDEX=$i POLYRUN_SHARD_TOTAL=$SHARD_TOTAL bundle exec "$POLYRUN" -c polyrun.yml db:setup-shard
done
echo "== provisioned $DEMO_REL (template + shards 0..$((SHARD_TOTAL - 1))) =="
