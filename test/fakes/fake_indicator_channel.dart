import 'package:honestsignal/features/indicator/data/indicator_channel.dart';

/// Stands in for the Android side of the indicator bridge.
///
/// The real channel is a no-op on anything but Android, and the host running
/// these tests is neither, so without this fake every Android indicator path —
/// including the permission gating that Play policy cares about — would be
/// silently skipped.
class FakeIndicatorChannel extends IndicatorChannel {
  FakeIndicatorChannel({
    this.supported = true,
    this.notificationsGranted = true,
    this.notificationRequestGranted = true,
    this.overlayGranted = false,
  });

  bool supported;

  /// What `hasNotificationPermission` answers before any request.
  bool notificationsGranted;

  /// What the runtime permission dialog would return.
  bool notificationRequestGranted;

  /// Whether SYSTEM_ALERT_WINDOW has been granted in system settings.
  bool overlayGranted;

  bool serviceRunning = false;
  bool overlayRunning = false;

  final List<String> calls = [];
  final List<Map<String, Object?>> starts = [];
  final List<Map<String, Object?>> configUpdates = [];
  final List<Map<String, Object?>> published = [];
  final List<bool> uiActive = [];

  @override
  bool get isSupported => supported;

  @override
  Future<bool> isRunning() async {
    calls.add('isIndicatorRunning');
    return serviceRunning;
  }

  @override
  Future<void> start({
    required String theme,
    required bool highContrast,
    required int intervalSeconds,
    required int budgetLimitBytes,
    required bool measureOnCellular,
    required bool uiActive,
  }) async {
    calls.add('startIndicator');
    starts.add({
      'theme': theme,
      'highContrast': highContrast,
      'intervalSeconds': intervalSeconds,
      'budgetLimitBytes': budgetLimitBytes,
      'measureOnCellular': measureOnCellular,
      'uiActive': uiActive,
    });
    serviceRunning = true;
  }

  @override
  Future<void> stop() async {
    calls.add('stopIndicator');
    serviceRunning = false;
  }

  @override
  Future<void> updateConfig({
    required String theme,
    required bool highContrast,
    required int intervalSeconds,
    required int budgetLimitBytes,
    required bool measureOnCellular,
  }) async {
    calls.add('updateConfig');
    configUpdates.add({
      'theme': theme,
      'highContrast': highContrast,
      'intervalSeconds': intervalSeconds,
      'budgetLimitBytes': budgetLimitBytes,
      'measureOnCellular': measureOnCellular,
    });
  }

  @override
  Future<void> publishSample({
    required int bars,
    required String verdict,
    required String detail,
    required String theme,
    required bool highContrast,
    required int uiIntervalSeconds,
  }) async {
    calls.add('publishSample');
    published.add({
      'bars': bars,
      'verdict': verdict,
      'detail': detail,
      'theme': theme,
      'highContrast': highContrast,
      'uiIntervalSeconds': uiIntervalSeconds,
    });
  }

  @override
  Future<void> setUiActive({required bool active}) async {
    calls.add('setUiActive');
    uiActive.add(active);
  }

  @override
  Future<bool> hasNotificationPermission() async {
    calls.add('notificationPermissionStatus');
    return notificationsGranted;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    calls.add('requestNotificationPermission');
    notificationsGranted = notificationRequestGranted;
    return notificationRequestGranted;
  }

  @override
  Future<bool> canDrawOverlays() async {
    calls.add('canDrawOverlays');
    return overlayGranted;
  }

  @override
  Future<void> openOverlaySettings() async => calls.add('openOverlaySettings');

  @override
  Future<void> startOverlay() async {
    calls.add('startOverlay');
    overlayRunning = true;
  }

  @override
  Future<void> stopOverlay() async {
    calls.add('stopOverlay');
    overlayRunning = false;
  }

  @override
  Future<bool> isOverlayRunning() async {
    calls.add('isOverlayRunning');
    return overlayRunning;
  }
}
