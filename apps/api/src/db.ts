import pg from "pg";

/** Fails a connection attempt after this long, so /health answers even when Postgres hangs. */
const connectionTimeoutMillis = 2_000;

export function createPool(databaseUrl: string): pg.Pool {
  return new pg.Pool({ connectionString: databaseUrl, connectionTimeoutMillis });
}
