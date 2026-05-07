#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# install.sh — First-time install of the PostgreSQL stack.
#
# What it does:
#   1. Clones repo (optional) or runs locally
#   2. Creates .env from template if absent, then exits to let
#      the user fill it in
#   3. Validates all CHANGE_ME_* are replaced
#   4. Bootstraps pgbouncer/userlist.txt from .env
#   5. Ensures pgbouncer.ini admin user and postgres DB mapping
#   6. Starts the full stack
#
# Usage (already cloned, run from repo root or docker/):
#   bash docker/scripts/install.sh --local
#
# Usage (clone + install in one step):
#   bash docker/scripts/install.sh \
#     --repo-url https://github.com/<owner>/<repo>.git \
#     --target-dir /root/apps/postgres-stack
# ============================================================

REPO_URL=""
TARGET_DIR="/root/apps/postgres-stack"
LOCAL_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)   REPO_URL="$2";    shift 2 ;;
    --target-dir) TARGET_DIR="$2";  shift 2 ;;
    --local)      LOCAL_MODE="true"; shift 1 ;;
    *)
      echo "Unknown arg: $1"
      echo "Usage: $0 [--repo-url URL --target-dir DIR] | [--local]"
      exit 1 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# --- Prereq checks ---
command -v docker >/dev/null 2>&1        || die "docker is not installed"
docker compose version >/dev/null 2>&1   || die "docker compose plugin is not installed"

# --- Resolve stack dir ---
if [[ "$LOCAL_MODE" == "true" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  [[ -n "$REPO_URL" ]] || die "--repo-url required (or use --local)"
  mkdir -p "$(dirname "$TARGET_DIR")"
  if [[ -d "$TARGET_DIR/.git" ]]; then
    log "Repo already cloned — pulling latest"
    git -C "$TARGET_DIR" pull --ff-only
  else
    log "Cloning $REPO_URL → $TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
  STACK_DIR="$TARGET_DIR/docker"
fi

ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
PGB_INI="$STACK_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$STACK_DIR/pgbouncer/userlist.txt"

# --- Env bootstrap ---
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$STACK_DIR/.env.example" "$ENV_FILE"
  log "Created $ENV_FILE from template."
  echo ""
  echo "  Fill in your values:"
  echo "    nano $ENV_FILE"
  echo ""
  echo "  Then re-run: bash $0 --local"
  echo ""
  exit 0
fi

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Replace all CHANGE_ME_* values in $ENV_FILE then re-run."
fi

# --- Make scripts executable ---
chmod +x "$STACK_DIR/scripts/"*.sh "$STACK_DIR/backup/"*.sh

# --- Load env ---
set -a && source "$ENV_FILE" && set +a

# --- Bootstrap pgbouncer/userlist.txt ---
if [[ ! -f "$USERLIST_FILE" ]] || ! grep -q "^\"${POSTGRES_USER}\" " "$USERLIST_FILE"; then
  log "Writing initial PgBouncer userlist for admin user"
  [[ "${POSTGRES_PASSWORD}" != *\"* ]] || die "POSTGRES_PASSWORD must not contain double quotes."
  printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > "$USERLIST_FILE"
fi

# --- Ensure pgbouncer.ini has postgres maintenance DB mapping ---
PGB_POSTGRES_LINE="postgres = host=postgres port=5432 dbname=postgres user=${POSTGRES_USER}"
if ! grep -qE "^postgres[[:space:]]*=" "$PGB_INI"; then
  sed -i "/^\[databases\]/a ${PGB_POSTGRES_LINE}" "$PGB_INI"
  log "Added 'postgres' maintenance DB mapping to pgbouncer.ini"
fi

# --- Sync admin_users / stats_users in pgbouncer.ini ---
sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"

# --- Start stack ---
log "Starting stack"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

log "Install complete."
echo ""
echo "  healthcheck : bash $STACK_DIR/scripts/healthcheck.sh"
echo "  provision db: bash $STACK_DIR/scripts/provision-db.sh <db_name> <db_user> <password>"
