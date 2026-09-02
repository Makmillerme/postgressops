# PostgreSQL + MCP Pack (Єдиний README)

Автономний серверний пакет PostgreSQL 16 + PgBouncer + backup + MCP для Cursor.

## Структура (організована)

```
.
├── docker/
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── backup/
│   ├── init/
│   ├── pgbouncer/
│   └── postgres/
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
- MCP (`tools/mcp-postgres-ops`) для керування стеком через Cursor

## Підготовка

Стандартний шлях установки: **`/opt/postgressops`** (змінюється через `POSTGRESSOPS_HOME`).

```bash
export POSTGRESSOPS_HOME=/opt/postgressops   # або свій шлях
git clone https://github.com/Makmillerme/postgressops.git "$POSTGRESSOPS_HOME"
cd "$POSTGRESSOPS_HOME"
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

Репозиторій: **https://github.com/Makmillerme/postgressops**

Шаблон для `~/.cursor/mcp.json`: [`.cursor/mcp.postgressops.example.json`](.cursor/mcp.postgressops.example.json)

### 1) На сервері (перший раз)

```bash
export POSTGRESSOPS_HOME=/opt/postgressops   # змініть за потреби
git clone https://github.com/Makmillerme/postgressops.git "$POSTGRESSOPS_HOME"
cd "$POSTGRESSOPS_HOME"
cp docker/.env.example docker/.env && nano docker/.env
bash scripts/server-update.sh
```

### 2) Локально — `~/.cursor/mcp.json`

Додайте блок `_postgressops` (метадані для AI) і сервер `postgres-ops`:

```json
{
  "_postgressops": {
    "repo": "https://github.com/Makmillerme/postgressops.git",
    "defaultInstallPath": "/opt/postgressops",
    "docs": "https://github.com/Makmillerme/postgressops#mcp-setup-cursor-ssh-mode"
  },
  "mcpServers": {
    "postgres-ops": {
      "command": "ssh",
      "args": [
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-T", "root@YOUR_SERVER_IP",
        "POSTGRESSOPS_HOME=/opt/postgressops POSTGRESSOPS_REPO=https://github.com/Makmillerme/postgressops.git bash -lc 'curl -fsSL https://raw.githubusercontent.com/Makmillerme/postgressops/main/scripts/mcp-ssh-entrypoint.sh | bash -s'"
      ],
      "postgressops": {
        "repo": "https://github.com/Makmillerme/postgressops.git",
        "installPath": "/opt/postgressops",
        "docs": "https://github.com/Makmillerme/postgressops#mcp-setup-cursor-ssh-mode"
      }
    }
  }
}
```

**Якщо репо вже на сервері** (швидший варіант, без curl):

```json
"POSTGRESSOPS_HOME=/opt/postgressops POSTGRESSOPS_REPO=https://github.com/Makmillerme/postgressops.git bash /opt/postgressops/scripts/mcp-ssh-entrypoint.sh"
```

Змініть:
- `YOUR_SERVER_IP` — IP або hostname сервера
- `/opt/postgressops` — ваш `POSTGRESSOPS_HOME`

### 3) Reload

`Ctrl+Shift+P` → `MCP: Reload Servers`

Cursor AI прочитає `_postgressops` / `postgressops` і зможе сама клонувати репо та запустити `server-update.sh` на SSH-сервері.

## MCP tools (основні)

- SQL tools: `healthcheck_stack`, `list_databases`, `list_roles`, `create_database`, `drop_database`, `create_role`, `drop_role`, `rotate_role_password`, `run_backup_now`
- Script tools (викликають `scripts/`): `run_healthcheck`, `run_install`, `run_reinstall`, `run_upgrade`, `run_provision_db`

## Troubleshooting

- `no such database: postgres` -> запустіть `bash scripts/server-update.sh` (додає postgres mapping в PgBouncer).
- `ECONNREFUSED 127.0.0.1:6432` -> перевірте `bash scripts/healthcheck.sh`.
- `SASL authentication failed` -> перегенеруйте `userlist.txt` через `bash scripts/reinstall.sh`.
