import '../local/local_store.dart';
import 'sync_api.dart';

/// What one sync run did, for the UI.
class SyncReport {
  int applied = 0;
  int replacedByServer = 0;
  int removedByServer = 0;
  int rejected = 0;
  int pulled = 0;

  bool get hasNotices => replacedByServer + removedByServer + rejected > 0;
}

/// Pushes the outbox, then pulls the change log. Safe to run again after any failure: a push
/// that lost its response is sent again with the same mutation ids, and the server returns the
/// stored results. A pull resumes from the last saved cursor.
class SyncEngine {
  SyncEngine(this._store, this._api, {this.pushBatchSize = 100, this.pullPageSize = 100});

  final LocalStore _store;
  final SyncApi _api;
  final int pushBatchSize;
  final int pullPageSize;

  Future<SyncReport> syncOnce() async {
    final report = SyncReport();
    await _push(report);
    await _pull(report);
    return report;
  }

  Future<void> _push(SyncReport report) async {
    // Changes made while this run is in progress wait for the next run.
    final maxSeq = _store.lastOutboxSeq();
    while (true) {
      final batch = _store.pendingMutations(limit: pushBatchSize, maxSeq: maxSeq);
      if (batch.isEmpty) return;
      final results = await _api.push([for (final pending in batch) pending.mutation]);
      for (final result in results) {
        switch (_store.recordResult(result)) {
          case ResultOutcome.applied:
            report.applied++;
          case ResultOutcome.replacedByServer:
            report.replacedByServer++;
          case ResultOutcome.removedByServer:
            report.removedByServer++;
          case ResultOutcome.rejected:
            report.rejected++;
          case ResultOutcome.alreadyHandled:
            break;
        }
      }
    }
  }

  Future<void> _pull(SyncReport report) async {
    while (true) {
      final page = await _api.pull(cursor: _store.cursor(), limit: pullPageSize);
      _store.applyPullPage(page);
      report.pulled += page.changes.length;
      if (!page.hasMore) return;
    }
  }
}
