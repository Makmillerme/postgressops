#!/usr/bin/env bash
# Start MCP server from POSTGRESSOPS_HOME (stdio).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/postgressops-home.sh
source "${SCRIPT_DIR}/lib/postgressops-home.sh"

cd "${POSTGRESSOPS_HOME}" || {
  echo "FATAL: POSTGRESSOPS_HOME not found: ${POSTGRESSOPS_HOME}" >&2
  echo "  Clone: git clone ${POSTGRESSOPS_REPO} ${POSTGRESSOPS_HOME}" >&2
  exit 1
}

MCP_DIR="${POSTGRESSOPS_HOME}/tools/mcp-postgres-ops"
export STACK_DIR="${STACK_DIR:-${POSTGRESSOPS_HOME}/docker}"
export SCRIPTS_DIR="${SCRIPTS_DIR:-${POSTGRESSOPS_HOME}/scripts}"

if [[ ! -d "${MCP_DIR}/node_modules" ]]; then
  echo "[postgressops] Installing MCP npm dependencies..." >&2
  (cd "${MCP_DIR}" && npm install --prefer-offline --no-audit)
fi

exec node "${MCP_DIR}/src/index.js"
