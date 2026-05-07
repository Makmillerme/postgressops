-- ============================================================
-- PostgreSQL Init: System Extensions Bootstrap
-- Runs automatically on first container start in database "postgres".
-- Do NOT add project-specific databases or roles here.
-- Use scripts/provision-db.sh for project provisioning.
-- ============================================================

-- Required for runtime CREATE DATABASE in PL/pgSQL DO-blocks (dblink).
CREATE EXTENSION IF NOT EXISTS dblink;

-- Uncomment as needed for projects:
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;  -- slow query tracking
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;             -- UUID v4, hashing
-- CREATE EXTENSION IF NOT EXISTS unaccent;             -- full-text search
