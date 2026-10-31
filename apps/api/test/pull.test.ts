import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { createDb, createPool } from "../src/db.js";
import { upsertProduct } from "../src/products.js";
import type { PullResponse } from "../src/sync/protocol.js";
import { databaseUrl, resetSyncTables } from "./helpers.js";

const pool = createPool(databaseUrl);
const db = createDb(pool);
const app = buildApp({ pool, logLevel: "silent" });

async function pull(query: string): Promise<{ statusCode: number; body: PullResponse }> {
  const response = await app.inject({ method: "GET", url: `/sync/pull${query}` });
  return { statusCode: response.statusCode, body: response.json<PullResponse>() };
}

const apple = { sku: "APL-1", name: "Apple juice 1L", priceCents: 250 };
const bread = { sku: "BRD-1", name: "Bread loaf", priceCents: 180 };
const cocoa = { sku: "COC-1", name: "Cocoa 200g", priceCents: 420 };

describe("GET /sync/pull", () => {
  beforeEach(async () => {
    await resetSyncTables(pool);
  });

  afterAll(async () => {
    await app.close();
    await pool.end();
  });

  it("returns no changes and the same cursor when the log is empty", async () => {
    const { statusCode, body } = await pull("");

    expect(statusCode).toBe(200);
    expect(body).toEqual({ changes: [], cursor: "0", hasMore: false });
  });

  it("returns server writes in the order they happened", async () => {
    const appleId = await upsertProduct(db, apple);
    await upsertProduct(db, { ...apple, priceCents: 275 });

    const { body } = await pull("");

    expect(body.changes).toEqual([
      { entity: "product", id: appleId, op: "upsert", version: 1, data: apple },
      {
        entity: "product",
        id: appleId,
        op: "upsert",
        version: 2,
        data: { ...apple, priceCents: 275 },
      },
    ]);
  });

  it("adds no change when a product is written again unchanged", async () => {
    await upsertProduct(db, apple);
    await upsertProduct(db, apple);

    const { body } = await pull("");

    expect(body.changes).toHaveLength(1);
  });

  it("pages through the log with the returned cursor", async () => {
    await upsertProduct(db, apple);
    await upsertProduct(db, bread);
    await upsertProduct(db, cocoa);

    const first = await pull("?limit=2");
    const second = await pull(`?limit=2&cursor=${first.body.cursor}`);
    const third = await pull(`?limit=2&cursor=${second.body.cursor}`);

    expect(first.body.changes.map(skuOf)).toEqual(["APL-1", "BRD-1"]);
    expect(first.body.hasMore).toBe(true);
    expect(second.body.changes.map(skuOf)).toEqual(["COC-1"]);
    expect(second.body.hasMore).toBe(false);
    expect(third.body).toEqual({ changes: [], cursor: second.body.cursor, hasMore: false });
  });

  it.each([["?cursor=abc"], ["?cursor=-1"], ["?limit=0"], ["?limit=501"]])(
    "rejects %s with 400",
    async (query) => {
      const { statusCode } = await pull(query);

      expect(statusCode).toBe(400);
    },
  );
});

function skuOf(change: PullResponse["changes"][number]): string | undefined {
  return change.op === "upsert" && change.entity === "product" ? change.data.sku : undefined;
}
