# PostgreSQL Production Stack

> Server-side PostgreSQL 16 operations pack with PgBouncer, automated backups, Prometheus monitoring, and an MCP server for AI-driven database management.

## Quick Start

```bash
cd docker
cp .env.example .env
# Fill POSTGRES_USER, POSTGRES_PASSWORD, SERVER_PUBLIC_IP
bash scripts/install.sh --local
bash scripts/healthcheck.sh
```

## Documentation

See [`docker/README.md`](docker/README.md) for full operational documentation.

## MCP Server

[`tools/mcp-postgres-ops/`](tools/mcp-postgres-ops/) — Node.js MCP server that lets Cursor AI manage the PostgreSQL stack: create/drop databases and roles, manage PgBouncer mappings, rotate passwords, trigger backups.

See [`tools/mcp-postgres-ops/README.md`](tools/mcp-postgres-ops/README.md) for setup.

## Repository Structure

```
├── docker/               # Stack: compose, config, scripts
│   ├── .env.example
│   ├── docker-compose.yml
│   ├── postgres/
│   ├── pgbouncer/
│   ├── init/
│   ├── backup/
│   ├── monitoring/
│   └── scripts/
└── tools/
    └── mcp-postgres-ops/ # MCP server (Node.js)
```
