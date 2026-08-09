import 'package:hive/hive.dart';

import '../../measurement/domain/data_budget.dart';
import '../domain/app_settings.dart';

/// Reads and writes everything that lives in the settings box.
class SettingsRepository {
  SettingsRepository(this._box);

  final Box<dynamic> _box;

  static const String _settingsKey = 'settings';
  static const String _budgetKey = 'budget';
  static const String _proKey = 'pro_unlocked';

  AppSettings load() {
    final raw = _box.get(_settingsKey);
    if (raw is Map) return AppSettings.fromJson(raw);
    return const AppSettings();
  }

  Future<void> save(AppSettings settings) =>
      _box.put(_settingsKey, settings.toJson());

  DataBudget loadBudget(DateTime now, int limitBytes) {
    final raw = _box.get(_budgetKey);
    if (raw is Map) {
      return DataBudget.fromJson(
        raw,
        fallbackLimit: limitBytes,
      ).normalisedFor(now, limitBytes);
    }
    return DataBudget.empty(now, limitBytes);
  }

  Future<void> saveBudget(DataBudget budget) =>
      _box.put(_budgetKey, budget.toJson());

  /// Cached entitlement so the app opens in the right tier before the store
  /// connection resolves. A verified purchase or restore can set this flag;
  /// it is not cleared merely because a launch is offline or the store is
  /// unavailable.
  bool loadProUnlocked() => _box.get(_proKey) as bool? ?? false;

  Future<void> saveProUnlocked(bool value) => _box.put(_proKey, value);
}
