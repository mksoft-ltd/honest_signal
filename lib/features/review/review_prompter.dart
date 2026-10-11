import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../core/demo/screenshot_mode.dart';

/// The store's own review sheet, behind a seam so tests never touch the
/// plugin.
abstract class ReviewRequester {
  Future<bool> isAvailable();
  Future<void> requestReview();
  Future<void> openStoreListing();
}

class PluginReviewRequester implements ReviewRequester {
  /// App Store Connect Apple ID. `openStoreListing` needs it on iOS; Android
  /// resolves the listing from the package name.
  static const String appStoreId = '6799269422';

  final InAppReview _plugin = InAppReview.instance;

  @override
  Future<bool> isAvailable() async {
    if (ScreenshotMode.isEnabled) return false;
    try {
      return await _plugin.isAvailable();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> requestReview() async {
    try {
      await _plugin.requestReview();
    } on Object {
      // A review prompt is never worth an error on screen.
    }
  }

  @override
  Future<void> openStoreListing() async {
    try {
      await _plugin.openStoreListing(appStoreId: appStoreId);
    } on Object {
      // Nothing useful to say; the tile simply does nothing.
    }
  }
}

/// Decides when to show the store's review sheet.
///
/// Uses the system sheet only, with no "are you enjoying the app?" pre-prompt:
/// Apple forbids custom review prompts and Google forbids filtering who gets
/// the real one, and gating on sentiment is the dark pattern this app avoids.
/// What it *does* choose is the moment — after the user has come back on
/// several days and is looking at a good reading, or just after buying Pro —
/// because a sheet that interrupts a dead connection only collects one-star
/// reviews of the user's mast.
///
/// Both stores rate-limit the sheet themselves and may silently show nothing;
/// the local cooldown keeps the app from even asking often.
class ReviewPrompter {
  ReviewPrompter(this._box, this._requester, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Box<dynamic> _box;
  final ReviewRequester _requester;
  final DateTime Function() _clock;

  static const String _key = 'review';

  static const int minDaysUsed = 3;
  static const Duration minInstallAge = Duration(days: 4);
  static const Duration cooldown = Duration(days: 120);
  static const int maxPrompts = 3;

  /// Time the app must have been in use this session before the sheet may
  /// appear, so it never lands on top of the very first frame.
  static const Duration minSessionAge = Duration(seconds: 20);

  DateTime? _sessionStart;
  bool _askedThisSession = false;

  /// Called whenever the app comes to the foreground.
  Future<void> recordUse() async {
    final now = _clock();
    _sessionStart = now;
    final state = _load();
    final today = _dayKey(now);
    if (state.lastDay == today) return;
    await _save(
      state.copyWith(
        firstUse: state.firstUse ?? now,
        daysUsed: state.daysUsed + 1,
        lastDay: today,
      ),
    );
  }

  /// Asks for a review if every condition holds. [afterPurchase] skips the
  /// days-of-use requirement — someone who has just paid has already decided
  /// the app is worth something — but never the cooldown.
  Future<bool> maybePrompt({
    required int currentBars,
    bool afterPurchase = false,
  }) async {
    if (!shouldPrompt(currentBars: currentBars, afterPurchase: afterPurchase)) {
      return false;
    }
    _askedThisSession = true;
    if (!await _requester.isAvailable()) return false;
    final state = _load();
    await _save(
      state.copyWith(lastPrompt: _clock(), prompts: state.prompts + 1),
    );
    await _requester.requestReview();
    return true;
  }

  @visibleForTesting
  bool shouldPrompt({required int currentBars, bool afterPurchase = false}) {
    if (_askedThisSession) return false;
    final now = _clock();
    final state = _load();
    if (state.prompts >= maxPrompts) return false;
    final last = state.lastPrompt;
    if (last != null && now.difference(last) < cooldown) return false;
    if (afterPurchase) return true;

    final session = _sessionStart;
    if (session == null || now.difference(session) < minSessionAge) {
      return false;
    }
    if (currentBars < 4) return false;
    final first = state.firstUse;
    if (first == null || now.difference(first) < minInstallAge) return false;
    return state.daysUsed >= minDaysUsed;
  }

  Future<void> openStoreListing() => _requester.openStoreListing();

  _ReviewState _load() {
    final raw = _box.get(_key);
    return raw is Map ? _ReviewState.fromJson(raw) : const _ReviewState();
  }

  Future<void> _save(_ReviewState state) => _box.put(_key, state.toJson());

  static String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';
}

@immutable
class _ReviewState {
  const _ReviewState({
    this.firstUse,
    this.daysUsed = 0,
    this.lastDay,
    this.lastPrompt,
    this.prompts = 0,
  });

  final DateTime? firstUse;
  final int daysUsed;
  final String? lastDay;
  final DateTime? lastPrompt;
  final int prompts;

  _ReviewState copyWith({
    DateTime? firstUse,
    int? daysUsed,
    String? lastDay,
    DateTime? lastPrompt,
    int? prompts,
  }) => _ReviewState(
    firstUse: firstUse ?? this.firstUse,
    daysUsed: daysUsed ?? this.daysUsed,
    lastDay: lastDay ?? this.lastDay,
    lastPrompt: lastPrompt ?? this.lastPrompt,
    prompts: prompts ?? this.prompts,
  );

  Map<String, dynamic> toJson() => {
    'first': firstUse?.millisecondsSinceEpoch,
    'days': daysUsed,
    'lastDay': lastDay,
    'lastPrompt': lastPrompt?.millisecondsSinceEpoch,
    'prompts': prompts,
  };

  static _ReviewState fromJson(Map<dynamic, dynamic> json) {
    DateTime? time(Object? v) =>
        v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    return _ReviewState(
      firstUse: time(json['first']),
      daysUsed: (json['days'] as num?)?.toInt() ?? 0,
      lastDay: json['lastDay'] as String?,
      lastPrompt: time(json['lastPrompt']),
      prompts: (json['prompts'] as num?)?.toInt() ?? 0,
    );
  }
}
