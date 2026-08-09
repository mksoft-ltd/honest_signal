import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/constants/app_constants.dart';
import 'package:honestsignal/core/demo/screenshot_mode.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/data/measurement_controller.dart';
import 'package:honestsignal/features/measurement/data/probe_client.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/probe_targets.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

/// Facts a later pipeline stage, a store listing, or a review submission
/// depends on.
///
/// Each of these has a copy somewhere outside the code — in the store record,
/// in `docs/PRODUCT_SPEC.md`, in the privacy policy, in the manifest — and the
/// two silently disagreeing is the failure mode. A change here should mean a
/// deliberate change over there too.
void main() {
  group('store identity', () {
    test('the publisher and app name match the store records', () {
      expect(AppConstants.appName, 'Honest Signal');
      expect(AppConstants.publisher, 'Froggy Eye Ltd');
    });

    test(
      'the privacy policy URL is the house raw-GitHub form for this repo',
      () {
        // The listing points at this exact URL; it must return 200 before
        // submission, and the binary and the listing must not disagree.
        expect(
          AppConstants.privacyPolicyUrl,
          'https://raw.githubusercontent.com/mksoft-ltd/honest_signal/'
          'refs/heads/main/PRIVACY_POLICY.md',
        );
      },
    );

    test('support and contact point at the studio, not a personal address', () {
      expect(AppConstants.supportUrl, 'https://honestsignal.froggyeye.com');
      expect(AppConstants.supportEmail, 'info@froggyeye.com');
    });
  });

  group('network surface', () {
    test('every probe endpoint is HTTPS and publicly documented', () {
      // The privacy policy names these operators by name. Adding a host is a
      // policy edit, not just a code edit.
      for (final uri in ProbeTargets.latency) {
        expect(uri.scheme, 'https');
      }
      expect(ProbeTargets.latency.map((u) => u.host).toSet(), {
        'www.gstatic.com',
        'cp.cloudflare.com',
        'connectivitycheck.gstatic.com',
      });
      expect(ProbeTargets.transfer(1000).scheme, 'https');
      expect(ProbeTargets.transfer(1000).host, 'speed.cloudflare.com');
    });

    test('the transfer endpoint is asked for exactly the bytes budgeted', () {
      // The hard data budget only works because the sample size is requested
      // rather than guessed.
      expect(ProbeTargets.transfer(120000).queryParameters['bytes'], '120000');
    });

    // Asking for 120 KB is only half the guarantee. `Stream.timeout` is an
    // inter-chunk timeout, so before the cap existed a responder that kept
    // sending was accepted without limit — measured at 3,072,000 bytes over
    // 13.6 s against an 8 s timeout. These two drive the real client against a
    // real socket, because the bug lived in how the response was read.
    group('and enforces that size on the response', () {
      late HttpServer server;

      tearDown(() => server.close(force: true));

      /// Serves [chunkBytes] every [gap] until the client gives up.
      Future<Uri> serve({
        required int chunkBytes,
        required Duration gap,
        int chunks = 4096,
      }) async {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final payload = List<int>.filled(chunkBytes, 65);
        unawaited(() async {
          await for (final request in server) {
            request.response.headers.contentType = ContentType.binary;
            try {
              for (var i = 0; i < chunks; i++) {
                request.response.add(payload);
                await request.response.flush();
                if (gap > Duration.zero) await Future<void>.delayed(gap);
              }
              await request.response.close();
            } on Object {
              // The client hanging up is the pass condition.
            }
          }
        }());
        return Uri.parse(
          'http://127.0.0.1:${server.port}/__down?bytes=$_requestedBytes',
        );
      }

      test('a responder that keeps sending is cut off near the budgeted size',
          () async {
        // 4096 x 16 KB = 64 MB on offer against a 120 KB request.
        final url = await serve(
          chunkBytes: 16 * 1024,
          gap: Duration.zero,
        );
        final client = HttpProbeClient();
        addTearDown(client.close);

        final result = await client.transfer(
          url,
          timeout: const Duration(seconds: 8),
        );

        // Reading stops at the first chunk that crosses the cap — but a chunk
        // is one socket read, not one server write, and the client coalesces.
        // The overshoot is therefore set by the peer's write size and receive
        // buffer autotuning, not by anything this code guarantees: measured
        // against the current client, 16 KB writes overshoot ~11 KB while 1 MB
        // writes overshoot ~907 KB. A tight margin would both flake on a
        // differently tuned machine and mask a regression that widened the
        // overshoot. 64 MB was on offer, so anything in this range proves the
        // read was cut off rather than run to completion.
        expect(result.bytes, lessThan(2 * 1024 * 1024));
        expect(result.ok, isFalse, reason: 'an oversized body is not a sample');
        // Whatever arrived is still charged to the daily budget.
        expect(result.bytes, greaterThan(0));
      });

      test('a slow drip cannot hold the cycle open past its timeout', () async {
        // 8 KB every 400 ms would take over an hour to reach the cap, so only a
        // total deadline ends this. A per-chunk timeout never fires.
        final url = await serve(
          chunkBytes: 8 * 1024,
          gap: const Duration(milliseconds: 400),
        );
        final client = HttpProbeClient();
        addTearDown(client.close);

        const timeout = Duration(seconds: 2);
        final wall = Stopwatch()..start();
        final result = await client.transfer(url, timeout: timeout);
        wall.stop();

        expect(
          wall.elapsed,
          lessThan(timeout + const Duration(seconds: 2)),
          reason: 'the transfer must observe a wall-clock deadline',
        );
        expect(result.ok, isFalse);
      });
    });

    test('rotation covers the whole endpoint list', () {
      final hosts = <String>{};
      for (var cycle = 0; cycle < ProbeTargets.latency.length; cycle++) {
        hosts.add(ProbeTargets.latencyRotation(cycle, 1).single.host);
      }
      expect(hosts, hasLength(ProbeTargets.latency.length));
    });

    test('the endpoint list cannot be mutated at runtime', () {
      expect(
        () => ProbeTargets.latency.add(Uri.parse('https://example.com')),
        throwsUnsupportedError,
      );
    });
  });

  group('documented defaults', () {
    test('the free tier matches the cadence table in the spec', () {
      // Spec §6: 5 s foreground, 5 min background, 25 MB/day.
      expect(AppSettings.defaultForegroundInterval, 5);
      expect(AppSettings.defaultBackgroundInterval, 300);
      expect(AppSettings.defaultDailyBudgetMb, 25);
    });

    test('the Pro ranges match the spec', () {
      expect(AppSettings.minForegroundInterval, 2);
      expect(AppSettings.maxForegroundInterval, 60);
      expect(AppSettings.minBackgroundInterval, 60);
      expect(AppSettings.maxBackgroundInterval, 3600);
      expect(AppSettings.minDailyBudgetMb, 5);
      expect(AppSettings.maxDailyBudgetMb, 250);
    });

    test('the transfer sample costs what the budget maths assumes', () {
      const config = MeasurementConfig();
      expect(config.transferBytes, 120000);
      expect(config.probeCount, 4);
      expect(config.probeTimeout, const Duration(seconds: 2));
      expect(config.throughputFreshness, const Duration(minutes: 5));
    });

    test('the transfer cadences match the spec table', () {
      expect(
        MeasurementController.foregroundTransferInterval,
        const Duration(seconds: 90),
      );
      expect(
        MeasurementController.backgroundTransferInterval,
        const Duration(minutes: 10),
      );
    });

    test('a day of background monitoring fits inside the default budget', () {
      // Spec §6 claims the default budget "comfortably covers all-day
      // background monitoring". At a 5-minute cadence that is 288 probe cycles
      // plus a transfer sample every 10 minutes.
      const cyclesPerDay = 24 * 60 ~/ 5;
      const transfersPerDay = 24 * 60 ~/ 10;
      const cost = cyclesPerDay * 4 * 700 + transfersPerDay * 120000;

      expect(cost, lessThan(AppSettings.defaultDailyBudgetMb * 1024 * 1024));
    });

    test('the published retention figure is the one the code enforces', () {
      // The privacy policy is a legal document for an app whose whole pitch is
      // telling the truth about numbers; it said 24 hours while the code kept
      // 25. The in-app copy on the history and "How the score works" screens
      // is interpolated from this same constant, so this covers all four.
      final hours = HistoryRepository.defaultRetention.inHours;
      final policy = File('PRIVACY_POLICY.md').readAsStringSync();

      expect(policy, contains('kept for up to $hours hours'));
      expect(policy, isNot(contains('24 hours and then deleted')));
    });
  });

  group('screenshot mode', () {
    test('is off unless the define is passed', () {
      // The suite runs without the define, so demo data can never leak into an
      // ordinary test run or an ordinary build.
      expect(ScreenshotMode.isEnabled, isFalse);
    });

    test('is welded shut in release builds', () {
      // A shipped binary that can be switched into fake data is a store-review
      // problem, so the flag is ANDed with `!kReleaseMode`. Asserted against
      // the source because a debug test cannot observe release mode.
      final source = File(
        'lib/core/demo/screenshot_mode.dart',
      ).readAsStringSync();
      final getter = source
          .split('\n')
          .firstWhere((line) => line.contains('get isEnabled'));

      expect(getter, contains('!kReleaseMode'));
      expect(kReleaseMode, isFalse, reason: 'tests always run in debug');
    });

    test('the demo data is a score the real engine could actually produce', () {
      // A screenshot showing an impossible reading would misrepresent the app
      // in the listing.
      expect(demoDataIsPlausible(), isTrue);
    });
  });

  group('Android manifest', () {
    late String manifest;

    setUpAll(() {
      manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
    });

    test('declares exactly the permissions the spec justifies', () {
      // Every one of these has a written justification in PRODUCT_SPEC §9 and
      // a Play Console declaration behind it. An extra one appearing here needs
      // both before it can ship.
      final declared = RegExp(
        r'android\.permission\.([A-Z_]+)',
      ).allMatches(manifest).map((m) => m.group(1)).toSet();

      expect(declared, {
        'INTERNET',
        'ACCESS_NETWORK_STATE',
        'POST_NOTIFICATIONS',
        'FOREGROUND_SERVICE',
        'FOREGROUND_SERVICE_SPECIAL_USE',
        'SYSTEM_ALERT_WINDOW',
        'RECEIVE_BOOT_COMPLETED',
      });
    });

    test('asks for no location, camera, storage, phone or contacts access', () {
      for (final forbidden in [
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'CAMERA',
        'READ_EXTERNAL_STORAGE',
        'READ_PHONE_STATE',
        'READ_CONTACTS',
        'RECORD_AUDIO',
      ]) {
        expect(manifest, isNot(contains(forbidden)));
      }
    });

    test('the foreground service is specialUse, which has no daily cap', () {
      // dataSync is capped at 6 hours a day from Android 15, which would kill
      // the indicator part-way through every day at an unpredictable time.
      expect(manifest, contains('android:foregroundServiceType="specialUse"'));
      expect(manifest, isNot(contains('"dataSync"')));
    });

    test(
      'keeps local history and the cached entitlement out of device backup',
      () {
        expect(manifest, contains('android:allowBackup="false"'));
        expect(
          manifest,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        );
        final rules = File(
          'android/app/src/main/res/xml/data_extraction_rules.xml',
        ).readAsStringSync();
        expect(rules, contains('<cloud-backup>'));
        expect(rules, contains('<device-transfer>'));
      },
    );

    test(
      'rejects cleartext traffic and trusts only system certificate roots',
      () {
        expect(
          manifest,
          contains(
            'android:networkSecurityConfig="@xml/network_security_config"',
          ),
        );
        final config = File(
          'android/app/src/main/res/xml/network_security_config.xml',
        ).readAsStringSync();
        expect(config, contains('cleartextTrafficPermitted="false"'));
        expect(config, contains('<certificates src="system"'));
      },
    );
  });
}

/// The size the app asks the transfer endpoint for, mirroring
/// `MeasurementConfig.transferBytes`.
const int _requestedBytes = 120000;
