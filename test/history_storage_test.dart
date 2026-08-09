import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';

/// How the rolling sample log behaves against the storage layer itself.
///
/// `history_and_controller_test.dart` covers the dedup and retention rules;
/// this file covers the box: the key limit that crashed the first on-device
/// write, rows that are not what we expect, and a device clock that moves.
void main() {
  late LocalStore store;
  late HistoryRepository history;

  setUp(() async {
    store = await LocalStore.openInMemory();
    history = HistoryRepository(store.history);
  });

  tearDown(() => store.close());

  SignalSample sample(
    DateTime at, {
    int bars = 4,
    NetworkKind kind = NetworkKind.wifi,
  }) =>
      SignalSample(
        timestamp: at,
        kind: kind,
        bars: bars,
        composite: bars / 5,
        latencyMs: 40,
        jitterMs: 5,
        throughputKbps: 20000,
        lossRatio: 0,
        probesSent: 4,
        bytesUsed: 2800,
      );

  group('keys', () {
    test('stay inside the 32-bit limit Hive enforces, however many samples '
        'are written', () async {
      // Keying by millisecondsSinceEpoch is the obvious design and it throws on
      // the very first write — Hive rejects integer keys above 0xFFFFFFFF, and
      // an epoch in milliseconds passed that in 1970. Auto keys are the fix, so
      // the limit is pinned here rather than discovered on a device again.
      final t0 = DateTime(2026, 8, 8, 12);
      for (var i = 0; i < 60; i++) {
        await history.record(
          sample(t0.add(Duration(seconds: i * 31)), bars: i % 6),
        );
      }

      final keys = store.history.keys.toList();
      expect(keys, isNotEmpty);
      for (final key in keys) {
        expect(key, isA<int>());
        expect(key as int, lessThanOrEqualTo(0xFFFFFFFF));
        expect(key, greaterThanOrEqualTo(0));
      }
    });

    test('ascend with insertion, so insertion order is chronological order',
        () async {
      final t0 = DateTime(2026, 8, 8, 12);
      for (var i = 0; i < 6; i++) {
        await history.record(sample(t0.add(Duration(minutes: i)), bars: i % 6));
      }

      final keys = store.history.keys.cast<int>().toList();
      expect(keys, orderedEquals(List.of(keys)..sort()));
    });

    test('a timestamp far in the future is stored in the value, never the key',
        () async {
      // The value carries its own timestamp precisely so the key never has to.
      final far = DateTime(2099, 1, 1);
      await history.record(sample(far));

      expect(store.history.keys.single, isA<int>());
      expect(history.latest()!.timestamp, far);
    });
  });

  group('unexpected rows', () {
    test('a row that is not a sample does not crash the chart', () async {
      // Nothing writes these today, but the box is on disk and outlives any
      // one version of the app.
      final now = DateTime(2026, 8, 8, 12);
      await store.history.add('not a sample');
      await store.history.add({'unrelated': true});
      await history.record(sample(now));

      expect(history.latest()?.bars, 4);
      expect(history.since(now, const Duration(hours: 1)), hasLength(1));
    });

    test('pruning removes rows it cannot date', () async {
      final now = DateTime(2026, 8, 8, 12);
      await store.history.add('not a sample');
      await history.record(sample(now));

      await history.prune(now);

      expect(store.history.length, 1);
    });

    test('latest() reads past a trailing unreadable row', () async {
      final now = DateTime(2026, 8, 8, 12);
      await history.record(sample(now, bars: 3));
      await store.history.add('junk appended later');

      expect(history.latest()?.bars, 3);
    });
  });

  group('retention', () {
    test('keeps a sample sitting exactly on the boundary and drops the one '
        'before it', () async {
      final now = DateTime(2026, 8, 8, 12);
      final onBoundary = now.subtract(history.retention);
      final justOlder = onBoundary.subtract(const Duration(milliseconds: 1));

      await store.history.add(sample(justOlder, bars: 1).toJson());
      await store.history.add(sample(onBoundary, bars: 2).toJson());
      await history.prune(now);

      final kept = history.since(now, const Duration(days: 7));
      expect(kept.map((s) => s.bars), [2]);
    });

    test('writing a new sample prunes the stale ones with it', () async {
      final old = DateTime(2026, 8, 6, 6);
      final now = DateTime(2026, 8, 8, 12);
      await store.history.add(sample(old).toJson());

      await history.record(sample(now, bars: 2));

      expect(store.history.length, 1);
    });

    test('the window is 25 hours, so a "last 24 hours" view is never short',
        () {
      expect(history.retention, const Duration(hours: 25));
    });
  });

  group('a clock that moves', () {
    test('since() returns chronological order even after the clock jumps back',
        () async {
      // A timezone change or an NTP correction would otherwise draw the chart
      // backwards.
      final now = DateTime(2026, 8, 8, 12);
      await history.record(sample(now, bars: 5));
      await history.record(sample(now.subtract(const Duration(minutes: 30)), bars: 2));

      final samples = history.since(now, const Duration(hours: 2));
      expect(samples, hasLength(2));
      expect(samples.first.bars, 2);
      expect(samples.last.bars, 5);
    });

    test('latest() follows insertion, not the timestamp', () async {
      // Documented behaviour: the app reopens on the last reading it took, even
      // if the device clock has since been corrected backwards.
      final now = DateTime(2026, 8, 8, 12);
      await history.record(sample(now, bars: 5));
      await history.record(sample(now.subtract(const Duration(hours: 1)), bars: 2));

      expect(history.latest()?.bars, 2);
    });
  });

  group('spacing', () {
    test('a sample exactly one spacing window later is kept', () async {
      final t0 = DateTime(2026, 8, 8, 12);
      await history.record(sample(t0));
      await history.record(sample(t0.add(HistoryRepository.minimumSpacing)));

      expect(history.since(t0.add(const Duration(hours: 1)), const Duration(hours: 2)),
          hasLength(2));
    });

    test('a sample a millisecond short of it is dropped', () async {
      final t0 = DateTime(2026, 8, 8, 12);
      await history.record(sample(t0));
      await history.record(sample(
        t0.add(HistoryRepository.minimumSpacing - const Duration(milliseconds: 1)),
      ));

      expect(history.since(t0.add(const Duration(hours: 1)), const Duration(hours: 2)),
          hasLength(1));
    });
  });

  test('recording still works after the log is cleared', () async {
    final now = DateTime(2026, 8, 8, 12);
    await history.record(sample(now, bars: 5));
    await history.clear();

    await history.record(sample(now.add(const Duration(minutes: 1)), bars: 3));

    expect(history.latest()?.bars, 3);
    expect(store.history.keys.single, isA<int>());
  });

  test('a sample survives the round trip through storage intact', () async {
    final now = DateTime(2026, 8, 8, 12);
    final original = SignalSample(
      timestamp: now,
      kind: NetworkKind.cellular,
      bars: 3,
      composite: 0.55,
      latencyMs: 120.5,
      jitterMs: 8.25,
      throughputKbps: 4200.75,
      throughputIsStale: true,
      lossRatio: 0.25,
      probesSent: 4,
      bytesUsed: 2800,
      networkDetail: 'Mobile data',
    );

    await history.record(original);
    final restored = history.latest()!;

    expect(restored.timestamp, original.timestamp);
    expect(restored.kind, NetworkKind.cellular);
    expect(restored.bars, 3);
    expect(restored.composite, 0.55);
    expect(restored.latencyMs, 120.5);
    expect(restored.jitterMs, 8.25);
    expect(restored.throughputKbps, 4200.75);
    expect(restored.throughputIsStale, isTrue);
    expect(restored.lossRatio, 0.25);
    expect(restored.networkDetail, 'Mobile data');
  });

  test('an unreadable stored kind falls back rather than throwing', () {
    final restored = SignalSample.fromJson(const {'kind': 'martian', 'ts': 1});
    expect(restored.kind, NetworkKind.other);
  });
}
