# 0002. Sync protocol: change log, cursors, push, and pull

- Status: accepted
- Date: 2026-10-31

## Context

A phone takes orders while offline and syncs later. The sync must satisfy these rules:

1. A change the phone sends must apply once, even if the phone sends it again after a timeout.
2. A phone that pulls with its last cursor must receive every change made since that cursor,
   and none twice.
3. If two phones edit the same order, the server must not silently drop either edit.

## Decision

### Data the phones sync

- `products` belong to the server. Phones only pull them. This branch has no endpoint that
  writes products. `pnpm --filter @offline-first-sync/api db:seed` adds demo products.
- `orders` are created, edited, and deleted on phones. An order keeps its lines in a `jsonb`
  column. The order is the unit that syncs and conflicts. A phone never sends one line on its
  own, so a separate `order_lines` table would only add joins. This replaces the
  `order_lines` table that ADR 0001 planned.

Every synced row has a `version` that starts at 1 and goes up by 1 on each write. Phones create
the `id` (a UUID) so they can create orders offline.

A deleted order stays in the table with `deleted_at` set. Its version still goes up. The
tombstone lets the server detect a stale edit to a deleted order.

### Change log

Every write to a synced row also inserts a row in `changes` in the same transaction. A change
records `seq`, the entity, the row id, the operation, the new version, and a copy of the row
data.

`seq` is a `bigserial`. A sequence alone does not give rule 2. Postgres hands out sequence
values when a transaction inserts, but transactions can commit in a different order. A pull
could see `seq` 11 before the transaction holding `seq` 10 commits. That pull returns cursor 11,
and the phone never receives 10.

To prevent that, every transaction that writes to `changes` first takes one transaction-level
advisory lock: `pg_advisory_xact_lock`. Writers then commit in `seq` order. Any change a reader
can see has a smaller `seq` than every change still in progress.

The cost is that writes to synced tables run one at a time. That is acceptable for one sales
team. Alternatives with more throughput are to filter by transaction ID with
`pg_snapshot_xmin`, or to use logical replication. Both are harder to get right and to test.

The log is never compacted. A new phone replays the whole log. Snapshots for new phones are
future work.

### Pull

`GET /sync/pull?cursor=<cursor>&limit=<n>` returns changes with `seq` greater than the cursor,
in `seq` order, at most `limit` (default 100, maximum 500). The response holds a new cursor and
`hasMore`. The cursor is the last `seq` as a string. Clients must treat it as opaque. Without
a cursor, the pull starts from the beginning of the log.

A phone also receives the changes it pushed itself. It can skip a change whose version is not
newer than its local copy.

### Push

`POST /sync/push` takes up to 100 mutations. Each mutation has a client-generated
`mutationId`. The server processes the batch in one transaction, in order, so a later mutation
can edit an order that an earlier one created.

Each mutation gets one of three results:

- `applied`, with the new version.
- `conflict`, with the server's copy of the row. This happens when `baseVersion` does not match
  the server's version. It also happens when a create uses an existing id, or when the order is
  deleted. The server does not write anything for a conflict.
- `rejected`, with a reason. This happens when a line refers to a product that does not exist.

The server stores every result in `applied_mutations`, keyed by `mutationId`. If a mutation
arrives again, the server returns the stored result and writes nothing. This gives rule 1. The
push transaction holds the change log lock, so two pushes with the same `mutationId` cannot
both apply it.

A request that does not match the schema gets HTTP 400 and the server applies nothing.

### Conflicts

The server detects conflicts and the phone resolves them. The server does not merge. The
conflict result carries the server's copy, so the phone has what it needs to resolve without
another request. The resolution policy, for example "keep the server copy and show the rep
a notice", belongs to the Flutter client and comes in a later change. This gives rule 3: the
server never overwrites an edit made from a version the phone has not seen.

## Consequences

- Writes to synced tables are serialized. Throughput is limited by one transaction at a time.
- `applied_mutations` and `changes` grow without limit. Both need retention rules later.
- There is no authentication. Any client can push and pull everything. This needs to change
  before a real deployment.
