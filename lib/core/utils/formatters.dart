/// Small display helpers, kept pure so the widget tests can assert on strings
/// without pumping a whole screen.
class Format {
  const Format._();

  static String throughput(double? kbps) {
    if (kbps == null) return '—';
    if (kbps <= 0) return 'stalled';
    if (kbps >= 1000) {
      final mbps = kbps / 1000;
      return '${mbps < 10 ? mbps.toStringAsFixed(1) : mbps.round()} Mbps';
    }
    return '${kbps.round()} kbps';
  }

  static String latency(double? ms) => ms == null ? '—' : '${ms.round()} ms';

  static String jitter(double? ms) => ms == null ? '—' : '±${ms.round()} ms';

  static String percent(double ratio) => '${(ratio * 100).round()}%';

  static String lossPercent(double ratio) => percent(ratio);

  static String bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).round()} KB';
    final mb = value / (1024 * 1024);
    return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
  }

  /// "just now" / "3 min ago" / "2 h ago". Freshness is a first-class part of
  /// the product's honesty, so it is never rounded up into vagueness.
  static String age(DateTime timestamp, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final delta = reference.difference(timestamp);
    if (delta.isNegative || delta.inSeconds < 5) return 'just now';
    if (delta.inSeconds < 60) return '${delta.inSeconds}s ago';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} h ago';
    return '${delta.inDays} d ago';
  }

  static String clockTime(DateTime timestamp) =>
      '${timestamp.hour.toString().padLeft(2, '0')}:'
      '${timestamp.minute.toString().padLeft(2, '0')}';

  static String interval(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds % 60 == 0 && seconds < 3600) return '${seconds ~/ 60} min';
    if (seconds % 3600 == 0) return '${seconds ~/ 3600} h';
    return '${(seconds / 60).toStringAsFixed(1)} min';
  }
}
