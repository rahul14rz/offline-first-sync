import { afterAll, describe, expect, it } from "vitest";
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
});
