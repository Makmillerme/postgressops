#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# reinstall.sh — Controlled reinstall WITHOUT wiping data volumes.
#
# Use case: existing installation with data you want to keep,
# but you need containers fully recreated (config changes,
# image updates, pgbouncer reset, etc.)
#
# What it does:
#   1. Validates .env and required config files
#   2. Syncs pgbouncer/userlist.txt and pgbouncer.ini admin user from .env
#   3. Stops and removes containers (volumes are NOT removed)
#   4. Pulls fresh images and recreates all containers
#   5. Waits for postgres + pgbouncer healthy
#   6. Runs smoke tests
#
# Usage:
#   bash docker/scripts/reinstall.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# --- Validate prerequisites ---
[[ -f "$ENV_FILE" ]]      || die ".env not found: $ENV_FILE (run install.sh first)"
[[ -f "$COMPOSE_FILE" ]]  || die "docker-compose.yml not found: $COMPOSE_FILE"
[[ -f "$PGB_INI" ]]       || die "pgbouncer.ini not found: $PGB_INI"

command -v docker >/dev/null 2>&1        || die "docker is not installed"
docker compose version >/dev/null 2>&1   || die "docker compose plugin is not installed"

set -a && source "$ENV_FILE" && set +a

[[ -n "${POSTGRES_USER:-}" ]]     || die "POSTGRES_USER is empty in .env"
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD is empty in .env"

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Replace all CHANGE_ME_* values in $ENV_FILE before running."
fi

# --- Sync pgbouncer userlist ---
log "Syncing pgbouncer/userlist.txt from .env"
[[ "${POSTGRES_PASSWORD}" != *\"* ]] || die "POSTGRES_PASSWORD contains double quote — please escape it."
printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > "$USERLIST_FILE"

# Ensure admin user entry for postgres maintenance DB
PGB_POSTGRES_LINE="postgres = host=postgres port=5432 dbname=postgres user=${POSTGRES_USER}"
if ! grep -qE "^postgres[[:space:]]*=" "$PGB_INI"; then
  sed -i "/^\[databases\]/a ${PGB_POSTGRES_LINE}" "$PGB_INI"
  log "Added 'postgres' maintenance DB mapping to pgbouncer.ini"
fi

# Sync admin_users / stats_users
sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"

# --- Stop containers (keep volumes) ---
log "Stopping containers (volumes preserved)"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans

# --- Pull fresh images and start ---
log "Pulling latest images"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull --quiet 2>/dev/null || true

log "Starting all services"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

# --- Wait for postgres ---
log "Waiting for postgres to be healthy"
retries=60
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1))
  sleep 2
done
[[ "$retries" -gt 0 ]] || die "Postgres did not become healthy in time."

# --- Wait for pgbouncer ---
log "Waiting for pgbouncer to be healthy"
retries=30
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' pgbouncer 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1))
  sleep 2
done
[[ "$retries" -gt 0 ]] || die "PgBouncer did not become healthy in time."

# --- Smoke tests ---
log "Running smoke tests"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

docker exec postgres pg_isready -U "$POSTGRES_USER" -d "${POSTGRES_DB:-postgres}" >/dev/null \
  && log "postgres: OK" \
  || die "postgres pg_isready failed"

docker exec pgbouncer bash -lc "exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_LISTEN_PORT:-6432}" >/dev/null \
  && log "pgbouncer TCP: OK" \
  || die "pgbouncer TCP check failed"

echo ""
echo "============================================================"
echo "Reinstall completed. Data volumes were NOT removed."
echo ""
echo "  healthcheck : bash $STACK_DIR/scripts/healthcheck.sh"
echo "  provision db: bash $STACK_DIR/scripts/provision-db.sh <db_name> <db_user> <password>"
echo "============================================================"
