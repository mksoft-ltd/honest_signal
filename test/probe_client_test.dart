import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:honestsignal/features/measurement/data/probe_client.dart';
import 'package:honestsignal/features/measurement/domain/probe_targets.dart';

void main() {
  test('a failed transfer still charges its response body', () async {
    final client = HttpProbeClient(
      client: _StreamClient(Stream.value([1, 2, 3]), statusCode: 503),
    );
    addTearDown(client.close);

    final result = await client.transfer(
      ProbeTargets.transfer(120000),
      timeout: const Duration(seconds: 1),
    );

    expect(result.ok, isFalse);
    expect(result.bytes, 3);
  });

  test('an oversized probe is aborted and charges every received byte', () async {
    final client = HttpProbeClient(
      client: _StreamClient(
        Stream.fromIterable([
          List<int>.filled(HttpProbeClient.maxProbeResponseBytes, 1),
          [1],
        ]),
      ),
    );
    addTearDown(client.close);

    final result = await client.probe(
      ProbeTargets.latency.first,
      timeout: const Duration(seconds: 1),
    );

    expect(result.ok, isFalse);
    expect(
      result.bytes,
      HttpProbeClient.probeOverheadBytes +
          HttpProbeClient.maxProbeResponseBytes +
          1,
    );
  });

  test('a transfer rejects and charges a response larger than the requested '
      'sample instead of reading indefinitely', () async {
    final client = HttpProbeClient(
      client: _StreamClient(
        Stream.fromIterable([
          List<int>.filled(120000, 1),
          [1],
        ]),
      ),
    );
    addTearDown(client.close);

    final result = await client.transfer(
      ProbeTargets.transfer(120000),
      timeout: const Duration(seconds: 1),
    );

    expect(result.ok, isFalse);
    // The final chunk reached the device and must be counted against the
    // budget rather than being invisibly forgiven.
    expect(result.bytes, 120001);
  });

  test(
    'the transfer timeout is a wall-clock deadline for the complete body',
    () async {
      final transport = _AbortAwareClient(
        bodyDelay: const Duration(milliseconds: 20),
      );
      final client = HttpProbeClient(client: transport);
      addTearDown(client.close);
      final stopwatch = Stopwatch()..start();

      final result = await client.transfer(
        ProbeTargets.transfer(120000),
        timeout: const Duration(milliseconds: 50),
      );
      stopwatch.stop();

      expect(result.ok, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
      expect(transport.aborted, isTrue);
      final bytesAtReturn = transport.bytesEmitted;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(transport.bytesEmitted, bytesAtReturn);
    },
  );

  test(
    'probe timeout aborts a request stalled before response headers',
    () async {
      final transport = _AbortAwareClient(
        headerDelay: const Duration(seconds: 1),
      );
      final client = HttpProbeClient(client: transport);
      addTearDown(client.close);

      final result = await client.probe(
        ProbeTargets.latency.first,
        timeout: const Duration(milliseconds: 40),
      );

      expect(result.ok, isFalse);
      expect(transport.aborted, isTrue);
    },
  );

  test('probe timeout aborts and cancels a stalled response body', () async {
    final transport = _AbortAwareClient(
      bodyDelay: const Duration(milliseconds: 20),
    );
    final client = HttpProbeClient(client: transport);
    addTearDown(client.close);

    final result = await client.probe(
      ProbeTargets.latency.first,
      timeout: const Duration(milliseconds: 50),
    );

    expect(result.ok, isFalse);
    expect(transport.aborted, isTrue);
    final bytesAtReturn = transport.bytesEmitted;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(transport.bytesEmitted, bytesAtReturn);
  });
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this._stream, {this.statusCode = 200});

  final Stream<List<int>> _stream;
  final int statusCode;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(_stream, statusCode);
}

class _AbortAwareClient extends http.BaseClient {
  _AbortAwareClient({this.headerDelay = Duration.zero, this.bodyDelay});

  final Duration headerDelay;
  final Duration? bodyDelay;
  bool aborted = false;
  int bytesEmitted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortTrigger = (request as http.AbortableRequest).abortTrigger!;
    if (headerDelay > Duration.zero) {
      await Future.any<void>([
        Future<void>.delayed(headerDelay),
        abortTrigger.then((_) {
          aborted = true;
          throw http.RequestAbortedException(request.url);
        }),
      ]);
    }
    return http.StreamedResponse(_body(abortTrigger), 200);
  }

  Stream<List<int>> _body(Future<void> abortTrigger) async* {
    if (bodyDelay == null) {
      yield [1];
      return;
    }
    while (!aborted) {
      await Future.any<void>([
        Future<void>.delayed(bodyDelay!),
        abortTrigger.then((_) => aborted = true),
      ]);
      if (aborted) break;
      bytesEmitted++;
      yield [1];
    }
    if (aborted) {
      throw http.RequestAbortedException(Uri.parse('https://aborted.invalid'));
    }
  }
}
