#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# upgrade.sh — Pull latest changes and restart services.
# Does NOT remove volumes or wipe data.
#
# Usage:
#   ./scripts/upgrade.sh [--stack-dir /path/to/docker]
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-dir) STACK_DIR="$2"; shift 2 ;;
    *)
      echo "Unknown arg: $1"
      echo "Usage: $0 [--stack-dir /path/to/docker]"
      exit 1 ;;
  esac
done

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

REPO_ROOT="$(cd "$STACK_DIR/.." && pwd)"
ENV_FILE="$STACK_DIR/.env"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"

[[ -f "$ENV_FILE" ]]     || die ".env not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || die "docker-compose.yml not found"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is not installed"

# --- Git pull if inside a repo ---
if [[ -d "$REPO_ROOT/.git" ]]; then
  log "Pulling latest changes"
  # Stash any on-server config overrides before pull to avoid conflicts
  git -C "$REPO_ROOT" stash push --include-untracked -m "upgrade-stash-$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  git -C "$REPO_ROOT" pull --ff-only
fi

chmod +x "$STACK_DIR/scripts/"*.sh "$STACK_DIR/backup/"*.sh

# --- Restart stack (no volume wipe) ---
log "Restarting stack (data volumes preserved)"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

# --- Healthcheck ---
if [[ -x "$STACK_DIR/scripts/healthcheck.sh" ]]; then
  log "Running healthcheck"
  bash "$STACK_DIR/scripts/healthcheck.sh" || true
fi

log "Upgrade complete."
