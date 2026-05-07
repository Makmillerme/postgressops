# PostgreSQL + MCP Pack (Єдиний README)

Автономний серверний пакет PostgreSQL 16 + PgBouncer + backup + monitoring + MCP для Cursor.

## Структура (організована)

```
.
├── docker/
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── backup/
│   ├── init/
│   ├── pgbouncer/
│   └── prometheus/
├── scripts/
│   ├── install.sh
│   ├── reinstall.sh
│   ├── clean-install.sh
│   ├── upgrade.sh
│   ├── healthcheck.sh
│   ├── provision-db.sh
│   ├── list-connections.sh
│   └── server-update.sh
├── tools/mcp-postgres-ops/
│   ├── src/index.js
│   └── .env.example
└── README.md
```

`scripts/` — єдина папка для всіх операційних shell-скриптів.

## Компоненти

- PostgreSQL 16 (внутрішній сервіс)
- PgBouncer (`SERVER_PUBLIC_IP:6432`)
- `pg_backup` (cron + manual backup)
- `postgres_exporter` + Prometheus
- MCP (`tools/mcp-postgres-ops`) для керування стеком через Cursor

## Підготовка

```bash
cd /root/apps/postgres-stack
cp docker/.env.example docker/.env
nano docker/.env
```

Заповніть мінімум:
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `SERVER_PUBLIC_IP`

## Інсталяційні сценарії

### 1) Canonical: one-command bootstrap/update
```bash
bash scripts/server-update.sh
```

### 2) Manual install (без wipe)
```bash
bash scripts/install.sh --local
```

### 3) Reinstall (без wipe volumes)
```bash
bash scripts/reinstall.sh
```

### 4) Clean install (wipe volumes, DESTRUCTIVE)
```bash
bash scripts/clean-install.sh
```

## Щоденні операції

### Healthcheck
```bash
bash scripts/healthcheck.sh
```

### Provision нової БД/ролі
```bash
bash scripts/provision-db.sh <db_name> <db_user> <password>
```

### Backup зараз
```bash
docker exec pg_backup sh /usr/local/bin/backup.sh
```

### Активні підключення
```bash
bash scripts/list-connections.sh
```

## MCP setup (Cursor, SSH mode)

1. На сервері:
```bash
cd /root/apps/postgres-stack
bash scripts/server-update.sh
```

2. Локально додайте в `~/.cursor/mcp.json`:
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

3. Reload: `Ctrl+Shift+P` -> `MCP: Reload Servers`.

## MCP tools (основні)

- SQL tools: `healthcheck_stack`, `list_databases`, `list_roles`, `create_database`, `drop_database`, `create_role`, `drop_role`, `rotate_role_password`, `run_backup_now`
- Script tools (викликають `scripts/`): `run_healthcheck`, `run_install`, `run_reinstall`, `run_upgrade`, `run_provision_db`

## Troubleshooting

- `no such database: postgres` -> запустіть `bash scripts/server-update.sh` (додає postgres mapping в PgBouncer).
- `ECONNREFUSED 127.0.0.1:6432` -> перевірте `bash scripts/healthcheck.sh`.
- `SASL authentication failed` -> перегенеруйте `userlist.txt` через `bash scripts/reinstall.sh`.
