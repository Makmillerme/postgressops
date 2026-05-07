# PostgreSQL Production Stack

Clean, production-ready PostgreSQL 16 server pack with PgBouncer, automated backups, monitoring, and an MCP server for AI-driven management.

No Prisma dependencies. All database provisioning is done via scripts or the MCP server.

---

## Stack Components

| Service            | Image                                           | Purpose                           |
|--------------------|--------------------------------------------------|-----------------------------------|
| `postgres`         | `postgres:16-alpine`                             | Primary database                  |
| `pgbouncer`        | `bitnamilegacy/pgbouncer:1.22.1-debian-12-r9`    | Connection pooler (port 6432)     |
| `pg_backup`        | `postgres:16-alpine`                             | Daily pg_dump + rotation cron     |
| `postgres_exporter`| `prometheuscommunity/postgres-exporter`          | Metrics → Prometheus              |
| `prometheus`       | `prom/prometheus`                                | Optional local metrics store      |

All services communicate on an internal Docker bridge network (`pg_private_net`).  
**Port 5432 is never published externally.** Use an SSH tunnel for direct connections.

---

## First-Time Install

```bash
# 1. Clone the repository
git clone https://github.com/<owner>/<repo>.git /root/apps/postgres-stack
cd /root/apps/postgres-stack/docker

# 2. Create .env from template
cp .env.example .env
nano .env          # fill POSTGRES_USER, POSTGRES_PASSWORD, SERVER_PUBLIC_IP

# 3. Generate pgbouncer/userlist.txt (admin user only, initially)
set -a && source .env && set +a
printf '"%s" "%s"\n' "$POSTGRES_USER" "$POSTGRES_PASSWORD" > pgbouncer/userlist.txt

# 4. Run install
bash scripts/install.sh --local

# 5. Health check
bash scripts/healthcheck.sh
```

---

## Daily Operations

### Provision a new database

```bash
bash scripts/provision-db.sh <db_name> <db_user> <password>
# Example:
bash scripts/provision-db.sh mtrucklending Makmiller 'Str0ngP@ss!'
```

This script:
1. Creates the role (or updates the password if it exists).
2. Creates the database with the role as owner.
3. Adds the mapping to `pgbouncer/pgbouncer.ini`.
4. Adds the user+password to `pgbouncer/userlist.txt`.
5. Force-recreates PgBouncer.
6. Verifies the connection.

Output includes ready-to-use `DATABASE_URL` and `DIRECT_URL` for Prisma.

---

### Connection strings (for your app / Prisma)

```env
# .env in your Next.js / Prisma project:

# Pooled (via PgBouncer — use for queries, add ?pgbouncer=true for Prisma)
DATABASE_URL="postgresql://<db_user>:<pass>@<SERVER_PUBLIC_IP>:6432/<db_name>?schema=public&pgbouncer=true&connect_timeout=10"

# Direct (for migrations — requires SSH tunnel: ssh -L 5432:localhost:5432 user@server)
DIRECT_URL="postgresql://<db_user>:<pass>@127.0.0.1:5432/<db_name>?schema=public&connect_timeout=10"
```

---

### Upgrade (pull changes, restart, preserve data)

```bash
bash scripts/upgrade.sh
```

---

### Clean reinstall (WIPE ALL DATA)

```bash
bash scripts/clean-install.sh         # prompts "Type YES"
bash scripts/clean-install.sh --yes   # non-interactive (CI)
```

---

### Manual backup

```bash
docker exec pg_backup sh /usr/local/bin/backup.sh
```

Backups are stored in the named Docker volume `pg_backups` at `/backups/full/`.

### Manual restore

```bash
# List available backups
docker exec pg_backup ls /backups/full/

# Restore a specific dump
docker exec pg_backup sh /usr/local/bin/restore.sh /backups/full/<db>_<timestamp>.dump <target_db>
```

---

### Active connections

```bash
bash scripts/list-connections.sh
```

---

## PgBouncer Configuration

- `pgbouncer/pgbouncer.ini` — database mapping and pool settings.
- `pgbouncer/userlist.txt` — plaintext password auth list (never commit real credentials).

After manual edits to either file, reload PgBouncer:

```bash
docker compose --env-file .env up -d pgbouncer --force-recreate
```

---

## Monitoring

Prometheus scrapes `postgres_exporter:9187` by default.  
Prometheus UI is available at `http://127.0.0.1:9090` (SSH tunnel recommended).

To add Grafana, connect the datasource from `monitoring/grafana-datasource.yml`.

---

## MCP Server (AI-driven management)

The MCP server is in `../tools/mcp-postgres-ops/`. It allows Cursor AI to manage the stack autonomously.

**Setup:** see [`../tools/mcp-postgres-ops/README.md`](../tools/mcp-postgres-ops/README.md).

Available tools:

| Tool                    | Description                                     | Destructive |
|-------------------------|-------------------------------------------------|-------------|
| `healthcheck_stack`     | Container states, connectivity, last backup     | No          |
| `list_databases`        | All databases with owner and size               | No          |
| `list_roles`            | All roles with attributes                       | No          |
| `run_sql`               | Read-only SELECT queries                        | No          |
| `create_database`       | Create DB + role + PgBouncer mapping            | No          |
| `drop_database`         | Drop database (requires `confirm: true`)        | **Yes**     |
| `create_role`           | Create/update role password                     | No          |
| `drop_role`             | Drop role (requires `confirm: true`)            | **Yes**     |
| `rotate_role_password`  | Rotate password + update PgBouncer              | No          |
| `map_pgbouncer_database`| Add/update PgBouncer mapping                    | No          |
| `reload_pgbouncer`      | Force-recreate PgBouncer container              | No          |
| `run_backup_now`        | Trigger immediate backup                        | No          |

---

## Directory Structure

```
docker/
├── .env.example             # Config template (copy to .env)
├── docker-compose.yml
├── postgres/
│   └── postgresql.conf      # PostgreSQL tuning
├── pgbouncer/
│   ├── pgbouncer.ini        # Pool config and DB mappings
│   └── userlist.txt         # Auth list (gitignored)
├── init/
│   └── 00-init-extensions.sql  # System extensions bootstrap
├── backup/
│   ├── backup.sh
│   └── restore.sh
├── monitoring/
│   ├── prometheus.yml
│   └── grafana-datasource.yml
└── scripts/
    ├── install.sh           # First-time install
    ├── clean-install.sh     # Wipe + reinstall (data loss!)
    ├── upgrade.sh           # Pull + restart (preserves data)
    ├── provision-db.sh      # Create DB + role + PgBouncer entry
    ├── healthcheck.sh       # Stack status
    └── list-connections.sh  # Active PgBouncer / Postgres connections

tools/
└── mcp-postgres-ops/        # MCP server (Node.js)
    ├── package.json
    ├── .env.example
    └── src/index.js
```
