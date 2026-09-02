#!/usr/bin/env node
// ============================================================
// MCP Postgres Ops Server
// Provides tools for managing a PostgreSQL production stack
// (databases, roles, PgBouncer, backups) over stdio MCP transport.
// ============================================================

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync, appendFileSync, existsSync, writeFileSync } from "fs";
import { execSync } from "child_process";
import pg from "pg";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// --- Load .env ---
const envPath = path.join(__dirname, "..", ".env");
if (existsSync(envPath)) {
  const lines = readFileSync(envPath, "utf8").split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const k = trimmed.slice(0, eq).trim();
    const v = trimmed.slice(eq + 1).trim().replace(/^["']|["']$/g, "");
    if (k && !(k in process.env)) process.env[k] = v;
  }
}

const POSTGRESSOPS_HOME = process.env.POSTGRESSOPS_HOME || "/opt/postgressops";

// On this stack, host-level SQL access goes through PgBouncer (port 6432).
// Direct Postgres port 5432 is NOT published on the host by default.
const CONFIG = {
  pgHost:         process.env.PG_HOST          || "127.0.0.1",
  pgPort:         parseInt(process.env.PG_PORT || process.env.PGBOUNCER_PORT || "6432", 10),
  pgUser:         process.env.PG_USER          || "",
  pgPassword:     process.env.PG_PASSWORD      || "",
  pgDb:           process.env.PG_MAINTENANCE_DB || "postgres",
  pgbouncerHost:  process.env.PGBOUNCER_HOST   || "127.0.0.1",
  pgbouncerPort:  parseInt(process.env.PGBOUNCER_PORT || "6432", 10),
  stackDir:       process.env.STACK_DIR        || path.join(POSTGRESSOPS_HOME, "docker"),
  scriptsDir:     process.env.SCRIPTS_DIR      || path.join(POSTGRESSOPS_HOME, "scripts"),
  logFile:        process.env.MCP_LOG_FILE     || "/tmp/mcp-postgres-ops.log",
};
if (!CONFIG.scriptsDir) {
  CONFIG.scriptsDir = path.join(path.dirname(CONFIG.stackDir), "scripts");
}

// --- Startup validation ---
const missingVars = [];
if (!CONFIG.pgUser)     missingVars.push("PG_USER");
if (!CONFIG.pgPassword) missingVars.push("PG_PASSWORD");
if (!CONFIG.stackDir)   missingVars.push("STACK_DIR");

if (missingVars.length > 0) {
  process.stderr.write(
    `[mcp-postgres-ops] FATAL: Missing required env vars: ${missingVars.join(", ")}\n` +
    `  Fix: edit tools/mcp-postgres-ops/.env on the server (copy from .env.example)\n` +
    `  Then re-run: bash scripts/server-update.sh\n`
  );
  process.exit(1);
}

// --- Helpers ---

function log(tool, msg) {
  const ts = new Date().toISOString();
  const line = `[${ts}] [${tool}] ${msg}\n`;
  try { appendFileSync(CONFIG.logFile, line); } catch {}
}

function pgClient() {
  return new pg.Client({
    host:     CONFIG.pgHost,
    port:     CONFIG.pgPort,
    user:     CONFIG.pgUser,
    password: CONFIG.pgPassword,
    database: CONFIG.pgDb,
    connectionTimeoutMillis: 5000,
  });
}

async function runQuery(sql, params = []) {
  const client = pgClient();
  try {
    await client.connect();
  } catch (e) {
    const hint = e.message.includes("no such database")
      ? `\n  Hint: The '${CONFIG.pgDb}' database is not mapped in PgBouncer.\n` +
        `  Fix: call map_pgbouncer_database with db_name="${CONFIG.pgDb}" pg_db="${CONFIG.pgDb}" pg_user="${CONFIG.pgUser}"\n` +
        `  Or re-run: bash scripts/server-update.sh`
      : e.message.includes("ECONNREFUSED")
        ? `\n  Hint: Cannot reach PgBouncer on ${CONFIG.pgHost}:${CONFIG.pgPort}. Is the stack running?\n` +
          `  Check: docker ps | grep pgbouncer`
        : "";
    throw new Error(e.message + hint);
  }
  try {
    const result = await client.query(sql, params);
    return result;
  } finally {
    await client.end();
  }
}

function shellExec(cmd) {
  return execSync(cmd, { encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] });
}

function pgbIniPath() { return path.join(CONFIG.stackDir, "pgbouncer", "pgbouncer.ini"); }
function userlistPath() { return path.join(CONFIG.stackDir, "pgbouncer", "userlist.txt"); }
function composeFile() { return path.join(CONFIG.stackDir, "docker-compose.yml"); }
function envFile()     { return path.join(CONFIG.stackDir, ".env"); }

function readFile(p) {
  try { return readFileSync(p, "utf8"); } catch (e) { throw new Error(`Cannot read ${p}: ${e.message}`); }
}

function writeFile(p, content) {
  writeFileSync(p, content, "utf8");
}

function composeCli() {
  return `docker compose -f "${composeFile()}" --env-file "${envFile()}"`;
}

const SCRIPT_ALLOWLIST = new Set([
  "install.sh",
  "reinstall.sh",
  "clean-install.sh",
  "upgrade.sh",
  "healthcheck.sh",
  "provision-db.sh",
  "list-connections.sh",
  "server-update.sh",
]);

function runScript(scriptName, args = []) {
  if (!SCRIPT_ALLOWLIST.has(scriptName)) {
    throw new Error(`Script is not allowed: ${scriptName}`);
  }
  if (!Array.isArray(args)) {
    throw new Error("args must be an array");
  }
  const sanitized = args.map((arg) => {
    if (typeof arg !== "string") throw new Error("script args must be strings");
    return `'${arg.replace(/'/g, "'\\''")}'`;
  });
  const scriptPath = path.join(CONFIG.scriptsDir, scriptName);
  return shellExec(`bash "${scriptPath}" ${sanitized.join(" ")}`.trim());
}

// --- MCP Server ---
const server = new McpServer({
  name: "mcp-postgres-ops",
  version: "1.0.0",
});

// ============================================================
// TOOL: healthcheck_stack
// ============================================================
server.tool(
  "healthcheck_stack",
  "Check the health of the PostgreSQL stack: container states, connectivity, last backup.",
  {},
  async () => {
    log("healthcheck_stack", "called");
    try {
      const containers = ["postgres", "pgbouncer", "pg_backup", "postgres_exporter", "prometheus"];
      const rows = [];
      for (const name of containers) {
        try {
          const status = shellExec(`docker inspect -f "{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}no-health{{end}}" ${name}`).trim();
          rows.push(`  ${name.padEnd(22)} ${status}`);
        } catch {
          rows.push(`  ${name.padEnd(22)} NOT FOUND`);
        }
      }

      let pgReady = "FAIL";
      try {
        await runQuery("SELECT 1");
        pgReady = "OK";
      } catch (e) {
        pgReady = `FAIL: ${e.message}`;
      }

      let dbs = [];
      try {
        const r = await runQuery("SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname");
        dbs = r.rows.map(row => row.datname);
      } catch {}

      const lines = [
        "=== PostgreSQL Stack Healthcheck ===",
        "",
        "Containers:",
        ...rows,
        "",
        `Postgres SQL connection: ${pgReady}`,
        "",
        "Databases:",
        ...dbs.map(d => `  ${d}`),
      ];

      return { content: [{ type: "text", text: lines.join("\n") }] };
    } catch (e) {
      log("healthcheck_stack", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

server.tool(
  "run_healthcheck",
  "Run scripts/healthcheck.sh and return output.",
  {},
  async () => {
    try {
      const out = runScript("healthcheck.sh");
      return { content: [{ type: "text", text: out }] };
    } catch (e) {
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

server.tool(
  "run_install",
  "Run scripts/install.sh --local.",
  {},
  async () => {
    try {
      const out = runScript("install.sh", ["--local"]);
      return { content: [{ type: "text", text: out }] };
    } catch (e) {
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

server.tool(
  "run_reinstall",
  "Run scripts/reinstall.sh (no volume wipe).",
  {},
  async () => {
    try {
      const out = runScript("reinstall.sh");
      return { content: [{ type: "text", text: out }] };
    } catch (e) {
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

server.tool(
  "run_upgrade",
  "Run scripts/upgrade.sh.",
  {},
  async () => {
    try {
      const out = runScript("upgrade.sh");
      return { content: [{ type: "text", text: out }] };
    } catch (e) {
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

server.tool(
  "run_provision_db",
  "Run scripts/provision-db.sh <db_name> <db_user> <password>.",
  {
    db_name: z.string().min(1).regex(/^[a-zA-Z_][a-zA-Z0-9_]*$/),
    db_user: z.string().min(1).regex(/^[a-zA-Z_][a-zA-Z0-9_]*$/),
    password: z.string().min(8),
  },
  async ({ db_name, db_user, password }) => {
    try {
      const out = runScript("provision-db.sh", [db_name, db_user, password]);
      return { content: [{ type: "text", text: out }] };
    } catch (e) {
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: list_databases
// ============================================================
server.tool(
  "list_databases",
  "List all non-template databases in the PostgreSQL cluster with owner and size.",
  {},
  async () => {
    log("list_databases", "called");
    try {
      const result = await runQuery(`
        SELECT
          d.datname AS name,
          r.rolname AS owner,
          pg_size_pretty(pg_database_size(d.datname)) AS size
        FROM pg_database d
        JOIN pg_roles r ON r.oid = d.datdba
        WHERE d.datistemplate = false
        ORDER BY d.datname
      `);
      const lines = ["Databases:", ...result.rows.map(r => `  ${r.name.padEnd(30)} owner=${r.owner.padEnd(20)} size=${r.size}`)];
      return { content: [{ type: "text", text: lines.join("\n") }] };
    } catch (e) {
      log("list_databases", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: list_roles
// ============================================================
server.tool(
  "list_roles",
  "List all roles in PostgreSQL with their attributes.",
  {},
  async () => {
    log("list_roles", "called");
    try {
      const result = await runQuery(`
        SELECT
          rolname AS name,
          rolsuper AS superuser,
          rolcreatedb AS createdb,
          rolcanlogin AS canlogin,
          rolreplication AS replication
        FROM pg_roles
        WHERE rolname NOT LIKE 'pg_%'
        ORDER BY rolname
      `);
      const lines = [
        "Roles:",
        "  name                           super  createdb  login  replication",
        "  " + "-".repeat(70),
        ...result.rows.map(r =>
          `  ${r.name.padEnd(30)} ${String(r.superuser).padEnd(6)} ${String(r.createdb).padEnd(9)} ${String(r.canlogin).padEnd(6)} ${r.replication}`
        ),
      ];
      return { content: [{ type: "text", text: lines.join("\n") }] };
    } catch (e) {
      log("list_roles", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: create_database
// ============================================================
server.tool(
  "create_database",
  "Create a new database with an owner role, add to PgBouncer, update userlist. Idempotent.",
  {
    db_name:  z.string().min(1).regex(/^[a-zA-Z_][a-zA-Z0-9_]*$/, "db_name must be a valid identifier"),
    db_user:  z.string().min(1).regex(/^[a-zA-Z_][a-zA-Z0-9_]*$/, "db_user must be a valid identifier"),
    password: z.string().min(8, "password must be at least 8 characters"),
  },
  async ({ db_name, db_user, password }) => {
    log("create_database", `db=${db_name} user=${db_user}`);
    const steps = [];
    try {
      const escapedPass = pg.escapeLiteral(password);

      // 1. Create role if not exists, or update password
      const roleExists = await runQuery(`SELECT 1 FROM pg_roles WHERE rolname = '${db_user}'`);
      if (roleExists.rowCount === 0) {
        await runQuery(`CREATE ROLE "${db_user}" LOGIN PASSWORD ${escapedPass}`);
        steps.push(`Role '${db_user}' created.`);
      } else {
        await runQuery(`ALTER ROLE "${db_user}" LOGIN PASSWORD ${escapedPass}`);
        steps.push(`Role '${db_user}' exists — password updated.`);
      }

      // 2. Create database if not exists
      const dbExists = await runQuery(`SELECT 1 FROM pg_database WHERE datname = '${db_name}'`);
      if (dbExists.rowCount === 0) {
        await runQuery(`CREATE DATABASE "${db_name}" OWNER "${db_user}"`);
        steps.push(`Database '${db_name}' created.`);
      } else {
        steps.push(`Database '${db_name}' already exists — skipped.`);
      }

      await runQuery(`GRANT ALL PRIVILEGES ON DATABASE "${db_name}" TO "${db_user}"`);
      steps.push(`Privileges granted.`);

      // 3. PgBouncer ini
      const iniContent = readFile(pgbIniPath());
      const iniLine = `${db_name} = host=postgres port=5432 dbname=${db_name} user=${db_user}`;
      if (!new RegExp(`^${db_name}\\s*=`,"m").test(iniContent)) {
        const updated = iniContent.replace(/(\[databases\][^\n]*)/, `$1\n${iniLine}`);
        writeFile(pgbIniPath(), updated);
        steps.push(`Added '${db_name}' to pgbouncer.ini.`);
      } else {
        steps.push(`pgbouncer.ini already has '${db_name}' entry — skipped.`);
      }

      // 4. userlist.txt
      let userlist = readFile(userlistPath());
      const userPattern = new RegExp(`^"${db_user}"\\s+"[^"]*"`, "m");
      const userLine = `"${db_user}" "${password}"`;
      if (userPattern.test(userlist)) {
        userlist = userlist.replace(userPattern, userLine);
        steps.push(`Updated '${db_user}' in userlist.txt.`);
      } else {
        userlist += (userlist.endsWith("\n") ? "" : "\n") + userLine + "\n";
        steps.push(`Added '${db_user}' to userlist.txt.`);
      }
      writeFile(userlistPath(), userlist);

      // 5. Reload PgBouncer
      shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);
      steps.push(`PgBouncer reloaded.`);

      log("create_database", `SUCCESS: ${steps.join("; ")}`);
      return { content: [{ type: "text", text: ["SUCCESS:", ...steps.map(s => `  - ${s}`)].join("\n") }] };
    } catch (e) {
      log("create_database", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}\nCompleted steps:\n${steps.map(s => `  - ${s}`).join("\n")}` }] };
    }
  }
);

// ============================================================
// TOOL: drop_database
// DESTRUCTIVE — requires confirm=true
// ============================================================
server.tool(
  "drop_database",
  "Drop a database. DESTRUCTIVE — requires confirm=true. Does NOT drop the owner role.",
  {
    db_name: z.string().min(1),
    confirm: z.boolean().describe("Must be true to execute. Safety guard against accidental deletion."),
  },
  async ({ db_name, confirm }) => {
    log("drop_database", `db=${db_name} confirm=${confirm}`);
    if (!confirm) {
      return { content: [{ type: "text", text: `Aborted: confirm must be true to drop database '${db_name}'.` }] };
    }
    try {
      await runQuery(`DROP DATABASE IF EXISTS "${db_name}"`);
      log("drop_database", `SUCCESS: dropped ${db_name}`);

      // Remove from pgbouncer.ini
      const iniContent = readFile(pgbIniPath());
      const cleaned = iniContent.split("\n").filter(l => !l.trim().startsWith(`${db_name} =`)).join("\n");
      writeFile(pgbIniPath(), cleaned);

      shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);

      return { content: [{ type: "text", text: `Database '${db_name}' dropped and removed from PgBouncer.` }] };
    } catch (e) {
      log("drop_database", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: create_role
// ============================================================
server.tool(
  "create_role",
  "Create a new PostgreSQL role with LOGIN. If exists — only updates password.",
  {
    role_name: z.string().min(1).regex(/^[a-zA-Z_][a-zA-Z0-9_]*$/),
    password:  z.string().min(8),
  },
  async ({ role_name, password }) => {
    log("create_role", `role=${role_name}`);
    try {
      const escapedPass = pg.escapeLiteral(password);
      const exists = await runQuery(`SELECT 1 FROM pg_roles WHERE rolname = '${role_name}'`);
      if (exists.rowCount === 0) {
        await runQuery(`CREATE ROLE "${role_name}" LOGIN PASSWORD ${escapedPass}`);
        return { content: [{ type: "text", text: `Role '${role_name}' created.` }] };
      } else {
        await runQuery(`ALTER ROLE "${role_name}" LOGIN PASSWORD ${escapedPass}`);
        return { content: [{ type: "text", text: `Role '${role_name}' exists — password updated.` }] };
      }
    } catch (e) {
      log("create_role", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: drop_role
// DESTRUCTIVE — requires confirm=true
// ============================================================
server.tool(
  "drop_role",
  "Drop a PostgreSQL role. DESTRUCTIVE — requires confirm=true. Role must have no owned objects.",
  {
    role_name: z.string().min(1),
    confirm:   z.boolean().describe("Must be true to execute."),
  },
  async ({ role_name, confirm }) => {
    log("drop_role", `role=${role_name} confirm=${confirm}`);
    if (!confirm) {
      return { content: [{ type: "text", text: `Aborted: confirm must be true to drop role '${role_name}'.` }] };
    }
    try {
      await runQuery(`DROP ROLE IF EXISTS "${role_name}"`);

      // Remove from userlist.txt
      const userlist = readFile(userlistPath());
      const cleaned = userlist.split("\n").filter(l => !l.startsWith(`"${role_name}"`)).join("\n");
      writeFile(userlistPath(), cleaned);

      shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);

      log("drop_role", `SUCCESS: dropped ${role_name}`);
      return { content: [{ type: "text", text: `Role '${role_name}' dropped and removed from userlist.txt.` }] };
    } catch (e) {
      log("drop_role", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: rotate_role_password
// ============================================================
server.tool(
  "rotate_role_password",
  "Change the password for a PostgreSQL role and update PgBouncer userlist.",
  {
    role_name:    z.string().min(1),
    new_password: z.string().min(8),
  },
  async ({ role_name, new_password }) => {
    log("rotate_role_password", `role=${role_name}`);
    try {
      const escapedPass = pg.escapeLiteral(new_password);
      await runQuery(`ALTER ROLE "${role_name}" PASSWORD ${escapedPass}`);

      let userlist = readFile(userlistPath());
      const pattern = new RegExp(`^"${role_name}"\\s+"[^"]*"`, "m");
      if (pattern.test(userlist)) {
        userlist = userlist.replace(pattern, `"${role_name}" "${new_password}"`);
      } else {
        userlist += `"${role_name}" "${new_password}"\n`;
      }
      writeFile(userlistPath(), userlist);
      shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);

      log("rotate_role_password", `SUCCESS: rotated for ${role_name}`);
      return { content: [{ type: "text", text: `Password rotated for role '${role_name}'. PgBouncer reloaded.` }] };
    } catch (e) {
      log("rotate_role_password", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: map_pgbouncer_database
// ============================================================
server.tool(
  "map_pgbouncer_database",
  "Add or update a PgBouncer [databases] entry and reload PgBouncer.",
  {
    db_name:   z.string().min(1),
    pg_db:     z.string().min(1).describe("Actual PostgreSQL database name"),
    pg_user:   z.string().min(1).describe("User that PgBouncer uses to connect to Postgres"),
  },
  async ({ db_name, pg_db, pg_user }) => {
    log("map_pgbouncer_database", `db_name=${db_name} pg_db=${pg_db} pg_user=${pg_user}`);
    try {
      let ini = readFile(pgbIniPath());
      const entry = `${db_name} = host=postgres port=5432 dbname=${pg_db} user=${pg_user}`;
      const pattern = new RegExp(`^${db_name}\\s*=.*`, "m");
      if (pattern.test(ini)) {
        ini = ini.replace(pattern, entry);
        writeFile(pgbIniPath(), ini);
        shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);
        log("map_pgbouncer_database", `SUCCESS: updated entry`);
        return { content: [{ type: "text", text: `Updated PgBouncer mapping for '${db_name}'. PgBouncer reloaded.` }] };
      } else {
        ini = ini.replace(/(\[databases\][^\n]*)/, `$1\n${entry}`);
        writeFile(pgbIniPath(), ini);
        shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);
        log("map_pgbouncer_database", `SUCCESS: added entry`);
        return { content: [{ type: "text", text: `Added PgBouncer mapping for '${db_name}'. PgBouncer reloaded.` }] };
      }
    } catch (e) {
      log("map_pgbouncer_database", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: reload_pgbouncer
// ============================================================
server.tool(
  "reload_pgbouncer",
  "Force-recreate the PgBouncer container to pick up config changes.",
  {},
  async () => {
    log("reload_pgbouncer", "called");
    try {
      const out = shellExec(`${composeCli()} up -d pgbouncer --force-recreate`);
      log("reload_pgbouncer", "SUCCESS");
      return { content: [{ type: "text", text: `PgBouncer reloaded.\n${out}` }] };
    } catch (e) {
      log("reload_pgbouncer", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: run_backup_now
// ============================================================
server.tool(
  "run_backup_now",
  "Trigger an immediate backup by running backup.sh inside the pg_backup container.",
  {},
  async () => {
    log("run_backup_now", "called");
    try {
      const out = shellExec("docker exec pg_backup sh /usr/local/bin/backup.sh");
      log("run_backup_now", "SUCCESS");
      return { content: [{ type: "text", text: `Backup completed.\n\n${out}` }] };
    } catch (e) {
      log("run_backup_now", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// ============================================================
// TOOL: run_sql
// ============================================================
server.tool(
  "run_sql",
  "Execute a raw SQL query on the maintenance database (admin user). Use for inspection only. No DDL changes via this tool.",
  {
    sql:     z.string().min(1).describe("SELECT query only — no DDL or DML that modifies data."),
    db_name: z.string().default("postgres").describe("Database to connect to (defaults to maintenance DB)."),
  },
  async ({ sql, db_name }) => {
    log("run_sql", `db=${db_name} sql=${sql.slice(0, 80)}`);
    const normalized = sql.trim().toLowerCase();
    const forbidden = ["drop ", "create ", "alter ", "truncate ", "delete ", "insert ", "update ", "grant ", "revoke "];
    if (forbidden.some(kw => normalized.startsWith(kw))) {
      return {
        content: [{ type: "text", text: `Blocked: run_sql is read-only. Use dedicated tools for DDL/DML operations.` }],
      };
    }
    try {
      const client = new pg.Client({
        host: CONFIG.pgHost, port: CONFIG.pgPort,
        user: CONFIG.pgUser, password: CONFIG.pgPassword,
        database: db_name,
        connectionTimeoutMillis: 5000,
      });
      await client.connect();
      const result = await client.query(sql);
      await client.end();
      const headers = result.fields?.map(f => f.name) || [];
      const rows = result.rows || [];
      const lines = [
        headers.join("\t"),
        ...rows.map(row => headers.map(h => row[h] ?? "").join("\t")),
        `\n(${rows.length} row${rows.length !== 1 ? "s" : ""})`,
      ];
      return { content: [{ type: "text", text: lines.join("\n") }] };
    } catch (e) {
      log("run_sql", `ERROR: ${e.message}`);
      return { content: [{ type: "text", text: `ERROR: ${e.message}` }] };
    }
  }
);

// --- Start ---
const transport = new StdioServerTransport();
await server.connect(transport);
