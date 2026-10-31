// Dart side of the wire format in apps/api/src/sync/protocol.ts. ADR 0002 explains the rules.

class OrderLine {
  const OrderLine({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  factory OrderLine.fromJson(Map<String, Object?> json) =>
      OrderLine(productId: json['productId']! as String, quantity: json['quantity']! as int);

  Map<String, Object?> toJson() => {'productId': productId, 'quantity': quantity};

  @override
  bool operator ==(Object other) =>
      other is OrderLine && other.productId == productId && other.quantity == quantity;

  @override
  int get hashCode => Object.hash(productId, quantity);
}

class OrderData {
  const OrderData({required this.customerName, required this.lines});

  final String customerName;
  final List<OrderLine> lines;

  factory OrderData.fromJson(Map<String, Object?> json) => OrderData(
    customerName: json['customerName']! as String,
    lines: [
      for (final line in json['lines']! as List<Object?>)
        OrderLine.fromJson(line! as Map<String, Object?>),
    ],
  );

  Map<String, Object?> toJson() => {
    'customerName': customerName,
    'lines': [for (final line in lines) line.toJson()],
  };
}

class ProductData {
  const ProductData({required this.sku, required this.name, required this.priceCents});

  final String sku;
  final String name;
  final int priceCents;

  factory ProductData.fromJson(Map<String, Object?> json) => ProductData(
    sku: json['sku']! as String,
    name: json['name']! as String,
    priceCents: json['priceCents']! as int,
  );
}

enum MutationOp { upsert, delete }

/// One queued change to an order, as POST /sync/push expects it.
class Mutation {
  const Mutation({
    required this.mutationId,
    required this.orderId,
    required this.op,
    required this.baseVersion,
    this.data,
  }) : assert((op == MutationOp.upsert) == (data != null));

  final String mutationId;
  final String orderId;
  final MutationOp op;

  /// The server version this change was made from. null creates the order.
  final int? baseVersion;

  /// Set for an upsert, null for a delete.
  final OrderData? data;

  Map<String, Object?> toJson() => {
    'mutationId': mutationId,
    'entity': 'order',
    'op': op.name,
    'id': orderId,
    'baseVersion': baseVersion,
    if (data != null) 'data': data!.toJson(),
  };
}

/// The server's copy of an order, sent with a conflict.
sealed class ServerRow {
  const ServerRow();

  factory ServerRow.fromJson(Map<String, Object?> json) {
    if (json['exists'] != true) return const MissingRow();
    final version = json['version']! as int;
    if (json['deleted'] == true) return DeletedRow(version);
    return LiveRow(version, OrderData.fromJson(json['data']! as Map<String, Object?>));
  }
}

class MissingRow extends ServerRow {
  const MissingRow();
}

class DeletedRow extends ServerRow {
  const DeletedRow(this.version);
  final int version;
}

class LiveRow extends ServerRow {
  const LiveRow(this.version, this.data);
  final int version;
  final OrderData data;
}

sealed class MutationResult {
  const MutationResult(this.mutationId);
  final String mutationId;

  factory MutationResult.fromJson(Map<String, Object?> json) {
    final mutationId = json['mutationId']! as String;
    return switch (json['status']) {
      'applied' => Applied(mutationId, json['version']! as int),
      'conflict' => Conflict(
        mutationId,
        ServerRow.fromJson(json['server']! as Map<String, Object?>),
      ),
      'rejected' => Rejected(mutationId, json['reason']! as String),
      final status => throw FormatException('unknown mutation status: $status'),
    };
  }
}

class Applied extends MutationResult {
  const Applied(super.mutationId, this.version);
  final int version;
}

class Conflict extends MutationResult {
  const Conflict(super.mutationId, this.server);
  final ServerRow server;
}

class Rejected extends MutationResult {
  const Rejected(super.mutationId, this.reason);
  final String reason;
}

/// One entry from GET /sync/pull.
sealed class Change {
  const Change(this.id, this.version);
  final String id;
  final int version;

  factory Change.fromJson(Map<String, Object?> json) {
    final id = json['id']! as String;
    final version = json['version']! as int;
    final data = json['data'] as Map<String, Object?>?;
    return switch ((json['entity'], json['op'])) {
      ('product', 'upsert') => ProductUpserted(id, version, ProductData.fromJson(data!)),
      ('order', 'upsert') => OrderUpserted(id, version, OrderData.fromJson(data!)),
      ('product', 'delete') => ProductDeleted(id, version),
      ('order', 'delete') => OrderDeleted(id, version),
      final other => throw FormatException('unknown change: $other'),
    };
  }
}

class ProductUpserted extends Change {
  const ProductUpserted(super.id, super.version, this.data);
  final ProductData data;
}

class ProductDeleted extends Change {
  const ProductDeleted(super.id, super.version);
}

class OrderUpserted extends Change {
  const OrderUpserted(super.id, super.version, this.data);
  final OrderData data;
}

class OrderDeleted extends Change {
  const OrderDeleted(super.id, super.version);
}

class PullPage {
  const PullPage({required this.changes, required this.cursor, required this.hasMore});

  final List<Change> changes;
  final String cursor;
  final bool hasMore;

  factory PullPage.fromJson(Map<String, Object?> json) => PullPage(
    changes: [
      for (final change in json['changes']! as List<Object?>)
        Change.fromJson(change! as Map<String, Object?>),
    ],
    cursor: json['cursor']! as String,
    hasMore: json['hasMore']! as bool,
  );
}
