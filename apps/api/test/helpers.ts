import type pg from "pg";

export const databaseUrl = process.env.DATABASE_URL ?? "postgres://sync:sync@localhost:5432/sync";

export async function resetSyncTables(pool: pg.Pool): Promise<void> {
  await pool.query("truncate products, orders, changes, applied_mutations restart identity");
}
