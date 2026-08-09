import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/data/probe_client.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/scoring.dart';

import 'fakes/fake_probe_client.dart';

/// No inter-probe pause: the gap exists to keep real round trips independent
/// and only slows the suite down.
const _config = MeasurementConfig(interProbeGap: Duration.zero);

MeasurementEngine _engine(FakeProbeClient client, {MeasurementConfig? config}) =>
    MeasurementEngine(client: client, config: config ?? _config);

void main() {
  group('transfer failure', () {
    test('discards the carried-over reading, so the next cheap cycle cannot '
        'show the speed the connection had before it died', () async {
      // The dangerous version of this bug is silent: probes still answer, the
      // transfer has started failing, and a latency-only cycle keeps painting
      // the healthy number measured five minutes ago.
      final client = FakeProbeClient(rtts: const [30, 31, 30, 30]);
      final engine = _engine(client);

      final healthy = await engine.measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );
      expect(healthy.throughputKbps, greaterThan(1000));

      client.transferSucceeds = false;
      final failed = await engine.measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );
      expect(failed.throughputKbps, 0);
      expect(failed.bars, SignalScoring.transferFailureBarCap);

      final cheap = await engine.measure(
        kind: NetworkKind.wifi,
        includeTransfer: false,
      );
      expect(cheap.throughputKbps, isNull);
      expect(cheap.throughputIsStale, isFalse);
    });

    test('caps the score without ever raising a worse one', () async {
      // The cap is a ceiling, not a floor: a link that is both lossy and slow
      // must keep its lower score.
      final client = FakeProbeClient(
        rtts: const [1500, null, 1500, 1500],
        transferSucceeds: false,
      );

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      expect(sample.lossRatio, 0.25);
      expect(sample.bars, lessThan(SignalScoring.transferFailureBarCap));
    });

    test('is scored from the retry when the smaller sample gets through',
        () async {
      // "Slow" and "broken" are different answers and the retry is what tells
      // them apart, so the retry's numbers must actually reach the score.
      final client = FakeProbeClient(
        rtts: const [30, 30, 30, 30],
        transferOutcomes: const [
          TransferResult.failed(),
          TransferResult(ok: true, bytes: 40000, elapsedMs: 100),
        ],
      );

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      // 40 KB in 100 ms, less two 30 ms round trips of setup: 320 kbit over
      // 40 ms is 8000 kbps.
      expect(sample.throughputKbps, closeTo(8000, 1));
      expect(client.transferCalls, 2);
      // A retry that worked is not a transfer failure, so no cap applies.
      expect(sample.bars, greaterThan(SignalScoring.transferFailureBarCap));
    });

    test('still charges the bytes a half-finished download cost', () async {
      // Data that arrived is data the user paid for, whether or not it was
      // enough to time. Not counting it would let a flapping link spend the
      // whole budget invisibly.
      final client = FakeProbeClient(
        rtts: const [30, 30, 30, 30],
        transferOutcomes: const [
          TransferResult(ok: false, bytes: 50000, elapsedMs: 0),
          TransferResult(ok: false, bytes: 10000, elapsedMs: 0),
        ],
      );

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      expect(sample.bytesUsed, 4 * 700 + 50000 + 10000);
      expect(sample.throughputKbps, 0);
      expect(sample.bars, SignalScoring.transferFailureBarCap);
    });

    test('a transfer that answers with nothing counts as a failure', () async {
      final client = FakeProbeClient(
        rtts: const [30, 30, 30, 30],
        transferOutcomes: const [
          TransferResult(ok: true, bytes: 0, elapsedMs: 90),
          TransferResult(ok: true, bytes: 0, elapsedMs: 90),
        ],
      );

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      expect(sample.throughputKbps, 0);
      expect(sample.bars, SignalScoring.transferFailureBarCap);
    });
  });

  group('throughput arithmetic', () {
    test('the setup discount cannot invent infinite speed on a slow link',
        () async {
      // Two 500 ms round trips of setup is more than the whole 200 ms transfer,
      // so the 25% floor is what keeps the division finite.
      final client = FakeProbeClient(
        rtts: const [500, 500, 500, 500],
        transferBytes: 120000,
        transferMs: 200,
      );

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      // 960 kbit over the floored 50 ms.
      expect(sample.throughputKbps, closeTo(19200, 1));
      expect(sample.throughputKbps!.isFinite, isTrue);
    });

    test('is measured from the bytes that arrived, not the bytes asked for',
        () async {
      // Cloudflare serves what it is asked for, but a truncated response must
      // not be scored as if the whole sample landed.
      final client = FakeProbeClient(
        rtts: const [10, 10, 10, 10],
        transferBytes: 60000,
        transferMs: 100,
      );

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      // 480 kbit over (100 - 20) ms.
      expect(sample.throughputKbps, closeTo(6000, 1));
      expect(sample.bytesUsed, 4 * 700 + 60000);
    });
  });

  group('statistics', () {
    test('the median of an even number of probes is the middle pair\'s mean',
        () async {
      final client = FakeProbeClient(rtts: const [10, 20, 30, 100]);

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: false,
      );

      expect(sample.latencyMs, 25);
    });

    test('jitter is the mean absolute deviation, so one outlier does not '
        'triple it', () async {
      // Hand-derived from [10, 20, 30, 100] against a median of 25:
      // (15 + 5 + 5 + 75) / 4 = 25. The standard deviation of the same set is
      // about 34.6, which is the number this model deliberately does not use.
      final client = FakeProbeClient(rtts: const [10, 20, 30, 100]);

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: false,
      );

      expect(sample.jitterMs, 25);
    });

    test('a single surviving probe leaves jitter unmeasured and redistributes '
        'its weight', () async {
      // One round trip cannot describe variation, so reporting a jitter of zero
      // would be an invented number rather than a measured one.
      final client = FakeProbeClient(rtts: const [40, null, null, null]);

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: false,
      );

      expect(sample.jitterMs, isNull);
      expect(sample.probesSent, 4);
      expect(sample.lossRatio, 0.75);
      expect(
        sample.composite,
        closeTo(
          SignalScoring.composite(
            lossRatio: 0.75,
            latencyMs: 40,
            jitterMs: null,
            throughputKbps: null,
          ),
          1e-9,
        ),
      );
      // Three quarters of the requests vanished, so the severe-loss cap applies
      // however fast the survivor was.
      expect(sample.bars, 1);
    });

    test('a first probe that answers keeps the cycle going through later '
        'failures', () async {
      // The early abort is only for "nothing is getting through at all"; two
      // failures after a success is a lossy connection, which is a measurement,
      // not a reason to stop.
      final client = FakeProbeClient(rtts: const [40, null, null, 45]);

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: false,
      );

      expect(client.probeCalls, 4);
      expect(sample.lossRatio, 0.5);
      expect(sample.latencyMs, 42.5);
    });
  });

  group('early abort', () {
    test('reports total loss and charges only the probes it actually sent',
        () async {
      final client = FakeProbeClient(rtts: const [null, null, null, null]);

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
      );

      expect(client.probeCalls, 2);
      expect(sample.bytesUsed, 2 * 700);
      expect(sample.lossRatio, 1.0);
      // `probesSent` counts what was actually attempted, so it agrees with the
      // byte figure beside it on the home screen: two probes sent, two probes'
      // worth of data spent. Total loss is asserted on its own above rather
      // than implied by inflating the count to the planned four.
      expect(sample.probesSent, 2);
    });

    test('does not run on a two-probe configuration until both have failed',
        () async {
      final client = FakeProbeClient(rtts: const [null, null]);

      final sample = await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: true,
        cycle: 0,
      );

      expect(
        client.probeCalls,
        2,
        reason: 'the abort needs two failures, which is the whole budget here',
      );
      expect(sample.lossRatio, 1.0);
    });
  });

  group('configuration', () {
    test('a shorter probe count still yields a median and a loss fraction',
        () async {
      final client = FakeProbeClient(rtts: const [30, null, 90]);

      final sample = await _engine(
        client,
        config: const MeasurementConfig(
          probeCount: 3,
          interProbeGap: Duration.zero,
        ),
      ).measure(kind: NetworkKind.wifi, includeTransfer: false);

      expect(client.probeCalls, 3);
      expect(sample.probesSent, 3);
      expect(sample.latencyMs, 60);
      expect(sample.lossRatio, closeTo(1 / 3, 1e-9));
    });

    test('the transfer sample size follows the configured budget', () async {
      final client = FakeProbeClient(rtts: const [30, 30, 30, 30]);

      await _engine(
        client,
        config: const MeasurementConfig(
          transferBytes: 60000,
          interProbeGap: Duration.zero,
        ),
      ).measure(kind: NetworkKind.wifi, includeTransfer: true);

      expect(client.transferredUrls.single.queryParameters['bytes'], '60000');
    });
  });

  group('privacy posture', () {
    test('probes only ever reach the documented connectivity-check endpoints',
        () async {
      // The privacy label says the app talks to Google's and Cloudflare's
      // public captive-portal endpoints and nothing else. A new host appearing
      // here is a listing change, not just a code change.
      final client = FakeProbeClient(rtts: const [30, 30, 30, 30]);
      final engine = _engine(client);

      for (var cycle = 0; cycle < 6; cycle++) {
        await engine.measure(
          kind: NetworkKind.wifi,
          includeTransfer: true,
          cycle: cycle,
        );
      }

      const allowed = {
        'www.gstatic.com',
        'cp.cloudflare.com',
        'connectivitycheck.gstatic.com',
      };
      for (final url in client.probedUrls) {
        expect(url.scheme, 'https');
        expect(allowed, contains(url.host));
      }
      for (final url in client.transferredUrls) {
        expect(url.scheme, 'https');
        expect(url.host, 'speed.cloudflare.com');
      }
    });

    test('carries no identifier, query or header of its own', () async {
      // Anything the engine appends to the URL would be visible to the endpoint
      // operator and would undermine the "indistinguishable from an ordinary
      // captive-portal check" claim. The cache buster is added by the real
      // client, one layer below.
      final client = FakeProbeClient(rtts: const [30, 30, 30, 30]);

      await _engine(client).measure(
        kind: NetworkKind.wifi,
        includeTransfer: false,
      );

      for (final url in client.probedUrls) {
        expect(url.queryParameters, isEmpty);
        expect(url.userInfo, isEmpty);
      }
    });

    test('an offline cycle contacts nothing and costs nothing', () async {
      final client = FakeProbeClient();

      final sample = await _engine(client).measure(
        kind: NetworkKind.none,
        includeTransfer: true,
        networkDetail: 'Airplane mode',
      );

      expect(client.probedUrls, isEmpty);
      expect(client.transferredUrls, isEmpty);
      expect(sample.bytesUsed, 0);
      expect(sample.networkDetail, 'Airplane mode');
      expect(sample.isOffline, isTrue);
    });
  });

  test('disposing the engine closes the network client', () {
    final client = FakeProbeClient();
    _engine(client).dispose();
    expect(client.closed, isTrue);
  });
}
