#!/bin/bash
# ============================================================
# add-project.sh — Додати новий проєкт до PostgreSQL стеку
# Використання: ./scripts/add-project.sh <project_name>
#
# Що робить:
#   1. Генерує випадковий пароль
#   2. Створює БД і користувача в Postgres
#   3. Оновлює pgbouncer.ini та userlist.txt
#   4. Виводить готові DATABASE_URL та DIRECT_URL для Prisma
# ============================================================
set -euo pipefail

PROJECT="${1:-}"
VPN_HOST="${VPN_HOST:-91.239.232.91}"

if [ -z "$PROJECT" ]; then
  echo "Usage: $0 <project_name>"
  echo "Example: $0 myapp"
  exit 1
fi

DB_NAME="${PROJECT}"
DB_USER="${PROJECT}_user"
DB_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!@#%^&*' | head -c 32)

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Завантажуємо env
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found at $ENV_FILE"
  echo "Copy .env.example → .env and fill in the values first."
  exit 1
fi

set -a && source "$ENV_FILE" && set +a

# --- 1. Створити роль і базу в Postgres ---
log "Creating role '$DB_USER' and database '$DB_NAME' in Postgres..."

docker exec -i postgres psql -U "$POSTGRES_USER" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';
  ELSE
    ALTER ROLE $DB_USER PASSWORD '$DB_PASS';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') \gexec

GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
SQL

log "Done: role and database created."

# --- 2. Додати до pgbouncer.ini ---
PGBOUNCER_INI="$SCRIPT_DIR/../pgbouncer/pgbouncer.ini"
if ! grep -q "^$DB_NAME " "$PGBOUNCER_INI"; then
  sed -i "/^\[databases\]/a $DB_NAME = host=postgres port=5432 dbname=$DB_NAME user=$DB_USER" "$PGBOUNCER_INI"
  log "Added '$DB_NAME' to pgbouncer.ini"
else
  log "pgbouncer.ini already has '$DB_NAME', skipping."
fi

# --- 3. Додати до userlist.txt ---
USERLIST="$SCRIPT_DIR/../pgbouncer/userlist.txt"
if ! grep -q "\"$DB_USER\"" "$USERLIST"; then
  echo "\"$DB_USER\" \"$DB_PASS\"" >> "$USERLIST"
  log "Added '$DB_USER' to userlist.txt"
fi

# --- 4. Перезавантажити PgBouncer ---
log "Reloading PgBouncer..."
docker exec pgbouncer pkill -HUP pgbouncer || docker restart pgbouncer

# --- 5. Вивести готові URL ---
echo ""
echo "============================================================"
echo " Project: $PROJECT"
echo "============================================================"
echo ""
echo "# .env для Prisma (додай у свій проєкт):"
echo ""
echo "DATABASE_URL=\"postgresql://${DB_USER}:${DB_PASS}@${VPN_HOST}:6432/${DB_NAME}?schema=public&pgbouncer=true&connect_timeout=10\""
echo "DIRECT_URL=\"postgresql://${DB_USER}:${DB_PASS}@${VPN_HOST}:5432/${DB_NAME}?schema=public&connect_timeout=10\""
echo ""
echo "# schema.prisma:"
echo "datasource db {"
echo "  provider  = \"postgresql\""
echo "  url       = env(\"DATABASE_URL\")"
echo "  directUrl = env(\"DIRECT_URL\")"
echo "}"
echo ""
echo "============================================================"
echo "ВАЖЛИВО: збережи пароль зараз — він більше не відображатиметься!"
echo "  DB:   $DB_NAME"
echo "  User: $DB_USER"
echo "  Pass: $DB_PASS"
echo "============================================================"
