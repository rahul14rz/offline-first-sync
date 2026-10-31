import { createPool, runMigrations } from "../src/db.js";
import { databaseUrl } from "./helpers.js";

export default async function setup(): Promise<void> {
  const pool = createPool(databaseUrl);
  try {
    await runMigrations(pool);
  } finally {
    await pool.end();
  }
}
