#!/usr/bin/env bash
# Ensure shell scripts are executable after git clone/pull (git may store mode 100644).
ensure_postgressops_executable() {
  local home="${1:-${POSTGRESSOPS_HOME:-}}"
  [[ -n "$home" ]] || return 0
  chmod +x "${home}/scripts/"*.sh 2>/dev/null || true
  chmod +x "${home}/scripts/lib/"*.sh 2>/dev/null || true
  chmod +x "${home}/docker/backup/"*.sh 2>/dev/null || true
}
