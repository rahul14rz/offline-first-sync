# offline-first-sync

A sync engine for a mobile app that has to keep working without a network connection.

## The problem

A sales rep takes orders in shops where the signal drops out. The app must save each order on
the phone right away and send it to the server later. Sending must survive retries,
app restarts, and edits made on the server in the meantime. This repository builds both sides of
that sync: a Fastify, TypeScript, and Postgres API, and a Flutter client with a local SQLite
database and an outbox queue. The domain is offline order taking. The reasons are in
[ADR 0001](docs/decisions/0001-stack.md).

Status: the API and the Flutter app both work. The app has run on Linux desktop. It has not
been run on Android, though CI builds the Android APK. See the [roadmap](#roadmap).

![The app offline with one change waiting, after it synced, and after a conflict](docs/images/mobile-sync.png)

## Architecture

```mermaid
flowchart LR
  subgraph phone["Flutter app"]
    ui[UI] --> sqlite[(SQLite)]
    ui --> outbox[(Outbox queue)]
    outbox --> client[Sync client]
  end
  client -- "push queued changes" --> api[Fastify API]
  client -- "pull changes after a cursor" --> api
  api --> pg[(Postgres: tables and change log)]
```

The phone writes to SQLite and adds each change to the outbox in the same transaction. The sync
client pushes the outbox to the API and retries until the API confirms. The client then pulls
the changes it has not seen, using a cursor into a change log in Postgres.

- [ADR 0002](docs/decisions/0002-sync-protocol.md) explains the protocol: why pushes are safe to
  retry, how the server detects conflicts, and why the change log takes a lock.
- [ADR 0003](docs/decisions/0003-mobile-client.md) explains the app: the outbox, the
  server-wins conflict policy, and retry with backoff.

## Run it

You need Docker with Compose.

```bash
git clone https://github.com/rahul14rz/offline-first-sync.git
```

```bash
cd offline-first-sync
```

```bash
docker compose up --build --detach
```

```bash
curl localhost:3000/health
```

The API answers with:

```json
{ "status": "ok", "database": "ok" }
```

If Postgres is down, the API answers with HTTP 503 and `{"status":"unavailable","database":"unreachable"}`.

To add three demo products, run the seed command in the API container:

```bash
docker compose exec api node dist/seed.js
```

Then pull the change log:

```bash
curl 'localhost:3000/sync/pull?limit=2'
```

The response holds the first two products, a cursor, and `"hasMore":true`. Pass the cursor back
as `?cursor=2` to get the rest.

To run the Flutter app against this stack, see [apps/mobile/README.md](apps/mobile/README.md).

To stop the stack and delete the database volume, run `docker compose down --volumes`.

## Sync API

Both endpoints take and return JSON. `apps/api/src/sync/protocol.ts` has the full schema.

`GET /sync/pull?cursor=<cursor>&limit=<n>` returns the changes after `cursor`, oldest first.
Omit `cursor` to start from the beginning. `limit` defaults to 100, with a maximum of 500.

After the seed, `curl 'localhost:3000/sync/pull?limit=1'` returns the following. The ids differ
on each machine.

```json
{
  "changes": [
    {
      "entity": "product",
      "id": "23297fd2-50a7-4c46-8d24-ae6cb7d02c03",
      "op": "upsert",
      "version": 1,
      "data": { "sku": "APL-1L", "name": "Apple juice 1L", "priceCents": 250 }
    }
  ],
  "cursor": "1",
  "hasMore": true
}
```

`POST /sync/push` takes up to 100 order mutations. The phone generates `mutationId` and the
order `id`. `baseVersion` is the version the phone last saw, or `null` to create the order.

```json
{
  "mutations": [
    {
      "mutationId": "8d1e4b0a-2c3f-4a5b-9c6d-7e8f9a0b1c2d",
      "entity": "order",
      "op": "upsert",
      "id": "3f2c9a52-6a51-4e0c-9a7e-2f9d1c7b8e10",
      "baseVersion": null,
      "data": {
        "customerName": "Corner Shop",
        "lines": [{ "productId": "23297fd2-50a7-4c46-8d24-ae6cb7d02c03", "quantity": 2 }]
      }
    }
  ]
}
```

Each mutation gets a result. `applied` carries the new version. `conflict` carries the server's
copy of the order. `rejected` carries a reason. Sending the same `mutationId` again returns the
first result and changes nothing. A delete has `"op": "delete"`, the `id`, and a `baseVersion`.

## Develop

You need Node 22 or later and Docker. Corepack installs the pnpm version pinned in
`package.json`.

```bash
corepack enable
```

```bash
pnpm install
```

```bash
docker compose up --detach --wait postgres
```

```bash
pnpm lint
```

```bash
pnpm typecheck
```

```bash
pnpm test
```

The tests run against the Postgres container. To use another database, set `DATABASE_URL`.

To run the API on your machine with reload on change:

```bash
DATABASE_URL=postgres://sync:sync@localhost:5432/sync pnpm --filter @offline-first-sync/api dev
```

The API reads these environment variables at startup and exits with a list of errors if any are
invalid:

| Variable       | Required | Default   | Notes                                                 |
| -------------- | -------- | --------- | ----------------------------------------------------- |
| `DATABASE_URL` | yes      |           | `postgres://` or `postgresql://` URL                  |
| `PORT`         | no       | `3000`    |                                                       |
| `HOST`         | no       | `0.0.0.0` |                                                       |
| `LOG_LEVEL`    | no       | `info`    | `fatal`, `error`, `warn`, `info`, `debug`, or `trace` |

Logs are JSON lines from pino.

## Repository layout

- `apps/api`: Fastify API. Migrations are in `apps/api/drizzle` and run when the API starts.
  The sync code is in `apps/api/src/sync`.
- `apps/mobile`: Flutter app with SQLite storage, an outbox, and the sync engine.
- `docs/decisions`: architecture decision records.
- `PROGRESS.md`: what is done and what comes next.

## Roadmap

- [x] API scaffold: config validation, `GET /health` with a Postgres check, Drizzle migrations,
      Docker Compose, CI
- [x] Schema for products and orders
- [x] Change log in Postgres and a pull endpoint that pages through it with a cursor
- [x] Push endpoint that applies a batch of order changes and returns the stored result for a
      retried mutation
- [x] Conflict detection with row versions. The server reports conflicts and does not merge.
- [x] Flutter client: SQLite storage, outbox queue, sync with retry and backoff
- [x] Conflict policy on the phone: the server copy wins and the rep sees a notice
- [x] Tests that run phones against a real API: offline edits, a lost response, a conflict
- [ ] Run and test on an Android device
- [ ] Authentication, and limiting each rep to their own orders
- [ ] Retention for the change log and the stored push results
- [ ] A snapshot for new phones, so they do not replay the whole log

The unchecked items do not exist yet.

## License

MIT. See [LICENSE](LICENSE).
