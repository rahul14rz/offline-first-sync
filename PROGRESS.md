# Progress

## Done

- pnpm workspace with `apps/api`, `apps/mobile` (placeholder), and `docs/`.
- API: environment config validated at startup, `GET /health` that queries Postgres, JSON logs.
- Drizzle set up with an empty `0000_init` migration that runs when the API starts.
- Docker Compose runs Postgres 18 and the API.
- ESLint, Prettier, and Vitest. Tests run against a real Postgres.
- GitHub Actions: lint, typecheck, and tests with a Postgres service, plus a compose smoke test.
- [ADR 0001](docs/decisions/0001-stack.md): stack and demo domain.

## Next

The sync API:

- Tables for products, orders, and order lines.
- A change log that records every server-side write in order.
- `pull`: return changes after a cursor, in pages.
- `push`: apply a batch of client changes in one transaction. A retried batch must not apply twice.
