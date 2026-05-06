#!/bin/bash
set -euo pipefail
PROJECT="${1:-}"
VPN_HOST="${VPN_HOST:-YOUR_VPN_IP_OR_HOSTNAME}"
DB_NAME="${PROJECT}"
DB_USER="${PROJECT}_user"
DB_PASS=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9!@#%^&*' | head -c 32)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
set -a && source "$ENV_FILE" && set +a
docker exec -i postgres psql -U "$POSTGRES_USER" <<SQL
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS'; END IF; END \$\$;
SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') \gexec
SQL
echo "DATABASE_URL=\"postgresql://${DB_USER}:${DB_PASS}@${VPN_HOST}:6432/${DB_NAME}?schema=public&pgbouncer=true\""
echo "DIRECT_URL=\"postgresql://${DB_USER}:${DB_PASS}@${VPN_HOST}:5432/${DB_NAME}?schema=public\""
