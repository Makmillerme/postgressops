#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_DIR="$REPO_DIR/docker"
ENV_FILE="$DOCKER_DIR/.env"
PGB_INI="$DOCKER_DIR/pgbouncer/pgbouncer.ini"

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

container_running() {
  local name="$1"
  [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null || echo false)" == "true" ]]
}

container_healthy() {
  local name="$1"
  [[ "$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "")" == "healthy" ]]
}

echo ""
echo "=== PostgreSQL Stack Health Check ==="
echo ""
echo "Services:"
check "postgres container running"     "container_running postgres"
check "postgres healthcheck healthy"   "container_healthy postgres"
check "pgbouncer container running"    "container_running pgbouncer"
check "pgbouncer healthcheck healthy"  "container_healthy pgbouncer"
check "pg_backup container running"    "container_running pg_backup"

echo ""
echo "Connectivity:"
check "postgres pg_isready"            "docker exec postgres pg_isready -U $POSTGRES_USER -d ${POSTGRES_DB:-postgres}"
check "pgbouncer TCP port"             "docker exec pgbouncer bash -lc 'exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_LISTEN_PORT:-6432}'"

echo ""
echo "Backups:"
# Alpine find lacks GNU -printf; use ls -t instead.
LAST_BACKUP=$(docker exec pg_backup sh -c 'ls -t /backups/full/full_*.sql.gz 2>/dev/null | head -1' || true)
if [[ -n "${LAST_BACKUP:-}" ]]; then
  printf "  %-38s [${OK}] %s\n" "Last backup found" "$LAST_BACKUP"
else
  printf "  %-38s [${WARN}] No backups yet — run: docker exec pg_backup sh /usr/local/bin/backup.sh\n" "Last backup"
fi

echo ""
echo "Databases:"
docker exec postgres psql -U "$POSTGRES_USER" -d postgres -tAc \
  "SELECT '  ' || datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null || true

echo ""
echo "PgBouncer mappings:"
grep -E '^[a-zA-Z].*= host=postgres' "$PGB_INI" | awk '{print "  " $0}' || true
echo ""

