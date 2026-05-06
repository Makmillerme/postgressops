#!/bin/bash
# ============================================================
# list-connections.sh — показати поточні підключення до PgBouncer
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
set -a && source "$ENV_FILE" && set +a

echo "=== PgBouncer Pools ==="
docker exec pgbouncer psql -h localhost -p 6432 -U "$POSTGRES_USER" pgbouncer -c "SHOW POOLS;"

echo ""
echo "=== PgBouncer Clients ==="
docker exec pgbouncer psql -h localhost -p 6432 -U "$POSTGRES_USER" pgbouncer -c "SHOW CLIENTS;"

echo ""
echo "=== PostgreSQL Active Connections ==="
docker exec postgres psql -U "$POSTGRES_USER" -c \
  "SELECT datname, usename, application_name, state, count(*) \
   FROM pg_stat_activity \
   WHERE state IS NOT NULL \
   GROUP BY datname, usename, application_name, state \
   ORDER BY count(*) DESC;"
