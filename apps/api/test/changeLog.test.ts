import { randomUUID } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { createDb, createPool } from "../src/db.js";
import { upsertProduct } from "../src/products.js";
import { readChanges, writeSynced } from "../src/sync/changeLog.js";
import { databaseUrl, resetSyncTables } from "./helpers.js";

const pool = createPool(databaseUrl);
const db = createDb(pool);

describe("change log", () => {
  beforeEach(async () => {
    await resetSyncTables(pool);
  });

  afterAll(async () => {
    await pool.end();
  });

  it("does not let a pull skip a change whose transaction commits after a later one", async () => {
    // Writer A appends a change (seq 1) and keeps its transaction open.
    const slowId = randomUUID();
    let appended!: () => void;
    let release!: () => void;
    const slowAppended = new Promise<void>((resolve) => (appended = resolve));
    const slowCanCommit = new Promise<void>((resolve) => (release = resolve));
    const slowWrite = writeSynced(db, async (_tx, append) => {
      const data = { sku: "SLOW-1", name: "Slow writer", priceCents: 1 };
      await append({ entity: "product", entityId: slowId, op: "upsert", version: 1, data });
      appended();
      await slowCanCommit;
    });
    await slowAppended;

    // Writer B starts after A, so it gets seq 2. Give it time to commit if nothing stops it.
    const fastWrite = upsertProduct(db, { sku: "FAST-1", name: "Fast writer", priceCents: 1 });
    await Promise.race([fastWrite, sleep(300)]);

    // A phone pulls while A is still open, then pulls again after A commits.
    const first = await readChanges(db, 0, 100);
    release();
    await Promise.all([slowWrite, fastWrite]);
    const second = await readChanges(db, Number(first.cursor), 100);

    const received = [...first.changes, ...second.changes].map((change) => change.id);
    expect(received).toContain(slowId);
    expect(received).toHaveLength(2);
  });
});
