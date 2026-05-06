#!/usr/bin/env bash
set -euo pipefail

# Update and restart existing installation.
# Usage:
#   ./scripts/deploy.sh --stack-dir /root/apps/postgres-prisma-stack/docker

STACK_DIR="/root/apps/postgres-prisma-stack/docker"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack-dir)
      STACK_DIR="$2"; shift 2 ;;
    *)
      echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ ! -d "$STACK_DIR" ]]; then
  echo "ERROR: stack dir not found: $STACK_DIR"
  exit 1
fi

REPO_ROOT="$(cd "$STACK_DIR/.." && pwd)"
if [[ -d "$REPO_ROOT/.git" ]]; then
  git -C "$REPO_ROOT" pull --ff-only
fi

chmod +x "$STACK_DIR/scripts/"*.sh "$STACK_DIR/backup/"*.sh

docker compose -f "$STACK_DIR/docker-compose.yml" --env-file "$STACK_DIR/.env" up -d --remove-orphans
docker compose -f "$STACK_DIR/docker-compose.yml" --env-file "$STACK_DIR/.env" ps

if [[ -x "$STACK_DIR/scripts/healthcheck.sh" ]]; then
  "$STACK_DIR/scripts/healthcheck.sh" || true
fi

echo "Deploy done."
