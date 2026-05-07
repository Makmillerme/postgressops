# MCP Postgres Ops

Node.js MCP server for managing the PostgreSQL production stack via Cursor AI.

Provides tools to create/drop databases and roles, manage PgBouncer mappings, rotate passwords, and run backups.

---

## Prerequisites

- Node.js >= 18 installed on the **same machine** that has Docker access to the stack (typically the server, or local via SSH tunnel).
- The PostgreSQL stack is running (from `docker/`).

---

## Setup

### 1. Install dependencies

```bash
cd tools/mcp-postgres-ops
npm install
```

### 2. Configure .env

```bash
cp .env.example .env
nano .env
```

Fill in:

```env
PG_HOST=127.0.0.1
PG_PORT=6432
PG_USER=pgadmin
PG_PASSWORD=your_admin_password
PG_MAINTENANCE_DB=postgres

PGBOUNCER_HOST=127.0.0.1
PGBOUNCER_PORT=6432

# Absolute path to the docker/ directory on the server
STACK_DIR=/root/apps/postgres-prisma-stack/postgressserver-prisma-postgres-stack-v2/docker

MCP_LOG_FILE=/var/log/mcp-postgres-ops.log
```

### 3. Register in Cursor (remote server via SSH)

Add to your Cursor MCP config (`~/.cursor/mcp.json` or workspace `.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "postgres-ops": {
      "command": "ssh",
      "args": [
        "-o",
        "StrictHostKeyChecking=accept-new",
        "-o",
        "BatchMode=yes",
        "-T",
        "root@91.239.232.91",
        "cd /root/apps/postgres-prisma-stack/postgressserver-prisma-postgres-stack-v2/tools/mcp-postgres-ops && node src/index.js"
      ]
    }
  }
}
```
> Use SSH key-based auth (no password prompt) because MCP stdio transport is non-interactive.

---

## Available Tools

| Tool                    | Description                                          | Requires confirm |
|-------------------------|------------------------------------------------------|------------------|
| `healthcheck_stack`     | Container states, PG connectivity, last backup       | No               |
| `list_databases`        | All databases with owner and size                    | No               |
| `list_roles`            | All roles with attributes                            | No               |
| `run_sql`               | Read-only SELECT queries on any DB                   | No               |
| `create_database`       | Create DB + role + PgBouncer entry + userlist        | No               |
| `drop_database`         | Drop database and remove from PgBouncer              | **Yes**          |
| `create_role`           | Create role or update password                       | No               |
| `drop_role`             | Drop role and remove from userlist                   | **Yes**          |
| `rotate_role_password`  | Change password in Postgres + PgBouncer userlist     | No               |
| `map_pgbouncer_database`| Add or update a PgBouncer [databases] entry          | No               |
| `reload_pgbouncer`      | Force-recreate PgBouncer container                   | No               |
| `run_backup_now`        | Trigger immediate backup.sh                          | No               |

---

## Security Notes

- Destructive tools (`drop_database`, `drop_role`) require `confirm: true` to execute.
- `run_sql` is read-only: DDL and DML statements are blocked.
- Never expose the MCP server on a public port — run it only via stdio (Cursor) or SSH tunnel.
- Credentials are read from `.env` (gitignored) and never committed.
- All operations are logged to `MCP_LOG_FILE`.
