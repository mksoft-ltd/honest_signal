import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/signal_bars.dart';

/// First run: what the app does, and the one permission it will ask for.
///
/// The notification permission is requested from here rather than silently at
/// launch, so the system dialog arrives with context already on screen.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
          child: Column(
            children: [
              const Spacer(),
              const _Comparison(),
              const SizedBox(height: 36),
              Text(
                'Your signal icon is lying to you',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                'Full bars means the mast is loud, not that data is moving. '
                'Honest Signal actually uses the connection — timing real '
                'requests and real transfers — and scores what it can do.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              if (Platform.isAndroid)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(
                    'Next, Android will ask whether Honest Signal may show '
                    'notifications. That is how the live score appears in your '
                    'status bar. You can say no and still use the app.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              FilledButton(
                onPressed: () async {
                  await ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(hasSeenOnboarding: true));
                  await ref
                      .read(indicatorControllerProvider)
                      .sync(ref.read(effectiveSettingsProvider));
                  if (context.mounted) context.go('/');
                },
                child: const Text('Measure my connection'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Column(
          children: [
            SignalBars(
              bars: 5,
              size: 76,
              animate: false,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text('What your phone says', style: theme.textTheme.labelSmall),
          ],
        ),
        const SizedBox(width: 28),
        Icon(Icons.arrow_forward, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 28),
        Column(
          children: [
            const SignalBars(bars: 1, size: 76, animate: false),
            const SizedBox(height: 10),
            Text(
              'What it can do',
              style: theme.textTheme.labelSmall
                  ?.copyWith(
                    color: AppColors.of(context).poor,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
