#!/bin/bash
# ============================================================
# PostgreSQL Restore Script
# Використання:
#   ./restore.sh <db_name> <backup_file.dump>
#   ./restore.sh all <full_TIMESTAMP.sql.gz>
# ============================================================
set -euo pipefail

DB_NAME="${1:-}"
BACKUP_FILE="${2:-}"
PG_HOST="${POSTGRES_HOST:-postgres}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_USER="${POSTGRES_USER:-pgadmin}"
PGPASSWORD="${POSTGRES_PASSWORD}"

export PGPASSWORD

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

if [ -z "$DB_NAME" ] || [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <db_name|all> <backup_file>"
  echo "  db_name=all  -> restore from full pg_dumpall .sql.gz"
  echo "  db_name=app1 -> restore from per-db .dump (custom format)"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "ERROR: Backup file not found: $BACKUP_FILE"
  exit 1
fi

if [ "$DB_NAME" = "all" ]; then
  log "Restoring ALL databases from $BACKUP_FILE"
  gunzip -c "$BACKUP_FILE" | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" postgres
  log "Full restore completed."
else
  log "Restoring database '$DB_NAME' from $BACKUP_FILE"
  pg_restore \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -d "$DB_NAME" \
    --clean \
    --if-exists \
    -v \
    "$BACKUP_FILE"
  log "Restore of '$DB_NAME' completed."
fi
