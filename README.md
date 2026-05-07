# PostgreSQL Production Stack + MCP

Autonomous, Docker-based PostgreSQL 16 production pack with PgBouncer, automated backups, Prometheus metrics, and a Cursor MCP server for remote database management.

## What's inside

| Component          | Description                                          |
|--------------------|------------------------------------------------------|
| PostgreSQL 16      | Main database server (not exposed on host directly)  |
| PgBouncer          | Connection pooler, exposed on `SERVER_PUBLIC_IP:6432`|
| pg_backup          | Cron-based daily backups + manual trigger            |
| postgres_exporter  | Prometheus metrics endpoint                          |
| Prometheus         | Metrics collection (localhost:9090)                  |
| MCP server         | Node.js MCP for Cursor — manage DB via AI assistant  |

## Quick start

### First-time server setup

```bash
# 1. Clone
git clone https://github.com/<owner>/<repo>.git /root/apps/postgres-stack
cd /root/apps/postgres-stack

# 2. Run the one-command setup (installs Node.js if needed)
bash scripts/server-update.sh
```

The script will:
- Create `docker/.env` from `docker/.env.example` and **exit** if it doesn't exist yet — fill in your values and re-run.
- Bootstrap PgBouncer config, start all containers, install MCP dependencies, and run a healthcheck.

### Subsequent updates

```bash
cd /root/apps/postgres-stack
bash scripts/server-update.sh
```

## Directory structure

```
.
├── docker/                     # Docker Compose stack
│   ├── scripts/
│   │   ├── install.sh          # First-time install (creates .env, starts stack)
│   │   ├── reinstall.sh        # Recreate containers, keep volumes
│   │   ├── clean-install.sh    # Full wipe + clean install (destructive!)
│   │   ├── upgrade.sh          # Pull images + rolling restart, no wipe
│   │   ├── provision-db.sh     # Create DB + role + PgBouncer mapping
│   │   └── healthcheck.sh      # Health status of all services
│   ├── backup/
│   │   ├── backup.sh           # Backup script (called by cron or manually)
│   │   └── restore.sh          # Restore from backup file
│   ├── pgbouncer/
│   │   ├── pgbouncer.ini       # PgBouncer config (databases, pooling, auth)
│   │   └── userlist.txt        # Auth file (gitignored — auto-generated)
│   ├── init/
│   │   └── 00-init-extensions.sql  # System extensions bootstrap
│   ├── prometheus/
│   │   └── prometheus.yml      # Prometheus scrape config
│   ├── docker-compose.yml
│   ├── .env.example            # Config template (copy to .env)
│   └── README.md               # Full stack documentation
├── tools/
│   └── mcp-postgres-ops/       # MCP server for Cursor
│       ├── src/index.js
│       ├── .env.example
│       └── README.md
├── scripts/
│   └── server-update.sh        # One-command server bootstrap/update
└── README.md                   # This file
```

## Documentation

- **Stack setup, scripts, and troubleshooting**: [`docker/README.md`](docker/README.md)
- **MCP server setup for Cursor**: [`tools/mcp-postgres-ops/README.md`](tools/mcp-postgres-ops/README.md)
