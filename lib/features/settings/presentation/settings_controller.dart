import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../domain/app_settings.dart';

/// Holds the stored settings exactly as the user set them.
///
/// Pro-only values are *not* stripped here — see [AppSettings.clampedForTier]
/// and `effectiveSettingsProvider`, so that a user who buys Pro, customises,
/// and later gets refunded still finds their choices intact if they buy again.
class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._repository) : super(_repository.load());

  final SettingsRepository _repository;

  Future<void> update(AppSettings Function(AppSettings) transform) async {
    final next = transform(state);
    state = next;
    await _repository.save(next);
  }
}
