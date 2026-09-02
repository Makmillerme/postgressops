#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# server-update.sh — One-command server bootstrap/update.
#
# Run this script whenever you:
#   - Set up the server for the first time
#   - Pull new changes from GitHub
#   - Need to ensure the stack + MCP are in a healthy state
#
# What it does:
#   1.  Check required tools (docker, git, node)
#   2.  Pull latest changes from origin/main
#   3.  Ensure docker/.env exists (creates from template if needed)
#   4.  Bootstrap pgbouncer.ini: postgres DB mapping + admin_users
#   5.  Upgrade Docker stack (no volume wipe)
#   6.  Ensure tools/mcp-postgres-ops/.env exists and is correct
#   7.  Install MCP npm dependencies
#   8.  Final healthcheck
#
# Usage (from the repo root, as root):
#   bash scripts/server-update.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_DIR="$REPO_DIR/docker"
MCP_DIR="$REPO_DIR/tools/mcp-postgres-ops"
ENV_FILE="$DOCKER_DIR/.env"
MCP_ENV_FILE="$MCP_DIR/.env"
PGB_INI="$DOCKER_DIR/pgbouncer/pgbouncer.ini"

TS()  { date +'%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(TS)] $*"; }
die() { echo "[$(TS)] FATAL: $*" >&2; exit 1; }
ok()  { echo "[$(TS)] OK: $*"; }

STEP=0
step() {
  STEP=$((STEP + 1))
  echo ""
  echo "============================================================"
  echo "[$(TS)] STEP $STEP: $*"
  echo "============================================================"
}

# ============================================================
# Step 1: Prerequisite checks
# ============================================================
step "Checking prerequisites"

command -v docker >/dev/null 2>&1       || die "docker not found. Install Docker first."
docker compose version >/dev/null 2>&1  || die "docker compose plugin not found."
command -v git >/dev/null 2>&1          || die "git not found."
command -v node >/dev/null 2>&1 || {
  log "Node.js not found — installing Node.js 20..."
  apt-get update -qq
  apt-get install -y curl ca-certificates gnupg >/dev/null
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null
  apt-get install -y nodejs >/dev/null
}
command -v node >/dev/null 2>&1 || die "Node.js install failed."

NODE_VER="$(node --version)"
NPM_VER="$(npm --version)"
ok "node=$NODE_VER npm=$NPM_VER"

# ============================================================
# Step 2: Git pull
# ============================================================
step "Pulling latest changes from origin"

[[ -d "$REPO_DIR/.git" ]] || die "$REPO_DIR is not a git repo."

CURRENT_BRANCH="$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
log "Branch: $CURRENT_BRANCH"

# Stash any local modifications so pull succeeds
if ! git -C "$REPO_DIR" diff --quiet; then
  STASH_LABEL="server-update-stash-$(date +'%Y%m%d_%H%M%S')"
  log "Stashing local changes as: $STASH_LABEL"
  git -C "$REPO_DIR" stash push -m "$STASH_LABEL"
fi

git -C "$REPO_DIR" pull --ff-only origin "$CURRENT_BRANCH" \
  && ok "Git pull complete." \
  || { log "WARNING: git pull failed (network/conflict). Continuing with local state."; }

# Ensure scripts are executable after pull
chmod +x "$SCRIPT_DIR/"*.sh "$DOCKER_DIR/backup/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/"*.sh 2>/dev/null || true

# ============================================================
# Step 3: Ensure docker/.env exists
# ============================================================
step "Checking docker/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  log "docker/.env not found — creating from template"
  cp "$DOCKER_DIR/.env.example" "$ENV_FILE"
  echo ""
  echo "  ACTION REQUIRED: Fill in your values in:"
  echo "    $ENV_FILE"
  echo ""
  echo "  Then re-run this script: bash $0"
  exit 0
fi

if grep -q "CHANGE_ME_" "$ENV_FILE"; then
  die "Found CHANGE_ME_* placeholders in $ENV_FILE. Fill them in and re-run."
fi

set -a && source "$ENV_FILE" && set +a
ok "docker/.env loaded. POSTGRES_USER=$POSTGRES_USER"

# ============================================================
# Step 4: Bootstrap PgBouncer config
# ============================================================
step "Bootstrapping PgBouncer config"

# 4a. userlist.txt
USERLIST_FILE="$DOCKER_DIR/pgbouncer/userlist.txt"
if [[ ! -f "$USERLIST_FILE" ]] || ! grep -q "^\"${POSTGRES_USER}\" " "$USERLIST_FILE"; then
  log "Writing admin user to pgbouncer/userlist.txt"
  [[ "${POSTGRES_PASSWORD}" != *\"* ]] || die "POSTGRES_PASSWORD must not contain double quotes."
  printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > "$USERLIST_FILE"
  ok "pgbouncer/userlist.txt bootstrapped."
else
  ok "pgbouncer/userlist.txt already has admin user entry."
fi

# 4b. postgres DB mapping in pgbouncer.ini
PGB_POSTGRES_LINE="postgres = host=postgres port=5432 dbname=postgres user=${POSTGRES_USER}"
if ! grep -qE "^postgres[[:space:]]*=" "$PGB_INI"; then
  sed -i "/^\[databases\]/a ${PGB_POSTGRES_LINE}" "$PGB_INI"
  ok "Added 'postgres' maintenance DB mapping to pgbouncer.ini"
else
  ok "pgbouncer.ini already has 'postgres' mapping."
fi

# 4c. admin_users / stats_users
sed -i \
  -e "s/^admin_users = .*/admin_users = ${POSTGRES_USER}/" \
  -e "s/^stats_users = .*/stats_users = ${POSTGRES_USER}/" \
  "$PGB_INI"
ok "pgbouncer.ini admin_users/stats_users set to $POSTGRES_USER"

# ============================================================
# Step 5: Upgrade Docker stack (no volume wipe)
# ============================================================
step "Upgrading Docker stack"

COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull --quiet 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --remove-orphans

# Wait for postgres healthy
log "Waiting for postgres..."
RETRIES=60
until [[ "$RETRIES" -eq 0 ]]; do
  STATUS="$(docker inspect -f '{{.State.Health.Status}}' postgres 2>/dev/null || true)"
  [[ "$STATUS" == "healthy" ]] && break
  RETRIES=$((RETRIES - 1))
  sleep 2
done
[[ "$RETRIES" -gt 0 ]] || die "Postgres did not become healthy within 120s."
ok "Postgres healthy."

# Wait for pgbouncer healthy
log "Waiting for pgbouncer..."
RETRIES=30
until [[ "$RETRIES" -eq 0 ]]; do
  STATUS="$(docker inspect -f '{{.State.Health.Status}}' pgbouncer 2>/dev/null || true)"
  [[ "$STATUS" == "healthy" ]] && break
  RETRIES=$((RETRIES - 1))
  sleep 2
done
[[ "$RETRIES" -gt 0 ]] || die "PgBouncer did not become healthy within 60s."
ok "PgBouncer healthy."

bash "$SCRIPT_DIR/fix-wal-archive.sh" || log "WARNING: wal_archive fix failed (non-fatal)."

# ============================================================
# Step 6: Ensure MCP .env exists and is correct
# ============================================================
step "Configuring MCP environment"

if [[ ! -f "$MCP_ENV_FILE" ]]; then
  log "MCP .env not found — creating from template"
  cp "$MCP_DIR/.env.example" "$MCP_ENV_FILE"
fi

# Normalize PG_PORT to 6432 (PgBouncer, not direct Postgres)
if grep -q "^PG_PORT=" "$MCP_ENV_FILE"; then
  sed -i "s/^PG_PORT=.*/PG_PORT=${PGBOUNCER_LISTEN_PORT:-6432}/" "$MCP_ENV_FILE"
else
  echo "PG_PORT=${PGBOUNCER_LISTEN_PORT:-6432}" >> "$MCP_ENV_FILE"
fi
ok "PG_PORT set to ${PGBOUNCER_LISTEN_PORT:-6432}"

# Normalize STACK_DIR to actual path
REAL_DOCKER_DIR="$(realpath "$DOCKER_DIR")"
if grep -q "^STACK_DIR=" "$MCP_ENV_FILE"; then
  sed -i "s|^STACK_DIR=.*|STACK_DIR=${REAL_DOCKER_DIR}|" "$MCP_ENV_FILE"
else
  echo "STACK_DIR=${REAL_DOCKER_DIR}" >> "$MCP_ENV_FILE"
fi
ok "STACK_DIR set to $REAL_DOCKER_DIR"

REAL_SCRIPTS_DIR="$(realpath "$SCRIPT_DIR")"
if grep -q "^SCRIPTS_DIR=" "$MCP_ENV_FILE"; then
  sed -i "s|^SCRIPTS_DIR=.*|SCRIPTS_DIR=${REAL_SCRIPTS_DIR}|" "$MCP_ENV_FILE"
else
  echo "SCRIPTS_DIR=${REAL_SCRIPTS_DIR}" >> "$MCP_ENV_FILE"
fi
ok "SCRIPTS_DIR set to $REAL_SCRIPTS_DIR"

# Fill in credentials from docker/.env if still placeholders
if grep -q "CHANGE_ME_" "$MCP_ENV_FILE"; then
  sed -i \
    -e "s|^PG_USER=CHANGE_ME.*|PG_USER=${POSTGRES_USER}|" \
    -e "s|^PG_PASSWORD=CHANGE_ME.*|PG_PASSWORD=${POSTGRES_PASSWORD}|" \
    "$MCP_ENV_FILE"
  ok "MCP credentials filled from docker/.env"
fi

# ============================================================
# Step 7: Install MCP npm dependencies
# ============================================================
step "Installing MCP dependencies"

cd "$MCP_DIR"
npm install --prefer-offline --no-audit 2>&1 | tail -5
ok "npm install complete"

# ============================================================
# Step 8: Final healthcheck
# ============================================================
step "Final stack healthcheck"

bash "$SCRIPT_DIR/healthcheck.sh" || true

# ============================================================
# Summary
# ============================================================
echo ""
echo "============================================================"
echo "  Server update completed."
echo ""
echo "  Stack:       running ($DOCKER_DIR)"
echo "  MCP server:  $MCP_DIR/src/index.js"
echo ""
echo "  Next steps — Cursor MCP setup:"
echo "  1) Ensure SSH key auth works:"
echo "       ssh -o BatchMode=yes root@$(hostname -I | awk '{print $1}') echo ok"
echo ""
REAL_REPO_DIR="$(realpath "$REPO_DIR")"
echo "  2) Add to your local ~/.cursor/mcp.json (see .cursor/mcp.postgressops.example.json):"
echo "     POSTGRESSOPS_HOME=${REAL_REPO_DIR}"
echo "     Remote command:"
echo "       POSTGRESSOPS_HOME=${REAL_REPO_DIR} POSTGRESSOPS_REPO=https://github.com/Makmillerme/postgressops.git \\"
echo "         bash ${REAL_REPO_DIR}/scripts/mcp-ssh-entrypoint.sh"
echo ""
echo "  3) Reload Cursor MCP: Ctrl+Shift+P → 'MCP: Reload Servers'"
echo "============================================================"
