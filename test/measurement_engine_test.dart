import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/scoring.dart';

import 'fakes/fake_probe_client.dart';

/// No inter-probe pause: the gap exists to keep real round trips independent
/// and only slows the suite down.
const _config = MeasurementConfig(interProbeGap: Duration.zero);

MeasurementEngine _engine(FakeProbeClient client) =>
    MeasurementEngine(client: client, config: _config);

void main() {
  test('a fast, steady connection with a good transfer scores five bars', () async {
    final client = FakeProbeClient(
      rtts: const [22, 24, 23, 22],
      transferBytes: 120000,
      transferMs: 120,
    );

    final sample = await _engine(client).measure(
      kind: NetworkKind.wifi,
      includeTransfer: true,
    );

    expect(sample.bars, 5);
    expect(sample.lossRatio, 0);
    expect(sample.latencyMs, 22.5);
    expect(sample.throughputKbps, greaterThan(10000));
    expect(sample.probesSent, 4);
  });

  test('probes that answer while a transfer fails cap the score — the '
      '"full bars, no data" case the app exists to catch', () async {
    final client = FakeProbeClient(
      rtts: const [18, 19, 18, 20],
      transferSucceeds: false,
    );

    final sample = await _engine(client).measure(
      kind: NetworkKind.wifi,
      includeTransfer: true,
      // Even coming down from a perfect previous reading, the cap applies at
      // once rather than being softened by hysteresis.
      previousBars: 5,
    );

    expect(sample.bars, SignalScoring.transferFailureBarCap);
    expect(sample.throughputKbps, 0);
    // Latency looked excellent throughout — which is exactly why the transfer
    // sample has to be the thing that decides.
    expect(sample.latencyMs, lessThan(25));
    expect(sample.lossRatio, 0);
  });

  test('a failed transfer is retried once at a smaller size before giving up',
      () async {
    final client = FakeProbeClient(
      rtts: const [30, 31, 30, 30],
      transferSucceeds: false,
    );

    await _engine(client).measure(kind: NetworkKind.wifi, includeTransfer: true);

    expect(client.transferCalls, 2);
    expect(
      client.transferredUrls.last.queryParameters['bytes'],
      (_config.transferBytes ~/ 3).toString(),
    );
  });

  test('every probe timing out gives zero bars and total loss', () async {
    final client = FakeProbeClient(rtts: const [null, null, null, null]);

    final sample = await _engine(client).measure(
      kind: NetworkKind.wifi,
      includeTransfer: true,
      previousBars: 5,
    );

    expect(sample.bars, 0);
    expect(sample.lossRatio, 1.0);
    expect(sample.isOffline, isTrue);
  });

  test('a dead connection aborts early instead of burning four timeouts',
      () async {
    final client = FakeProbeClient(rtts: const [null, null, null, null]);

    await _engine(client).measure(kind: NetworkKind.wifi, includeTransfer: true);

    // Two failures with nothing to show is already the answer; the remaining
    // probes would cost the user four more seconds of waiting.
    expect(client.probeCalls, 2);
    // And no data is spent on a transfer that cannot possibly succeed.
    expect(client.transferCalls, 0);
  });

  test('partial loss is reported without triggering the severe-loss cap',
      () async {
    final client = FakeProbeClient(rtts: const [40, null, 42, 41]);

    final sample = await _engine(client).measure(
      kind: NetworkKind.wifi,
      includeTransfer: false,
    );

    expect(sample.probesSent, 4);
    expect(sample.lossRatio, 0.25);
    expect(sample.bars, greaterThan(1));
  });

  test('being offline costs nothing and reports nothing', () async {
    final client = FakeProbeClient();

    final sample = await _engine(client).measure(
      kind: NetworkKind.none,
      includeTransfer: true,
    );

    expect(sample.bars, 0);
    expect(sample.bytesUsed, 0);
    expect(sample.probesSent, 0);
    expect(client.probeCalls, 0);
    expect(client.transferCalls, 0);
  });

  test('bytes are counted for the daily budget', () async {
    final client = FakeProbeClient(transferBytes: 120000);

    final sample = await _engine(client).measure(
      kind: NetworkKind.wifi,
      includeTransfer: true,
    );

    // Four probes of overhead plus the transfer payload.
    expect(sample.bytesUsed, 4 * 700 + 120000);
  });

  test('a cycle without a transfer reuses the last reading and marks it stale',
      () async {
    final client = FakeProbeClient(rtts: const [30, 31, 30, 30]);
    final engine = _engine(client);

    final first = await engine.measure(kind: NetworkKind.wifi, includeTransfer: true);
    expect(first.throughputIsStale, isFalse);

    final second = await engine.measure(kind: NetworkKind.wifi, includeTransfer: false);
    expect(second.throughputKbps, first.throughputKbps);
    expect(second.throughputIsStale, isTrue);
    expect(client.transferCalls, 1);
  });

  test('a stale throughput reading expires rather than being reused forever',
      () async {
    var now = DateTime(2026, 8, 7, 12);
    final client = FakeProbeClient(rtts: const [30, 31, 30, 30]);
    final engine = MeasurementEngine(
      client: client,
      config: _config,
      clock: () => now,
    );

    await engine.measure(kind: NetworkKind.wifi, includeTransfer: true);
    now = now.add(_config.throughputFreshness + const Duration(minutes: 1));

    final later = await engine.measure(kind: NetworkKind.wifi, includeTransfer: false);
    expect(later.throughputKbps, isNull);
  });

  test('probe targets rotate between cycles so one host is not hammered',
      () async {
    final client = FakeProbeClient(rtts: const [30, 31, 30, 30]);
    final engine = _engine(client);

    await engine.measure(kind: NetworkKind.wifi, includeTransfer: false, cycle: 0);
    final firstHost = client.probedUrls.first.host;

    client.probedUrls.clear();
    await engine.measure(kind: NetworkKind.wifi, includeTransfer: false, cycle: 1);

    expect(client.probedUrls.first.host, isNot(firstHost));
  });

  test('a cached probe response cannot fake a fast connection', () async {
    final client = FakeProbeClient(rtts: const [30, 31, 30, 30]);

    await _engine(client).measure(kind: NetworkKind.wifi, includeTransfer: false);

    // The engine hands the client plain URLs; HttpProbeClient adds the cache
    // buster. What matters here is that the engine never reuses a result.
    expect(client.probeCalls, 4);
  });
}
