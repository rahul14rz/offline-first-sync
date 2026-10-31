import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_orders/src/sync/sync_api.dart';
import 'package:offline_orders/src/sync/sync_engine.dart';
import 'package:offline_orders/src/sync/sync_scheduler.dart';

/// A sync step that fails while [failing] is set and counts how often it ran.
class ScriptedSync {
  Exception? failing;
  int runs = 0;

  Future<SyncReport> call() async {
    runs++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (failing != null) throw failing!;
    return SyncReport();
  }
}

/// Returns 1.0, so the jitter factor is exactly 1 and delays are the full backoff.
class MaxRandom implements Random {
  @override
  double nextDouble() => 1.0;
  @override
  int nextInt(int max) => max - 1;
  @override
  bool nextBool() => true;
}

void main() {
  test('backoff doubles from one second up to a one-minute cap', () {
    final delays = [
      for (var attempt = 1; attempt <= 8; attempt++) backoffDelay(attempt, random: MaxRandom()),
    ];

    expect(delays.map((d) => d.inSeconds), [1, 2, 4, 8, 16, 32, 60, 60]);
  });

  test('jitter keeps each delay between half and all of the backoff', () {
    final random = Random(1);
    for (var attempt = 1; attempt <= 10; attempt++) {
      final delay = backoffDelay(attempt, random: random);
      final full = Duration(seconds: min(1 << (attempt - 1), 60));
      expect(
        delay.inMicroseconds,
        inInclusiveRange((full * 0.5).inMicroseconds, full.inMicroseconds),
      );
    }
  });

  test('retries after a failure with growing delays, then returns to the normal interval', () {
    fakeAsync((time) {
      final sync = ScriptedSync()..failing = const SyncUnreachable('no signal');
      final scheduler = SyncScheduler(sync.call, random: MaxRandom())..start();

      time.elapse(const Duration(milliseconds: 20));
      expect(sync.runs, 1);
      expect(
        scheduler.status.value,
        isA<SyncWaitingToRetry>().having((s) => s.attempt, 'attempt', 1),
      );

      time.elapse(const Duration(seconds: 1, milliseconds: 20));
      expect(sync.runs, 2);
      expect(
        scheduler.status.value,
        isA<SyncWaitingToRetry>().having((s) => s.attempt, 'attempt', 2),
      );

      sync.failing = null;
      time.elapse(const Duration(seconds: 2, milliseconds: 20));
      expect(sync.runs, 3);
      expect(scheduler.status.value, isA<SyncIdle>());

      time.elapse(const Duration(seconds: 29));
      expect(sync.runs, 3, reason: 'next run waits for the 30 second interval');
      time.elapse(const Duration(seconds: 1));
      expect(sync.runs, 4);

      scheduler.dispose();
    });
  });

  test('stops retrying when the server refuses the request', () {
    fakeAsync((time) {
      final sync = ScriptedSync()..failing = const SyncHttpError(400, 'invalid_request');
      final scheduler = SyncScheduler(sync.call)..start();

      time.elapse(const Duration(minutes: 5));

      expect(sync.runs, 1);
      expect(scheduler.status.value, isA<SyncStopped>());
      scheduler.dispose();
    });
  });

  test('a request during a run starts one more run after it', () {
    fakeAsync((time) {
      final sync = ScriptedSync();
      final scheduler = SyncScheduler(sync.call)..start();

      scheduler.requestSync();
      scheduler.requestSync();
      time.elapse(const Duration(milliseconds: 50));

      expect(sync.runs, 2);
      scheduler.dispose();
    });
  });
}
