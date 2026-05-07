#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# healthcheck.sh — Stack status check.
# Run from inside docker/ directory (reads ../.env relative to script).
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
[[ -f "$ENV_FILE" ]] || { echo "ERROR: .env not found at $ENV_FILE"; exit 1; }

set -a && source "$ENV_FILE" && set +a

OK="\033[0;32mOK\033[0m"
FAIL="\033[0;31mFAIL\033[0m"
WARN="\033[0;33mWARN\033[0m"

check() {
  local name="$1" cmd="$2"
  if eval "$cmd" &>/dev/null; then
    printf "  %-38s [${OK}]\n" "$name"
  else
    printf "  %-38s [${FAIL}]\n" "$name"
  fi
}

echo ""
echo "=== PostgreSQL Stack Health Check ==="
echo ""

echo "Services:"
check "postgres container running"     "docker inspect -f '{{.State.Running}}' postgres | grep -q true"
check "postgres healthcheck healthy"   "docker inspect -f '{{.State.Health.Status}}' postgres | grep -q healthy"
check "pgbouncer container running"    "docker inspect -f '{{.State.Running}}' pgbouncer | grep -q true"
check "pgbouncer healthcheck healthy"  "docker inspect -f '{{.State.Health.Status}}' pgbouncer | grep -q healthy"
check "pg_backup container running"    "docker inspect -f '{{.State.Running}}' pg_backup | grep -q true"
check "postgres_exporter running"      "docker inspect -f '{{.State.Running}}' postgres_exporter | grep -q true"
check "prometheus running"             "docker inspect -f '{{.State.Running}}' prometheus | grep -q true"

echo ""
echo "Connectivity:"
check "postgres pg_isready"            "docker exec postgres pg_isready -U $POSTGRES_USER -d ${POSTGRES_DB:-postgres}"
# TCP check — pg_isready against PgBouncer gives false negatives.
check "pgbouncer TCP port"             "docker exec pgbouncer bash -lc 'exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_LISTEN_PORT:-6432}'"

echo ""
echo "Backups:"
LAST_BACKUP=$(docker exec pg_backup find /backups/full -type f -name '*.gz' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | awk '{print $2}')
if [[ -n "$LAST_BACKUP" ]]; then
  printf "  %-38s [${OK}] %s\n" "Last backup found" "$LAST_BACKUP"
else
  printf "  %-38s [${WARN}] No backups yet — run: docker exec pg_backup sh /usr/local/bin/backup.sh\n" "Last backup"
fi

echo ""
echo "Databases (in Postgres cluster):"
docker exec postgres psql -U "$POSTGRES_USER" -d postgres -tAc \
  "SELECT '  ' || datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null || true

echo ""
echo "PgBouncer pool mappings:"
grep -E "^[a-zA-Z]" "$SCRIPT_DIR/../pgbouncer/pgbouncer.ini" 2>/dev/null | \
  grep -v "^\[" | awk '{print "  " $0}' || true

echo ""
echo "=== Done ==="
echo ""
