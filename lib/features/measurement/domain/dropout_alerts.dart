import 'package:flutter/foundation.dart';

import 'network_kind.dart';
import 'signal_sample.dart';

enum AlertKind { drop, recovered }

@immutable
class AlertMessage {
  const AlertMessage({
    required this.kind,
    required this.title,
    required this.body,
  });

  final AlertKind kind;
  final String title;
  final String body;

  Map<String, String> toChannelArgs() => {
    'kind': kind.name,
    'title': title,
    'body': body,
  };
}

/// Decides when a background reading deserves a notification.
///
/// One alert when the score has stayed at or below the user's threshold for
/// their chosen time, one when it comes back — never a stream of them. Pure
/// and clock-free (time comes from the samples) so every rule is unit-tested.
class DropoutAlertTracker {
  /// Recovery needs a clear margin above the threshold, so a link wobbling
  /// across the line does not produce a drop/back/drop sequence.
  static const int recoveryMargin = 2;

  /// A second drop alert inside this window after a recovery is suppressed;
  /// the earlier notification already told the story.
  static const Duration repeatQuietPeriod = Duration(minutes: 10);

  /// Longer than this between readings and the tracker forgets what it knew:
  /// the app has no idea what happened in the gap and says nothing about it.
  static const Duration maximumGap = Duration(minutes: 10);

  DateTime? _poorSince;
  DateTime? _lastSeen;
  DateTime? _alertedAt;
  DateTime? _lastRecovery;
  NetworkKind? _kind;

  bool get isAlerting => _alertedAt != null;

  AlertMessage? observe(
    SignalSample sample, {
    required int thresholdBars,
    required Duration after,
  }) {
    final now = sample.timestamp;
    final last = _lastSeen;
    _lastSeen = now;
    if (last != null && now.difference(last).abs() > maximumGap) {
      _poorSince = null;
      _alertedAt = null;
    }

    if (sample.bars <= thresholdBars) {
      _poorSince ??= now;
      _kind ??= sample.kind;
      if (_alertedAt != null) return null;
      if (now.difference(_poorSince!) < after) return null;
      final recovered = _lastRecovery;
      if (recovered != null && now.difference(recovered) < repeatQuietPeriod) {
        return null;
      }
      _alertedAt = now;
      return _dropMessage(sample, now.difference(_poorSince!));
    }

    if (_alertedAt != null) {
      if (sample.bars < thresholdBars + recoveryMargin) return null;
      final lasted = now.difference(_poorSince ?? _alertedAt!);
      _poorSince = null;
      _alertedAt = null;
      _kind = null;
      _lastRecovery = now;
      return AlertMessage(
        kind: AlertKind.recovered,
        title: 'Connection is back',
        body:
            '${sample.kind.label} is at ${sample.bars}/5 again '
            'after ${_duration(lasted)}.',
      );
    }

    _poorSince = null;
    _kind = null;
    return null;
  }

  AlertMessage _dropMessage(SignalSample sample, Duration lasted) {
    final network = (_kind ?? sample.kind);
    final title = network == NetworkKind.none
        ? 'You are offline'
        : sample.bars == 0
        ? 'Nothing is getting through'
        : 'Connection has dropped out';
    final where = network == NetworkKind.none ? 'No network' : network.label;
    return AlertMessage(
      kind: AlertKind.drop,
      title: title,
      body:
          '$where has been at ${sample.bars}/5 for ${_duration(lasted)}. '
          'You will hear again when it is back.',
    );
  }

  static String _duration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final minutes = d.inMinutes % 60;
    return minutes == 0
        ? '${d.inHours} h'
        : '${d.inHours} h ${minutes.toString().padLeft(2, '0')} min';
  }
}
