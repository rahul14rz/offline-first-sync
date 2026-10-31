# Progress

## Done

- pnpm workspace with `apps/api`, `apps/mobile` (placeholder), and `docs/`.
- API: environment config validated at startup, `GET /health` that queries Postgres, JSON logs.
- Drizzle migrations that run when the API starts.
- Docker Compose runs Postgres 18 and the API.
- ESLint, Prettier, and Vitest. Tests run against a real Postgres.
- GitHub Actions: lint, typecheck, and tests with a Postgres service, plus a compose smoke test
  that seeds products and pulls them.
- Tables for products, orders, the change log, and applied mutations.
- `GET /sync/pull`: changes after a cursor, in pages.
- `POST /sync/push`: a batch of order mutations in one transaction. A retried mutation returns
  its first result. A stale `baseVersion` returns a conflict with the server's copy.
- A test that fails if the change log lock is removed. Without the lock, a pull can skip a
  change that commits late.
- Seed command for demo products.
- [ADR 0001](docs/decisions/0001-stack.md): stack and demo domain.
- [ADR 0002](docs/decisions/0002-sync-protocol.md): sync protocol.

## Next

The Flutter client:

- SQLite tables for products and orders, plus an outbox table.
- Write an order and its outbox entry in one local transaction.
- Push the outbox, retry with backoff, and remove entries once the server returns a result.
- Pull with the stored cursor and apply changes that are newer than the local copy.
- A conflict policy, such as keeping the server copy and telling the rep.

Open questions for the server:

- Retention for `changes` and `applied_mutations`. Both grow without limit.
- Authentication, and limiting a phone to its own orders.
