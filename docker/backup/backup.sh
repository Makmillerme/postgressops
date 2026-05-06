#!/bin/bash
set -euo pipefail
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DEST_PATH:-/backups}"
PG_HOST="${POSTGRES_HOST:-postgres}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_USER="${POSTGRES_USER:-pgadmin}"
PGPASSWORD="${POSTGRES_PASSWORD}"
export PGPASSWORD
mkdir -p "$BACKUP_DIR/full"
pg_dumpall -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" --clean --if-exists | gzip > "$BACKUP_DIR/full/full_${TIMESTAMP}.sql.gz"
