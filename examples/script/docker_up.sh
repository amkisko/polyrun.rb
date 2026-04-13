#!/usr/bin/env bash
# Start shared Postgres for Polyrun parallel runs (see examples/README.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export POLYRUN_PG_PORT="${POLYRUN_PG_PORT:-5433}"
COMPOSE=(docker compose -f "$ROOT/docker-compose.yml")
if ! docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker-compose -f "$ROOT/docker-compose.yml")
fi
"${COMPOSE[@]}" up -d
echo "Waiting for Postgres..."
for _ in $(seq 1 45); do
  if "${COMPOSE[@]}" exec -T postgres pg_isready -U postgres -d postgres 2>/dev/null; then
    break
  fi
  sleep 1
done
echo "Postgres is up on ${PGHOST:-127.0.0.1}:${POLYRUN_PG_PORT} (export PGPORT=${POLYRUN_PG_PORT} PGPASSWORD=postgres before polyrun)."
