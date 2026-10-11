import 'package:flutter/material.dart';

/// The icon shape used for the bars, both in-app and in the Android status-bar
/// notification. Non-default themes are a Pro unlock.
enum BarTheme {
  bars('Bars'),
  dots('Dots'),
  wave('Wave');

  const BarTheme(this.label);
  final String label;

  bool get isFree => this == BarTheme.bars;

  static BarTheme fromStorage(String? value) => BarTheme.values.firstWhere(
    (t) => t.name == value,
    orElse: () => BarTheme.bars,
  );
}

/// User-controlled behaviour. Persisted as a single JSON map in the Hive
/// settings box — the house pattern for small local-first apps.
@immutable
class AppSettings {
  const AppSettings({
    this.notificationIndicatorEnabled = true,
    this.overlayEnabled = false,
    this.foregroundIntervalSeconds = defaultForegroundInterval,
    this.backgroundIntervalSeconds = defaultBackgroundInterval,
    this.dailyBudgetMb = defaultDailyBudgetMb,
    this.barTheme = BarTheme.bars,
    this.highContrastIndicator = true,
    this.measureOnCellular = true,
    this.themeMode = ThemeMode.system,
    this.hasSeenOnboarding = false,
    this.alertsEnabled = false,
    this.alertBars = defaultAlertBars,
    this.alertMinutes = defaultAlertMinutes,
  });

  // Free-tier defaults, and the values a non-Pro install is pinned to.
  static const int defaultForegroundInterval = 5;
  static const int defaultBackgroundInterval = 2;
  static const int defaultDailyBudgetMb = 25;

  // Pro-adjustable ranges.
  static const int minForegroundInterval = 2;
  static const int maxForegroundInterval = 60;
  static const int minBackgroundInterval = 2;
  static const int maxBackgroundInterval = 3600;
  static const int minDailyBudgetMb = 5;
  static const int maxDailyBudgetMb = 250;

  static const int defaultAlertBars = 1;
  static const int defaultAlertMinutes = 2;
  static const List<int> alertBarChoices = [0, 1, 2];
  static const List<int> alertMinuteChoices = [1, 2, 5, 10, 30];

  /// Android only: run the foreground service whose status-bar icon shows the
  /// live score.
  final bool notificationIndicatorEnabled;

  /// Android only, Pro: the draggable floating bubble drawn over other apps.
  final bool overlayEnabled;

  final int foregroundIntervalSeconds;
  final int backgroundIntervalSeconds;
  final int dailyBudgetMb;
  final BarTheme barTheme;

  /// Android only: draw the status-bar icon on a filled plate instead of as
  /// bare strokes.
  ///
  /// Free for everyone and on by default, unlike [barTheme]. It is a
  /// legibility accommodation, not decoration — users reported the bare mark
  /// disappearing into busy wallpaper — and charging for one would be the kind
  /// of thing this app exists not to do.
  final bool highContrastIndicator;

  /// When false the engine skips probing on a metered mobile connection, for
  /// users on very small data plans.
  final bool measureOnCellular;

  final ThemeMode themeMode;
  final bool hasSeenOnboarding;

  /// Android only, Pro: notify when the score stays at or below [alertBars]
  /// for [alertMinutes], and again when it recovers. Runs in the same
  /// background service as the status-bar indicator, so it needs that on.
  final bool alertsEnabled;
  final int alertBars;
  final int alertMinutes;

  int get dailyBudgetBytes => dailyBudgetMb * 1024 * 1024;

  Duration get foregroundInterval =>
      Duration(seconds: foregroundIntervalSeconds);
  Duration get backgroundInterval =>
      Duration(seconds: backgroundIntervalSeconds);

  /// Settings a free install cannot change are clamped on read rather than
  /// blocked on write, so a lapsed or refunded purchase degrades cleanly
  /// instead of leaving the app in a state the tier does not allow.
  AppSettings clampedForTier({required bool isPro}) {
    if (isPro) return this;
    return copyWith(
      foregroundIntervalSeconds: defaultForegroundInterval,
      backgroundIntervalSeconds: defaultBackgroundInterval,
      barTheme: BarTheme.bars,
      overlayEnabled: false,
      alertsEnabled: false,
    );
  }

  AppSettings copyWith({
    bool? notificationIndicatorEnabled,
    bool? overlayEnabled,
    int? foregroundIntervalSeconds,
    int? backgroundIntervalSeconds,
    int? dailyBudgetMb,
    BarTheme? barTheme,
    bool? highContrastIndicator,
    bool? measureOnCellular,
    ThemeMode? themeMode,
    bool? hasSeenOnboarding,
    bool? alertsEnabled,
    int? alertBars,
    int? alertMinutes,
  }) => AppSettings(
    notificationIndicatorEnabled:
        notificationIndicatorEnabled ?? this.notificationIndicatorEnabled,
    overlayEnabled: overlayEnabled ?? this.overlayEnabled,
    foregroundIntervalSeconds:
        foregroundIntervalSeconds ?? this.foregroundIntervalSeconds,
    backgroundIntervalSeconds:
        backgroundIntervalSeconds ?? this.backgroundIntervalSeconds,
    dailyBudgetMb: dailyBudgetMb ?? this.dailyBudgetMb,
    barTheme: barTheme ?? this.barTheme,
    highContrastIndicator: highContrastIndicator ?? this.highContrastIndicator,
    measureOnCellular: measureOnCellular ?? this.measureOnCellular,
    themeMode: themeMode ?? this.themeMode,
    hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
    alertsEnabled: alertsEnabled ?? this.alertsEnabled,
    alertBars: alertBars ?? this.alertBars,
    alertMinutes: alertMinutes ?? this.alertMinutes,
  );

  Map<String, dynamic> toJson() => {
    'notification': notificationIndicatorEnabled,
    'overlay': overlayEnabled,
    'fgInterval': foregroundIntervalSeconds,
    'bgInterval': backgroundIntervalSeconds,
    'bgCadenceV2': true,
    'budgetMb': dailyBudgetMb,
    'barTheme': barTheme.name,
    'highContrast': highContrastIndicator,
    'cellular': measureOnCellular,
    'themeMode': themeMode.name,
    'onboarded': hasSeenOnboarding,
    'alerts': alertsEnabled,
    'alertBars': alertBars,
    'alertMinutes': alertMinutes,
  };

  static AppSettings fromJson(Map<dynamic, dynamic> json) => AppSettings(
    notificationIndicatorEnabled: json['notification'] as bool? ?? true,
    overlayEnabled: json['overlay'] as bool? ?? false,
    foregroundIntervalSeconds:
        (json['fgInterval'] as num?)?.toInt() ?? defaultForegroundInterval,
    backgroundIntervalSeconds:
        // 300 seconds was the old free default. Settings written by this
        // version carry a marker so a deliberate new 300-second choice
        // survives reloads. Older custom 300-second choices cannot be
        // distinguished from the old default.
        (json['bgCadenceV2'] != true &&
            (json['bgInterval'] as num?)?.toInt() == 300
        ? defaultBackgroundInterval
        : (json['bgInterval'] as num?)?.toInt() ?? defaultBackgroundInterval),
    dailyBudgetMb: (json['budgetMb'] as num?)?.toInt() ?? defaultDailyBudgetMb,
    barTheme: BarTheme.fromStorage(json['barTheme'] as String?),
    // Absent for every install that predates 1.0.1, which is the whole
    // live population — they get the high-contrast icon on upgrade, which
    // is the point of the release.
    highContrastIndicator: json['highContrast'] as bool? ?? true,
    measureOnCellular: json['cellular'] as bool? ?? true,
    themeMode: ThemeMode.values.firstWhere(
      (m) => m.name == json['themeMode'],
      orElse: () => ThemeMode.system,
    ),
    hasSeenOnboarding: json['onboarded'] as bool? ?? false,
    alertsEnabled: json['alerts'] as bool? ?? false,
    alertBars: _oneOf(
      (json['alertBars'] as num?)?.toInt(),
      alertBarChoices,
      defaultAlertBars,
    ),
    alertMinutes: _oneOf(
      (json['alertMinutes'] as num?)?.toInt(),
      alertMinuteChoices,
      defaultAlertMinutes,
    ),
  );

  static int _oneOf(int? value, List<int> allowed, int fallback) =>
      value != null && allowed.contains(value) ? value : fallback;
}
