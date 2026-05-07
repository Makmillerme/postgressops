#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# server-update.sh
# One-command server bootstrap/update for this PostgreSQL pack.
#
# What it does:
# 1) Ensures Node.js 20 + npm (for MCP server)
# 2) Ensures docker/.env exists
# 3) Runs stack upgrade (no data wipe)
# 4) Ensures MCP .env exists and has correct defaults for this stack
# 5) Installs MCP dependencies and validates entrypoint syntax
#
# Usage:
#   bash scripts/server-update.sh
# ============================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="$ROOT_DIR/docker"
MCP_DIR="$ROOT_DIR/tools/mcp-postgres-ops"
DOCKER_ENV="$DOCKER_DIR/.env"
MCP_ENV="$MCP_DIR/.env"

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$DOCKER_DIR" ]] || die "docker/ directory not found in $ROOT_DIR"
[[ -d "$MCP_DIR" ]] || die "tools/mcp-postgres-ops/ not found in $ROOT_DIR"

command -v docker >/dev/null 2>&1 || die "docker is not installed"
docker compose version >/dev/null 2>&1 || die "docker compose plugin is not installed"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  log "Installing Node.js 20 (required for MCP)"
  apt update
  apt install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt install -y nodejs
fi

log "Node version: $(node -v)"
log "NPM version: $(npm -v)"

if [[ ! -f "$DOCKER_ENV" ]]; then
  log "Creating docker/.env from template"
  cp "$DOCKER_DIR/.env.example" "$DOCKER_ENV"
fi

chmod +x "$DOCKER_DIR/scripts/"*.sh "$DOCKER_DIR/backup/"*.sh

log "Upgrading stack (no wipe)"
bash "$DOCKER_DIR/scripts/upgrade.sh" --stack-dir "$DOCKER_DIR"

if [[ ! -f "$MCP_ENV" ]]; then
  log "Creating MCP .env from template"
  cp "$MCP_DIR/.env.example" "$MCP_ENV"
fi

log "Normalizing MCP runtime env"
if grep -q '^PG_PORT=' "$MCP_ENV"; then
  sed -i 's/^PG_PORT=.*/PG_PORT=6432/' "$MCP_ENV"
else
  printf '\nPG_PORT=6432\n' >> "$MCP_ENV"
fi

if grep -q '^STACK_DIR=' "$MCP_ENV"; then
  sed -i "s|^STACK_DIR=.*|STACK_DIR=$DOCKER_DIR|" "$MCP_ENV"
else
  printf '\nSTACK_DIR=%s\n' "$DOCKER_DIR" >> "$MCP_ENV"
fi

log "Installing MCP dependencies"
cd "$MCP_DIR"
npm install
node --check src/index.js

log "Final stack healthcheck"
bash "$DOCKER_DIR/scripts/healthcheck.sh" || true

echo ""
echo "============================================================"
echo "Server update completed."
echo ""
echo "MCP is ready at:"
echo "  $MCP_DIR/src/index.js"
echo ""
echo "Next:"
echo "  1) Ensure your local Cursor can SSH to this server without password."
echo "  2) Configure local ~/.cursor/mcp.json to run via ssh:"
echo "     ssh -T root@<server-ip> 'cd $MCP_DIR && node src/index.js'"
echo "============================================================"
