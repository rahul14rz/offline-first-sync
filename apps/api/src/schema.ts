import { bigserial, integer, jsonb, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import type { MutationResult, OrderData } from "./sync/protocol.js";

/** Catalog owned by the server. Phones only pull it. */
export const products = pgTable("products", {
  id: uuid().primaryKey().defaultRandom(),
  sku: text().notNull().unique(),
  name: text().notNull(),
  priceCents: integer().notNull(),
  version: integer().notNull(),
  updatedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

/** Orders created on phones. The id comes from the phone. A delete sets deletedAt. */
export const orders = pgTable("orders", {
  id: uuid().primaryKey(),
  customerName: text().notNull(),
  lines: jsonb().$type<OrderData["lines"]>().notNull(),
  version: integer().notNull(),
  updatedAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
  deletedAt: timestamp({ withTimezone: true }),
});

/** One row per write to a synced table. Pull pages through it by seq. */
export const changes = pgTable("changes", {
  seq: bigserial({ mode: "number" }).primaryKey(),
  entity: text({ enum: ["product", "order"] }).notNull(),
  entityId: uuid().notNull(),
  op: text({ enum: ["upsert", "delete"] }).notNull(),
  version: integer().notNull(),
  /** Row data after the write. Null for a delete. */
  data: jsonb(),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});

/** The result of every pushed mutation, so a retried mutation returns the same result. */
export const appliedMutations = pgTable("applied_mutations", {
  mutationId: uuid().primaryKey(),
  result: jsonb().$type<MutationResult>().notNull(),
  createdAt: timestamp({ withTimezone: true }).notNull().defaultNow(),
});
