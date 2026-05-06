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
