# Progress

## Done

API (`apps/api`):

- Environment config validated at startup, JSON logs, and `GET /health` that queries Postgres.
- Drizzle migrations that run when the API starts.
- `GET /sync/pull`: changes after a cursor, in pages.
- `POST /sync/push`: a batch of order changes in one transaction. A retried change returns its
  first result. A stale `baseVersion` returns a conflict with the server's copy.
- A test that fails if the change log lock is removed.
- A seed command for demo products.

Flutter app (`apps/mobile`):

- SQLite storage with an outbox. Each local write and its outbox entry share one transaction.
- A sync engine that pushes the outbox, then pulls the change log.
- Server-wins conflict handling with a notice on the order.
- Retry with exponential backoff and jitter.
- Orders list, order editor, and a sync status bar.
- Tests: the local store, the scheduler with fake time, a widget test, and phones syncing
  against a real API.
- Run on Linux desktop against a local API: offline order, automatic retry, and a conflict.

Repository:

- Docker Compose for Postgres and the API.
- CI: lint, typecheck, and API tests. A compose smoke test. Flutter format, analyze, and tests
  against a running API. A debug Android APK build.
- ADRs [0001](docs/decisions/0001-stack.md), [0002](docs/decisions/0002-sync-protocol.md), and
  [0003](docs/decisions/0003-mobile-client.md).

## Next

- Run the app on an Android emulator and a device.
- Authentication, and limiting each rep to their own orders.
- Retention for `changes` and `applied_mutations`. Both grow without limit.
- A snapshot for new phones, so they do not replay the whole log.
- Keep a copy of an edit that a conflict replaced, so the rep can recover it.
