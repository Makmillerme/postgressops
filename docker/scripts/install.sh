#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# install.sh — First-time install of the PostgreSQL stack.
#
# Usage (remote clone + install):
#   ./install.sh --repo-url https://github.com/<owner>/<repo>.git \
#                --target-dir /root/apps/postgres-stack
#
# Usage (already cloned, run from inside docker/):
#   ./install.sh --local
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

die()  { echo "ERROR: $*" >&2; exit 1; }
log()  { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# --- Prereq checks ---
command -v docker >/dev/null 2>&1         || die "docker is not installed"
docker compose version >/dev/null 2>&1    || die "docker compose plugin is not installed"

# --- Resolve stack dir ---
if [[ "$LOCAL_MODE" == "true" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  [[ -n "$REPO_URL" ]] || die "--repo-url required (or use --local)"
  mkdir -p "$(dirname "$TARGET_DIR")"
  if [[ -d "$TARGET_DIR/.git" ]]; then
    log "Repo already exists, pulling latest…"
    git -C "$TARGET_DIR" pull --ff-only
  else
    log "Cloning $REPO_URL → $TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
  STACK_DIR="$TARGET_DIR/docker"
fi

ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

# --- Env bootstrap ---
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$STACK_DIR/.env.example" "$ENV_FILE"
  log "Created $ENV_FILE from template — fill in real values before continuing."
  echo ""
  echo "  nano $ENV_FILE"
  echo ""
  exit 0
fi

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Replace all CHANGE_ME_* values in $ENV_FILE then re-run."
fi

# --- Make scripts executable ---
chmod +x "$STACK_DIR/scripts/"*.sh "$STACK_DIR/backup/"*.sh

# --- Start stack ---
log "Starting stack…"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

log "Install complete."
echo ""
echo "Next steps:"
echo "  healthcheck : bash $STACK_DIR/scripts/healthcheck.sh"
echo "  provision db: bash $STACK_DIR/scripts/provision-db.sh <db_name> <db_user> <password>"
