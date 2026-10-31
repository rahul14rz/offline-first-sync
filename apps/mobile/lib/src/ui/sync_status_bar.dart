import 'package:flutter/material.dart';

import '../sync/sync_scheduler.dart';

class SyncStatusBar extends StatelessWidget {
  const SyncStatusBar({super.key, required this.status, required this.pendingChanges});

  final SyncStatus status;
  final int pendingChanges;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, text, color) = switch (status) {
      SyncRunning() => (Icons.sync, 'Syncing', colors.primary),
      SyncIdle(lastSyncedAt: null) => (Icons.cloud_outlined, 'Not synced yet', colors.outline),
      SyncIdle(:final lastSyncedAt?) => (
        Icons.cloud_done_outlined,
        'Synced at ${TimeOfDay.fromDateTime(lastSyncedAt).format(context)}',
        colors.primary,
      ),
      SyncWaitingToRetry(:final retryIn) => (
        Icons.cloud_off_outlined,
        'Offline. Retrying in ${retryIn.inSeconds + 1} s',
        colors.tertiary,
      ),
      SyncStopped(:final error) => (Icons.error_outline, 'Sync stopped: $error', colors.error),
    };
    final waiting = pendingChanges == 0
        ? ''
        : ' · $pendingChanges ${pendingChanges == 1 ? 'change' : 'changes'} waiting';

    return Container(
      width: double.infinity,
      color: colors.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$text$waiting',
              key: const Key('sync-status'),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
