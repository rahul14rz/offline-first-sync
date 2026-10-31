import { fileURLToPath } from "node:url";
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate } from "drizzle-orm/node-postgres/migrator";
import pg from "pg";

/** Fails a connection attempt after this long, so /health answers even when Postgres hangs. */
const connectionTimeoutMillis = 2_000;

export function createPool(databaseUrl: string): pg.Pool {
  return new pg.Pool({ connectionString: databaseUrl, connectionTimeoutMillis });
}

// Resolves to apps/api/drizzle from both src/ (tsx, tests) and dist/ (built image).
const migrationsFolder = fileURLToPath(new URL("../drizzle", import.meta.url));

/** Applies pending migrations. Safe to call on every start: applied ones are skipped. */
export async function runMigrations(pool: pg.Pool): Promise<void> {
  await migrate(drizzle({ client: pool }), { migrationsFolder });
}
