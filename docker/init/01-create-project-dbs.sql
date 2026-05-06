-- ============================================================
-- PostgreSQL Init: Per-Project Databases & Users
-- Виконується автоматично при першому старті контейнера.
-- Додай блок нижче для кожного нового проєкту.
-- ============================================================

-- ---- Project: app1 ----
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app1_user') THEN
    CREATE ROLE app1_user LOGIN PASSWORD 'CHANGE_ME_APP1_PASSWORD';
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'app1') THEN
    PERFORM dblink_exec('dbname=postgres', 'CREATE DATABASE app1 OWNER app1_user');
  END IF;
END
$$;

GRANT ALL PRIVILEGES ON DATABASE app1 TO app1_user;

-- ---- Project: app2 ----
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'app2_user') THEN
    CREATE ROLE app2_user LOGIN PASSWORD 'CHANGE_ME_APP2_PASSWORD';
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = 'app2') THEN
    PERFORM dblink_exec('dbname=postgres', 'CREATE DATABASE app2 OWNER app2_user');
  END IF;
END
$$;

GRANT ALL PRIVILEGES ON DATABASE app2 TO app2_user;

-- ---- Моніторинг: read-only роль для postgres_exporter ----
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'pg_exporter') THEN
    CREATE ROLE pg_exporter LOGIN PASSWORD 'CHANGE_ME_EXPORTER_PASSWORD';
  END IF;
END
$$;

GRANT pg_monitor TO pg_exporter;
