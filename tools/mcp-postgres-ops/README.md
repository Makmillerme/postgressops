# MCP Postgres Ops — Cursor Integration

Node.js MCP (Model Context Protocol) server that gives your Cursor AI assistant direct control over the PostgreSQL Docker stack: manage databases, roles, PgBouncer, and backups without touching the server manually.

---

## How it works

```
Cursor (local) ──SSH──► server-update.sh ──► Node.js MCP server
                                                │
                                        PgBouncer (port 6432)
                                                │
                                        PostgreSQL 16 (internal)
```

The MCP server runs on the remote server and communicates with Cursor over SSH stdio. All SQL commands go through PgBouncer on port 6432 (the host-exposed port — direct Postgres 5432 is not published).

---

## Prerequisites

On the **server**:
- Node.js 20+ (`node --version`)
- PostgreSQL stack running (`bash docker/scripts/healthcheck.sh`)
- MCP `.env` configured (see below)

On your **local machine** (Windows/Mac):
- OpenSSH client
- SSH key-based auth to the server (no password prompt)

---

## Setup

### Step 1 — Run server-update.sh

This single command sets up everything on the server, including the MCP `.env`:

```bash
# On the server:
cd /root/apps/postgres-stack
bash scripts/server-update.sh
```

### Step 2 — Verify the MCP .env on server

```bash
cat /root/apps/postgres-stack/tools/mcp-postgres-ops/.env
```

Expected values:
```env
PG_HOST=127.0.0.1
PG_PORT=6432
PG_USER=<your_postgres_user>
PG_PASSWORD=<your_postgres_password>
PG_MAINTENANCE_DB=postgres
PGBOUNCER_HOST=127.0.0.1
PGBOUNCER_PORT=6432
STACK_DIR=/root/apps/postgres-stack/docker
```

### Step 3 — Set up SSH key auth (Windows)

```powershell
# Generate key (skip if you already have one):
ssh-keygen --% -t ed25519 -C cursor-mcp -f C:\Users\<you>\.ssh\id_ed25519 -N ""

# Copy public key to server:
type "$env:USERPROFILE\.ssh\id_ed25519.pub" | ssh root@<SERVER_IP> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

# Test (must print "ok" without password prompt):
ssh -o BatchMode=yes -T root@<SERVER_IP> "echo ok"
```

### Step 4 — Configure Cursor MCP

Edit (or create) `C:\Users\<you>\.cursor\mcp.json`:

```json
{
  "mcpServers": {
    "postgres-ops": {
      "command": "ssh",
      "args": [
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-T", "root@<SERVER_IP>",
        "cd /root/apps/postgres-stack && node tools/mcp-postgres-ops/src/index.js"
      ]
    }
  }
}
```

Replace `<SERVER_IP>` with your actual server IP.

### Step 5 — Reload Cursor MCP

`Ctrl+Shift+P` → **MCP: Reload Servers**

The `postgres-ops` server should appear as connected.

---

## Available tools

| Tool                   | Description                                                              | Destructive |
|------------------------|--------------------------------------------------------------------------|-------------|
| `healthcheck_stack`    | Container states, SQL connectivity, database list                        |             |
| `list_databases`       | All non-template DBs with owner and size                                 |             |
| `list_roles`           | All roles with attributes                                                |             |
| `create_database`      | Create DB + role + PgBouncer mapping. Idempotent.                        |             |
| `drop_database`        | Drop DB + remove PgBouncer mapping. Requires `confirm: true`.            | YES         |
| `create_role`          | Create a role with LOGIN. Updates password if exists.                    |             |
| `drop_role`            | Drop role. Requires `confirm: true`.                                     | YES         |
| `rotate_role_password` | Change password in Postgres + update `userlist.txt`                      |             |
| `map_pgbouncer_database` | Add or update a PgBouncer `[databases]` entry, reload PgBouncer.      |             |
| `reload_pgbouncer`     | Force-recreate PgBouncer container to apply config changes               |             |
| `run_backup_now`       | Trigger immediate backup via `backup.sh` in pg_backup container          |             |
| `run_sql`              | Read-only SELECT queries on the maintenance database                     |             |

---

## Usage examples in Cursor

In the Cursor chat, you can ask:

- "Create a database `mtrucklending` with owner `mtrucklending_user` and password `Str0ngPass!`"
- "List all databases and their sizes"
- "Run a backup now"
- "Rotate the password for role `app_user` to `NewPass2026!`"
- "Drop the `old_project` database — confirm"
- "Show me all active roles"

---

## Troubleshooting

### MCP server fails to start

```bash
# Test locally on the server:
cd /root/apps/postgres-stack
node tools/mcp-postgres-ops/src/index.js
# Should start without errors (waiting for stdin input)
```

If you see `FATAL: Missing required env vars` — check `.env` file.

### `ERROR: no such database: postgres`

The `postgres` maintenance DB is not in PgBouncer config. Re-run:
```bash
bash scripts/server-update.sh
```

### `ECONNREFUSED 127.0.0.1:6432`

PgBouncer is not running or not listening on localhost. Check:
```bash
docker ps --filter name=pgbouncer
bash docker/scripts/healthcheck.sh
```

### SSH connection fails in Cursor

Test from your local terminal:
```powershell
ssh -o BatchMode=yes -T root@<SERVER_IP> "echo ok"
```
Must print `ok` without a password prompt. If it fails, re-add the SSH key to the server.

### MCP tools not visible in Cursor

1. Check `C:\Users\<you>\.cursor\mcp.json` has the correct server IP and path.
2. Reload MCP: `Ctrl+Shift+P` → `MCP: Reload Servers`.
3. Check Cursor MCP logs: `Ctrl+Shift+P` → `MCP: Show Logs`.
