import { eq, inArray, sql } from "drizzle-orm";
import type { Db } from "../db.js";
import { appliedMutations, orders, products } from "../schema.js";
import { type AppendChange, type Tx, writeSynced } from "./changeLog.js";
import type { Mutation, MutationResult, ServerRow } from "./protocol.js";

/** Applies a batch in one transaction, in order. Returns one result per mutation. */
export async function applyPush(db: Db, mutations: Mutation[]): Promise<MutationResult[]> {
  return writeSynced(db, async (tx, append) => {
    const results: MutationResult[] = [];
    for (const mutation of mutations) {
      results.push(await applyOnce(tx, append, mutation));
    }
    return results;
  });
}

/**
 * Returns the stored result if this mutationId was seen before. writeSynced holds the change
 * log lock, so no other push can apply the same mutationId between the lookup and the insert.
 */
async function applyOnce(
  tx: Tx,
  append: AppendChange,
  mutation: Mutation,
): Promise<MutationResult> {
  const [previous] = await tx
    .select({ result: appliedMutations.result })
    .from(appliedMutations)
    .where(eq(appliedMutations.mutationId, mutation.mutationId));
  if (previous) return previous.result;

  const result = await apply(tx, append, mutation);
  await tx.insert(appliedMutations).values({ mutationId: mutation.mutationId, result });
  return result;
}

async function apply(tx: Tx, append: AppendChange, mutation: Mutation): Promise<MutationResult> {
  const { mutationId, id } = mutation;
  const server = await readOrder(tx, id);
  const baseMatches =
    mutation.baseVersion === null
      ? !server.exists
      : server.exists && !server.deleted && server.version === mutation.baseVersion;
  if (!baseMatches) return { mutationId, status: "conflict", server };

  if (mutation.op === "delete") {
    const version = mutation.baseVersion + 1;
    await tx
      .update(orders)
      .set({ version, deletedAt: sql`now()`, updatedAt: sql`now()` })
      .where(eq(orders.id, id));
    await append({ entity: "order", entityId: id, op: "delete", version });
    return { mutationId, status: "applied", version };
  }

  const unknown = await unknownProductIds(
    tx,
    mutation.data.lines.map((line) => line.productId),
  );
  if (unknown.length > 0) {
    return { mutationId, status: "rejected", reason: `unknown product ids: ${unknown.join(", ")}` };
  }

  const { customerName, lines } = mutation.data;
  const version = (mutation.baseVersion ?? 0) + 1;
  if (mutation.baseVersion === null) {
    await tx.insert(orders).values({ id, customerName, lines, version });
  } else {
    await tx
      .update(orders)
      .set({ customerName, lines, version, updatedAt: sql`now()` })
      .where(eq(orders.id, id));
  }
  await append({ entity: "order", entityId: id, op: "upsert", version, data: mutation.data });
  return { mutationId, status: "applied", version };
}

async function readOrder(tx: Tx, id: string): Promise<ServerRow> {
  const [row] = await tx.select().from(orders).where(eq(orders.id, id));
  if (!row) return { exists: false };
  if (row.deletedAt) return { exists: true, version: row.version, deleted: true };
  return {
    exists: true,
    version: row.version,
    deleted: false,
    data: { customerName: row.customerName, lines: row.lines },
  };
}

async function unknownProductIds(tx: Tx, ids: string[]): Promise<string[]> {
  const wanted = [...new Set(ids)];
  if (wanted.length === 0) return [];
  const found = await tx
    .select({ id: products.id })
    .from(products)
    .where(inArray(products.id, wanted));
  const known = new Set(found.map((row) => row.id));
  return wanted.filter((id) => !known.has(id));
}
