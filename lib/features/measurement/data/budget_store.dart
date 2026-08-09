import 'package:flutter/services.dart';

import '../domain/data_budget.dart';

/// Where the day's probe-byte counter lives.
///
/// It must be shared by the UI isolate and the Android background isolate, and
/// Hive is not safe across isolates, so the real implementation keeps the
/// counter on the native side (SharedPreferences / UserDefaults) and both
/// isolates read and write it through the same channel.
abstract class BudgetStore {
  Future<DataBudget> read({required DateTime now, required int limitBytes});
  Future<DataBudget> spend({
    required DateTime now,
    required int bytes,
    required int limitBytes,
  });
}

class PlatformBudgetStore implements BudgetStore {
  PlatformBudgetStore({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.froggyeye.honestsignal/budget';

  final MethodChannel _channel;

  @override
  Future<DataBudget> read({required DateTime now, required int limitBytes}) async {
    final result = await _call('budgetRead', {'day': DataBudget.keyFor(now)});
    return _toBudget(result, now, limitBytes);
  }

  @override
  Future<DataBudget> spend({
    required DateTime now,
    required int bytes,
    required int limitBytes,
  }) async {
    final result = await _call('budgetSpend', {
      'day': DataBudget.keyFor(now),
      'bytes': bytes,
    });
    return _toBudget(result, now, limitBytes);
  }

  Future<Map<dynamic, dynamic>?> _call(String method, Map<String, dynamic> args) async {
    try {
      return await _channel.invokeMapMethod<dynamic, dynamic>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// A failed read must not read as "budget free" — that would let a broken
  /// channel spend unlimited data. Report the limit as already consumed and let
  /// the caller fall back to probing only when the user explicitly refreshes.
  DataBudget _toBudget(Map<dynamic, dynamic>? raw, DateTime now, int limitBytes) {
    if (raw == null) {
      return DataBudget(
        dayKey: DataBudget.keyFor(now),
        bytesUsed: limitBytes,
        limitBytes: limitBytes,
      );
    }
    return DataBudget(
      dayKey: raw['day'] as String? ?? DataBudget.keyFor(now),
      bytesUsed: (raw['used'] as num?)?.toInt() ?? 0,
      limitBytes: limitBytes,
    );
  }
}

/// Used by tests and by the screenshot harness.
class InMemoryBudgetStore implements BudgetStore {
  DataBudget? _budget;

  @override
  Future<DataBudget> read({required DateTime now, required int limitBytes}) async {
    final current = (_budget ?? DataBudget.empty(now, limitBytes))
        .normalisedFor(now, limitBytes);
    _budget = current;
    return current;
  }

  @override
  Future<DataBudget> spend({
    required DateTime now,
    required int bytes,
    required int limitBytes,
  }) async {
    final current = await read(now: now, limitBytes: limitBytes);
    final next = current.spend(bytes);
    _budget = next;
    return next;
  }
}
