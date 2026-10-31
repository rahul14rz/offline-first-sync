import { readFile } from "node:fs/promises";
import { afterAll, describe, expect, it } from "vitest";
import { createPool, runMigrations } from "../src/db.js";

const databaseUrl = process.env.DATABASE_URL ?? "postgres://sync:sync@localhost:5432/sync";

describe("runMigrations", () => {
  const pool = createPool(databaseUrl);

  afterAll(async () => {
    await pool.end();
  });

  it("records each migration in the journal exactly once, even when run twice", async () => {
    const journal = JSON.parse(
      await readFile(new URL("../drizzle/meta/_journal.json", import.meta.url), "utf8"),
    ) as { entries: unknown[] };

    await runMigrations(pool);
    await runMigrations(pool);

    const { rows } = await pool.query<{ count: number }>(
      "select count(*)::int as count from drizzle.__drizzle_migrations",
    );
    expect(rows[0]?.count).toBe(journal.entries.length);
  });
});
