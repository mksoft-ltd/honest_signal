import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';

void main() {
  test(
    'background rows are acknowledged only after Hive persistence',
    () async {
      final store = await LocalStore.openInMemory();
      addTearDown(store.close);
      final sample = SignalSample(
        timestamp: DateTime(2026, 9, 25, 12),
        kind: NetworkKind.wifi,
        bars: 4,
        composite: 0.8,
        lossRatio: 0,
        probesSent: 4,
        bytesUsed: 700,
      );
      final bridge = _Bridge([sample]);
      final repository = HistoryRepository(
        store.history,
        backgroundBridge: bridge,
      );

      expect(await repository.importBackgroundSamples(), 1);

      expect(repository.latest()?.bars, 4);
      expect(store.history.length, 1);
      expect(bridge.acknowledged, 1);
    },
  );

  test('a retried queue is deduplicated before the batch write', () async {
    final store = await LocalStore.openInMemory();
    addTearDown(store.close);
    final at = DateTime(2026, 9, 25, 12);
    final sample = SignalSample(
      timestamp: at,
      kind: NetworkKind.wifi,
      bars: 4,
      composite: 0.8,
      lossRatio: 0,
      probesSent: 4,
      bytesUsed: 700,
    );
    // This bridge intentionally does not remove acknowledged rows, modelling
    // a retry after the native acknowledgement was lost.
    final bridge = _Bridge([sample]);
    final repository = HistoryRepository(
      store.history,
      backgroundBridge: bridge,
    );

    await repository.importBackgroundSamples();
    await repository.importBackgroundSamples();

    expect(store.history.length, 1);
    expect(bridge.acknowledged, 2);
  });

  test('a failed batch write leaves the native rows unacknowledged', () async {
    final store = await LocalStore.openInMemory();
    final sample = SignalSample(
      timestamp: DateTime(2026, 9, 25, 12),
      kind: NetworkKind.wifi,
      bars: 4,
      composite: 0.8,
      lossRatio: 0,
      probesSent: 4,
      bytesUsed: 700,
    );
    final bridge = _Bridge([sample]);
    final repository = HistoryRepository(
      store.history,
      backgroundBridge: bridge,
    );
    await store.close();

    await expectLater(repository.importBackgroundSamples(), throwsA(anything));
    expect(bridge.acknowledged, 0);
  });
}

class _Bridge implements BackgroundHistoryBridge {
  _Bridge(this.pending);

  final List<SignalSample> pending;
  int acknowledged = 0;

  @override
  Future<void> append(SignalSample sample) async => pending.add(sample);

  @override
  Future<List<SignalSample>> drain() async => List.of(pending);

  @override
  Future<void> acknowledge(List<SignalSample> samples) async =>
      acknowledged += samples.length;
}
