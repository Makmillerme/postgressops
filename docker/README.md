# Docker Stack — PostgreSQL 16 + PgBouncer

Complete reference for installing, managing, and troubleshooting the production PostgreSQL Docker stack.

---

## Prerequisites

- Linux server (Ubuntu 22.04+ / Debian 12+)
- Docker 24+ with Compose plugin (`docker compose version`)
- Git
- Root or sudo access
- Port `6432` open in your firewall for external PgBouncer access

---

## Configuration

### 1. Copy `.env.example` to `.env`

```bash
cd /root/apps/postgres-stack/docker
cp .env.example .env
nano .env
```

### Required values to fill in

| Variable             | Description                                       |
|----------------------|---------------------------------------------------|
| `POSTGRES_USER`      | Superuser name                                    |
| `POSTGRES_PASSWORD`  | Superuser password (strong, no double quotes)     |
| `SERVER_PUBLIC_IP`   | Server public IP that clients connect to          |

All other values have sensible defaults.

### What is auto-configured by scripts

- `pgbouncer/userlist.txt` — generated from `POSTGRES_USER`/`POSTGRES_PASSWORD`
- `pgbouncer.ini` `[databases]` `postgres` entry — added automatically
- `pgbouncer.ini` `admin_users` / `stats_users` — synced to `POSTGRES_USER`

---

## Installation scenarios

### Scenario A — First-time install (recommended)

```bash
cd /root/apps/postgres-stack
bash scripts/server-update.sh
```

This is the canonical entry point. It handles `.env` bootstrap, PgBouncer config, Docker start, MCP setup, and a final healthcheck in one run.

---

### Scenario B — Manual install

From the `docker/` directory:

```bash
cd /root/apps/postgres-stack/docker
bash scripts/install.sh --local
```

- Creates `.env` from template if absent (then exits for you to fill it in).
- Validates no `CHANGE_ME_*` left.
- Bootstraps `userlist.txt`, ensures PgBouncer `postgres` mapping.
- Starts all containers.

---

### Scenario C — Reinstall (keep data, recreate containers)

Use when: you changed `pgbouncer.ini`, updated Docker images, or need a clean container restart without wiping data.

```bash
cd /root/apps/postgres-stack/docker
bash scripts/reinstall.sh
```

- Does NOT touch data volumes.
- Re-writes `userlist.txt` from `.env`.
- Ensures `postgres` maintenance DB mapping in `pgbouncer.ini`.
- Pulls images, stops+recreates all containers.
- Waits for healthy status, runs smoke tests.

---

### Scenario D — Clean install (DESTRUCTIVE — wipes all data)

Use when: you want a completely fresh database with no existing data.

```bash
cd /root/apps/postgres-stack/docker
bash scripts/clean-install.sh
```

- Prompts for `YES` confirmation.
- Removes all named Docker volumes (all data is lost).
- Rewrites `userlist.txt` and `pgbouncer.ini`.
- Starts fresh stack.

---

## Update from GitHub

```bash
cd /root/apps/postgres-stack
bash scripts/server-update.sh
```

The update script:
- Stashes local changes if any.
- `git pull --ff-only` from origin.
- Bootstraps PgBouncer config if anything changed.
- Restarts containers (no volume wipe).
- Normalizes MCP `.env` values.
- Runs npm install for MCP.
- Final healthcheck.

---

## Provisioning a new project database

```bash
cd /root/apps/postgres-stack/docker
bash scripts/provision-db.sh <db_name> <db_user> <password>

# Example:
bash scripts/provision-db.sh myproject myproject_user 'Str0ngPass!'
```

This script is **idempotent** — safe to re-run. It will:
1. Create role and database in Postgres (or update password if role exists).
2. Add the database to `pgbouncer.ini`.
3. Add the user to `pgbouncer/userlist.txt`.
4. Force-recreate PgBouncer.
5. Verify connection.

**Output connection strings:**
```
DATABASE_URL (pooled via PgBouncer):
  postgresql://myproject_user:<pass>@<SERVER_IP>:6432/myproject?pgbouncer=true

DIRECT_URL (Prisma migrations, SSH tunnel):
  postgresql://myproject_user:<pass>@127.0.0.1:5432/myproject
```

---

## Healthcheck

```bash
bash /root/apps/postgres-stack/docker/scripts/healthcheck.sh
```

Checks:
- Container running/healthy status for all services
- `pg_isready` on Postgres
- TCP port check on PgBouncer
- Last backup timestamp

---

## Manual backup / restore

**Trigger backup now:**
```bash
docker exec pg_backup sh /usr/local/bin/backup.sh
```

**List backups:**
```bash
ls -lh /opt/backups/full/
```

**Restore specific database:**
```bash
docker exec -i postgres pg_restore \
  -U <admin_user> -d <target_db> -Fc \
  < /opt/backups/full/<db_name>_<timestamp>.dump
```

**Restore full cluster (all databases):**
```bash
gunzip -c /opt/backups/full/full_<timestamp>.sql.gz \
  | docker exec -i postgres psql -U <admin_user> -d postgres
```

---

## Active connections

```bash
# Via Postgres (direct):
docker exec -it postgres psql -U <POSTGRES_USER> -d postgres \
  -c "SELECT pid, usename, datname, application_name, state FROM pg_stat_activity WHERE state <> 'idle';"

# Via PgBouncer admin:
PGPASSWORD=<POSTGRES_PASSWORD> psql \
  "host=127.0.0.1 port=6432 dbname=pgbouncer user=<POSTGRES_USER> sslmode=disable" \
  -c "SHOW CLIENTS;"
```

---

## PgBouncer manual edit

`docker/pgbouncer/pgbouncer.ini` — edit directly, then reload:

```bash
docker compose -f docker-compose.yml --env-file .env up -d pgbouncer --force-recreate
```

**To add a database manually:**
```ini
[databases]
mydb = host=postgres port=5432 dbname=mydb user=mydb_user
```

`docker/pgbouncer/userlist.txt` — plaintext passwords (file is gitignored):
```
"mydb_user" "plaintextpassword"
```

---

## Monitoring

Prometheus UI: `http://<SERVER_IP>:9090`  
Scrapes: `postgres_exporter` on port `9187`.

---

## Troubleshooting

### `FATAL: no such database: postgres` (MCP / psql to PgBouncer)

The `postgres` maintenance database is not mapped in PgBouncer. Fix:
```bash
bash scripts/reinstall.sh
# or manually:
sed -i '/^\[databases\]/a postgres = host=postgres port=5432 dbname=postgres user=<POSTGRES_USER>' pgbouncer/pgbouncer.ini
docker compose --env-file .env up -d pgbouncer --force-recreate
```

### `FATAL: SASL authentication failed` (PgBouncer)

PgBouncer `userlist.txt` contains a SCRAM hash but `auth_type = scram-sha-256` requires plaintext for server-side auth.  
Fix: re-run `reinstall.sh` or `server-update.sh` — they always write plaintext passwords to `userlist.txt`.

### `Connection refused` on port 6432 (from localhost)

PgBouncer may not have the `127.0.0.1` binding. Check `docker-compose.yml` `ports` for pgbouncer:
```yaml
ports:
  - "${SERVER_PUBLIC_IP:-0.0.0.0}:${PGBOUNCER_LISTEN_PORT:-6432}:6432"
  - "127.0.0.1:${PGBOUNCER_LISTEN_PORT:-6432}:6432"
```

### `permission denied` running backup.sh

Bind-mounted scripts may not have execute bit. Use `sh` explicitly:
```bash
docker exec pg_backup sh /usr/local/bin/backup.sh
```

---

## Directory structure

```
docker/
├── scripts/
│   ├── install.sh          # First-time install
│   ├── reinstall.sh        # Recreate containers, keep volumes
│   ├── clean-install.sh    # Full wipe + reinstall (destructive)
│   ├── upgrade.sh          # Lightweight: pull + rolling restart
│   ├── provision-db.sh     # Create DB + role + PgBouncer mapping
│   └── healthcheck.sh      # Health status of all services
├── backup/
│   ├── backup.sh           # Daily cron backup script
│   └── restore.sh          # Restore from dump
├── pgbouncer/
│   ├── pgbouncer.ini       # PgBouncer configuration
│   └── userlist.txt        # Auth file (gitignored)
├── init/
│   └── 00-init-extensions.sql
├── prometheus/
│   └── prometheus.yml
├── docker-compose.yml
├── .env                    # Your config (gitignored)
└── .env.example            # Template
```
