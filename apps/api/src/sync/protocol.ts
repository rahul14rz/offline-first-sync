// Wire format for POST /sync/push and GET /sync/pull. ADR 0002 explains the rules.
import { z } from "zod";

const maxMutationsPerPush = 100;
export const defaultPullLimit = 100;
const maxPullLimit = 500;

const orderLine = z.object({
  productId: z.uuid(),
  quantity: z.int().min(1),
});

export const orderData = z.object({
  customerName: z.string().trim().min(1).max(200),
  lines: z.array(orderLine).max(200),
});
export type OrderData = z.infer<typeof orderData>;

const upsertOrder = z.object({
  mutationId: z.uuid(),
  entity: z.literal("order"),
  op: z.literal("upsert"),
  id: z.uuid(),
  /** Version the client last saw. null means the client is creating the order. */
  baseVersion: z.int().min(1).nullable(),
  data: orderData,
});

const deleteOrder = z.object({
  mutationId: z.uuid(),
  entity: z.literal("order"),
  op: z.literal("delete"),
  id: z.uuid(),
  baseVersion: z.int().min(1),
});

export const mutation = z.discriminatedUnion("op", [upsertOrder, deleteOrder]);
export type Mutation = z.infer<typeof mutation>;

export const pushRequest = z.object({
  mutations: z.array(mutation).min(1).max(maxMutationsPerPush),
});

/** The server's copy of a row, sent back when a mutation conflicts with it. */
export type ServerRow =
  | { exists: false }
  | { exists: true; version: number; deleted: true }
  | { exists: true; version: number; deleted: false; data: OrderData };

export type MutationResult =
  | { mutationId: string; status: "applied"; version: number }
  | { mutationId: string; status: "conflict"; server: ServerRow }
  | { mutationId: string; status: "rejected"; reason: string };

export type PushResponse = { results: MutationResult[] };

export const pullQuery = z.object({
  /** Opaque to clients. Omit it to start from the beginning of the log. */
  cursor: z
    .string()
    .regex(/^(0|[1-9][0-9]{0,15})$/, "must be a cursor returned by a previous pull")
    .default("0"),
  limit: z.coerce.number().int().min(1).max(maxPullLimit).default(defaultPullLimit),
});

export type ProductData = { sku: string; name: string; priceCents: number };

export type Entity = "product" | "order";

export type Change =
  | { entity: "product"; id: string; op: "upsert"; version: number; data: ProductData }
  | { entity: "order"; id: string; op: "upsert"; version: number; data: OrderData }
  | { entity: Entity; id: string; op: "delete"; version: number };

export type PullResponse = {
  changes: Change[];
  /** Pass this to the next pull. Equal to the request cursor when there are no new changes. */
  cursor: string;
  hasMore: boolean;
};
