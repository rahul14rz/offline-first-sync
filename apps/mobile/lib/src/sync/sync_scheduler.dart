import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'sync_api.dart';
import 'sync_engine.dart';

sealed class SyncStatus {
  const SyncStatus();
}

class SyncIdle extends SyncStatus {
  const SyncIdle({this.lastSyncedAt, this.lastReport});
  final DateTime? lastSyncedAt;
  final SyncReport? lastReport;
}

class SyncRunning extends SyncStatus {
  const SyncRunning();
}

class SyncWaitingToRetry extends SyncStatus {
  const SyncWaitingToRetry({required this.error, required this.retryIn, required this.attempt});
  final Object error;
  final Duration retryIn;
  final int attempt;
}

/// A request the server refused. Retrying the same request will not help.
class SyncStopped extends SyncStatus {
  const SyncStopped(this.error);
  final Object error;
}

/// Delay before retry number [attempt] (1 for the first retry): 2^(attempt-1) seconds, at most
/// [max], scaled by a random factor between 0.5 and 1 so phones that lost signal together do
/// not retry together.
Duration backoffDelay(int attempt, {Duration max = const Duration(minutes: 1), Random? random}) {
  final exponential = Duration(seconds: 1) * pow(2, min(attempt - 1, 30));
  final capped = exponential > max ? max : exponential;
  final jitter = 0.5 + (random ?? Random()).nextDouble() * 0.5;
  return capped * jitter;
}

/// Decides when a sync runs: on request, on a timer, and after failures with backoff. Requests
/// that arrive during a run start one more run when it finishes. The app passes
/// [SyncEngine.syncOnce] as [sync].
class SyncScheduler {
  SyncScheduler(this._sync, {this.interval = const Duration(seconds: 30), Random? random})
    : _random = random ?? Random();

  final Future<SyncReport> Function() _sync;
  final Duration interval;
  final Random _random;

  final status = ValueNotifier<SyncStatus>(const SyncIdle());

  Timer? _timer;
  bool _running = false;
  bool _runAgain = false;
  int _failures = 0;
  bool _disposed = false;

  void start() => requestSync();

  /// Runs a sync now, or right after the one in progress.
  void requestSync() {
    if (_disposed) return;
    if (_running) {
      _runAgain = true;
      return;
    }
    _timer?.cancel();
    unawaited(_run());
  }

  Future<void> _run() async {
    _running = true;
    status.value = const SyncRunning();
    try {
      final report = await _sync();
      _failures = 0;
      _set(SyncIdle(lastSyncedAt: DateTime.now(), lastReport: report));
      _schedule(interval);
    } on SyncHttpError catch (error) {
      error.retryable ? _retryLater(error) : _set(SyncStopped(error));
    } on Exception catch (error) {
      _retryLater(error);
    } finally {
      _running = false;
    }
    if (_runAgain) {
      _runAgain = false;
      requestSync();
    }
  }

  void _retryLater(Exception error) {
    _failures++;
    final delay = backoffDelay(_failures, random: _random);
    _set(SyncWaitingToRetry(error: error, retryIn: delay, attempt: _failures));
    _schedule(delay);
  }

  void _set(SyncStatus value) {
    if (!_disposed) status.value = value;
  }

  void _schedule(Duration delay) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(delay, requestSync);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    status.dispose();
  }
}
