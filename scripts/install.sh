#!/usr/bin/env bash
set -euo pipefail

REPO_URL=""
TARGET_DIR="${POSTGRESSOPS_HOME:-/opt/postgressops}"
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

command -v docker >/dev/null 2>&1      || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is not installed"

if [[ "$LOCAL_MODE" == "true" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  [[ -n "$REPO_URL" ]] || die "--repo-url required (or use --local)"
  mkdir -p "$(dirname "$TARGET_DIR")"
  if [[ -d "$TARGET_DIR/.git" ]]; then
    log "Repo already cloned — pulling latest"
    git -C "$TARGET_DIR" pull --ff-only
  else
    log "Cloning $REPO_URL -> $TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
  REPO_DIR="$TARGET_DIR"
fi

# shellcheck source=lib/ensure-executable.sh
source "$REPO_DIR/scripts/lib/ensure-executable.sh"
ensure_postgressops_executable "$REPO_DIR"

DOCKER_DIR="$REPO_DIR/docker"
SCRIPTS_DIR="$REPO_DIR/scripts"
ENV_FILE="$DOCKER_DIR/.env"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
PGB_INI="$DOCKER_DIR/pgbouncer/pgbouncer.ini"
USERLIST_FILE="$DOCKER_DIR/pgbouncer/userlist.txt"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$DOCKER_DIR/.env.example" "$ENV_FILE"
  log "Created $ENV_FILE from template."
  echo ""
  echo "Fill in your values and rerun:"
  echo "  nano $ENV_FILE"
  echo "  bash $SCRIPTS_DIR/install.sh --local"
  echo ""
  exit 0
fi

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Replace all CHANGE_ME_* values in $ENV_FILE then rerun."
fi

set -a && source "$ENV_FILE" && set +a

if [[ ! -f "$USERLIST_FILE" ]] || ! grep -q "^\"${POSTGRES_USER}\" " "$USERLIST_FILE"; then
  [[ "${POSTGRES_PASSWORD}" != *\"* ]] || die "POSTGRES_PASSWORD must not contain double quotes."
  printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > "$USERLIST_FILE"
  log "Wrote admin user to userlist.txt"
fi

PGB_POSTGRES_LINE="postgres = host=postgres port=5432 dbname=postgres user=${POSTGRES_USER}"
if ! grep -qE "^postgres[[:space:]]*=" "$PGB_INI"; then
  sed -i "/^\[databases\]/a ${PGB_POSTGRES_LINE}" "$PGB_INI"
  log "Added postgres mapping to pgbouncer.ini"
fi

sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
bash "$SCRIPTS_DIR/fix-wal-archive.sh" || true
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

echo ""
echo "Install complete."
echo "  bash $SCRIPTS_DIR/healthcheck.sh"
echo "  bash $SCRIPTS_DIR/provision-db.sh <db_name> <db_user> <password>"
