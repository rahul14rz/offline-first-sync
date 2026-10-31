# offline-first-sync

A sync engine for a mobile app that has to keep working without a network connection.

## The problem

A sales rep takes orders in shops where the signal drops out. The app must save each order on
the phone right away and send it to the server later. Sending must survive retries,
app restarts, and edits made on the server in the meantime. This repository builds both sides of
that sync: a Fastify, TypeScript, and Postgres API, and a Flutter client with a local SQLite
database and an outbox queue. The domain is offline order taking. The reasons are in
[ADR 0001](docs/decisions/0001-stack.md).

Status: only the API scaffold exists. See the [roadmap](#roadmap).

## Planned architecture

```mermaid
flowchart LR
  subgraph phone["Flutter app (planned)"]
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
the changes it has not seen, using a cursor into a change log in Postgres. Only the API and
Postgres boxes exist today, with a health check and no sync endpoints.

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

To stop the stack and delete the database volume, run `docker compose down --volumes`.

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
- `apps/mobile`: placeholder for the Flutter app.
- `docs/decisions`: architecture decision records.
- `PROGRESS.md`: what is done and what comes next.

## Roadmap

- [x] API scaffold: config validation, `GET /health` with a Postgres check, Drizzle migrations,
      Docker Compose, CI
- [ ] Schema for products, orders, and order lines
- [ ] Change log in Postgres and a pull endpoint that pages through it with a cursor
- [ ] Push endpoint that applies a batch of client changes and ignores a batch it already applied
- [ ] Conflict handling when the device and the server both change the same order
- [ ] Flutter client: SQLite storage, outbox queue, sync with retry and backoff
- [ ] End-to-end test of an offline edit, a reconnect, and a sync

Nothing after the first item exists yet.

## License

MIT. See [LICENSE](LICENSE).
