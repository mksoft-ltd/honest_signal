import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/purchase_controller.dart';
import '../domain/purchase_state.dart';
import '../domain/pro_teaser.dart';

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
    _subscription = ref.listenManual(purchaseControllerProvider, (
      _,
      controller,
    ) {
      _showMessage(controller);
      _maybeAskForReview(controller);
    });
    _wasPro = ref.read(purchaseControllerProvider).state.isPro;
  }

  bool _wasPro = false;

  /// Just after a purchase is the best moment the app gets: the user has
  /// decided it is worth money. The delay lets the store's own sheet finish
  /// dismissing first, so the two never collide.
  void _maybeAskForReview(PurchaseController controller) {
    final isPro = controller.state.isPro;
    if (isPro && !_wasPro) {
      final prompter = ref.read(reviewPrompterProvider);
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) prompter.maybePrompt(currentBars: 5, afterPurchase: true);
      });
    }
    _wasPro = isPro;
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
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: controller.state.isError
              ? Theme.of(context).colorScheme.errorContainer
              : null,
        ),
      );
    controller.clearMessage();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(purchaseControllerProvider);
    final state = controller.state;
    final teaser = ref.watch(proTeaserProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Honest Signal Pro')),
      // The button sits outside the scroll view so the price and the way to
      // pay are on screen from the first frame, not below the fold.
      bottomNavigationBar: state.isPro
          ? null
          : _PurchaseBar(state: state, controller: controller),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            state.isPro
                ? 'You have Pro'
                // Only Android measures in the background, so only Android
                // can promise the drop-outs the user did not see.
                : Platform.isAndroid
                ? 'Catch every drop-out, not just the ones you see'
                : 'Every drop-out on record, with the times to prove it',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Honest Signal is useful for free and always will be. Pro adds the '
            'record and the controls — for one payment, not a subscription.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (state.isPro) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Pro is unlocked on this device.'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (!state.isPro && teaser != null) ...[
            const SizedBox(height: 20),
            _AlreadyRecorded(teaser: teaser),
          ],
          const SizedBox(height: 28),
          _Feature(
            icon: Icons.show_chart,
            title: '30 days of history',
            body: Platform.isAndroid
                ? 'The last hour, day, week or month as a chart, with every '
                      'drop-out listed by time and length and split by Wi-Fi '
                      'and mobile — so a connection that fails when you are '
                      'not looking still gets caught.'
                : 'The last hour, day, week or month of readings taken while '
                      'the app is open, as a chart, with every drop-out listed '
                      'by time and length and split by Wi-Fi and mobile.',
          ),
          const _Feature(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Evidence reports',
            body:
                'Export a PDF of every drop-out with dates and durations, or '
                'every reading as a spreadsheet, ready to send to your '
                'broadband or mobile provider.',
          ),
          if (Platform.isAndroid)
            const _Feature(
              icon: Icons.notifications_active_outlined,
              title: 'Drop-out alerts',
              body:
                  'A notification when the connection has been down for as '
                  'long as you choose, and another when it is back.',
            ),
          if (Platform.isAndroid)
            const _Feature(
              icon: Icons.bubble_chart_outlined,
              title: 'Floating indicator',
              body:
                  'A tiny draggable bubble over other apps. Off by default; '
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
                      'and choose a slower background rate when you want to '
                      'save battery or data.'
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
          const _Feature(
            icon: Icons.favorite_outline,
            title: 'Keeps an ad-free app going',
            body:
                'No ads, no tracking and no subscription means Pro is the only '
                'thing that pays for Honest Signal. Thank you.',
          ),
          const SizedBox(height: 16),
          Text(
            'A single non-consumable purchase, billed by '
            '${Platform.isIOS ? 'Apple' : 'Google Play'}. No subscription, no '
            'account or ads. Measurements and settings stay on this device.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The free tier's own recorded history, quoted back. History is recorded on
/// every tier, so this states a fact about the device rather than a promise.
class _AlreadyRecorded extends StatelessWidget {
  const _AlreadyRecorded({required this.teaser});

  final ProTeaser teaser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = AppColors.of(context);
    final hasDrops = teaser.dropouts > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasDrops
                  ? Icons.signal_cellular_connected_no_internet_0_bar
                  : Icons.history,
              color: hasDrops ? colours.dead : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasDrops
                        ? '${teaser.dropoutPhrase} in the last 24 hours'
                        : 'Already recording',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasDrops
                        ? 'Honest Signal logged ${teaser.readings} readings on '
                              'this phone, and your connection fell to 0–1 bars '
                              '${teaser.dropouts == 1 ? 'once' : '${teaser.dropouts} separate times'}. '
                              'Pro shows exactly when, and for how long.'
                        : 'Honest Signal has logged ${teaser.readings} readings '
                              'on this phone in the last 24 hours. Pro shows them '
                              'as a chart, so the next drop-out is on record.',
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
    );
  }
}

class _PurchaseBar extends StatelessWidget {
  const _PurchaseBar({required this.state, required this.controller});

  final PurchaseState state;
  final PurchaseController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
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
              const SizedBox(height: 6),
              Text(
                'Pay once · Yours for good · No subscription',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!state.storeAvailable) ...[
                const SizedBox(height: 8),
                Text(
                  'The store is unreachable right now. Check your connection '
                  'and try again — which, admittedly, is the whole point of '
                  'this app.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  onPressed: controller.init,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry store'),
                ),
              ],
              TextButton(
                onPressed: state.restoring ? null : () => controller.restore(),
                child: Text(
                  state.restoring ? 'Restoring…' : 'Restore purchase',
                ),
              ),
            ],
          ),
        ),
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
    );
  }
}
