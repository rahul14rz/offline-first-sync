# 0003. Mobile client: local storage, outbox, and conflict policy

- Status: accepted
- Date: 2026-10-31

## Context

The Flutter app in `apps/mobile` lets a sales rep take orders with no connection and syncs
them with the API from [ADR 0002](0002-sync-protocol.md). The app must:

1. Save an order on the phone immediately, whatever the network does.
2. Never lose a saved change because a request failed, timed out, or lost its response.
3. Show the rep what is synced, what is waiting, and what another device changed.

## Decision

### SQLite with plain SQL

The app uses the `sqlite3` package, which bundles SQLite and has a synchronous API.
`lib/src/local/local_store.dart` holds all SQL. Drift would add typed queries but needs code
generation. sqflite is asynchronous, which lets other code run in the middle of a multi-step
write. With synchronous calls, a store method that runs a transaction finishes before any other
Dart code runs.

The calls run on the UI isolate. Each one touches a few rows. They have not been timed on a
phone. If the outbox or the catalog grows large, the store can move to a background isolate.

### An append-only outbox

Each create, edit, or delete saves the order and appends an outbox row in one SQLite
transaction (rule 1). The outbox row holds the mutation the server will receive, including its
`mutationId`. A retry sends the same row, so the server returns the stored result (rule 2).

Queued edits are not merged into one. Each entry carries the `baseVersion` the server will have
once the entries before it apply. The server adds 1 to the version for each applied change, so
the next entry's base is the previous entry's base plus 1. Merging entries would be smaller on
the wire, but an entry might already be in flight, and changing it would break the retry rule.

`SyncEngine.syncOnce` pushes before it pulls. It reads the outbox up to the last row that
existed when the run started, so edits made during a run wait for the next one.

### Server wins on conflict

When the server reports a conflict, the phone replaces the local order with the server's copy,
drops the queued entries for that order, and shows a notice on the order and a snackbar. If the
server's copy is deleted, the order disappears from the phone.

This loses the rep's edit. The alternatives are a field-level merge, or keeping both copies and
asking the rep to choose. Both need more UI and rules about which fields can merge. This project assumes conflicts
are rare, because one rep usually owns an order. The notice tells the rep to
check the order again. The policy is in one place, `LocalStore.recordResult`, so a different
policy changes one method.

A rejected change, such as an order with a product the server does not know, keeps the local
data and shows the reason. The rep can edit or delete the order.

### Pulled changes do not overwrite queued work

A pulled change to an order is skipped if the order has queued entries, because the next push
settles that order. It is also skipped if it is not newer than the local copy, which covers the
phone's own pushes coming back. The cursor is saved in the same transaction as each page.

### Retry with backoff, no connectivity plugin

`SyncScheduler` runs a sync after each local write, every 30 seconds, and on the sync button.
After a failure it waits 1, 2, 4, and so on up to 60 seconds, times a random factor between 0.5
and 1. A 4xx other than 429 stops retries, because the same request would fail again.

A connectivity plugin could trigger a sync when the network returns. It reports that an
interface is up, not that the server is reachable, so the app would still need the retry loop.
The retry loop alone is enough at a 60-second maximum delay.

### Plain ChangeNotifier for state

`OrdersController` is a `ChangeNotifier` that reloads from SQLite after each write and each
sync. The app has two screens and one source of truth, so Provider, Riverpod, or Bloc would add
a dependency without removing code.

## Consequences

- A conflict discards the rep's edit to that order. The rep sees a notice, but the edit itself
  is not kept anywhere.
- The snackbar for an order deleted on another device is not stored. If the app closes before
  the rep sees it, there is no other trace.
- The integration tests need a running API with seeded products, and they leave orders in that
  database.
- The app has not been run on an Android device or emulator. CI builds the debug APK. The app
  was run on Linux desktop against a local API.
