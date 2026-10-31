import 'package:flutter_test/flutter_test.dart';
import 'package:offline_orders/src/local/local_store.dart';
import 'package:offline_orders/src/sync/protocol.dart';

const productId = '00000000-0000-4000-8000-000000000001';

OrderData order(String customerName, {int quantity = 1}) => OrderData(
  customerName: customerName,
  lines: [OrderLine(productId: productId, quantity: quantity)],
);

List<Mutation> queued(LocalStore store) => [
  for (final pending in store.pendingMutations(limit: 100, maxSeq: store.lastOutboxSeq()))
    pending.mutation,
];

void main() {
  late LocalStore store;

  setUp(() => store = LocalStore.inMemory());
  tearDown(() => store.close());

  group('local writes', () {
    test('creating an order saves it and queues a create', () {
      final id = store.createOrder(order('Corner Shop'));

      expect(store.order(id)?.data.customerName, 'Corner Shop');
      expect(store.order(id)?.pendingChanges, 1);
      expect(
        queued(store).single,
        isA<Mutation>()
            .having((m) => m.op, 'op', MutationOp.upsert)
            .having((m) => m.baseVersion, 'baseVersion', null),
      );
    });

    test('edits queued before a sync are based on the versions the server will reach', () {
      final id = store.createOrder(order('Corner Shop'));
      store.editOrder(id, order('Corner Shop', quantity: 2));
      store.deleteOrder(id);

      expect(queued(store).map((m) => (m.op, m.baseVersion)), [
        (MutationOp.upsert, null),
        (MutationOp.upsert, 1),
        (MutationOp.delete, 2),
      ]);
      expect(store.order(id), isNull, reason: 'a deleted order is hidden right away');
    });

    test('an edit after a confirmed sync is based on the confirmed version', () {
      final id = store.createOrder(order('Corner Shop'));
      store.recordResult(Applied(queued(store).single.mutationId, 1));

      store.editOrder(id, order('Corner Shop Ltd'));

      expect(queued(store).single.baseVersion, 1);
      expect(store.order(id)?.serverVersion, 1);
    });
  });

  group('push results', () {
    test('an applied result removes the change from the outbox', () {
      final id = store.createOrder(order('Corner Shop'));

      store.recordResult(Applied(queued(store).single.mutationId, 1));

      expect(store.order(id)?.pendingChanges, 0);
      expect(store.pendingCount(), 0);
    });

    test('a conflict replaces the local order with the server copy and drops queued edits', () {
      final id = store.createOrder(order('Corner Shop'));
      store.recordResult(Applied(queued(store).single.mutationId, 1));
      store.editOrder(id, order('Edited here'));
      store.editOrder(id, order('Edited here again'));

      final outcome = store.recordResult(
        Conflict(queued(store).first.mutationId, LiveRow(2, order('Edited elsewhere'))),
      );

      expect(outcome, ResultOutcome.replacedByServer);
      final local = store.order(id)!;
      expect(local.data.customerName, 'Edited elsewhere');
      expect(local.serverVersion, 2);
      expect(local.notice, replacedNotice);
      expect(store.pendingCount(), 0);
    });

    test('a conflict with an order deleted on the server removes it locally', () {
      final id = store.createOrder(order('Corner Shop'));
      store.recordResult(Applied(queued(store).single.mutationId, 1));
      store.editOrder(id, order('Edited here'));

      store.recordResult(Conflict(queued(store).single.mutationId, const DeletedRow(2)));

      expect(store.order(id), isNull);
    });

    test('a rejected create keeps the local order, explains why, and can be deleted locally', () {
      final id = store.createOrder(order('Corner Shop'));

      store.recordResult(Rejected(queued(store).single.mutationId, 'unknown product ids: x'));

      expect(store.order(id)?.notice, 'Not synced: unknown product ids: x');
      expect(store.pendingCount(), 0);

      store.deleteOrder(id);
      expect(store.order(id), isNull);
      expect(store.pendingCount(), 0, reason: 'the server never had it, so nothing to send');
    });

    test('a result for a change that is no longer queued is ignored', () {
      expect(
        store.recordResult(const Applied('00000000-0000-4000-8000-00000000000f', 1)),
        ResultOutcome.alreadyHandled,
      );
    });
  });

  group('pulled changes', () {
    PullPage page(List<Change> changes, String cursor) =>
        PullPage(changes: changes, cursor: cursor, hasMore: false);

    test('saves products, orders from other phones, and the cursor', () {
      store.applyPullPage(
        page([
          const ProductUpserted(
            productId,
            1,
            ProductData(sku: 'APL-1L', name: 'Apple', priceCents: 250),
          ),
          OrderUpserted('00000000-0000-4000-8000-0000000000aa', 1, order('From phone B')),
        ], '2'),
      );

      expect(store.products().single.name, 'Apple');
      expect(store.orders().single.data.customerName, 'From phone B');
      expect(store.cursor(), '2');
    });

    test('does not overwrite an order that has queued local edits', () {
      final id = store.createOrder(order('Corner Shop'));
      store.recordResult(Applied(queued(store).single.mutationId, 1));
      store.editOrder(id, order('Edited here'));

      store.applyPullPage(page([OrderUpserted(id, 2, order('Edited elsewhere'))], '5'));

      expect(store.order(id)?.data.customerName, 'Edited here');
      expect(store.cursor(), '5');
    });

    test('skips a change the phone already has, such as its own push', () {
      final id = store.createOrder(order('Corner Shop'));
      store.recordResult(Applied(queued(store).single.mutationId, 1));

      store.applyPullPage(page([OrderUpserted(id, 1, order('Stale copy'))], '3'));

      expect(store.order(id)?.data.customerName, 'Corner Shop');
    });

    test('applies a delete made on another phone', () {
      const id = '00000000-0000-4000-8000-0000000000bb';
      store.applyPullPage(page([OrderUpserted(id, 1, order('From phone B'))], '1'));

      store.applyPullPage(page([const OrderDeleted(id, 2)], '2'));

      expect(store.order(id), isNull);
    });
  });
}
