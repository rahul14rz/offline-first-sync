import 'package:flutter/material.dart';

import '../local/local_store.dart';
import '../orders_controller.dart';
import '../sync/sync_scheduler.dart';
import 'order_editor.dart';
import 'sync_status_bar.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.controller});

  final OrdersController controller;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  OrdersController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.scheduler.status.addListener(_showSyncNotices);
  }

  @override
  void dispose() {
    controller.scheduler.status.removeListener(_showSyncNotices);
    super.dispose();
  }

  void _showSyncNotices() {
    final status = controller.scheduler.status.value;
    if (status is! SyncIdle) return;
    final report = status.lastReport;
    if (report == null || !report.hasNotices) return;
    final changed = report.replacedByServer + report.removedByServer;
    final parts = [
      if (changed > 0)
        '$changed ${changed == 1 ? 'order was' : 'orders were'} changed on another device',
      if (report.rejected > 0) '${report.rejected} rejected',
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(parts.join('. '))));
  }

  Future<void> _openEditor({LocalOrder? order}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OrderEditor(controller: controller, order: order),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.scheduler.status]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          actions: [
            IconButton(
              tooltip: 'Sync now',
              icon: const Icon(Icons.sync),
              onPressed: controller.syncNow,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: SyncStatusBar(
              status: controller.scheduler.status.value,
              pendingChanges: controller.pendingChanges,
            ),
          ),
        ),
        body: controller.orders.isEmpty
            ? const Center(child: Text('No orders yet. Tap + to take one.'))
            : ListView.separated(
                itemCount: controller.orders.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _OrderTile(order: controller.orders[index], onTap: _openEditor),
              ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'New order',
          onPressed: _openEditor,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final LocalOrder order;
  final Future<void> Function({LocalOrder? order}) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = order.data.lines.fold(0, (sum, line) => sum + line.quantity);
    final synced = order.pendingChanges == 0 && order.serverVersion != null;
    final notice = order.notice;

    return ListTile(
      title: Text(order.data.customerName),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$items ${items == 1 ? 'item' : 'items'}'),
            if (notice != null)
              TextSpan(
                text: '\n$notice',
                style: TextStyle(color: colors.error),
              ),
          ],
        ),
      ),
      isThreeLine: notice != null,
      trailing: Tooltip(
        message: synced ? 'Synced' : 'Waiting to sync',
        child: Icon(
          synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
          color: synced ? colors.primary : colors.outline,
        ),
      ),
      onTap: () => onTap(order: order),
    );
  }
}
