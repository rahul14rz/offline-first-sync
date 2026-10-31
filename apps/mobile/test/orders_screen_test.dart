import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_orders/main.dart';
import 'package:offline_orders/src/local/local_store.dart';
import 'package:offline_orders/src/orders_controller.dart';
import 'package:offline_orders/src/sync/protocol.dart';
import 'package:offline_orders/src/sync/sync_api.dart';
import 'package:offline_orders/src/sync/sync_engine.dart';
import 'package:offline_orders/src/sync/sync_scheduler.dart';

void main() {
  testWidgets('a rep can take an order with no connection', (tester) async {
    final store = LocalStore.inMemory()
      ..applyPullPage(
        const PullPage(
          changes: [
            ProductUpserted(
              '00000000-0000-4000-8000-000000000001',
              1,
              ProductData(sku: 'APL-1L', name: 'Apple juice 1L', priceCents: 250),
            ),
          ],
          cursor: '1',
          hasMore: false,
        ),
      );
    Future<SyncReport> offline() async => throw const SyncUnreachable('no signal');
    final scheduler = SyncScheduler(offline)..start();
    addTearDown(store.close);

    await tester.pumpWidget(OrdersApp(controller: OrdersController(store, scheduler)));
    await tester.pump();
    expect(find.textContaining('Offline. Retrying'), findsOneWidget);
    expect(find.text('No orders yet. Tap + to take one.'), findsOneWidget);

    await tester.tap(find.byTooltip('New order'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('customer-name')), 'Corner Shop');
    await tester.tap(find.byTooltip('Add one Apple juice 1L'));
    await tester.tap(find.byTooltip('Add one Apple juice 1L'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Corner Shop'), findsOneWidget);
    expect(find.text('2 items', findRichText: true), findsOneWidget);
    expect(find.byTooltip('Waiting to sync'), findsOneWidget);
    expect(find.textContaining('1 change waiting'), findsOneWidget);
    expect(store.orders().single.data.customerName, 'Corner Shop');

    // Unmount first so the screen stops listening, then cancel the pending retry timer.
    await tester.pumpWidget(const SizedBox());
    scheduler.dispose();
  });
}
