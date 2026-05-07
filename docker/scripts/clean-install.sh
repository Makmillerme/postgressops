#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# clean-install.sh — Full wipe and clean reinstall.
# WARNING: Removes ALL Docker volumes for this stack (data loss!).
# Only use on a fresh server or when intentionally wiping data.
#
# Usage:
#   ./scripts/clean-install.sh [--yes]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"
AUTO_YES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)     AUTO_YES="true"; shift 1 ;;
    --stack-dir)
      STACK_DIR="$2"
      ENV_FILE="$STACK_DIR/.env"
      COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
      PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
      USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"
      shift 2 ;;
    *)
      echo "Unknown arg: $1"
      echo "Usage: $0 [--yes] [--stack-dir /path/to/docker]"
      exit 1 ;;
  esac
done

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# --- Validate ---
[[ -f "$ENV_FILE" ]]       || die ".env not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]]   || die "docker-compose.yml not found: $COMPOSE_FILE"
[[ -f "$PGB_INI" ]]        || die "pgbouncer.ini not found: $PGB_INI"
[[ -f "$USERLIST_FILE" ]]  || die "userlist.txt not found: $USERLIST_FILE"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is not installed"

set -a && source "$ENV_FILE" && set +a

[[ -n "${POSTGRES_USER:-}" ]]     || die "POSTGRES_USER is empty in .env"
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD is empty in .env"

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Replace all CHANGE_ME_* values in $ENV_FILE before running."
fi

# --- Confirm ---
if [[ "$AUTO_YES" != "true" ]]; then
  echo ""
  echo "WARNING: This will perform a CLEAN reinstall:"
  echo "  - docker compose down -v --remove-orphans  (ALL DATA REMOVED)"
  echo "  - Fresh stack start from .env"
  echo ""
  read -r -p "Type YES to continue: " answer
  [[ "$answer" == "YES" ]] || die "Aborted by user."
fi

# --- Sync PgBouncer userlist from .env ---
log "Rewriting pgbouncer/userlist.txt from .env"
[[ "${POSTGRES_PASSWORD}" != *\"* ]] || die "POSTGRES_PASSWORD contains double quote — escape it first."
printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > "$USERLIST_FILE"

# --- Sync admin_users / stats_users ---
sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"

# --- Wipe ---
log "Stopping stack and removing volumes"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down -v --remove-orphans

# --- Start postgres first, wait healthy ---
log "Starting postgres"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d postgres

log "Waiting for postgres healthcheck"
retries=60
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1))
  sleep 2
done
[[ "$retries" -gt 0 ]] || die "Postgres did not become healthy in time."

# --- Start remaining services ---
log "Starting all services"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

# --- Smoke tests ---
log "Running smoke tests"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

docker exec postgres pg_isready -U "$POSTGRES_USER" -d "${POSTGRES_DB:-postgres}" >/dev/null
docker exec pgbouncer bash -lc "exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_LISTEN_PORT:-6432}" >/dev/null
docker exec pg_backup sh /usr/local/bin/backup.sh >/dev/null

log "Smoke tests passed (postgres, pgbouncer TCP, backup)"

echo ""
echo "============================================================"
echo "Clean install completed."
echo "Stack dir: $STACK_DIR"
echo ""
echo "Next: provision a database"
echo "  bash $STACK_DIR/scripts/provision-db.sh <db_name> <db_user> <password>"
echo "============================================================"
