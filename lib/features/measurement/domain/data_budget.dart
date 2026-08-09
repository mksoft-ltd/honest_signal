import 'package:flutter/foundation.dart';

/// How much probe traffic today has cost so far.
///
/// The app spends the user's data without them watching, so the budget is a
/// hard stop rather than a guideline, and the counter is shown in the UI.
@immutable
class DataBudget {
  const DataBudget({
    required this.dayKey,
    required this.bytesUsed,
    required this.limitBytes,
  });

  /// Local calendar day, `yyyy-mm-dd`. Local rather than UTC so "today's usage"
  /// matches what the user's carrier and their intuition both call today.
  final String dayKey;
  final int bytesUsed;
  final int limitBytes;

  double get fraction =>
      limitBytes <= 0 ? 1 : (bytesUsed / limitBytes).clamp(0.0, 1.0);

  bool get isExhausted => bytesUsed >= limitBytes;

  int get bytesRemaining => (limitBytes - bytesUsed).clamp(0, limitBytes);

  static String keyFor(DateTime when) =>
      '${when.year.toString().padLeft(4, '0')}-'
      '${when.month.toString().padLeft(2, '0')}-'
      '${when.day.toString().padLeft(2, '0')}';

  /// Rolls the counter over when the calendar day changes, and picks up a
  /// changed limit from settings.
  DataBudget normalisedFor(DateTime now, int limitBytes) {
    final key = keyFor(now);
    if (key != dayKey) {
      return DataBudget(dayKey: key, bytesUsed: 0, limitBytes: limitBytes);
    }
    if (limitBytes != this.limitBytes) {
      return DataBudget(dayKey: dayKey, bytesUsed: bytesUsed, limitBytes: limitBytes);
    }
    return this;
  }

  DataBudget spend(int bytes) => DataBudget(
        dayKey: dayKey,
        bytesUsed: bytesUsed + bytes,
        limitBytes: limitBytes,
      );

  Map<String, dynamic> toJson() => {
        'day': dayKey,
        'used': bytesUsed,
        'limit': limitBytes,
      };

  static DataBudget fromJson(Map<dynamic, dynamic> json, {required int fallbackLimit}) =>
      DataBudget(
        dayKey: json['day'] as String? ?? '',
        bytesUsed: (json['used'] as num?)?.toInt() ?? 0,
        limitBytes: (json['limit'] as num?)?.toInt() ?? fallbackLimit,
      );

  static DataBudget empty(DateTime now, int limitBytes) =>
      DataBudget(dayKey: keyFor(now), bytesUsed: 0, limitBytes: limitBytes);
}
