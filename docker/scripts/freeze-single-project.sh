#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# freeze-single-project.sh
# Safe reconfiguration for one active project without data wipe.
# - Keeps Docker volumes intact (NO down -v)
# - Keeps one PROJECT_<KEY>_* block in .env, removes the rest
# - Rebuilds PgBouncer [databases] and userlist for admin + one app user
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"
PROJECT_KEY="APP1"
AUTO_YES="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-key)
      PROJECT_KEY="$2"; shift 2 ;;
    --yes|-y)
      AUTO_YES="true"; shift 1 ;;
    --stack-dir)
      STACK_DIR="$2"
      ENV_FILE="$STACK_DIR/.env"
      PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
      USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"
      shift 2 ;;
    *)
      echo "Unknown arg: $1"
      echo "Usage: $0 [--project-key APP1] [--yes] [--stack-dir /path/to/docker]"
      exit 1 ;;
  esac
done

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die ".env not found: $ENV_FILE"
[[ -f "$PGB_INI" ]] || die "pgbouncer.ini not found: $PGB_INI"
[[ -f "$USERLIST_FILE" ]] || die "userlist.txt not found: $USERLIST_FILE"

set -a && source "$ENV_FILE" && set +a

[[ -n "${POSTGRES_USER:-}" ]] || die "POSTGRES_USER is empty in .env"
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD is empty in .env"

DB_VAR="PROJECT_${PROJECT_KEY}_DB"
USER_VAR="PROJECT_${PROJECT_KEY}_USER"
PASS_VAR="PROJECT_${PROJECT_KEY}_PASS"

PROJECT_DB="${!DB_VAR:-}"
PROJECT_USER="${!USER_VAR:-}"
PROJECT_PASS="${!PASS_VAR:-}"

[[ -n "$PROJECT_DB" ]] || die "$DB_VAR not found in .env"
[[ -n "$PROJECT_USER" ]] || die "$USER_VAR not found in .env"
[[ -n "$PROJECT_PASS" ]] || die "$PASS_VAR not found in .env"

if [[ "$AUTO_YES" != "true" ]]; then
  echo ""
  echo "Will keep only project key: $PROJECT_KEY"
  echo "  DB:   $PROJECT_DB"
  echo "  USER: $PROJECT_USER"
  echo ""
  echo "Will update:"
  echo "  - .env (remove other PROJECT_* entries)"
  echo "  - pgbouncer.ini [databases]"
  echo "  - pgbouncer/userlist.txt"
  echo "  - recreate pgbouncer only (NO data volume removal)"
  echo ""
  read -r -p "Type YES to continue: " answer
  [[ "$answer" == "YES" ]] || die "Aborted by user."
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$ENV_FILE" "${ENV_FILE}.bak.${TS}"
cp "$PGB_INI" "${PGB_INI}.bak.${TS}"
cp "$USERLIST_FILE" "${USERLIST_FILE}.bak.${TS}"
log "Backups created with suffix .bak.${TS}"

log "Rewriting .env (keep only PROJECT_${PROJECT_KEY}_*)"
awk -v keep="$PROJECT_KEY" '
  /^PROJECT_[A-Z0-9_]+_(DB|USER|PASS)=/ {
    if ($0 ~ ("^PROJECT_" keep "_(DB|USER|PASS)=")) print;
    next
  }
  { print }
' "$ENV_FILE" > "${ENV_FILE}.tmp"
mv "${ENV_FILE}.tmp" "$ENV_FILE"

log "Rebuilding pgbouncer [databases] for one project"
TMP_INI="$(mktemp)"
awk '
  BEGIN { in_db=0 }
  /^\[databases\]/ { print; in_db=1; next }
  /^\[/ && in_db==1 { in_db=0; print; next }
  { if (in_db==0) print }
' "$PGB_INI" > "$TMP_INI"

awk -v db="$PROJECT_DB" -v usr="$PROJECT_USER" '
  /^\[databases\]/ {
    print
    printf "%s = host=postgres port=5432 dbname=%s user=%s\n", db, db, usr
    next
  }
  { print }
' "$TMP_INI" > "$PGB_INI"
rm -f "$TMP_INI"

sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"

log "Rewriting pgbouncer/userlist.txt"
cat > "$USERLIST_FILE" <<EOF
"$POSTGRES_USER" "$POSTGRES_PASSWORD"
"$PROJECT_USER" "$PROJECT_PASS"
EOF

log "Applying PgBouncer changes (safe: no volume wipe)"
docker compose -f "$STACK_DIR/docker-compose.yml" --env-file "$ENV_FILE" up -d pgbouncer --force-recreate

log "Quick verification"
docker exec postgres pg_isready -U "$POSTGRES_USER" -d "${POSTGRES_DB:-postgres}" >/dev/null
PGPASSWORD="$PROJECT_PASS" psql "host=127.0.0.1 port=${PGBOUNCER_LISTEN_PORT:-6432} dbname=${PROJECT_DB} user=${PROJECT_USER} sslmode=disable" -c "SELECT 1;" >/dev/null

echo ""
echo "============================================================"
echo "Done. Single project mode enabled for key: $PROJECT_KEY"
echo "Database: $PROJECT_DB"
echo "User:     $PROJECT_USER"
echo "Backups:  ${ENV_FILE}.bak.${TS}, ${PGB_INI}.bak.${TS}, ${USERLIST_FILE}.bak.${TS}"
echo "No data volumes were removed."
echo "============================================================"
