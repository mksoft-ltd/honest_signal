import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/core/utils/formatters.dart';
import 'package:honestsignal/features/measurement/data/budget_store.dart';
import 'package:honestsignal/features/measurement/domain/data_budget.dart';
import 'package:honestsignal/features/settings/data/settings_repository.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

void main() {
  group('DataBudget', () {
    test('rolls the counter over when the calendar day changes', () {
      final today = DateTime(2026, 8, 7, 23, 59);
      final budget = DataBudget.empty(today, 1000).spend(900);
      expect(budget.bytesUsed, 900);

      final tomorrow = today.add(const Duration(minutes: 2));
      final rolled = budget.normalisedFor(tomorrow, 1000);
      expect(rolled.bytesUsed, 0);
      expect(rolled.dayKey, DataBudget.keyFor(tomorrow));
    });

    test('picks up a raised limit without losing today\'s usage', () {
      final now = DateTime(2026, 8, 7, 10);
      final budget = DataBudget.empty(now, 1000).spend(600);
      final raised = budget.normalisedFor(now, 5000);

      expect(raised.bytesUsed, 600);
      expect(raised.limitBytes, 5000);
      expect(raised.isExhausted, isFalse);
    });

    test('is exhausted at exactly the limit', () {
      final budget = DataBudget.empty(DateTime(2026, 8, 7), 1000).spend(1000);
      expect(budget.isExhausted, isTrue);
      expect(budget.bytesRemaining, 0);
      expect(budget.fraction, 1.0);
    });

    test('a broken platform channel reports the budget as spent, not free', () async {
      // Failing open would let a channel error spend unlimited mobile data.
      final store = PlatformBudgetStore(channel: const _DeadChannel());
      final budget = await store.read(now: DateTime(2026, 8, 7), limitBytes: 500);
      expect(budget.isExhausted, isTrue);
    });
  });

  group('AppSettings tier clamping', () {
    test('a free install is pinned to the default intervals and theme', () {
      const customised = AppSettings(
        foregroundIntervalSeconds: 2,
        backgroundIntervalSeconds: 60,
        barTheme: BarTheme.wave,
        overlayEnabled: true,
      );

      final free = customised.clampedForTier(isPro: false);

      expect(free.foregroundIntervalSeconds, AppSettings.defaultForegroundInterval);
      expect(free.backgroundIntervalSeconds, AppSettings.defaultBackgroundInterval);
      expect(free.barTheme, BarTheme.bars);
      expect(free.overlayEnabled, isFalse);
    });

    test('Pro keeps every customisation', () {
      const customised = AppSettings(
        foregroundIntervalSeconds: 2,
        barTheme: BarTheme.wave,
        overlayEnabled: true,
      );
      expect(customised.clampedForTier(isPro: true), same(customised));
    });

    test('clamping does not overwrite what was stored, so buying again '
        'restores the user\'s choices', () async {
      final store = await LocalStore.openInMemory();
      final repository = SettingsRepository(store.settings);

      await repository.save(const AppSettings(barTheme: BarTheme.wave));
      final reloaded = repository.load();

      expect(reloaded.barTheme, BarTheme.wave);
      expect(reloaded.clampedForTier(isPro: false).barTheme, BarTheme.bars);
      await store.close();
    });

    test('the daily data budget is adjustable on every tier', () {
      const settings = AppSettings(dailyBudgetMb: 100);
      expect(settings.clampedForTier(isPro: false).dailyBudgetMb, 100);
      expect(settings.dailyBudgetBytes, 100 * 1024 * 1024);
    });

    test('survives a round trip through storage', () {
      const original = AppSettings(
        notificationIndicatorEnabled: false,
        overlayEnabled: true,
        foregroundIntervalSeconds: 12,
        backgroundIntervalSeconds: 900,
        dailyBudgetMb: 60,
        barTheme: BarTheme.dots,
        measureOnCellular: false,
        themeMode: ThemeMode.dark,
        hasSeenOnboarding: true,
      );

      final restored = AppSettings.fromJson(original.toJson());

      expect(restored.notificationIndicatorEnabled, isFalse);
      expect(restored.overlayEnabled, isTrue);
      expect(restored.foregroundIntervalSeconds, 12);
      expect(restored.backgroundIntervalSeconds, 900);
      expect(restored.dailyBudgetMb, 60);
      expect(restored.barTheme, BarTheme.dots);
      expect(restored.measureOnCellular, isFalse);
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.hasSeenOnboarding, isTrue);
    });

    test('an empty stored map falls back to the free defaults', () {
      final defaults = AppSettings.fromJson(const {});
      expect(defaults.barTheme, BarTheme.bars);
      expect(defaults.overlayEnabled, isFalse);
      expect(defaults.notificationIndicatorEnabled, isTrue);
    });
  });

  group('Format', () {
    test('throughput switches to Mbps and names a stall', () {
      expect(Format.throughput(null), '—');
      expect(Format.throughput(0), 'stalled');
      expect(Format.throughput(640), '640 kbps');
      expect(Format.throughput(1500), '1.5 Mbps');
      expect(Format.throughput(48000), '48 Mbps');
    });

    test('bytes read as a human would say them', () {
      expect(Format.bytes(512), '512 B');
      expect(Format.bytes(2048), '2 KB');
      expect(Format.bytes(5 * 1024 * 1024), '5.0 MB');
      expect(Format.bytes(25 * 1024 * 1024), '25 MB');
    });

    test('age never rounds staleness away', () {
      final now = DateTime(2026, 8, 7, 12);
      expect(Format.age(now, now: now), 'just now');
      expect(Format.age(now.subtract(const Duration(seconds: 30)), now: now), '30s ago');
      expect(Format.age(now.subtract(const Duration(minutes: 7)), now: now), '7 min ago');
      expect(Format.age(now.subtract(const Duration(hours: 3)), now: now), '3 h ago');
      expect(Format.age(now.subtract(const Duration(days: 2)), now: now), '2 d ago');
    });

    test('intervals read naturally at every scale the sliders allow', () {
      expect(Format.interval(2), '2s');
      expect(Format.interval(45), '45s');
      expect(Format.interval(300), '5 min');
      expect(Format.interval(3600), '1 h');
    });
  });
}

/// Stands in for a platform channel that is not there — iOS before the Swift
/// handler is registered, or a genuine failure.
class _DeadChannel extends MethodChannel {
  const _DeadChannel() : super('test/dead');

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(String method, [dynamic arguments]) async {
    throw MissingPluginException('no handler');
  }
}
