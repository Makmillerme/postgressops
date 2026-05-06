#!/usr/bin/env bash
set -euo pipefail

# One-shot installer for PostgreSQL Prisma stack.
# Usage:
#   ./scripts/install.sh --repo-url https://github.com/<owner>/<repo>.git --target-dir /root/apps/postgres-prisma-stack --vpn-host 91.239.232.91 --vpn-bind-ip 91.239.232.91
#   ./scripts/install.sh --local --vpn-host 91.239.232.91 --vpn-bind-ip 91.239.232.91

REPO_URL=""
TARGET_DIR="/root/apps/postgres-prisma-stack"
VPN_HOST="91.239.232.91"
VPN_BIND_IP="91.239.232.91"
LOCAL_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)
      REPO_URL="$2"; shift 2 ;;
    --target-dir)
      TARGET_DIR="$2"; shift 2 ;;
    --vpn-host)
      VPN_HOST="$2"; shift 2 ;;
    --vpn-bind-ip)
      VPN_BIND_IP="$2"; shift 2 ;;
    --local)
      LOCAL_MODE="true"; shift 1 ;;
    *)
      echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ "$LOCAL_MODE" != "true" && -z "$REPO_URL" ]]; then
  echo "ERROR: --repo-url required (or use --local)"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is not installed"
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin is not installed"
  exit 1
fi

if [[ "$LOCAL_MODE" == "true" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  STACK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  mkdir -p "$(dirname "$TARGET_DIR")"
  if [[ -d "$TARGET_DIR/.git" ]]; then
    git -C "$TARGET_DIR" pull --ff-only
  else
    git clone "$REPO_URL" "$TARGET_DIR"
  fi
  STACK_DIR="$TARGET_DIR/docker"
fi

if [[ ! -f "$STACK_DIR/.env" ]]; then
  cp "$STACK_DIR/.env.example" "$STACK_DIR/.env"
  echo "Created $STACK_DIR/.env from template."
fi

if grep -q "CHANGE_ME_" "$STACK_DIR/.env"; then
  echo "ERROR: replace all CHANGE_ME_* values in $STACK_DIR/.env"
  exit 1
fi

COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
if grep -q '0.0.0.0:6432:6432' "$COMPOSE_FILE"; then
  sed -i "s/0.0.0.0:6432:6432/${VPN_BIND_IP}:6432:6432/g" "$COMPOSE_FILE"
fi

chmod +x "$STACK_DIR/scripts/"*.sh "$STACK_DIR/backup/"*.sh

docker compose -f "$COMPOSE_FILE" --env-file "$STACK_DIR/.env" up -d
docker compose -f "$COMPOSE_FILE" --env-file "$STACK_DIR/.env" ps

echo ""
echo "Install completed."
echo "VPN host for Prisma URLs: $VPN_HOST"
echo "Run next:"
echo "  cd \"$STACK_DIR\""
echo "  VPN_HOST=$VPN_HOST ./scripts/add-project.sh myapp"
