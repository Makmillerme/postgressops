#!/usr/bin/env bash
set -euo pipefail

# Ensure WAL archive directory is writable by the postgres user inside the container.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_DIR/docker/.env"

[[ -f "$ENV_FILE" ]] || { echo "WARN: $ENV_FILE not found — skipping wal_archive fix"; exit 0; }

if ! docker inspect postgres >/dev/null 2>&1; then
  echo "WARN: postgres container not running — skipping wal_archive fix"
  exit 0
fi

docker exec -u root postgres sh -c '
  mkdir -p /var/lib/postgresql/wal_archive
  chown -R postgres:postgres /var/lib/postgresql/wal_archive
  chmod 700 /var/lib/postgresql/wal_archive
'

echo "OK: wal_archive permissions fixed"
