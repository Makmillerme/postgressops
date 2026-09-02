#!/bin/bash
# ============================================================
# PostgreSQL Backup Script — Full + WAL
# Виконується всередині backup-контейнера за розкладом cron.
# ============================================================
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DEST_PATH:-/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
PG_HOST="${POSTGRES_HOST:-postgres}"
PG_PORT="${POSTGRES_PORT:-5432}"
PG_USER="${POSTGRES_USER:-pgadmin}"
# Завжди system DB для admin/psql (не POSTGRES_DB з .env — там може бути кастомне ім’я без фактичної БД)
PSQL_ADMIN_DB="${POSTGRES_MAINTENANCE_DB:-postgres}"
PGPASSWORD="${POSTGRES_PASSWORD}"

export PGPASSWORD

mkdir -p "$BACKUP_DIR/full" "$BACKUP_DIR/wal"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# --- Full backup: pg_dumpall (усі бази) ---
log "Starting full backup: $TIMESTAMP"
pg_dumpall \
  -h "$PG_HOST" \
  -p "$PG_PORT" \
  -U "$PG_USER" \
  --clean \
  --if-exists \
  | gzip > "$BACKUP_DIR/full/full_${TIMESTAMP}.sql.gz"

log "Full backup saved: $BACKUP_DIR/full/full_${TIMESTAMP}.sql.gz"

# --- Per-database backup (зручніший restore) ---
# Список БД: підключатися до maintenance DB (зазвичай postgres), інакше psql шукає БД з іменем юзера
DATABASES=$(psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PSQL_ADMIN_DB" -t -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

for DB in $DATABASES; do
  DB=$(echo "$DB" | tr -d '[:space:]')
  [ -z "$DB" ] && continue
  log "Dumping database: $DB"
  pg_dump \
    -h "$PG_HOST" \
    -p "$PG_PORT" \
    -U "$PG_USER" \
    -Fc \
    -d "$DB" \
    -f "$BACKUP_DIR/full/${DB}_${TIMESTAMP}.dump"
  log "Saved: $BACKUP_DIR/full/${DB}_${TIMESTAMP}.dump"
done

# --- Rotate old backups ---
log "Rotating backups older than $RETENTION_DAYS days"
find "$BACKUP_DIR/full" -type f -mtime "+$RETENTION_DAYS" -delete

log "Backup completed successfully."
