import { fileURLToPath } from "node:url";
import { drizzle, type NodePgDatabase } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import pg from "pg";
import * as schema from "./schema.js";

/** Fails a connection attempt after this long, so /health answers even when Postgres hangs. */
const connectionTimeoutMillis = 2_000;

export type Db = NodePgDatabase<typeof schema>;

export function createPool(databaseUrl: string): pg.Pool {
  return new pg.Pool({ connectionString: databaseUrl, connectionTimeoutMillis });
}

export function createDb(pool: pg.Pool): Db {
  return drizzle({ client: pool, schema, casing: "snake_case" });
}

// Resolves to apps/api/drizzle from both src/ (tsx, tests) and dist/ (built image).
const migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));

/** Applies pending migrations. Safe to call on every start: applied ones are skipped. */
export async function runMigrations(pool: pg.Pool): Promise<void> {
  await migrate(createDb(pool), { migrationsFolder });
}
