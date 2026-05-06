#!/bin/bash
set -euo pipefail
DB_NAME="${1:-}"
BACKUP_FILE="${2:-}"
PGPASSWORD="${POSTGRES_PASSWORD}"
export PGPASSWORD
if [ "$DB_NAME" = "all" ]; then
  gunzip -c "$BACKUP_FILE" | psql -h "${POSTGRES_HOST:-postgres}" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USER:-pgadmin}" postgres
else
  pg_restore -h "${POSTGRES_HOST:-postgres}" -p "${POSTGRES_PORT:-5432}" -U "${POSTGRES_USER:-pgadmin}" -d "$DB_NAME" --clean --if-exists -v "$BACKUP_FILE"
fi
