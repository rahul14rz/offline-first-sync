# 0001. Stack and demo domain

- Status: accepted. [ADR 0002](0002-sync-protocol.md) replaces the planned `order_lines` table
  with a `lines` column on `orders`.
- Date: 2026-10-31

## Context

This repository is a portfolio project: an offline-first sync engine. A Flutter app writes to a
local SQLite database while offline and syncs with a backend when it has a connection. This ADR
covers the backend stack chosen for the scaffold and the demo domain that later work builds on.

Constraints:

- One developer. Choose tools with few concepts to learn and complete TypeScript types.
- The interesting code is the sync protocol. The stack must not hide the SQL that the protocol
  depends on, such as transactions, ordering, and unique constraints.
- A reviewer must be able to run everything with Docker and one command.

## Decision

### Demo domain: offline order taking

A sales rep visits shops, often with poor signal, and records orders on a phone. The back office
needs those orders once the phone reconnects.

Planned entities, kept small on purpose:

- `products`: a catalog the server owns. Devices only pull it.
- `orders` and `order_lines`: created and edited on the device, pushed to the server.

The domain is small, but it has real sync cases. An order is created offline and must arrive
exactly once, even if the push is retried. The same order can be edited on the device while the
back office changes its status. A product can change price while a device holds an old copy.

Rejected alternatives: a to-do app has too little to conflict over. A field-inspection app with
photos adds file upload, which is a separate problem.

### Fastify for HTTP

Fastify ships its own TypeScript types, structured logging through pino with no extra setup,
and `app.inject()` for HTTP tests without opening a port. Express needs extra libraries for the
same things. NestJS adds a module and decorator layer that a project this size does not need.

### Postgres for storage

The sync protocol needs transactions, a strictly ordered change log, and unique constraints that
make retried pushes idempotent. Postgres has all three. Postgres 18 is the current major
version.

### Drizzle for schema and migrations

Drizzle schemas are TypeScript, each query builder call maps to one SQL clause, and `.toSQL()`
returns the statement it will send. `drizzle-kit` writes migrations as plain `.sql` files.
Prisma runs queries through its own engine and does not show the SQL in the code. Knex and raw
SQL have no typed schema.

The driver is `pg` (node-postgres), which Drizzle supports directly.

### Vitest for tests

Vitest runs TypeScript ESM without a separate build step and has a Jest-compatible API. Jest
needs extra configuration to run TypeScript as ESM.

## Scaffold choices

These are small decisions made while building the scaffold. Each one took the simplest option.

- **Migrations run when the API starts.** `src/server.ts` runs them before it listens. A separate
  migration job is safer with several API replicas, but the project runs one replica.
- **The app takes its dependencies as arguments.** `buildApp({ pool, logLevel })` receives the
  Postgres pool instead of a Fastify plugin that decorates the instance. Tests can pass a
  different pool without module mocking, and there is no declaration merging to follow.
- **`/health` returns 503 when Postgres fails.** It runs `select 1` on each request. The pool
  gives up connecting after 2 seconds, so a hung database still produces an answer.
- **Tests use a real Postgres.** Tests read `DATABASE_URL` and fall back to the compose database
  at `localhost:5432`. All tests share that database. No test needs its own database yet,
  because the only data a test writes is the migration journal.
- **TypeScript 6.0.** `typescript-eslint` 8 supports TypeScript below 6.1, so the project stays on
  6.0 until it supports TypeScript 7.
- **Node 22** in the Docker image and in CI.
- **No `.env` file.** `compose.yaml` sets the environment for the containers. The variables are
  listed in the README. The GitHub Node `.gitignore` ignores `.env.*`, so an `.env.example`
  would also need a negation rule.
- **CI runs a compose smoke test** in addition to lint, typecheck, and tests. It builds the stack
  from a clean checkout and waits for `GET /health` to return 200.

## Consequences

- The schema, the change log, and the sync endpoints can use Postgres features directly.
- Tests need a running Postgres. Locally that is `docker compose up --detach postgres`. In CI it
  is a service container.
- Running migrations on start must change before the API runs as more than one replica.
