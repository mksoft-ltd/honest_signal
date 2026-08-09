import 'dart:async';

import 'package:honestsignal/features/measurement/data/probe_client.dart';
import 'package:honestsignal/features/measurement/data/connectivity_source.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';

/// A scripted network.
///
/// The engine's whole contract is "given these round trips and this transfer,
/// produce this score", so the tests drive it with exact numbers rather than a
/// real socket.
class FakeProbeClient implements ProbeClient {
  FakeProbeClient({
    this.rtts = const [40, 42, 41, 40],
    this.transferBytes = 120000,
    this.transferMs = 120,
    this.transferSucceeds = true,
    this.transferOutcomes,
  });

  /// One entry per probe. A null entry is a timeout.
  List<double?> rtts;
  int transferBytes;
  double transferMs;
  bool transferSucceeds;

  /// One entry per transfer attempt, consumed in order, for the cases where the
  /// two attempts of a cycle have to differ — a failed 120 KB sample followed by
  /// a successful 40 KB retry, or a partial transfer that still cost data. When
  /// null (or exhausted) the flat fields above apply.
  List<TransferResult>? transferOutcomes;

  final List<Uri> probedUrls = [];
  final List<Uri> transferredUrls = [];
  int probeCalls = 0;
  int transferCalls = 0;
  bool closed = false;

  @override
  Future<ProbeResult> probe(Uri url, {required Duration timeout}) async {
    probedUrls.add(url);
    final index = probeCalls++;
    final rtt = index < rtts.length ? rtts[index] : rtts.last;
    if (rtt == null) return const ProbeResult.failed(bytes: 700);
    return ProbeResult(ok: true, rttMs: rtt, bytes: 700);
  }

  @override
  Future<TransferResult> transfer(Uri url, {required Duration timeout}) async {
    transferredUrls.add(url);
    final index = transferCalls++;

    final script = transferOutcomes;
    if (script != null && index < script.length) return script[index];

    if (!transferSucceeds) return const TransferResult.failed();
    return TransferResult(
      ok: true,
      bytes: transferBytes,
      elapsedMs: transferMs,
    );
  }

  @override
  void close() => closed = true;
}

/// A connectivity source the test drives by hand.
///
/// Backed by a broadcast controller rather than a fixed list so a test can hand
/// the controller a transport change part-way through and watch it react.
class FakeConnectivitySource implements ConnectivitySource {
  FakeConnectivitySource([this.kind = NetworkKind.wifi]);

  NetworkKind kind;
  bool disposed = false;

  final _controller = StreamController<NetworkKind>.broadcast();

  @override
  Future<NetworkKind> current() async => kind;

  @override
  Stream<NetworkKind> get changes => _controller.stream;

  /// Publishes a transport change, as the plugin would when the device moves
  /// between Wi-Fi and mobile data.
  void emit(NetworkKind next) {
    kind = next;
    _controller.add(next);
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_controller.close());
  }
}

/// Lets an asynchronous chain that is not awaited anywhere — a connectivity
/// reaction, or a cycle kicked off by `start()` — run to completion.
///
/// The engine's inter-probe gap is a zero-duration delay in tests, which still
/// costs one event-loop turn per probe.
Future<void> drain([int turns = 40]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
