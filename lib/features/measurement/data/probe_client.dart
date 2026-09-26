import 'dart:async';

import 'package:http/http.dart' as http;

/// Outcome of a single latency probe.
class ProbeResult {
  const ProbeResult({
    required this.ok,
    required this.rttMs,
    required this.bytes,
  });

  const ProbeResult.failed({this.bytes = 0}) : ok = false, rttMs = null;

  final bool ok;
  final double? rttMs;

  /// Approximate bytes on the wire, charged to the daily data budget.
  final int bytes;
}

/// Outcome of a transfer (throughput) sample.
class TransferResult {
  const TransferResult({
    required this.ok,
    required this.bytes,
    required this.elapsedMs,
  });

  const TransferResult.failed({this.bytes = 0}) : ok = false, elapsedMs = 0;

  final bool ok;
  final int bytes;
  final double elapsedMs;
}

/// The network seam of the measurement engine.
///
/// The engine depends only on this interface, so tests drive it with a scripted
/// fake and never touch a socket.
abstract class ProbeClient {
  /// Fetches [url] expecting a tiny (ideally empty) response, timing the full
  /// round trip.
  Future<ProbeResult> probe(Uri url, {required Duration timeout});

  /// Downloads [url] fully, reporting bytes received and wall-clock time.
  Future<TransferResult> transfer(Uri url, {required Duration timeout});

  void close();
}

/// Real implementation over `package:http`.
///
/// Requests carry no identifiers, cookies or app-specific headers — they are
/// indistinguishable from an ordinary captive-portal check, which is what keeps
/// the app's privacy label at "no data collected".
class HttpProbeClient implements ProbeClient {
  HttpProbeClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Request line + headers we send, plus the response status line + headers.
  /// Measured empirically against the 204 endpoints; used for the data budget
  /// counter, which is an estimate and is labelled as one in the UI.
  static const int probeOverheadBytes = 700;

  /// A transfer URL requests this exact amount. Stop a malformed or hostile
  /// responder from keeping a metered connection busy beyond that request.
  /// The final received chunk is still charged if it crosses the boundary — it
  /// has already reached the device and must never disappear from the budget.
  static const int defaultMaxTransferResponseBytes = 120000;

  /// A latency endpoint should return an empty body. Cap unexpected responses
  /// so a captive portal cannot spend the user's data budget on a probe.
  static const int maxProbeResponseBytes = 8192;

  @override
  Future<ProbeResult> probe(Uri url, {required Duration timeout}) async {
    final stopwatch = Stopwatch()..start();
    final abort = Completer<void>();
    var received = 0;
    try {
      final bodyAndStatus =
          await (() async {
            final request =
                http.AbortableRequest(
                    'GET',
                    _cacheBust(url),
                    abortTrigger: abort.future,
                  )
                  ..headers['cache-control'] = 'no-cache, no-store'
                  ..headers['pragma'] = 'no-cache';
            final streamed = await _client.send(request);
            await for (final chunk in streamed.stream) {
              received += chunk.length;
              if (received > maxProbeResponseBytes) {
                abort.complete();
                throw StateError('Probe response exceeded byte cap');
              }
            }
            return streamed.statusCode;
          })().timeout(
            timeout,
            onTimeout: () async {
              abort.complete();
              await Future<void>.delayed(Duration.zero);
              throw TimeoutException('Probe exceeded its wall-clock deadline');
            },
          );
      stopwatch.stop();

      // Any HTTP response at all proves the path works end to end. A captive
      // portal's 302 to a login page is still a reachable network — the
      // throughput and latency numbers stay meaningful.
      if (bodyAndStatus >= 500) {
        return ProbeResult.failed(
          bytes: probeOverheadBytes + received,
        );
      }
      return ProbeResult(
        ok: true,
        rttMs: stopwatch.elapsedMicroseconds / 1000.0,
        bytes: probeOverheadBytes + received,
      );
    } on Object {
      // Timeouts, DNS failures, TLS failures and socket errors are all "the
      // connection did not deliver", which is exactly what we want to count.
      return ProbeResult.failed(bytes: probeOverheadBytes + received);
    }
  }

  @override
  Future<TransferResult> transfer(Uri url, {required Duration timeout}) async {
    final stopwatch = Stopwatch()..start();
    var received = 0;
    final requestedBytes = int.tryParse(url.queryParameters['bytes'] ?? '');
    final maxBytes = (requestedBytes != null && requestedBytes > 0)
        ? requestedBytes
        : defaultMaxTransferResponseBytes;
    final abort = Completer<void>();
    try {
      final statusCode =
          await (() async {
            final request = http.AbortableRequest(
              'GET',
              _cacheBust(url),
              abortTrigger: abort.future,
            )..headers['cache-control'] = 'no-cache, no-store';
            final streamed = await _client.send(request);
            await for (final chunk in streamed.stream) {
              received += chunk.length;
              if (received > maxBytes) {
                throw StateError(
                  'Transfer response exceeded requested byte cap',
                );
              }
            }
            return streamed.statusCode;
          })().timeout(
            timeout,
            onTimeout: () async {
              abort.complete();
              await Future<void>.delayed(Duration.zero);
              throw TimeoutException(
                'Transfer exceeded its wall-clock deadline',
              );
            },
          );
      stopwatch.stop();
      if (statusCode >= 400 || received == 0) {
        return TransferResult.failed(bytes: received);
      }
      return TransferResult(
        ok: true,
        bytes: received,
        elapsedMs: stopwatch.elapsedMicroseconds / 1000.0,
      );
    } on Object {
      // Partial transfers still cost data; charge what actually arrived.
      return TransferResult(ok: false, bytes: received, elapsedMs: 0);
    }
  }

  /// Defeats intermediate caches — a cached 204 would report a 2ms round trip
  /// on a dead connection.
  Uri _cacheBust(Uri url) => url.replace(
    queryParameters: {
      ...url.queryParameters,
      '_ts': DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    },
  );

  @override
  void close() => _client.close();
}
