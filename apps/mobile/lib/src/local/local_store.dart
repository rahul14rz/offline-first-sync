import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../sync/protocol.dart';

class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.name,
    required this.priceCents,
  });

  final String id;
  final String sku;
  final String name;
  final int priceCents;
}

class LocalOrder {
  const LocalOrder({
    required this.id,
    required this.data,
    required this.serverVersion,
    required this.pendingChanges,
    required this.notice,
  });

  final String id;
  final OrderData data;

  /// The last version the server confirmed. null until the server has the order.
  final int? serverVersion;

  /// Changes in the outbox that the server has not confirmed yet.
  final int pendingChanges;

  /// Set when sync replaced or rejected a local change. Cleared by the next local edit.
  final String? notice;
}

class PendingMutation {
  const PendingMutation(this.seq, this.mutation);
  final int seq;
  final Mutation mutation;
}

/// What happened to an order when the store recorded a push result.
enum ResultOutcome { applied, replacedByServer, removedByServer, rejected, alreadyHandled }

const replacedNotice = 'Changed on another device. Your edit was replaced.';

/// The phone's SQLite database. Every local write to an order also appends to the outbox in
/// the same transaction, so a change is never saved without being queued for sync.
class LocalStore {
  LocalStore._(this._db) {
    _migrate();
  }

  factory LocalStore.open(String path) => LocalStore._(sqlite3.open(path));
  factory LocalStore.inMemory() => LocalStore._(sqlite3.openInMemory());

  final Database _db;
  static const _uuid = Uuid();

  void close() => _db.close();

  void _migrate() {
    _db.execute('PRAGMA foreign_keys = ON');
    if (_db.userVersion >= 1) return;
    _transaction(() {
      _db.execute('''
        CREATE TABLE products (
          id TEXT PRIMARY KEY,
          sku TEXT NOT NULL,
          name TEXT NOT NULL,
          price_cents INTEGER NOT NULL,
          version INTEGER NOT NULL
        );
        CREATE TABLE orders (
          id TEXT PRIMARY KEY,
          customer_name TEXT NOT NULL,
          lines TEXT NOT NULL,
          server_version INTEGER,
          deleted INTEGER NOT NULL DEFAULT 0,
          notice TEXT
        );
        CREATE TABLE outbox (
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          mutation_id TEXT NOT NULL UNIQUE,
          order_id TEXT NOT NULL,
          op TEXT NOT NULL CHECK (op IN ('upsert', 'delete')),
          base_version INTEGER,
          data TEXT
        );
        CREATE INDEX outbox_order_id ON outbox (order_id);
        CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      ''');
      _db.userVersion = 1;
    });
  }

  T _transaction<T>(T Function() work) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = work();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // Reads for the UI.

  List<Product> products() => [
    for (final row in _db.select('SELECT * FROM products ORDER BY name'))
      Product(
        id: row['id'] as String,
        sku: row['sku'] as String,
        name: row['name'] as String,
        priceCents: row['price_cents'] as int,
      ),
  ];

  List<LocalOrder> orders() => [
    for (final row in _db.select('''
      SELECT o.*, (SELECT count(*) FROM outbox WHERE order_id = o.id) AS pending
      FROM orders o WHERE deleted = 0 ORDER BY o.rowid DESC
    '''))
      _toOrder(row),
  ];

  LocalOrder? order(String id) {
    final rows = _db.select(
      '''
      SELECT o.*, (SELECT count(*) FROM outbox WHERE order_id = o.id) AS pending
      FROM orders o WHERE id = ? AND deleted = 0
    ''',
      [id],
    );
    return rows.isEmpty ? null : _toOrder(rows.first);
  }

  LocalOrder _toOrder(Row row) => LocalOrder(
    id: row['id'] as String,
    data: OrderData(
      customerName: row['customer_name'] as String,
      lines: [
        for (final line in jsonDecode(row['lines'] as String) as List<Object?>)
          OrderLine.fromJson(line! as Map<String, Object?>),
      ],
    ),
    serverVersion: row['server_version'] as int?,
    pendingChanges: row['pending'] as int,
    notice: row['notice'] as String?,
  );

  int pendingCount() => _db.select('SELECT count(*) AS n FROM outbox').first['n'] as int;

  // Local writes. Each one saves the order and queues it in one transaction.

  String createOrder(OrderData data) {
    final id = _uuid.v4();
    _transaction(() {
      _db.execute('INSERT INTO orders (id, customer_name, lines) VALUES (?, ?, ?)', [
        id,
        data.customerName,
        _encodeLines(data),
      ]);
      _enqueue(id, MutationOp.upsert, null, data);
    });
    return id;
  }

  void editOrder(String id, OrderData data) {
    _transaction(() {
      _db.execute(
        'UPDATE orders SET customer_name = ?, lines = ?, notice = NULL WHERE id = ? AND deleted = 0',
        [data.customerName, _encodeLines(data), id],
      );
      if (_db.updatedRows == 0) throw StateError('order $id does not exist');
      _enqueue(id, MutationOp.upsert, _nextBaseVersion(id), data);
    });
  }

  void deleteOrder(String id) {
    _transaction(() {
      final base = _nextBaseVersion(id);
      if (base == null) {
        // The server has never had this order and nothing is queued for it.
        _db.execute('DELETE FROM orders WHERE id = ?', [id]);
        return;
      }
      _db.execute('UPDATE orders SET deleted = 1 WHERE id = ?', [id]);
      _enqueue(id, MutationOp.delete, base, null);
    });
  }

  /// The version the server will have once every queued change for this order applies. The
  /// server raises the version by 1 per applied change, so the next change is based on that.
  int? _nextBaseVersion(String orderId) {
    final last = _db.select(
      'SELECT base_version FROM outbox WHERE order_id = ? ORDER BY seq DESC LIMIT 1',
      [orderId],
    );
    if (last.isNotEmpty) return ((last.first['base_version'] as int?) ?? 0) + 1;
    final order = _db.select('SELECT server_version FROM orders WHERE id = ?', [orderId]);
    return order.isEmpty ? null : order.first['server_version'] as int?;
  }

  void _enqueue(String orderId, MutationOp op, int? baseVersion, OrderData? data) {
    _db.execute(
      'INSERT INTO outbox (mutation_id, order_id, op, base_version, data) VALUES (?, ?, ?, ?, ?)',
      [_uuid.v4(), orderId, op.name, baseVersion, data == null ? null : jsonEncode(data.toJson())],
    );
  }

  String _encodeLines(OrderData data) => jsonEncode([for (final line in data.lines) line.toJson()]);

  // Sync side.

  /// The oldest queued changes, up to [limit], with seq at most [maxSeq].
  List<PendingMutation> pendingMutations({required int limit, required int maxSeq}) => [
    for (final row in _db.select('SELECT * FROM outbox WHERE seq <= ? ORDER BY seq LIMIT ?', [
      maxSeq,
      limit,
    ]))
      PendingMutation(
        row['seq'] as int,
        Mutation(
          mutationId: row['mutation_id'] as String,
          orderId: row['order_id'] as String,
          op: MutationOp.values.byName(row['op'] as String),
          baseVersion: row['base_version'] as int?,
          data: row['data'] == null
              ? null
              : OrderData.fromJson(jsonDecode(row['data'] as String) as Map<String, Object?>),
        ),
      ),
  ];

  int lastOutboxSeq() =>
      _db.select('SELECT coalesce(max(seq), 0) AS seq FROM outbox').first['seq'] as int;

  /// Applies the server's answer to one pushed change. Conflicts follow a server-wins policy:
  /// the server's copy replaces the local order and its queued changes are dropped.
  ResultOutcome recordResult(MutationResult result) => _transaction(() {
    final rows = _db.select('SELECT * FROM outbox WHERE mutation_id = ?', [result.mutationId]);
    if (rows.isEmpty) return ResultOutcome.alreadyHandled;
    final entry = rows.first;
    final orderId = entry['order_id'] as String;
    final seq = entry['seq'] as int;

    switch (result) {
      case Applied(:final version):
        _db.execute('DELETE FROM outbox WHERE seq = ?', [seq]);
        _db.execute('UPDATE orders SET server_version = ? WHERE id = ?', [version, orderId]);
        if (entry['op'] == 'delete' && !_hasPending(orderId)) {
          _db.execute('DELETE FROM orders WHERE id = ?', [orderId]);
        }
        return ResultOutcome.applied;

      case Conflict(:final server):
        _db.execute('DELETE FROM outbox WHERE order_id = ?', [orderId]);
        switch (server) {
          case LiveRow(:final version, :final data):
            _upsertOrder(orderId, data, version, notice: replacedNotice);
            return ResultOutcome.replacedByServer;
          case MissingRow() || DeletedRow():
            _db.execute('DELETE FROM orders WHERE id = ?', [orderId]);
            return ResultOutcome.removedByServer;
        }

      case Rejected(:final reason):
        // Later changes to the order were based on this one, so they would fail too.
        _db.execute('DELETE FROM outbox WHERE order_id = ? AND seq >= ?', [orderId, seq]);
        _db.execute('UPDATE orders SET notice = ? WHERE id = ?', ['Not synced: $reason', orderId]);
        return ResultOutcome.rejected;
    }
  });

  bool _hasPending(String orderId) =>
      _db.select('SELECT 1 FROM outbox WHERE order_id = ? LIMIT 1', [orderId]).isNotEmpty;

  void _upsertOrder(String id, OrderData data, int version, {String? notice}) {
    _db.execute(
      '''
      INSERT INTO orders (id, customer_name, lines, server_version, deleted, notice)
      VALUES (?, ?, ?, ?, 0, ?)
      ON CONFLICT (id) DO UPDATE SET customer_name = excluded.customer_name,
        lines = excluded.lines, server_version = excluded.server_version, deleted = 0,
        notice = excluded.notice
      ''',
      [id, data.customerName, _encodeLines(data), version, notice],
    );
  }

  String cursor() {
    final rows = _db.select("SELECT value FROM sync_state WHERE key = 'cursor'");
    return rows.isEmpty ? '0' : rows.first['value'] as String;
  }

  /// Applies one page of pulled changes and saves the new cursor in the same transaction.
  /// A change is skipped when the order has queued local changes (the next push settles those)
  /// or when the local copy is already at that version, such as this phone's own pushes.
  void applyPullPage(PullPage page) => _transaction(() {
    for (final change in page.changes) {
      switch (change) {
        case ProductUpserted(:final id, :final version, :final data):
          _db.execute(
            '''
            INSERT INTO products (id, sku, name, price_cents, version) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET sku = excluded.sku, name = excluded.name,
              price_cents = excluded.price_cents, version = excluded.version
            WHERE excluded.version > products.version
            ''',
            [id, data.sku, data.name, data.priceCents, version],
          );
        case ProductDeleted(:final id):
          _db.execute('DELETE FROM products WHERE id = ?', [id]);
        case OrderUpserted(:final id, :final version, :final data):
          if (!_isNewerThanLocal(id, version)) continue;
          _upsertOrder(id, data, version);
        case OrderDeleted(:final id, :final version):
          if (!_isNewerThanLocal(id, version)) continue;
          _db.execute('DELETE FROM orders WHERE id = ?', [id]);
      }
    }
    _db.execute(
      "INSERT INTO sync_state (key, value) VALUES ('cursor', ?) "
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [page.cursor],
    );
  });

  bool _isNewerThanLocal(String orderId, int version) {
    if (_hasPending(orderId)) return false;
    final rows = _db.select('SELECT server_version FROM orders WHERE id = ?', [orderId]);
    if (rows.isEmpty) return true;
    final local = rows.first['server_version'] as int?;
    return local == null || version > local;
  }
}
