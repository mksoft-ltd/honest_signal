import 'package:flutter/material.dart';

/// The five score colours, for one brightness.
///
/// The ramp is the app's core vocabulary — it appears on the bars, the verdict
/// headline, the metric tiles and the history graph — so it is defined here
/// rather than pulled from the Material scheme, which has no notion of "two
/// bars".
///
/// There are two sets because one cannot work. A ramp bright enough to read on
/// a near-black surface is 1.9–2.9:1 on a near-white one, which fails WCAG for
/// both text and non-text contrast; the same ramp taken down to a register that
/// reads on white disappears into a dark scaffold. Both sets keep the original
/// hues and move only lightness, so the app looks like itself in either theme.
@immutable
class ScoreColors {
  const ScoreColors({
    required this.dead,
    required this.poor,
    required this.fair,
    required this.good,
    required this.great,
  });

  final Color dead;
  final Color poor;
  final Color fair;
  final Color good;
  final Color great;

  /// Colour for a bar count. Two and three bars deliberately share the "fair"
  /// band: the difference the user cares about is usable vs not.
  Color forBars(int bars) => switch (bars) {
        0 => dead,
        1 => poor,
        2 => fair,
        3 => fair,
        4 => good,
        _ => great,
      };
}

class AppColors {
  const AppColors._();

  /// Brand green. Seeds the Material scheme and is the icon and store creative
  /// accent; it is *not* a UI foreground — [light]/[dark] carry those.
  static const Color seed = Color(0xFF1FA97A);

  /// Score ramp for dark surfaces. `SignalBubbleView.colourFor` in Kotlin is a
  /// copy of exactly this set — the floating bubble always draws on its own
  /// dark plate, so it never needs the light one. Change the two together.
  static const ScoreColors dark = ScoreColors(
    dead: Color(0xFFE0483C),
    poor: Color(0xFFE8863B),
    fair: Color(0xFFD8B22E),
    good: Color(0xFF4FA83D),
    great: Color(0xFF1FA97A),
  );

  /// Score ramp for light surfaces: the same hues in a darker register.
  /// Every one clears 4.5:1 on both light surfaces the app paints on
  /// (`surface` #F5FBF5 and `surfaceContainerLow` #EFF5EF), which covers the
  /// small-text uses — the metric-tile emphasis and the onboarding label — as
  /// well as the 3:1 floor the bars and the chart need as non-text marks.
  static const ScoreColors light = ScoreColors(
    dead: Color(0xFFC0271B),
    poor: Color(0xFFA85A0A),
    fair: Color(0xFF8A6B00),
    good: Color(0xFF357A27),
    great: Color(0xFF0E7A57),
  );

  static ScoreColors forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static ScoreColors of(BuildContext context) =>
      forBrightness(Theme.of(context).brightness);
}

/// Corner radii, as a scale rather than a number picked per widget.
class AppRadius {
  const AppRadius._();

  /// Progress tracks and other thin bars — half the track height, so they read
  /// as pills at any thickness.
  static const double pill = 999;

  /// Tiles, buttons, banners, swatches.
  static const double control = 14;

  /// Cards — the largest surface, so the largest radius.
  static const double card = 18;
}

/// Page padding, so every scrolling screen starts in the same place.
class AppSpacing {
  const AppSpacing._();

  static const EdgeInsets page = EdgeInsets.fromLTRB(20, 12, 20, 32);
}

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);

    // Material's tonal elevation is nearly invisible in the light scheme —
    // `surfaceContainerLow` is 1.03:1 against `surface` — so cards and tiles
    // are defined by a hairline instead of by fill alone. The same outline in
    // the dark scheme keeps both themes reading as one design.
    final outline = scheme.outlineVariant.withValues(alpha: 0.7);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: outline),
        ),
        margin: EdgeInsets.zero,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
