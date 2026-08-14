import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/purchase_controller.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  ProviderSubscription<PurchaseController>? _subscription;

  @override
  void initState() {
    super.initState();
    // Messages arrive from the store's purchase stream, not from the button
    // press, so they are surfaced by listening rather than awaiting `buy()`.
    _subscription = ref.listenManual(
      purchaseControllerProvider,
      (_, controller) => _showMessage(controller),
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _showMessage(PurchaseController controller) {
    final message = controller.state.message;
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: controller.state.isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ));
    controller.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(purchaseControllerProvider);
    final state = controller.state;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Honest Signal Pro')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            state.isPro ? 'You have Pro' : 'One payment. Yours for good.',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Honest Signal is useful for free and always will be. Pro adds the '
            'parts power users ask for.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          const _Feature(
            icon: Icons.show_chart,
            title: 'History and graphs',
            body: 'See the last hour and the last 24 hours, so a connection '
                'that drops out only when you are not looking still gets caught.',
          ),
          if (Platform.isAndroid)
            const _Feature(
              icon: Icons.bubble_chart_outlined,
              title: 'Floating indicator',
              body: 'A tiny draggable bubble over other apps. Off by default; '
                  'you grant the permission yourself and can revoke it any time.',
            ),
          // Both bodies are platform-specific on purpose. The background
          // interval exists only on Android, and the daily data budget is
          // adjustable on *every* tier — `clampedForTier` never touches
          // `dailyBudgetMb` — so selling it here contradicted both store
          // listings, which say "on every tier" out loud.
          _Feature(
            icon: Icons.tune,
            title: 'Your own sampling rate',
            body: Platform.isAndroid
                ? 'Measure as often as every 2 seconds while the app is open, '
                      'and choose a background rate from once a minute to once '
                      'an hour.'
                : 'Measure as often as every 2 seconds while the app is open, '
                      'instead of the standard 5.',
          ),
          _Feature(
            icon: Icons.palette_outlined,
            title: 'Indicator themes',
            body: Platform.isAndroid
                ? 'Bars, dots or wave — in the app and in the status bar.'
                : 'Bars, dots or wave — in the app.',
          ),
          const SizedBox(height: 20),
          if (state.isPro)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Pro is unlocked on this device.')),
                  ],
                ),
              ),
            )
          else ...[
            FilledButton(
              onPressed: state.busy || !state.storeAvailable
                  ? null
                  : () => controller.buy(),
              child: state.busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      state.priceLabel == null
                          ? 'Unlock Pro'
                          : 'Unlock Pro — ${state.priceLabel}',
                    ),
            ),
            if (!state.storeAvailable) ...[
              const SizedBox(height: 10),
              Text(
                'The store is unreachable right now. Check your connection and '
                'try again — which, admittedly, is the whole point of this app.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: state.restoring ? null : () => controller.restore(),
              child: Text(
                state.restoring ? 'Restoring…' : 'Restore purchase',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'A single non-consumable purchase, billed by '
            '${Platform.isIOS ? 'Apple' : 'Google Play'}. No subscription, no '
            'account, no ads, and no data leaves your phone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
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
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
