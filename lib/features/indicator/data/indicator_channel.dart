import 'dart:io';

import 'package:flutter/services.dart';

/// The Dart half of the Android status-bar indicator bridge.
///
/// Every method is a no-op returning a safe default on iOS, so callers never
/// need a platform check. The channel names are shared with
/// `android/app/src/main/kotlin/.../IndicatorPlugin.kt` — change both together.
class IndicatorChannel {
  IndicatorChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.froggyeye.honestsignal/indicator';

  final MethodChannel _channel;

  /// Only Android can show an always-visible indicator outside the app.
  bool get isSupported => Platform.isAndroid;

  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? args]) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      // The indicator is a convenience layer; a failure to reach the service
      // must never take down the in-app meter, which is the actual product.
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> isRunning() async =>
      await _invoke<bool>('isIndicatorRunning') ?? false;

  Future<void> start({
    required String theme,
    required bool highContrast,
    required int intervalSeconds,
    required int budgetLimitBytes,
    required bool measureOnCellular,
    required bool uiActive,
    bool alertsEnabled = false,
    int alertBars = 1,
    int alertMinutes = 2,
  }) => _invoke<void>('startIndicator', {
    'theme': theme,
    'highContrast': highContrast,
    'intervalSeconds': intervalSeconds,
    'budgetLimitBytes': budgetLimitBytes,
    'measureOnCellular': measureOnCellular,
    'uiActive': uiActive,
    'alertsEnabled': alertsEnabled,
    'alertBars': alertBars,
    'alertMinutes': alertMinutes,
  });

  Future<void> stop() => _invoke<void>('stopIndicator');

  /// Refreshes the home-screen widget and Quick Settings tile with a reading
  /// taken in the app. Never starts the indicator service: the widget is free
  /// and works with the indicator switched off.
  Future<void> updateWidgets({
    required int bars,
    required String verdict,
    required String detail,
    required DateTime timestamp,
    required String theme,
  }) => _invoke<void>('updateWidgets', {
    'bars': bars,
    'verdict': verdict,
    'detail': detail,
    'timestampMs': timestamp.millisecondsSinceEpoch,
    'theme': theme,
  });

  /// The in-app route a notification asked to open (e.g. `/history` from a
  /// drop-out alert), consumed once.
  Future<String?> takeLaunchRoute() => _invoke<String>('takeLaunchRoute');

  /// True, once, after the user tapped "Turn off" on the indicator
  /// notification while the app was not looking.
  Future<bool> takeStoppedFromNotification() async =>
      await _invoke<bool>('takeStoppedFromNotification') ?? false;

  /// Pushes a sample measured by the UI isolate so the status-bar icon stays
  /// live without the background isolate duplicating the work.
  Future<void> publishSample({
    required int bars,
    required String verdict,
    required String detail,
    required String theme,
    required bool highContrast,
    required int uiIntervalSeconds,
  }) => _invoke<void>('publishSample', {
    'bars': bars,
    'verdict': verdict,
    'detail': detail,
    'theme': theme,
    'highContrast': highContrast,
    // A foreground reading is also an acknowledgement that the UI is
    // still alive. The Android service treats this as a renewable lease.
    'uiActive': true,
    // How often the next renewal is due. A flat lease shorter than the
    // publishing cadence expires between publishes, and the service then runs
    // the duplicate cycle the lease exists to prevent — reachable on Pro, whose
    // foreground interval also goes up to 60 s.
    'uiIntervalSeconds': uiIntervalSeconds,
  });

  /// Tells the service whether the UI is measuring, so the background isolate
  /// can stay idle instead of probing in parallel with it.
  Future<void> setUiActive({required bool active}) =>
      _invoke<void>('setUiActive', {'active': active});

  Future<bool> hasNotificationPermission() async =>
      await _invoke<bool>('notificationPermissionStatus') ?? false;

  Future<bool> requestNotificationPermission() async =>
      await _invoke<bool>('requestNotificationPermission') ?? false;

  Future<void> openNotificationSettings() =>
      _invoke<void>('openNotificationSettings');

  Future<bool> canDrawOverlays() async =>
      await _invoke<bool>('canDrawOverlays') ?? false;

  /// Opens the system "Display over other apps" screen. Android gives no
  /// in-app grant path for this permission.
  Future<void> openOverlaySettings() => _invoke<void>('openOverlaySettings');

  Future<void> startOverlay() => _invoke<void>('startOverlay');

  Future<void> stopOverlay() => _invoke<void>('stopOverlay');

  Future<bool> isOverlayRunning() async =>
      await _invoke<bool>('isOverlayRunning') ?? false;
}
