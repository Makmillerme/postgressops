#!/bin/bash
# ============================================================
# healthcheck.sh — Перевірка стану всього стеку
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
set -a && source "$ENV_FILE" && set +a

OK="\033[0;32mOK\033[0m"
FAIL="\033[0;31mFAIL\033[0m"

check() {
  local name="$1" cmd="$2"
  if eval "$cmd" &>/dev/null; then
    printf "  %-30s [${OK}]\n" "$name"
  else
    printf "  %-30s [${FAIL}]\n" "$name"
  fi
}

echo ""
echo "=== PostgreSQL Stack Health Check ==="
echo ""

echo "Services:"
check "postgres container running"    "docker inspect -f '{{.State.Running}}' postgres | grep -q true"
check "postgres healthcheck healthy"  "docker inspect -f '{{.State.Health.Status}}' postgres | grep -q healthy"
check "pgbouncer container running"   "docker inspect -f '{{.State.Running}}' pgbouncer | grep -q true"
check "pg_backup container running"   "docker inspect -f '{{.State.Running}}' pg_backup | grep -q true"
check "postgres_exporter running"     "docker inspect -f '{{.State.Running}}' postgres_exporter | grep -q true"

echo ""
echo "Connectivity:"
check "postgres reachable"            "docker exec postgres pg_isready -U $POSTGRES_USER -d ${POSTGRES_DB:-postgres}"
# pg_isready до PgBouncer часто дає false negative (SASL/протокол); перевіряємо лише TCP.
check "pgbouncer TCP (pool port)"   "docker exec pgbouncer bash -lc 'exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_LISTEN_PORT:-6432}'"

echo ""
echo "Backups:"
LAST_BACKUP=$(docker exec pg_backup find /backups/full -type f -name '*.gz' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | awk '{print $2}')
if [ -n "$LAST_BACKUP" ]; then
  printf "  %-30s [${OK}] %s\n" "Last backup found" "$LAST_BACKUP"
else
  printf "  %-30s [${FAIL}] No backups found yet\n" "Last backup"
fi

echo ""
echo "=== Done ==="
echo ""
