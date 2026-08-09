import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:honestsignal/features/measurement/data/probe_client.dart';
import 'package:honestsignal/features/measurement/domain/probe_targets.dart';

void main() {
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
      final client = HttpProbeClient(client: _StreamClient(_slowChunks()));
      addTearDown(client.close);
      final stopwatch = Stopwatch()..start();

      final result = await client.transfer(
        ProbeTargets.transfer(120000),
        timeout: const Duration(milliseconds: 50),
      );
      stopwatch.stop();

      expect(result.ok, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));
    },
  );
}

class _StreamClient extends http.BaseClient {
  _StreamClient(this._stream);

  final Stream<List<int>> _stream;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(_stream, 200);
}

Stream<List<int>> _slowChunks() async* {
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    yield [1];
  }
}
