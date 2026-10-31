import { afterAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../src/app.js";
import { createPool } from "../src/db.js";

const databaseUrl = process.env.DATABASE_URL ?? "postgres://sync:sync@localhost:5432/sync";

describe("GET /health", () => {
  const reachable = createPool(databaseUrl);
  // Nothing listens on port 1, so connecting fails immediately.
  const unreachable = createPool("postgres://sync:sync@127.0.0.1:1/sync");

  afterAll(async () => {
    await Promise.all([reachable.end(), unreachable.end()]);
  });

  it("returns 200 when Postgres answers a query", async () => {
    const app = buildApp({ pool: reachable, logLevel: "silent" });

    const response = await app.inject({ method: "GET", url: "/health" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok", database: "ok" });
  });

  it("returns 503 when Postgres cannot be reached", async () => {
    const app = buildApp({ pool: unreachable, logLevel: "silent" });

    const response = await app.inject({ method: "GET", url: "/health" });

    expect(response.statusCode).toBe(503);
    expect(response.json()).toEqual({ status: "unavailable", database: "unreachable" });
  });

  it("keeps serving after Postgres drops an idle pooled connection", async () => {
    const pool = createPool(databaseUrl);
    const admin = createPool(databaseUrl);
    const app = buildApp({ pool, logLevel: "silent" });
    try {
      // After this query the connection sits idle in the pool.
      const { rows } = await pool.query<{ pid: number }>("select pg_backend_pid() as pid");
      const pid = rows[0]?.pid;
      await admin.query("select pg_terminate_backend($1)", [pid]);
      await vi.waitFor(() => {
        expect(pool.totalCount).toBe(0);
      });

      const response = await app.inject({ method: "GET", url: "/health" });

      expect(response.statusCode).toBe(200);
    } finally {
      await Promise.all([pool.end(), admin.end()]);
    }
  });
});
