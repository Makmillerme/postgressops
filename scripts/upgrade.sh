#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_DIR="$REPO_DIR/docker"
ENV_FILE="$DOCKER_DIR/.env"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -f "$ENV_FILE" ]] || die ".env not found: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || die "docker-compose.yml not found: $COMPOSE_FILE"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is not installed"

if [[ -d "$REPO_DIR/.git" ]]; then
  git -C "$REPO_DIR" stash push --include-untracked -m "upgrade-stash-$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  git -C "$REPO_DIR" pull --ff-only || true
fi

chmod +x "$SCRIPT_DIR/"*.sh "$DOCKER_DIR/backup/"*.sh 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

if [[ -x "$SCRIPT_DIR/healthcheck.sh" ]]; then
  bash "$SCRIPT_DIR/healthcheck.sh" || true
fi

log "Upgrade complete."
