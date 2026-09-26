import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/utils/formatters.dart';
import 'package:honestsignal/features/measurement/data/background_host.dart';
import 'package:honestsignal/features/measurement/data/budget_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/domain/indicator_text.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';

import 'fakes/fake_probe_client.dart';

/// The Dart half of the Android foreground service.
///
/// Kotlin owns the timing; everything decided in Dart — whether this cycle
/// spends 120 KB, what the notification says, what the service is told when a
/// cycle deliberately does nothing — is exercised here. The engine actually
/// booting inside the service needs a device and is in the manual checklist.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test/honestsignal-background';
  const channel = MethodChannel(channelName);
  const codec = StandardMethodCodec();

  late _SpyEngine engine;
  late FakeConnectivitySource connectivity;
  late InMemoryBudgetStore budget;
  late BackgroundMeasurementHost host;
  late _HistoryBridge history;
  late List<MethodCall> outgoing;

  const defaultBudget = 25 * 1024 * 1024;

  void build({
    NetworkKind kind = NetworkKind.wifi,
    DateTime Function()? clock,
  }) {
    engine = _SpyEngine();
    connectivity = FakeConnectivitySource(kind);
    budget = InMemoryBudgetStore();
    outgoing = [];
    history = _HistoryBridge();
    host = BackgroundMeasurementHost(
      channel: channel,
      engine: engine,
      connectivity: connectivity,
      budgetStore: budget,
      historyBridge: history,
      clock: clock,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          outgoing.add(call);
          return null;
        });
  }

  tearDown(() {
    connectivity.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  /// Delivers a call *from* the service to the Dart handler `attach()` installed.
  Future<Object?> callIn(String method, [Object? arguments]) async {
    ByteData? reply;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(MethodCall(method, arguments)),
          (response) => reply = response,
        );
    return reply == null ? null : codec.decodeEnvelope(reply!);
  }

  group('cycle decisions', () {
    test(
      'the first cycle spends a transfer sample; the next one does not',
      () async {
        // The 120 KB sample is the expensive part, so in the background it runs
        // on a ten-minute clock of its own while probes keep the icon live.
        build();

        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );
        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );

        expect(engine.calls.map((c) => c.includeTransfer), [true, false]);
        expect(history.samples, hasLength(1));
      },
    );

    test('a spent budget stops the transfer but not the reading', () async {
      build();
      await budget.spend(
        now: DateTime.now(),
        bytes: defaultBudget,
        limitBytes: defaultBudget,
      );

      final sample = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      expect(engine.calls.single.includeTransfer, isFalse);
      expect(sample, isNotNull);
    });

    test('mobile data is left alone when the user opted out, and nothing is '
        'spent', () async {
      // Returning null tells the service to leave the previous icon in place
      // rather than painting a false zero.
      build(kind: NetworkKind.cellular);

      final sample = await host.runCycle(
        measureOnCellular: false,
        budgetLimitBytes: defaultBudget,
      );

      expect(sample, isNull);
      expect(engine.calls, isEmpty);
      final after = await budget.read(
        now: DateTime.now(),
        limitBytes: defaultBudget,
      );
      expect(after.bytesUsed, 0);
    });

    test('an offline cycle never pays for a transfer', () async {
      build(kind: NetworkKind.none);

      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      expect(engine.calls.single.kind, NetworkKind.none);
      expect(engine.calls.single.includeTransfer, isFalse);
    });

    test('the previous reading feeds the next cycle, so the status-bar icon '
        'does not flicker on a boundary', () async {
      build();
      engine.barsFor = (index) => index == 0 ? 4 : 3;

      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      expect(engine.calls.map((c) => c.previousBars), [null, 4, 3]);
    });

    test('the cycle counter advances so probe targets rotate', () async {
      build();

      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      expect(engine.calls.map((c) => c.cycle), [0, 1, 2]);
    });

    test(
      'rapid unchanged readings update the icon without flooding history',
      () async {
        build();

        for (var index = 0; index < 5; index++) {
          expect(
            await host.runCycle(
              measureOnCellular: true,
              budgetLimitBytes: defaultBudget,
            ),
            isNotNull,
          );
        }

        expect(engine.calls, hasLength(5));
        expect(history.samples, hasLength(1));
      },
    );

    test(
      'a changed bar level reaches the icon and history immediately',
      () async {
        build();
        engine.barsFor = (index) => index == 0 ? 4 : 2;

        final first = await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );
        final second = await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );

        expect([first?.bars, second?.bars], [4, 2]);
        expect(history.samples.map((sample) => sample.bars), [4, 2]);
      },
    );

    test(
      'background history stores a steady heartbeat after one minute',
      () async {
        build();
        final base = DateTime(2026, 9, 26, 12);
        engine.timestampFor = (index) =>
            base.add(Duration(seconds: index == 2 ? 60 : index));

        for (var index = 0; index < 3; index++) {
          await host.runCycle(
            measureOnCellular: true,
            budgetLimitBytes: defaultBudget,
          );
        }

        expect(history.samples.map((sample) => sample.timestamp), [
          base,
          base.add(const Duration(seconds: 60)),
        ]);
      },
    );

    test('one failed provider does not falsely publish zero bars', () async {
      build();
      engine.barsFor = (index) => index == 1 ? 0 : 4;
      engine.lossFor = (index) => index == 1 ? 1 : 0;

      final healthy = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      final isolatedFailure = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      final nextProvider = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      expect(healthy?.bars, 4);
      expect(isolatedFailure, isNull);
      expect(nextProvider?.bars, 4);
      expect(engine.calls.map((call) => call.cycle), [0, 1, 2]);
      expect(history.samples.map((sample) => sample.bars), [4]);
    });

    test('two failed providers confirm a dead background link', () async {
      build();
      engine.barsFor = (_) => 0;
      engine.lossFor = (_) => 1;

      final first = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );
      final second = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      expect(first, isNull);
      expect(second?.bars, 0);
      expect(history.samples.map((sample) => sample.bars), [0]);
    });

    test(
      'a failed transfer is retried after thirty seconds, not ten minutes',
      () async {
        var now = DateTime(2026, 9, 26, 12);
        build(clock: () => now);
        engine.throughputFor = (index, includeTransfer) =>
            includeTransfer ? (index == 0 ? 0 : 20000) : null;

        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );
        now = now.add(const Duration(seconds: 29));
        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );
        now = now.add(const Duration(seconds: 1));
        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        );

        expect(engine.calls.map((call) => call.includeTransfer), [
          true,
          false,
          true,
        ]);
      },
    );

    test(
      'a long interval confirms a failure against another target now',
      () async {
        build();
        engine.barsFor = (index) => index == 0 ? 0 : 4;
        engine.lossFor = (index) => index == 0 ? 1 : 0;

        final sample = await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
          intervalSeconds: 3600,
        );

        expect(sample?.bars, 4);
        expect(sample?.bytesUsed, 5600);
        expect(engine.calls.map((call) => call.cycle), [0, 1]);
        expect(history.samples.map((sample) => sample.bars), [4]);
      },
    );

    test('a long interval publishes zero after two failed targets', () async {
      build();
      engine.barsFor = (_) => 0;
      engine.lossFor = (_) => 1;

      final sample = await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
        intervalSeconds: 3600,
      );

      expect(sample?.bars, 0);
      expect(engine.calls.map((call) => call.cycle), [0, 1]);
    });

    test('a transport switch restarts outage confirmation', () async {
      build();
      engine.barsFor = (_) => 0;
      engine.lossFor = (_) => 1;

      expect(
        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        ),
        isNull,
      );
      connectivity.emit(NetworkKind.cellular);
      expect(
        await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        ),
        isNull,
      );
      expect(
        (await host.runCycle(
          measureOnCellular: true,
          budgetLimitBytes: defaultBudget,
        ))?.bars,
        0,
      );
    });

    test('bytes are charged to the counter both isolates share', () async {
      // The UI isolate and this one spend from the same daily budget, through
      // the same platform channel, because Hive is not isolate-safe.
      build();
      engine.bytesUsed = 4200;

      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      final after = await budget.read(
        now: DateTime.now(),
        limitBytes: defaultBudget,
      );
      expect(after.bytesUsed, 4200);
    });

    test('a cycle that spent nothing does not touch the counter', () async {
      build();
      engine.bytesUsed = 0;

      await host.runCycle(
        measureOnCellular: true,
        budgetLimitBytes: defaultBudget,
      );

      final after = await budget.read(
        now: DateTime.now(),
        limitBytes: defaultBudget,
      );
      expect(after.bytesUsed, 0);
    });
  });

  group('service bridge', () {
    test('attaching announces that the isolate is ready', () async {
      // The service waits for this rather than guessing how long plugin
      // registration takes.
      build();

      host.attach();
      await Future<void>.delayed(Duration.zero);

      expect(outgoing.single.method, 'backgroundReady');
    });

    test(
      'runCycle answers with the sample plus the notification wording',
      () async {
        build();
        host.attach();
        engine.barsFor = (_) => 4;

        final result =
            await callIn('runCycle', {
                  'measureOnCellular': true,
                  'budgetLimitBytes': defaultBudget,
                })
                as Map<Object?, Object?>?;

        expect(result, isNotNull);
        expect(result!['bars'], 4);
        expect(result['verdict'], 'Good');
        expect(result['detail'], isA<String>());
        // The icon needs the level and the notification needs the words; both
        // come from Dart so the wording exists in one language only.
        expect(result['ts'], isA<int>());
        expect(result['kind'], NetworkKind.wifi.name);
      },
    );

    test(
      'a cycle that deliberately did nothing answers with nothing',
      () async {
        build(kind: NetworkKind.cellular);
        host.attach();

        final result = await callIn('runCycle', {
          'measureOnCellular': false,
          'budgetLimitBytes': defaultBudget,
        });

        expect(result, isNull);
      },
    );

    test(
      'missing arguments fall back to measuring on the default budget',
      () async {
        // The service is the only caller, but a partial argument map must not
        // crash the isolate that keeps the indicator alive.
        build();
        host.attach();

        final result = await callIn('runCycle');

        expect(result, isNotNull);
        expect(engine.calls, hasLength(1));
      },
    );

    test('an unknown method is ignored rather than throwing', () async {
      build();
      host.attach();

      expect(await callIn('somethingElse'), isNull);
    });
  });

  group('notification wording', () {
    SignalSample sample({
      NetworkKind kind = NetworkKind.wifi,
      double? latency = 42,
      double? throughput = 12000,
      double loss = 0,
    }) => SignalSample(
      timestamp: DateTime(2026, 8, 8, 12),
      kind: kind,
      bars: 4,
      composite: 0.8,
      latencyMs: latency,
      throughputKbps: throughput,
      lossRatio: loss,
      probesSent: 4,
      bytesUsed: 2800,
    );

    test('names the transport, the round trip and the speed', () {
      // Worded by Format.throughput, the single source PRODUCT_SPEC names, so
      // the notification and the in-app meter cannot disagree about the same
      // reading. These two had drifted at and above 10 Mbps.
      expect(IndicatorText.detail(sample()), 'Wi-Fi · 42 ms · 12 Mbps');
    });

    test('words throughput identically to the in-app meter', () {
      for (final kbps in [640.0, 1500.0, 9500.0, 12000.0, 48000.0]) {
        expect(IndicatorText.throughput(kbps), Format.throughput(kbps));
      }
    });

    test('says plainly when nothing is getting through', () {
      expect(
        IndicatorText.detail(sample(loss: 1)),
        'Wi-Fi · no data getting through',
      );
      expect(
        IndicatorText.detail(sample(kind: NetworkKind.none)),
        'Offline · no data getting through',
      );
    });

    test('omits a speed that was never measured, and one that stalled', () {
      expect(IndicatorText.detail(sample(throughput: null)), 'Wi-Fi · 42 ms');
      expect(IndicatorText.detail(sample(throughput: 0)), 'Wi-Fi · 42 ms');
    });

    test('drops to kbps below a megabit', () {
      expect(IndicatorText.throughput(640), '640 kbps');
      expect(IndicatorText.throughput(1500), '1.5 Mbps');
    });
  });
}

class _HistoryBridge implements BackgroundHistoryBridge {
  final List<SignalSample> samples = [];

  @override
  Future<void> append(SignalSample sample) async => samples.add(sample);

  @override
  Future<List<SignalSample>> drain() async => const [];

  @override
  Future<void> acknowledge(List<SignalSample> samples) async {}
}

/// A stand-in engine that records how each cycle was asked for.
///
/// Subclassing the real engine keeps the host's call signature honest: a
/// changed parameter breaks compilation here rather than silently going
/// unmeasured in the background.
class _SpyEngine extends MeasurementEngine {
  _SpyEngine()
    : super(
        client: FakeProbeClient(),
        config: const MeasurementConfig(interProbeGap: Duration.zero),
      );

  final List<
    ({NetworkKind kind, bool includeTransfer, int? previousBars, int cycle})
  >
  calls = [];

  int bytesUsed = 2800;
  int Function(int callIndex) barsFor = (_) => 4;
  double Function(int callIndex) lossFor = (_) => 0;
  double? Function(int callIndex, bool includeTransfer)? throughputFor;
  DateTime Function(int callIndex)? timestampFor;

  @override
  Future<SignalSample> measure({
    required NetworkKind kind,
    required bool includeTransfer,
    String? networkDetail,
    int? previousBars,
    int cycle = 0,
  }) async {
    final index = calls.length;
    calls.add((
      kind: kind,
      includeTransfer: includeTransfer,
      previousBars: previousBars,
      cycle: cycle,
    ));
    final bars = barsFor(index);
    return SignalSample(
      timestamp: timestampFor?.call(index) ?? DateTime.now(),
      kind: kind,
      bars: bars,
      composite: bars / 5,
      latencyMs: 30,
      jitterMs: 4,
      throughputKbps:
          throughputFor?.call(index, includeTransfer) ??
          (includeTransfer && lossFor(index) < 1 ? 20000 : null),
      lossRatio: lossFor(index),
      probesSent: 1,
      bytesUsed: bytesUsed,
    );
  }
}
