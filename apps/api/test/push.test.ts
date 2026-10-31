import { randomUUID } from "node:crypto";
import { afterAll, beforeEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/app.js";
import { createDb, createPool } from "../src/db.js";
import { upsertProduct } from "../src/products.js";
import type { Mutation, PullResponse, PushResponse } from "../src/sync/protocol.js";
import { databaseUrl, resetSyncTables } from "./helpers.js";

const pool = createPool(databaseUrl);
const db = createDb(pool);
const app = buildApp({ pool, logLevel: "silent" });

async function push(mutations: unknown[]) {
  const response = await app.inject({ method: "POST", url: "/sync/push", payload: { mutations } });
  return { statusCode: response.statusCode, body: response.json<PushResponse>() };
}

async function pullAll(): Promise<PullResponse["changes"]> {
  const response = await app.inject({ method: "GET", url: "/sync/pull?limit=500" });
  return response.json<PullResponse>().changes;
}

let productId: string;

type UpsertMutation = Extract<Mutation, { op: "upsert" }>;

function upsert(
  id: string,
  baseVersion: number | null,
  customerName = "Corner Shop",
): UpsertMutation {
  return {
    mutationId: randomUUID(),
    entity: "order",
    op: "upsert",
    id,
    baseVersion,
    data: { customerName, lines: [{ productId, quantity: 2 }] },
  };
}

function remove(id: string, baseVersion: number): Mutation {
  return { mutationId: randomUUID(), entity: "order", op: "delete", id, baseVersion };
}

describe("POST /sync/push", () => {
  beforeEach(async () => {
    await resetSyncTables(pool);
    productId = await upsertProduct(db, { sku: "APL-1", name: "Apple juice 1L", priceCents: 250 });
  });

  afterAll(async () => {
    await app.close();
    await pool.end();
  });

  it("creates an order and adds it to the change log", async () => {
    const id = randomUUID();
    const create = upsert(id, null);

    const { statusCode, body } = await push([create]);

    expect(statusCode).toBe(200);
    expect(body.results).toEqual([
      { mutationId: create.mutationId, status: "applied", version: 1 },
    ]);
    expect(await pullAll()).toContainEqual({
      entity: "order",
      id,
      op: "upsert",
      version: 1,
      data: create.data,
    });
  });

  it("returns the stored result for a retried mutation and applies it once", async () => {
    const create = upsert(randomUUID(), null);

    const first = await push([create]);
    const retry = await push([create]);

    expect(retry.body).toEqual(first.body);
    expect((await pullAll()).filter((change) => change.entity === "order")).toHaveLength(1);
  });

  it("updates an order when baseVersion matches the server version", async () => {
    const id = randomUUID();
    await push([upsert(id, null)]);
    const update = upsert(id, 1, "Corner Shop Ltd");

    const { body } = await push([update]);

    expect(body.results).toEqual([
      { mutationId: update.mutationId, status: "applied", version: 2 },
    ]);
  });

  it("returns a conflict with the server copy when baseVersion is stale", async () => {
    const id = randomUUID();
    await push([upsert(id, null)]);
    await push([upsert(id, 1, "Edited on phone A")]);
    const staleEdit = upsert(id, 1, "Edited on phone B");

    const { body } = await push([staleEdit]);

    expect(body.results).toEqual([
      {
        mutationId: staleEdit.mutationId,
        status: "conflict",
        server: {
          exists: true,
          deleted: false,
          version: 2,
          data: { customerName: "Edited on phone A", lines: [{ productId, quantity: 2 }] },
        },
      },
    ]);
    expect((await pullAll()).filter((change) => change.entity === "order")).toHaveLength(2);
  });

  it("returns a conflict when a create uses an id that already exists", async () => {
    const id = randomUUID();
    await push([upsert(id, null)]);
    const secondCreate = upsert(id, null);

    const { body } = await push([secondCreate]);

    expect(body.results[0]).toMatchObject({
      status: "conflict",
      server: { exists: true, version: 1 },
    });
  });

  it("returns a conflict when an update targets an order the server does not have", async () => {
    const { body } = await push([upsert(randomUUID(), 1)]);

    expect(body.results[0]).toMatchObject({ status: "conflict", server: { exists: false } });
  });

  it("deletes an order and rejects later edits to it as conflicts", async () => {
    const id = randomUUID();
    await push([upsert(id, null)]);

    const deleted = await push([remove(id, 1)]);
    const lateEdit = await push([upsert(id, 2)]);

    expect(deleted.body.results[0]).toMatchObject({ status: "applied", version: 2 });
    expect(await pullAll()).toContainEqual({ entity: "order", id, op: "delete", version: 2 });
    expect(lateEdit.body.results[0]).toMatchObject({
      status: "conflict",
      server: { exists: true, deleted: true, version: 2 },
    });
  });

  it("rejects an order that refers to an unknown product and writes nothing", async () => {
    const mutation = upsert(randomUUID(), null);
    mutation.data.lines = [{ productId: randomUUID(), quantity: 1 }];

    const { body } = await push([mutation]);

    expect(body.results[0]).toMatchObject({ status: "rejected" });
    expect((await pullAll()).filter((change) => change.entity === "order")).toHaveLength(0);
  });

  it("applies a batch in order, so a later mutation can edit an order created earlier", async () => {
    const id = randomUUID();

    const { body } = await push([upsert(id, null), upsert(id, 1, "Renamed")]);

    expect(body.results.map((result) => result.status)).toEqual(["applied", "applied"]);
    expect(body.results[1]).toMatchObject({ version: 2 });
  });

  it("rejects a malformed batch with 400 and applies none of it", async () => {
    const valid = upsert(randomUUID(), null);
    const missingId = { ...upsert(randomUUID(), null), mutationId: undefined };

    const { statusCode } = await push([valid, missingId]);

    expect(statusCode).toBe(400);
    expect((await pullAll()).filter((change) => change.entity === "order")).toHaveLength(0);
  });
});
