import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/pro_lock.dart';

/// Explains and gates the floating overlay.
///
/// SYSTEM_ALERT_WINDOW is the app's most intrusive permission, so it gets a
/// whole screen: what it draws, why it needs the grant, and how to take it
/// away. The permission is only ever requested after the user asks for the
/// feature here.
class OverlaySetupScreen extends ConsumerStatefulWidget {
  const OverlaySetupScreen({super.key});

  @override
  ConsumerState<OverlaySetupScreen> createState() => _OverlaySetupScreenState();
}

class _OverlaySetupScreenState extends ConsumerState<OverlaySetupScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(indicatorControllerProvider).refresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The grant happens in system settings, so the only way to learn the
    // outcome is to re-check when the user comes back.
    if (state == AppLifecycleState.resumed) {
      ref.read(indicatorControllerProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);
    final indicator = ref.watch(indicatorControllerProvider);
    final settings = ref.watch(effectiveSettingsProvider);
    final status = indicator.status;

    return Scaffold(
      appBar: AppBar(title: const Text('Floating indicator')),
      body: !isPro
          ? ProLock(
              title: 'The floating indicator is a Pro feature',
              body:
                  'A tiny, semi-transparent bubble that stays on screen over '
                  'other apps so you can watch the real signal while you use '
                  'them. Drag it anywhere, tap it to come back here.',
              onUnlock: () => context.push('/pro'),
            )
          : ListView(
              padding: AppSpacing.page,
              children: [
                const _Explainer(),
                const SizedBox(height: 24),
                if (!settings.notificationIndicatorEnabled)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Turn on the status-bar indicator first. It keeps the '
                        'floating indicator alive and supplies its current '
                        'score while you use other apps.',
                      ),
                    ),
                  )
                else if (!status.overlayAllowed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Android needs your permission',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Drawing over other apps can only be switched on in '
                            'system settings. Honest Signal cannot grant it for '
                            'you, and you can revoke it in the same place at '
                            'any time.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => ref
                                .read(indicatorControllerProvider)
                                .openOverlayPermissionSettings(),
                            child: const Text('Open Android settings'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show the floating indicator'),
                    subtitle: const Text(
                      'Appears over other apps. Drag to move, tap to open '
                      'Honest Signal, long-press to hide.',
                    ),
                    value: settings.overlayEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(overlayEnabled: value)),
                  ),
              ],
            ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const points = [
      (
        Icons.crop_free,
        'Small and out of the way',
        'About the size of a status-bar icon, semi-transparent, and it never '
            'takes touch input away from the app underneath except on the '
            'bubble itself.',
      ),
      (
        Icons.open_with,
        'You decide where it sits',
        'Drag it anywhere on screen. It stays put between apps and across '
            'restarts.',
      ),
      (
        Icons.visibility_off_outlined,
        'Off unless you ask',
        'It never appears until you turn it on here, and switching it off '
            'stops it immediately. It uses the status-bar indicator service '
            'to stay current while you use other apps.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, title, body) in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        body,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
