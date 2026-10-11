import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/data/history_export.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/data/probe_client.dart';
import 'package:honestsignal/features/measurement/domain/diagnosis.dart';
import 'package:honestsignal/features/measurement/domain/dropout_alerts.dart';
import 'package:honestsignal/features/measurement/domain/history_insights.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/probe_issue.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

SignalSample _s(
  DateTime at,
  int bars, {
  NetworkKind kind = NetworkKind.wifi,
  double loss = 0,
  double? latency = 40,
  double? jitter = 5,
  double? throughput = 20000,
  ProbeIssue? issue,
}) => SignalSample(
  timestamp: at,
  kind: kind,
  bars: bars,
  composite: bars / 5,
  lossRatio: loss,
  probesSent: 4,
  bytesUsed: 2800,
  latencyMs: latency,
  jitterMs: jitter,
  throughputKbps: throughput,
  issue: issue,
);

/// Scripted probe results, for the diagnosis inputs the engine summarises.
class _IssueClient implements ProbeClient {
  _IssueClient(this.results);
  final List<ProbeResult> results;
  var _i = 0;

  @override
  Future<ProbeResult> probe(Uri url, {required Duration timeout}) async =>
      results[_i++ % results.length];

  @override
  Future<TransferResult> transfer(Uri url, {required Duration timeout}) async =>
      const TransferResult(ok: true, bytes: 120000, elapsedMs: 100);

  @override
  void close() {}
}

void main() {
  final t0 = DateTime(2026, 10, 1, 9);
  DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

  group('drop-out alerts', () {
    late DropoutAlertTracker tracker;
    AlertMessage? feed(int minute, int bars, {NetworkKind? kind}) =>
        tracker.observe(
          _s(at(minute), bars, kind: kind ?? NetworkKind.wifi),
          thresholdBars: 1,
          after: const Duration(minutes: 2),
        );

    setUp(() => tracker = DropoutAlertTracker());

    test('a brief dip under the time limit says nothing', () {
      expect(feed(0, 5), isNull);
      expect(feed(1, 0), isNull);
      expect(feed(2, 5), isNull);
    });

    test('a sustained drop alerts once, then recovery alerts once', () {
      feed(0, 5);
      expect(feed(1, 0), isNull);
      expect(feed(2, 1), isNull);
      final drop = feed(3, 0);
      expect(drop?.kind, AlertKind.drop);
      expect(drop?.body, contains('Wi-Fi'));
      expect(feed(4, 0), isNull, reason: 'one alert per drop-out');
      final back = feed(5, 4);
      expect(back?.kind, AlertKind.recovered);
      expect(back?.body, contains('4 min'));
    });

    test('recovery needs a clear margin above the threshold', () {
      feed(0, 0);
      feed(3, 0);
      expect(feed(4, 2), isNull, reason: '2 bars is only just above 1');
      expect(feed(5, 3)?.kind, AlertKind.recovered);
    });

    test('a quick relapse after recovery is not re-announced', () {
      feed(0, 0);
      feed(3, 0);
      feed(4, 5);
      feed(5, 0);
      expect(feed(8, 0), isNull);
      expect(feed(16, 0)?.kind, AlertKind.drop);
    });

    test('a long gap between readings forgets the episode', () {
      feed(0, 0);
      feed(3, 0);
      expect(feed(60, 5), isNull, reason: 'no idea what happened in between');
    });

    test('being offline is called that', () {
      feed(0, 0, kind: NetworkKind.none);
      expect(feed(3, 0, kind: NetworkKind.none)?.title, 'You are offline');
    });
  });

  group('history insights', () {
    test('contiguous poor readings are one drop-out with a real length', () {
      final samples = [
        _s(at(0), 5),
        _s(at(1), 1),
        _s(at(2), 0),
        _s(at(3), 4),
        _s(at(4), 4),
      ];
      final drops = HistoryInsights.dropouts(
        samples,
        end: at(5),
        maxHold: const Duration(minutes: 2),
      );
      expect(drops, hasLength(1));
      expect(drops.single.start, at(1));
      expect(drops.single.duration, const Duration(minutes: 2));
      expect(drops.single.worstBars, 0);
      expect(drops.single.ongoing, isFalse);
    });

    test('a drop-out still happening at the end of the window is ongoing', () {
      final drops = HistoryInsights.dropouts(
        [_s(at(0), 5), _s(at(1), 0)],
        end: at(2),
        maxHold: const Duration(minutes: 2),
      );
      expect(drops.single.ongoing, isTrue);
    });

    test('a gap with no fresh reading splits episodes', () {
      final drops = HistoryInsights.dropouts(
        [_s(at(0), 0), _s(at(30), 0)],
        end: at(31),
        maxHold: const Duration(minutes: 2),
      );
      expect(drops, hasLength(2));
    });

    test('networks are summarised separately, busiest first', () {
      final samples = [
        for (var i = 0; i < 10; i++) _s(at(i), 5),
        for (var i = 10; i < 14; i++) _s(at(i), 1, kind: NetworkKind.cellular),
      ];
      final networks = HistoryInsights.byNetwork(
        samples,
        end: at(14),
        maxHold: const Duration(minutes: 2),
      );
      expect(networks.map((n) => n.kind), [
        NetworkKind.wifi,
        NetworkKind.cellular,
      ]);
      expect(networks.first.averageBars, 5);
      expect(networks.last.poorFraction, 1);
      expect(networks.last.dropouts, 1);
    });
  });

  group('history retention', () {
    late LocalStore store;
    late HistoryRepository history;

    setUp(() async {
      store = await LocalStore.openInMemory();
      history = HistoryRepository(store.history);
    });

    tearDown(() => store.close());

    test(
      'Pro keeps a month; older rows keep the worst of each bucket',
      () async {
        history.retention = HistoryRepository.proRetention;
        final now = DateTime(2026, 10, 30, 12);
        final old = now.subtract(const Duration(days: 3));
        final bucketStart = DateTime.fromMillisecondsSinceEpoch(
          old.millisecondsSinceEpoch -
              old.millisecondsSinceEpoch %
                  HistoryRepository.compactionBucket.inMilliseconds,
        );
        await store.history.addAll([
          _s(bucketStart, 5).toJson(),
          _s(bucketStart.add(const Duration(minutes: 1)), 0).toJson(),
          _s(bucketStart.add(const Duration(minutes: 2)), 3).toJson(),
          _s(now.subtract(const Duration(days: 40)), 4).toJson(),
          _s(now.subtract(const Duration(hours: 1)), 5).toJson(),
          _s(now.subtract(const Duration(minutes: 59)), 4).toJson(),
        ]);

        await history.prune(now);

        final kept = history.since(now, const Duration(days: 60));
        expect(kept.map((s) => s.bars), [0, 5, 4]);
      },
    );

    test('the free window deletes what Pro kept', () async {
      final now = DateTime(2026, 10, 30, 12);
      await store.history.addAll([
        _s(now.subtract(const Duration(days: 3)), 4).toJson(),
        _s(now.subtract(const Duration(hours: 1)), 5).toJson(),
      ]);
      await history.prune(now);
      expect(history.since(now, const Duration(days: 60)), hasLength(1));
    });
  });

  group('diagnosis', () {
    test('a healthy reading has nothing to say', () {
      expect(Diagnosis.of(_s(at(0), 5)), isNull);
    });

    test('a sign-in page outranks everything but offline', () {
      expect(
        Diagnosis.of(_s(at(0), 4, issue: ProbeIssue.intercepted))?.title,
        'This network wants you to sign in',
      );
    });

    test('total loss is explained per network', () {
      expect(
        Diagnosis.of(_s(at(0), 0, loss: 1, latency: null))?.title,
        "Wi-Fi is connected, the internet isn't",
      );
      expect(
        Diagnosis.of(
          _s(at(0), 0, loss: 1, latency: null, kind: NetworkKind.cellular),
        )?.title,
        'Signal, but no data',
      );
      expect(
        Diagnosis.of(
          _s(at(0), 0, loss: 1, latency: null, issue: ProbeIssue.dns),
        )?.title,
        "Connected, but addresses won't look up",
      );
    });

    test('a stalled transfer, slow replies and jitter each get named', () {
      expect(
        Diagnosis.of(_s(at(0), 2, throughput: 0))?.title,
        "Pings get through, downloads don't",
      );
      expect(
        Diagnosis.of(_s(at(0), 2, latency: 450))?.title,
        'Slow to respond',
      );
      expect(Diagnosis.of(_s(at(0), 3, jitter: 120))?.title, 'Unsteady');
      expect(
        Diagnosis.of(_s(at(0), 3, throughput: 600))?.title,
        'Slow downloads',
      );
    });

    test('the issue survives storage', () {
      final sample = _s(at(0), 0, issue: ProbeIssue.dns);
      expect(SignalSample.fromJson(sample.toJson()).issue, ProbeIssue.dns);
      expect(SignalSample.fromJson(_s(at(0), 5).toJson()).issue, isNull);
    });
  });

  group('probe issues', () {
    test('errors are classified by what the platform says', () {
      expect(ProbeIssue.classify(TimeoutException('x')), ProbeIssue.timeout);
      expect(
        ProbeIssue.classify(Exception("Failed host lookup: 'www.gstatic.com'")),
        ProbeIssue.dns,
      );
      expect(
        ProbeIssue.classify(Exception('nodename nor servname provided')),
        ProbeIssue.dns,
      );
      expect(
        ProbeIssue.classify(Exception('Connection reset by peer')),
        ProbeIssue.unreachable,
      );
    });

    Future<SignalSample> measureWith(List<ProbeResult> results) =>
        MeasurementEngine(
          client: _IssueClient(results),
          config: const MeasurementConfig(interProbeGap: Duration.zero),
        ).measure(kind: NetworkKind.wifi, includeTransfer: false);

    test('one intercepted answer flags a sign-in page', () async {
      final sample = await measureWith(const [
        ProbeResult(ok: true, rttMs: 30, bytes: 700),
        ProbeResult(
          ok: true,
          rttMs: 30,
          bytes: 900,
          issue: ProbeIssue.intercepted,
        ),
      ]);
      expect(sample.issue, ProbeIssue.intercepted);
    });

    test('failure kinds only count when nothing answered', () async {
      expect(
        (await measureWith(const [
          ProbeResult.failed(bytes: 700, issue: ProbeIssue.dns),
        ])).issue,
        ProbeIssue.dns,
      );
      expect(
        (await measureWith(const [
          ProbeResult(ok: true, rttMs: 30, bytes: 700),
          ProbeResult.failed(bytes: 700, issue: ProbeIssue.timeout),
        ])).issue,
        isNull,
      );
    });
  });

  group('export', () {
    final samples = [
      _s(at(0), 5),
      _s(at(1), 0, issue: ProbeIssue.timeout, latency: null),
      _s(at(2), 4),
    ];

    test('CSV has a header and one row per reading', () {
      final lines = const LineSplitter().convert(HistoryExport.csv(samples));
      expect(lines.first, startsWith('timestamp_utc,'));
      expect(lines, hasLength(4));
      expect(lines[2], contains(',0,'));
      expect(lines[2], endsWith(',timeout'));
    });

    test('the PDF report renders, en dashes and all', () async {
      final bytes = await HistoryExport.pdfReport(
        samples: samples,
        window: const Duration(hours: 1),
        now: at(3),
        maxHold: const Duration(minutes: 2),
      );
      expect(ascii.decode(bytes.sublist(0, 4)), '%PDF');
    });
  });

  group('alert settings', () {
    test('round-trip, and only allowed values survive storage', () {
      const settings = AppSettings(
        alertsEnabled: true,
        alertBars: 0,
        alertMinutes: 10,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.alertsEnabled, isTrue);
      expect(restored.alertBars, 0);
      expect(restored.alertMinutes, 10);

      final bogus = AppSettings.fromJson({'alertBars': 4, 'alertMinutes': 7});
      expect(bogus.alertBars, AppSettings.defaultAlertBars);
      expect(bogus.alertMinutes, AppSettings.defaultAlertMinutes);
    });

    test('a free install never alerts', () {
      expect(
        const AppSettings(
          alertsEnabled: true,
        ).clampedForTier(isPro: false).alertsEnabled,
        isFalse,
      );
    });
  });
}
