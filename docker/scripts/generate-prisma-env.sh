#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
VPN_HOST="${VPN_HOST:-YOUR_VPN_IP}"
set -a && source "$ENV_FILE" && set +a
while IFS= read -r line; do
  if [[ "$line" =~ ^PROJECT_([A-Z0-9]+)_DB=(.+)$ ]]; then
    NAME="${BASH_REMATCH[1]}"; DB="${BASH_REMATCH[2]}"
    USER_VAR="PROJECT_${NAME}_USER"; PASS_VAR="PROJECT_${NAME}_PASS"
    USER="${!USER_VAR:-}"; PASS="${!PASS_VAR:-}"
    [ -z "$USER" ] || [ -z "$PASS" ] && continue
    echo "DATABASE_URL=\"postgresql://${USER}:${PASS}@${VPN_HOST}:6432/${DB}?schema=public&pgbouncer=true\""
    echo "DIRECT_URL=\"postgresql://${USER}:${PASS}@${VPN_HOST}:5432/${DB}?schema=public\""
  fi
done < "$ENV_FILE"
