import '../../measurement/domain/history_insights.dart';
import '../../measurement/domain/history_stats.dart';
import '../../measurement/domain/signal_sample.dart';

/// What a free install has already recorded, in numbers the paywall can quote.
///
/// History is recorded on every tier; Pro only unlocks viewing it. Quoting the
/// user's own counts is therefore a true statement about data already on the
/// device, not a promise about what buying would do.
class ProTeaser {
  const ProTeaser({
    required this.readings,
    required this.dropouts,
    required this.window,
  });

  final int readings;

  /// Separate episodes at 0–1 bars, counted exactly as the History screen
  /// lists them (see [HistoryInsights.dropouts]).
  final int dropouts;

  final Duration window;

  static const Duration defaultWindow = Duration(hours: 24);

  /// Below this the numbers say more about how long the app has been installed
  /// than about the connection.
  static const int minReadings = 10;

  /// Null when there is too little history to say anything honest.
  static ProTeaser? from(
    List<SignalSample> samples, {
    DateTime? now,
    Duration window = defaultWindow,
  }) {
    if (samples.length < minReadings) return null;
    final end = now ?? DateTime.now();
    return ProTeaser(
      readings: samples.length,
      dropouts: HistoryInsights.dropouts(
        samples,
        end: end,
        maxHold: HistoryInterval.maximumFreshness,
      ).length,
      window: window,
    );
  }

  String get dropoutPhrase =>
      dropouts == 1 ? '1 drop-out' : '$dropouts drop-outs';
}
