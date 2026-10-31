# Mobile app

A Flutter app for taking orders offline. It stores orders in SQLite, queues every change in an
outbox, and syncs with the API in `apps/api`. [ADR 0003](../../docs/decisions/0003-mobile-client.md)
explains the design.

![The app offline with one change waiting, after it synced, and after a conflict](../../docs/images/mobile-sync.png)

These screenshots come from the Linux desktop build at phone size. From left to right: an
order taken with the API stopped, the same order after the API came back and the app retried on
its own, and the result of a conflict with an edit made on another device.

## Run it

You need Flutter 3.47 or later and the API running on port 3000 with seeded products. The
[root README](../../README.md#run-it) shows how to start it.

On Linux desktop, build the app and start it:

```bash
flutter build linux --debug
```

```bash
build/linux/x64/debug/bundle/offline_orders
```

The app uses `http://localhost:3000/`. To use another server, pass its URL at build time:

```bash
flutter build linux --debug --dart-define=API_URL=http://127.0.0.1:3000/
```

On Android, the app uses `http://10.0.2.2:3000/`, the emulator's address for the host machine.
The app has not been run on Android yet. CI builds the debug APK on each pull request, and
`flutter run` with an emulator selected is the usual way to start it.

## Test it

The tests in `test/sync_engine_test.dart` talk to a real API. Start it and seed the products
first. Set `API_URL` if it is not on `http://localhost:3000/`. Each run adds orders to that
database.

```bash
flutter test
```

Other checks:

```bash
dart format --output=none --set-exit-if-changed lib test
```

```bash
flutter analyze
```

## Code layout

| File                                | What it does                                                    |
| ----------------------------------- | --------------------------------------------------------------- |
| `lib/src/local/local_store.dart`    | SQLite schema, local writes with the outbox, push results, pull |
| `lib/src/sync/protocol.dart`        | Request and response types, matching `apps/api`                 |
| `lib/src/sync/sync_api.dart`        | HTTP client for `/sync/push` and `/sync/pull`                   |
| `lib/src/sync/sync_engine.dart`     | One sync run: push the outbox, then pull until done             |
| `lib/src/sync/sync_scheduler.dart`  | When to sync, and retry with backoff                            |
| `lib/src/orders_controller.dart`    | State for the screens                                           |
| `lib/src/ui/`                       | Orders list, order editor, sync status bar                      |
