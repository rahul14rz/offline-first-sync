// Runs against a real API. Start it first (see apps/mobile/README.md) and seed the products.
// Set API_URL to use a server other than http://localhost:3000/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:offline_orders/src/local/local_store.dart';
import 'package:offline_orders/src/sync/protocol.dart';
import 'package:offline_orders/src/sync/sync_api.dart';
import 'package:offline_orders/src/sync/sync_engine.dart';

final apiUrl = Uri.parse(Platform.environment['API_URL'] ?? 'http://localhost:3000/');

/// One phone: its own SQLite database and its own connection to the API.
class Phone {
  Phone({http.Client? client, Uri? url, int pullPageSize = 100})
    : store = LocalStore.inMemory(),
      api = SyncApi(baseUrl: url ?? apiUrl, client: client, timeout: const Duration(seconds: 5)) {
    engine = SyncEngine(store, api, pullPageSize: pullPageSize);
  }

  final LocalStore store;
  final SyncApi api;
  late final SyncEngine engine;

  Future<SyncReport> sync() => engine.syncOnce();

  void dispose() {
    store.close();
    api.close();
  }
}

/// Lets the server handle the first push, then drops its response, like a connection that
/// fails while the answer is on the way back.
class DropFirstPushResponse extends http.BaseClient {
  final _inner = http.Client();
  bool dropped = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (!dropped && request.url.path.endsWith('/sync/push')) {
      dropped = true;
      await response.stream.drain<void>();
      throw http.ClientException('connection reset before the response arrived');
    }
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  final phones = <Phone>[];
  Phone phone({http.Client? client, Uri? url, int pullPageSize = 100}) {
    final created = Phone(client: client, url: url, pullPageSize: pullPageSize);
    phones.add(created);
    return created;
  }

  late String productId;

  setUpAll(() async {
    final health = await http
        .get(apiUrl.resolve('health'))
        .catchError((Object error) => throw StateError('API not reachable at $apiUrl: $error'));
    expect(health.statusCode, 200, reason: 'API at $apiUrl is not healthy');
    final seeded = phone();
    await seeded.sync();
    expect(seeded.store.products(), isNotEmpty, reason: 'seed the products first');
    productId = seeded.store.products().first.id;
  });

  tearDown(() {
    for (final p in phones) {
      p.dispose();
    }
    phones.clear();
  });

  OrderData order(String customerName, {int quantity = 1}) => OrderData(
    customerName: customerName,
    lines: [OrderLine(productId: productId, quantity: quantity)],
  );

  test('an order created on one phone reaches another phone', () async {
    final a = phone();
    final b = phone();
    final id = a.store.createOrder(order('Corner Shop', quantity: 3));

    final report = await a.sync();
    await b.sync();

    expect(report.applied, 1);
    expect(a.store.order(id)?.serverVersion, 1);
    expect(b.store.order(id)?.data.lines.single.quantity, 3);
    expect(b.store.order(id)?.serverVersion, 1);
  });

  test('changes made offline go out together and arrive in order', () async {
    final a = phone();
    final b = phone();
    final id = a.store.createOrder(order('Corner Shop'));
    a.store.editOrder(id, order('Corner Shop', quantity: 2));
    a.store.editOrder(id, order('Corner Shop Ltd', quantity: 2));

    final report = await a.sync();
    await b.sync();

    expect(report.applied, 3);
    expect(b.store.order(id)?.data.customerName, 'Corner Shop Ltd');
    expect(b.store.order(id)?.serverVersion, 3);
  });

  test('a push whose response was lost is sent again and applied once', () async {
    final client = DropFirstPushResponse();
    final a = phone(client: client);
    final id = a.store.createOrder(order('Corner Shop'));

    await expectLater(a.sync(), throwsA(isA<SyncUnreachable>()));
    expect(client.dropped, isTrue);
    expect(a.store.order(id)?.pendingChanges, 1, reason: 'the change stays queued');

    final retry = await a.sync();

    expect(retry.applied, 1);
    expect(a.store.order(id)?.serverVersion, 1);
    expect(a.store.pendingCount(), 0);
    expect(await serverChangesFor(a.api, id), 1, reason: 'the server wrote the order once');
  });

  test(
    'when two phones edit the same order, the phone that syncs second gets the server copy',
    () async {
      final a = phone();
      final b = phone();
      final id = a.store.createOrder(order('Corner Shop'));
      await a.sync();
      await b.sync();

      a.store.editOrder(id, order('Edited on A'));
      b.store.editOrder(id, order('Edited on B'));
      await a.sync();
      final report = await b.sync();

      expect(report.replacedByServer, 1);
      final onB = b.store.order(id)!;
      expect(onB.data.customerName, 'Edited on A');
      expect(onB.serverVersion, 2);
      expect(onB.notice, replacedNotice);
      expect(b.store.pendingCount(), 0);
    },
  );

  test('a delete on one phone removes the order on another', () async {
    final a = phone();
    final b = phone();
    final id = a.store.createOrder(order('Corner Shop'));
    await a.sync();
    await b.sync();

    a.store.deleteOrder(id);
    await a.sync();
    await b.sync();

    expect(a.store.order(id), isNull);
    expect(b.store.order(id), isNull);
  });

  test('an order the server rejects stays on the phone with the reason', () async {
    final a = phone();
    final id = a.store.createOrder(
      const OrderData(
        customerName: 'Corner Shop',
        lines: [OrderLine(productId: '00000000-0000-4000-8000-00000000dead', quantity: 1)],
      ),
    );

    final report = await a.sync();

    expect(report.rejected, 1);
    expect(a.store.order(id)?.notice, startsWith('Not synced: unknown product ids'));
    expect(a.store.pendingCount(), 0);
  });

  test('a small page size still pulls the whole log', () async {
    final full = phone();
    final paged = phone(pullPageSize: 2);
    full.store.createOrder(order('Corner Shop'));
    await full.sync();

    await paged.sync();

    expect(paged.store.cursor(), full.store.cursor());
    expect(paged.store.products().length, full.store.products().length);
    expect(paged.store.orders().length, full.store.orders().length);
  });

  test('when the server is unreachable, the change stays queued', () async {
    final offline = phone(url: Uri.parse('http://127.0.0.1:1/'));
    final id = offline.store.createOrder(order('Corner Shop'));

    await expectLater(offline.sync(), throwsA(isA<SyncUnreachable>()));

    expect(offline.store.order(id)?.pendingChanges, 1);
  });
}

/// How many change log entries the server has for this order.
Future<int> serverChangesFor(SyncApi api, String orderId) async {
  var cursor = '0';
  var count = 0;
  while (true) {
    final page = await api.pull(cursor: cursor, limit: 500);
    count += page.changes.where((change) => change.id == orderId).length;
    if (!page.hasMore) return count;
    cursor = page.cursor;
  }
}
