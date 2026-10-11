import 'package:flutter/material.dart';

/// Shown in place of a Pro-only screen.
///
/// It states plainly what the feature does before asking for money — a locked
/// screen that only says "upgrade" is the pattern both stores' reviewers flag.
class ProLock extends StatelessWidget {
  const ProLock({
    super.key,
    required this.title,
    required this.body,
    required this.onUnlock,
    this.preview,
  });

  final String title;
  final String body;
  final VoidCallback onUnlock;

  /// Shown in place of the badge icon — e.g. the user's own recorded data,
  /// blurred, so the lock shows what is behind it rather than a padlock.
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              preview ??
                  Icon(
                    Icons.workspace_premium_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(onPressed: onUnlock, child: const Text('See Pro')),
            ],
          ),
        ),
      ),
    );
  }
}
