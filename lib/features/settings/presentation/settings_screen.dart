import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/signal_bars.dart';
import '../domain/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final effective = ref.watch(effectiveSettingsProvider);
    final isPro = ref.watch(isProProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Indicator'),
          if (Platform.isAndroid) ...[
            SwitchListTile(
              title: const Text('Status-bar indicator'),
              subtitle: const Text(
                'Keeps Honest Signal measuring and shows the live score as an '
                'icon in your status bar.',
              ),
              value: effective.notificationIndicatorEnabled,
              onChanged: (value) => controller.update(
                (s) => s.copyWith(notificationIndicatorEnabled: value),
              ),
            ),
            SwitchListTile(
              title: const Text('High-contrast icon'),
              subtitle: const Text(
                'Draws the status-bar icon on a plate so it stays readable '
                'over any wallpaper.',
              ),
              value: effective.highContrastIndicator,
              onChanged: effective.notificationIndicatorEnabled
                  ? (value) => controller.update(
                      (s) => s.copyWith(highContrastIndicator: value),
                    )
                  : null,
            ),
            ListTile(
              title: const Text('Floating indicator'),
              subtitle: Text(
                !effective.notificationIndicatorEnabled
                    ? 'Requires the status-bar indicator to keep its score current.'
                    : effective.overlayEnabled
                    ? 'On — a small bubble is drawn over other apps.'
                    : 'Off — a small draggable bubble over other apps.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/overlay'),
            ),
          ],
          // Deliberately NOT inside the Android block. This is the only writer
          // of `barTheme` in the app, and Pro sells "indicator themes" on both
          // stores — gating it behind Android left an iPhone buyer paying for a
          // feature with no control anywhere in the app. The mark itself is
          // already themed on iOS (`home_screen` passes barTheme to SignalBars),
          // so only the control was missing.
          _ThemePicker(
            current: effective.barTheme,
            isPro: isPro,
            description: Platform.isAndroid
                ? 'Bars, dots or wave — in the app and in the status bar.'
                : 'Bars, dots or wave — in the app.',
            onChanged: (value) =>
                controller.update((s) => s.copyWith(barTheme: value)),
            onLocked: () => context.push('/pro'),
          ),
          const _SectionHeader('Measurement'),
          _IntervalTile(
            title: 'While the app is open',
            seconds: effective.foregroundIntervalSeconds,
            min: AppSettings.minForegroundInterval,
            max: AppSettings.maxForegroundInterval,
            isPro: isPro,
            onChanged: (value) => controller.update(
              (s) => s.copyWith(foregroundIntervalSeconds: value),
            ),
            onLocked: () => context.push('/pro'),
          ),
          if (Platform.isAndroid)
            _IntervalTile(
              title: 'In the background',
              seconds: effective.backgroundIntervalSeconds,
              min: AppSettings.minBackgroundInterval,
              max: AppSettings.maxBackgroundInterval,
              isPro: isPro,
              onChanged: (value) => controller.update(
                (s) => s.copyWith(backgroundIntervalSeconds: value),
              ),
              onLocked: () => context.push('/pro'),
            ),
          _BudgetTile(
            megabytes: settings.dailyBudgetMb,
            onChanged: (value) =>
                controller.update((s) => s.copyWith(dailyBudgetMb: value)),
          ),
          SwitchListTile(
            title: const Text('Measure on mobile data'),
            subtitle: const Text(
              'Turn off to probe only on Wi-Fi. Your score will stop updating '
              'when you leave Wi-Fi.',
            ),
            value: effective.measureOnCellular,
            onChanged: (value) =>
                controller.update((s) => s.copyWith(measureOnCellular: value)),
          ),
          const _SectionHeader('Appearance'),
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(switch (effective.themeMode) {
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
              ThemeMode.system => 'Match system',
            }),
            trailing: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {effective.themeMode},
              onSelectionChanged: (values) =>
                  controller.update((s) => s.copyWith(themeMode: values.first)),
            ),
          ),
          const _SectionHeader('About'),
          if (!isPro)
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('Honest Signal Pro'),
              subtitle: const Text('History, themes, custom intervals'),
              onTap: () => context.push('/pro'),
            ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore purchase'),
            onTap: () => ref.read(purchaseControllerProvider).restore(),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('Honest Signal collects nothing.'),
            onTap: () => _open(AppConstants.privacyPolicyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('How the score works'),
            onTap: () => context.push('/how-it-works'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Honest Signal'),
            subtitle: Text('© 2026 ${AppConstants.publisher}'),
          ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({
    required this.current,
    required this.isPro,
    required this.description,
    required this.onChanged,
    required this.onLocked,
  });

  final BarTheme current;
  final bool isPro;

  /// What the chosen style actually affects, which differs by platform: on iOS
  /// there is no status bar to theme, so promising one would be the same
  /// inaccuracy in miniature.
  final String description;
  final ValueChanged<BarTheme> onChanged;
  final VoidCallback onLocked;

  @override
  Widget build(BuildContext context) {
    final appTheme = Theme.of(context);
    return ListTile(
      title: const Text('Indicator style'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            description,
            style: appTheme.textTheme.bodySmall?.copyWith(
              color: appTheme.colorScheme.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                for (final barTheme in BarTheme.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: _ThemeSwatch(
                      theme: barTheme,
                      selected: barTheme == current,
                      locked: !isPro && !barTheme.isFree,
                      onTap: () => (!isPro && !barTheme.isFree)
                          ? onLocked()
                          : onChanged(barTheme),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.theme,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final BarTheme theme;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${theme.label} indicator style${locked ? ', Pro only' : ''}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Container(
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Opacity(
                opacity: locked ? 0.4 : 1,
                child: SignalBars(
                  bars: 4,
                  theme: theme,
                  size: 34,
                  animate: false,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                locked ? 'Pro' : theme.label,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntervalTile extends StatelessWidget {
  const _IntervalTile({
    required this.title,
    required this.seconds,
    required this.min,
    required this.max,
    required this.isPro,
    required this.onChanged,
    required this.onLocked,
  });

  final String title;
  final int seconds;
  final int min;
  final int max;
  final bool isPro;
  final ValueChanged<int> onChanged;
  final VoidCallback onLocked;

  @override
  Widget build(BuildContext context) {
    if (!isPro) {
      return ListTile(
        title: Text(title),
        subtitle: Text('Every ${Format.interval(seconds)} · Pro to change'),
        trailing: const Icon(Icons.lock_outline, size: 18),
        onTap: onLocked,
      );
    }

    return ListTile(
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Every ${Format.interval(seconds)}'),
          Slider(
            value: seconds.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            label: Format.interval(seconds),
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.megabytes, required this.onChanged});

  final int megabytes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: const Text('Daily data budget'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$megabytes MB of probe traffic per day'),
          Slider(
            value: megabytes.toDouble().clamp(
              AppSettings.minDailyBudgetMb.toDouble(),
              AppSettings.maxDailyBudgetMb.toDouble(),
            ),
            min: AppSettings.minDailyBudgetMb.toDouble(),
            max: AppSettings.maxDailyBudgetMb.toDouble(),
            divisions:
                (AppSettings.maxDailyBudgetMb - AppSettings.minDailyBudgetMb) ~/
                5,
            label: '$megabytes MB',
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}
