import 'package:flutter/material.dart';

import '../local/local_store.dart';
import '../orders_controller.dart';
import '../sync/protocol.dart';

class OrderEditor extends StatefulWidget {
  const OrderEditor({super.key, required this.controller, this.order});

  final OrdersController controller;

  /// null for a new order.
  final LocalOrder? order;

  @override
  State<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends State<OrderEditor> {
  late final _customer = TextEditingController(text: widget.order?.data.customerName);
  late final Map<String, int> _quantities = {
    for (final line in widget.order?.data.lines ?? const <OrderLine>[])
      line.productId: line.quantity,
  };

  @override
  void dispose() {
    _customer.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _customer.text.trim().isNotEmpty && _quantities.values.any((quantity) => quantity > 0);

  // Reads the quantity when the tap is handled, so taps that arrive before a rebuild all count.
  void _change(String productId, int delta) => setState(() {
    final next = (_quantities[productId] ?? 0) + delta;
    _quantities[productId] = next < 0 ? 0 : next;
  });

  void _save() {
    final data = OrderData(
      customerName: _customer.text.trim(),
      lines: [
        for (final MapEntry(key: productId, value: quantity) in _quantities.entries)
          if (quantity > 0) OrderLine(productId: productId, quantity: quantity),
      ],
    );
    final existing = widget.order;
    existing == null
        ? widget.controller.createOrder(data)
        : widget.controller.editOrder(existing.id, data);
    Navigator.of(context).pop();
  }

  void _delete() {
    widget.controller.deleteOrder(widget.order!.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.controller.products;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.order == null ? 'New order' : 'Edit order'),
        actions: [
          if (widget.order != null)
            IconButton(
              tooltip: 'Delete order',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('customer-name'),
            controller: _customer,
            decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          if (products.isEmpty)
            const Text('No products yet. Sync to download the catalog.')
          else
            for (final product in products)
              _ProductRow(
                product: product,
                quantity: _quantities[product.id] ?? 0,
                onAdd: () => _change(product.id, 1),
                onRemove: () => _change(product.id, -1),
              ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _canSave ? _save : null, child: const Text('Save')),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final Product product;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final price = (product.priceCents / 100).toStringAsFixed(2);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(product.name),
      subtitle: Text('${product.sku} · $price'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove one ${product.name}',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: quantity > 0 ? onRemove : null,
          ),
          SizedBox(width: 24, child: Text('$quantity', textAlign: TextAlign.center)),
          IconButton(
            tooltip: 'Add one ${product.name}',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
