#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${1:-}"
DB_USER="${2:-}"
DB_PASS="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_DIR="$REPO_DIR/docker"
ENV_FILE="$DOCKER_DIR/.env"
PGB_INI="$DOCKER_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$DOCKER_DIR/pgbouncer/userlist.txt"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "$DB_NAME" ]] || die "Usage: $0 <db_name> <db_user> <password>"
[[ -n "$DB_USER" ]] || die "db_user is required"
[[ -n "$DB_PASS" ]] || die "password is required"
[[ -f "$ENV_FILE" ]] || die ".env not found: $ENV_FILE"
[[ -f "$PGB_INI" ]] || die "pgbouncer.ini not found: $PGB_INI"

set -a && source "$ENV_FILE" && set +a
[[ -n "${POSTGRES_USER:-}" ]] || die "POSTGRES_USER empty"

[[ "$DB_USER" != *\"* ]] || die "db_user must not contain double quotes"
[[ "$DB_PASS" != *\"* ]] || die "password must not contain double quotes"

docker exec -i postgres psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${DB_USER}', '${DB_PASS}');
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${DB_USER}', '${DB_PASS}');
  END IF;
END
\$\$;
SELECT format('CREATE DATABASE %I OWNER %I', '${DB_NAME}', '${DB_USER}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') \gexec
SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', '${DB_NAME}', '${DB_USER}') \gexec
SQL

PGB_LINE="${DB_NAME} = host=postgres port=5432 dbname=${DB_NAME} user=${DB_USER}"
if ! rg "^${DB_NAME}[[:space:]]*=" "$PGB_INI" >/dev/null 2>&1; then
  sed -i "/^\[databases\]/a ${PGB_LINE}" "$PGB_INI"
fi

if rg "\"${DB_USER}\"" "$USERLIST_FILE" >/dev/null 2>&1; then
  sed -i "s|\"${DB_USER}\" \".*\"|\"${DB_USER}\" \"${DB_PASS}\"|" "$USERLIST_FILE"
else
  printf '"%s" "%s"\n' "$DB_USER" "$DB_PASS" >> "$USERLIST_FILE"
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d pgbouncer --force-recreate

retries=30
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' pgbouncer 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1)); sleep 1
done
[[ "$retries" -gt 0 ]] || die "PgBouncer did not become healthy"

echo ""
echo "Database provisioned."
echo "  DB: $DB_NAME"
echo "  User: $DB_USER"
