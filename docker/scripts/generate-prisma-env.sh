#!/bin/bash
# ============================================================
# generate-prisma-env.sh — Вивести Prisma .env для всіх проєктів
# Використання: VPN_HOST=91.239.232.91 ./scripts/generate-prisma-env.sh
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
VPN_HOST="${VPN_HOST:-91.239.232.91}"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found. Run: cp .env.example .env && nano .env"
  exit 1
fi

set -a && source "$ENV_FILE" && set +a

echo "# ============================================================"
echo "# Prisma Connection Strings для всіх проєктів"
echo "# Згенеровано: $(date)"
echo "# VPN Host: $VPN_HOST"
echo "# ============================================================"
echo ""

# Читаємо проєкти з .env (паттерн PROJECT_*_DB)
while IFS= read -r line; do
  if [[ "$line" =~ ^PROJECT_([A-Z0-9]+)_DB=(.+)$ ]]; then
    NAME="${BASH_REMATCH[1]}"
    DB="${BASH_REMATCH[2]}"
    USER_VAR="PROJECT_${NAME}_USER"
    PASS_VAR="PROJECT_${NAME}_PASS"
    USER="${!USER_VAR:-}"
    PASS="${!PASS_VAR:-}"

    if [ -z "$USER" ] || [ -z "$PASS" ]; then
      echo "# WARN: $NAME — не задані USER або PASS в .env, пропускаємо."
      continue
    fi

    echo "# --- Project: $NAME ---"
    echo "DATABASE_URL=\"postgresql://${USER}:${PASS}@${VPN_HOST}:6432/${DB}?schema=public&pgbouncer=true&connect_timeout=10\""
    echo "DIRECT_URL=\"postgresql://${USER}:${PASS}@${VPN_HOST}:5432/${DB}?schema=public&connect_timeout=10\""
    echo ""
  fi
done < "$ENV_FILE"

echo "# schema.prisma — одноразово для кожного проєкту:"
echo "# datasource db {"
echo "#   provider  = \"postgresql\""
echo "#   url       = env(\"DATABASE_URL\")"
echo "#   directUrl = env(\"DIRECT_URL\")"
echo "# }"
