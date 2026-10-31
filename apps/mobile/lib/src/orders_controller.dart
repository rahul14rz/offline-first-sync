import 'package:flutter/foundation.dart';

import 'local/local_store.dart';
import 'sync/protocol.dart';
import 'sync/sync_scheduler.dart';

/// What the screens read and call. Local writes go to SQLite first and then ask for a sync, so
/// the app works the same with or without a connection.
class OrdersController extends ChangeNotifier {
  OrdersController(this._store, this.scheduler) {
    scheduler.status.addListener(_onSyncStatus);
    _reload();
  }

  final LocalStore _store;
  final SyncScheduler scheduler;

  List<LocalOrder> orders = const [];
  List<Product> products = const [];
  int pendingChanges = 0;

  void createOrder(OrderData data) => _write(() => _store.createOrder(data));
  void editOrder(String id, OrderData data) => _write(() => _store.editOrder(id, data));
  void deleteOrder(String id) => _write(() => _store.deleteOrder(id));
  void syncNow() => scheduler.requestSync();

  void _write(void Function() change) {
    change();
    _reload();
    scheduler.requestSync();
  }

  void _onSyncStatus() {
    // A finished sync may have changed orders, products, or the outbox.
    if (scheduler.status.value is! SyncRunning) _reload();
  }

  void _reload() {
    orders = _store.orders();
    products = _store.products();
    pendingChanges = _store.pendingCount();
    notifyListeners();
  }

  @override
  void dispose() {
    scheduler.status.removeListener(_onSyncStatus);
    super.dispose();
  }
}
