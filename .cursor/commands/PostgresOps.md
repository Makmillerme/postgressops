# PostgresOps

Single-entry operational command for PostgreSQL + server management.

## What this command should do

When user asks for PostgresOps actions, execute this sequence:

1. **Inspect**
   - Run health and state checks first.
   - Confirm active server path is `/root/apps/PostgressOps`.
2. **Operate**
   - Perform requested action via MCP tool or `scripts/*.sh`.
3. **Verify**
   - Re-run health checks and verify expected result.
4. **Report**
   - Return concise summary with status and next safe step.

## Supported operation categories

- **Health & diagnostics**
  - `healthcheck_stack`
  - `run_healthcheck`
  - container status, logs, connectivity checks

- **Database lifecycle**
  - list/create/drop databases
  - list/create/drop roles
  - rotate passwords
  - read-only SQL checks

- **PgBouncer management**
  - create/update DB mappings
  - reload PgBouncer

- **Backup & restore**
  - trigger backup now
  - confirm backup artifact presence

- **Server/project operations**
  - `run_install`
  - `run_reinstall`
  - `run_upgrade`
  - `scripts/server-update.sh`
  - path migration checks (`STACK_DIR`, `SCRIPTS_DIR`, MCP path)

## Safety guardrails

- Ask confirmation before destructive actions:
  - clean reinstall
  - dropping databases/roles
- Never run multiple risky operations in one step.
- Always verify post-operation health.

## Quick examples

- “PostgresOps health” -> run full stack healthcheck and report.
- “PostgresOps create db mtrucklending” -> create role+db, map PgBouncer, verify.
- “PostgresOps server update” -> run `scripts/server-update.sh`, then healthcheck.
- “PostgresOps backup now” -> trigger backup and show resulting files.
