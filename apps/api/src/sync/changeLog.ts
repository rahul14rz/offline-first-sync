import { asc, gt, sql } from "drizzle-orm";
import type { Db } from "../db.js";
import { changes } from "../schema.js";
import type { Change, Entity, OrderData, ProductData, PullResponse } from "./protocol.js";

export type Tx = Parameters<Parameters<Db["transaction"]>[0]>[0];

export type NewChange =
  | { entity: "product"; entityId: string; op: "upsert"; version: number; data: ProductData }
  | { entity: "order"; entityId: string; op: "upsert"; version: number; data: OrderData }
  | { entity: Entity; entityId: string; op: "delete"; version: number };

export type AppendChange = (change: NewChange) => Promise<void>;

// Arbitrary key for pg_advisory_xact_lock. Only change log writers use it.
const changeLogLockKey = 7_011_001;

/**
 * Runs `work` in a transaction that may write synced rows. Every write to a synced row must
 * go through here and call `append` with the matching change.
 *
 * The transaction first takes an advisory lock, so change log writers commit one at a time and
 * in seq order. Without it, a pull could see seq 11 before seq 10 commits and skip 10.
 * ADR 0002 has the details.
 */
export async function writeSynced<T>(
  db: Db,
  work: (tx: Tx, append: AppendChange) => Promise<T>,
): Promise<T> {
  return db.transaction(async (tx) => {
    await tx.execute(sql`select pg_advisory_xact_lock(${changeLogLockKey})`);
    return work(tx, async (change) => {
      await tx.insert(changes).values({ ...change, data: "data" in change ? change.data : null });
    });
  });
}

/** Returns up to `limit` changes after `cursor`, oldest first. */
export async function readChanges(db: Db, cursor: number, limit: number): Promise<PullResponse> {
  const rows = await db
    .select()
    .from(changes)
    .where(gt(changes.seq, cursor))
    .orderBy(asc(changes.seq))
    .limit(limit + 1);

  const page = rows.slice(0, limit);
  const last = page.at(-1);
  return {
    changes: page.map(toChange),
    cursor: String(last ? last.seq : cursor),
    hasMore: rows.length > limit,
  };
}

function toChange(row: typeof changes.$inferSelect): Change {
  const { entity, entityId: id, op, version } = row;
  if (op === "delete") {
    return { entity, id, op, version };
  }
  // writeSynced stored this data from a NewChange of the same entity.
  return { entity, id, op, version, data: row.data } as Change;
}
