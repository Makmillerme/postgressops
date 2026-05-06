#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
set -a && source "$ENV_FILE" && set +a
docker exec postgres psql -U "$POSTGRES_USER" -c "SELECT datname, usename, state, count(*) FROM pg_stat_activity GROUP BY datname, usename, state ORDER BY count(*) DESC;"
