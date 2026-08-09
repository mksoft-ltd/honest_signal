import 'package:flutter/foundation.dart';

import '../../settings/domain/app_settings.dart';
import 'indicator_channel.dart';

/// Live state of the two Android indicators and the permissions they need.
@immutable
class IndicatorStatus {
  const IndicatorStatus({
    this.supported = false,
    this.serviceRunning = false,
    this.notificationsAllowed = false,
    this.overlayAllowed = false,
    this.overlayRunning = false,
  });

  /// False on iOS, where nothing can be drawn outside the app.
  final bool supported;
  final bool serviceRunning;
  final bool notificationsAllowed;

  /// SYSTEM_ALERT_WINDOW has been granted in system settings.
  final bool overlayAllowed;
  final bool overlayRunning;

  IndicatorStatus copyWith({
    bool? supported,
    bool? serviceRunning,
    bool? notificationsAllowed,
    bool? overlayAllowed,
    bool? overlayRunning,
  }) => IndicatorStatus(
    supported: supported ?? this.supported,
    serviceRunning: serviceRunning ?? this.serviceRunning,
    notificationsAllowed: notificationsAllowed ?? this.notificationsAllowed,
    overlayAllowed: overlayAllowed ?? this.overlayAllowed,
    overlayRunning: overlayRunning ?? this.overlayRunning,
  );
}

/// Keeps the Android foreground service and overlay in step with settings and
/// with the permissions the user has actually granted.
class IndicatorController extends ChangeNotifier {
  IndicatorController({required this._channel});

  final IndicatorChannel _channel;

  IndicatorStatus _status = const IndicatorStatus();
  IndicatorStatus get status => _status;

  Future<void> refresh() async {
    if (!_channel.isSupported) {
      _set(const IndicatorStatus());
      return;
    }
    _set(
      IndicatorStatus(
        supported: true,
        serviceRunning: await _channel.isRunning(),
        notificationsAllowed: await _channel.hasNotificationPermission(),
        overlayAllowed: await _channel.canDrawOverlays(),
        overlayRunning: await _channel.isOverlayRunning(),
      ),
    );
  }

  /// Brings the service and overlay in line with [settings], requesting the
  /// notification permission if the user has asked for the indicator but not
  /// yet granted it.
  Future<void> sync(AppSettings settings) async {
    if (!_channel.isSupported) return;

    if (settings.notificationIndicatorEnabled) {
      var allowed = await _channel.hasNotificationPermission();
      if (!allowed) allowed = await _channel.requestNotificationPermission();
      if (allowed) {
        await _channel.start(
          theme: settings.barTheme.name,
          intervalSeconds: settings.backgroundIntervalSeconds,
          budgetLimitBytes: settings.dailyBudgetBytes,
          measureOnCellular: settings.measureOnCellular,
          // sync only runs while the app is in the foreground. Including this
          // in the start intent closes the race where start()'s first UI-active
          // message arrives before the service exists.
          uiActive: true,
        );
      }
    } else {
      await _channel.stop();
    }

    // The overlay is never started implicitly: Android requires the user to
    // grant "display over other apps" in system settings, and an app that
    // silently starts drawing over other apps the moment the grant lands is
    // exactly the pattern Play policy targets.
    // OverlayService is intentionally kept alive by the same foreground
    // service as the status-bar indicator. Do not offer a bubble that would
    // display stale values or be killed by Android when that service is off.
    if (settings.notificationIndicatorEnabled &&
        settings.overlayEnabled &&
        await _channel.canDrawOverlays()) {
      await _channel.startOverlay();
    } else {
      await _channel.stopOverlay();
    }

    await refresh();
  }

  Future<void> openOverlayPermissionSettings() =>
      _channel.openOverlaySettings();

  Future<bool> requestNotificationPermission() async {
    final granted = await _channel.requestNotificationPermission();
    await refresh();
    return granted;
  }

  void _set(IndicatorStatus next) {
    _status = next;
    notifyListeners();
  }
}
