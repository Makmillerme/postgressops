#!/usr/bin/env bash
# SSH entrypoint for Cursor MCP: bootstrap clone (if needed) then run MCP.
# Usage (remote):
#   POSTGRESSOPS_HOME=/opt/postgressops bash scripts/mcp-ssh-entrypoint.sh
# Or bootstrap from GitHub without local clone:
#   POSTGRESSOPS_HOME=/opt/postgressops POSTGRESSOPS_REPO=https://github.com/Makmillerme/postgressops.git \
#     bash -lc 'curl -fsSL https://raw.githubusercontent.com/Makmillerme/postgressops/main/scripts/mcp-ssh-entrypoint.sh | bash -s'
set -euo pipefail

: "${POSTGRESSOPS_HOME:=/opt/postgressops}"
: "${POSTGRESSOPS_REPO:=https://github.com/Makmillerme/postgressops.git}"

if [[ ! -f "${POSTGRESSOPS_HOME}/scripts/mcp-run.sh" ]]; then
  echo "[postgressops] Installing to ${POSTGRESSOPS_HOME} from ${POSTGRESSOPS_REPO}..." >&2
  mkdir -p "$(dirname "${POSTGRESSOPS_HOME}")"
  if [[ -d "${POSTGRESSOPS_HOME}/.git" ]]; then
    git -C "${POSTGRESSOPS_HOME}" pull --ff-only origin main 2>/dev/null || git -C "${POSTGRESSOPS_HOME}" pull --ff-only 2>/dev/null || true
  else
    git clone "${POSTGRESSOPS_REPO}" "${POSTGRESSOPS_HOME}"
  fi
  chmod +x "${POSTGRESSOPS_HOME}/scripts/"*.sh 2>/dev/null || true
  if [[ -f "${POSTGRESSOPS_HOME}/docker/.env.example" && ! -f "${POSTGRESSOPS_HOME}/docker/.env" ]]; then
    cp "${POSTGRESSOPS_HOME}/docker/.env.example" "${POSTGRESSOPS_HOME}/docker/.env"
    echo "[postgressops] Created docker/.env — fill credentials, then: bash scripts/server-update.sh" >&2
  fi
fi

exec "${POSTGRESSOPS_HOME}/scripts/mcp-run.sh"
