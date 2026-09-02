#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_DIR="$REPO_DIR/docker"
ENV_FILE="$DOCKER_DIR/.env"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
PGB_INI="$DOCKER_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$DOCKER_DIR/pgbouncer/userlist.txt"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die ".env not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || die "docker-compose.yml not found: $COMPOSE_FILE"
[[ -f "$PGB_INI" ]] || die "pgbouncer.ini not found: $PGB_INI"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is not installed"

set -a && source "$ENV_FILE" && set +a
[[ -n "${POSTGRES_USER:-}" ]] || die "POSTGRES_USER is empty in .env"
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD is empty in .env"

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Replace all CHANGE_ME_* values in $ENV_FILE before running."
fi

[[ "${POSTGRES_PASSWORD}" != *\"* ]] || die "POSTGRES_PASSWORD must not contain double quotes."
printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > "$USERLIST_FILE"

PGB_POSTGRES_LINE="postgres = host=postgres port=5432 dbname=postgres user=${POSTGRES_USER}"
if ! grep -qE "^postgres[[:space:]]*=" "$PGB_INI"; then
  sed -i "/^\[databases\]/a ${PGB_POSTGRES_LINE}" "$PGB_INI"
fi
sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull --quiet 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

retries=60
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1)); sleep 2
done
[[ "$retries" -gt 0 ]] || die "Postgres did not become healthy in time."

retries=30
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' pgbouncer 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1)); sleep 2
done
[[ "$retries" -gt 0 ]] || die "PgBouncer did not become healthy in time."

docker exec postgres pg_isready -U "$POSTGRES_USER" -d "${POSTGRES_DB:-postgres}" >/dev/null
docker exec pgbouncer bash -lc "exec 3<>/dev/tcp/127.0.0.1/${PGBOUNCER_LISTEN_PORT:-6432}" >/dev/null
bash "$SCRIPT_DIR/fix-wal-archive.sh" || true

echo ""
echo "Reinstall completed. Data volumes were NOT removed."
echo "  bash $REPO_DIR/scripts/healthcheck.sh"
echo "  bash $REPO_DIR/scripts/provision-db.sh <db_name> <db_user> <password>"
