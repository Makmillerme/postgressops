-- ============================================================
-- PostgreSQL Init: Extensions (має виконуватися ПЕРЕД 01 — там dblink)
-- Виконується при першому старті в базі postgres.
-- ============================================================

-- Потрібно для dblink у скрипті 01 (CREATE DATABASE в DO-блоці)
CREATE EXTENSION IF NOT EXISTS dblink;

-- Корисні розширення (додай за потребою для кожного проєкту)
-- CREATE EXTENSION IF NOT EXISTS pg_stat_statements;  -- slow query tracking
-- CREATE EXTENSION IF NOT EXISTS pgcrypto;             -- UUID v4, хешування
-- CREATE EXTENSION IF NOT EXISTS unaccent;             -- full-text search
