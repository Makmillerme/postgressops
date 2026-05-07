#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# provision-db.sh — Create a database + role + PgBouncer mapping.
# Idempotent: safe to re-run (role/db recreated only if absent).
#
# Usage:
#   ./scripts/provision-db.sh <db_name> <db_user> <password>
#
# Example:
#   ./scripts/provision-db.sh mtrucklending Makmiller 'Str0ngPass!'
# ============================================================

DB_NAME="${1:-}"
DB_USER="${2:-}"
DB_PASS="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -n "$DB_NAME" ]] || die "db_name is required. Usage: $0 <db_name> <db_user> <password>"
[[ -n "$DB_USER" ]] || die "db_user is required."
[[ -n "$DB_PASS" ]] || die "password is required."

[[ -f "$ENV_FILE" ]]  || die ".env not found: $ENV_FILE"
[[ -f "$PGB_INI" ]]   || die "pgbouncer.ini not found: $PGB_INI"
[[ -f "$USERLIST_FILE" ]] || die "userlist.txt not found: $USERLIST_FILE"

set -a && source "$ENV_FILE" && set +a

[[ -n "${POSTGRES_USER:-}" ]]     || die "POSTGRES_USER is empty in .env"
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD is empty in .env"

# Validate no double quotes in names/passwords (PgBouncer userlist format)
[[ "$DB_USER" != *\"* ]] || die "db_user must not contain double quotes."
[[ "$DB_PASS" != *\"* ]] || die "password must not contain double quotes."

# --- 1. Create role and database in Postgres ---
log "Creating role '$DB_USER' and database '$DB_NAME'"

docker exec -i postgres psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${DB_USER}', '${DB_PASS}');
    RAISE NOTICE 'Role % created.', '${DB_USER}';
  ELSE
    EXECUTE format('ALTER ROLE %I LOGIN PASSWORD %L', '${DB_USER}', '${DB_PASS}');
    RAISE NOTICE 'Role % already exists — password updated.', '${DB_USER}';
  END IF;
END
\$\$;

SELECT format('CREATE DATABASE %I OWNER %I', '${DB_NAME}', '${DB_USER}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') \gexec

SELECT format('GRANT ALL PRIVILEGES ON DATABASE %I TO %I', '${DB_NAME}', '${DB_USER}') \gexec
SQL

log "Postgres role and database ready."

# --- 2. Add to pgbouncer.ini [databases] ---
PGB_LINE="${DB_NAME} = host=postgres port=5432 dbname=${DB_NAME} user=${DB_USER}"

if grep -qE "^${DB_NAME}[[:space:]]*=" "$PGB_INI"; then
  log "pgbouncer.ini already contains '$DB_NAME' — skipping (no change)."
else
  sed -i "/^\[databases\]/a ${PGB_LINE}" "$PGB_INI"
  log "Added '$DB_NAME' to pgbouncer.ini [databases]."
fi

# --- 3. Add to userlist.txt ---
if grep -q "\"${DB_USER}\"" "$USERLIST_FILE"; then
  # Update existing line
  sed -i "s|\"${DB_USER}\" \".*\"|\"${DB_USER}\" \"${DB_PASS}\"|" "$USERLIST_FILE"
  log "Updated '${DB_USER}' in userlist.txt."
else
  printf '"%s" "%s"\n' "$DB_USER" "$DB_PASS" >> "$USERLIST_FILE"
  log "Added '${DB_USER}' to userlist.txt."
fi

# --- 4. Reload PgBouncer ---
log "Reloading PgBouncer"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d pgbouncer --force-recreate

# Wait for healthy
retries=30
until [[ "$retries" -eq 0 ]]; do
  status="$(docker inspect -f '{{.State.Health.Status}}' pgbouncer 2>/dev/null || true)"
  [[ "$status" == "healthy" ]] && break
  retries=$((retries - 1))
  sleep 1
done
[[ "$retries" -gt 0 ]] || die "PgBouncer did not become healthy after reload."

# --- 5. Verify connection ---
log "Verifying connection via PgBouncer"
retries=10
until [[ "$retries" -eq 0 ]]; do
  if PGPASSWORD="$DB_PASS" psql \
    "host=127.0.0.1 port=${PGBOUNCER_LISTEN_PORT:-6432} dbname=${DB_NAME} user=${DB_USER} sslmode=disable" \
    -c "SELECT 1;" >/dev/null 2>&1; then
    break
  fi
  retries=$((retries - 1))
  sleep 1
done
[[ "$retries" -gt 0 ]] || die "Connection verification failed. Check pgbouncer logs: docker logs pgbouncer --tail 40"

echo ""
echo "============================================================"
echo "Database provisioned successfully."
echo "  DB:   $DB_NAME"
echo "  User: $DB_USER"
echo ""
echo "Connection strings:"
SERVER_IP="${SERVER_PUBLIC_IP:-$(hostname -I | awk '{print $1}')}"
echo "  DATABASE_URL (pooled):"
echo "    postgresql://${DB_USER}:<pass>@${SERVER_IP}:${PGBOUNCER_LISTEN_PORT:-6432}/${DB_NAME}?schema=public&pgbouncer=true&connect_timeout=10"
echo ""
echo "  DIRECT_URL (migrations, SSH tunnel):"
echo "    postgresql://${DB_USER}:<pass>@127.0.0.1:5432/${DB_NAME}?schema=public&connect_timeout=10"
echo "============================================================"
