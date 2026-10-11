import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import 'network_kind.dart';
import 'probe_issue.dart';
import 'scoring.dart';
import 'signal_sample.dart';

/// A plain-English reading of *why* a connection scored the way it did, and
/// what usually helps. Free on every tier: it is the explanation of the score,
/// not an extra.
///
/// Every rule is a direct reading of the measured sample. When nothing stands
/// out there is no diagnosis at all, rather than filler.
@immutable
class Diagnosis {
  const Diagnosis({required this.title, required this.advice});

  final String title;
  final String advice;

  /// Thresholds for the softer findings. Chosen to sit where people notice the
  /// problem, not where the score curve starts to bend.
  static const double slowLatencyMs = 300;
  static const double unsteadyJitterMs = 80;
  static const double slowThroughputKbps = 1000;

  static Diagnosis? of(SignalSample sample) {
    if (sample.isPlaceholder) return null;
    final kind = sample.kind;

    if (kind == NetworkKind.none) {
      return const Diagnosis(
        title: 'You are offline',
        advice:
            'Your phone is not connected to Wi-Fi or mobile data. Check '
            'airplane mode, or move somewhere with coverage.',
      );
    }

    if (sample.issue == ProbeIssue.intercepted) {
      return const Diagnosis(
        title: 'This network wants you to sign in',
        advice:
            'Requests are being answered by something other than the '
            'internet — usually a hotel, café or train Wi-Fi login page. Open '
            'a browser and accept the terms, then measure again.',
      );
    }

    final nothingThrough = sample.lossRatio >= 1;
    if (nothingThrough && sample.issue == ProbeIssue.dns) {
      return const Diagnosis(
        title: "Connected, but addresses won't look up",
        advice:
            'The network is up but name lookups (DNS) are failing, so '
            'websites cannot be found. Turning Wi-Fi off and on, or switching '
            'to mobile data, usually fixes it. On your own router, restart it.',
      );
    }

    if (nothingThrough) {
      return switch (kind) {
        NetworkKind.wifi => const Diagnosis(
          title: "Wi-Fi is connected, the internet isn't",
          advice:
              'Your phone reaches the router but nothing gets beyond it. If '
              'it is your router, restart it. If other devices are stuck too, '
              'the fault is with your provider.',
        ),
        NetworkKind.cellular => const Diagnosis(
          title: 'Signal, but no data',
          advice:
              'Your phone has a mobile connection but data is not moving. '
              'Turn airplane mode on and off. If it carries on, the mast is '
              'probably congested or has lost its own link.',
        ),
        _ => const Diagnosis(
          title: 'Connected, but nothing gets through',
          advice:
              'The phone reports a connection but no request is answered. If '
              'a VPN is on, try turning it off.',
        ),
      };
    }

    if (sample.throughputKbps != null && sample.throughputKbps! <= 0) {
      return const Diagnosis(
        title: "Pings get through, downloads don't",
        advice:
            'Small requests are answered but real data stalls — the "full '
            'bars, no data" failure. Pages will start loading and then hang. '
            'This is usually congestion; moving or switching network helps.',
      );
    }

    if (sample.lossRatio >= SignalScoring.severeLossRatio) {
      return Diagnosis(
        title: 'Requests are getting lost',
        advice:
            'About ${Format.percent(sample.lossRatio)} of requests never came '
            'back. Expect pages that half-load and calls that cut out. Weak '
            'signal at the edge of coverage is the usual cause.',
      );
    }

    final latency = sample.latencyMs;
    if (latency != null && latency >= slowLatencyMs) {
      return Diagnosis(
        title: 'Slow to respond',
        advice:
            'Each request takes about ${Format.latency(latency)}. Browsing '
            'works but feels sluggish, and calls or games will lag.',
      );
    }

    final jitter = sample.jitterMs;
    if (jitter != null && jitter >= unsteadyJitterMs) {
      return Diagnosis(
        title: 'Unsteady',
        advice:
            'Response times swing by ${Format.jitter(jitter)}. Video calls may '
            'stutter even though speed looks fine.',
      );
    }

    final speed = sample.throughputKbps;
    if (speed != null && speed > 0 && speed < slowThroughputKbps) {
      return Diagnosis(
        title: 'Slow downloads',
        advice:
            'Data is moving at about ${Format.throughput(speed)}. Fine for '
            'messages, slow for photos and video.',
      );
    }

    return null;
  }
}
