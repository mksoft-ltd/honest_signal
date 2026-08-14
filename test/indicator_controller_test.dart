import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/indicator/data/indicator_controller.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

import 'fakes/fake_indicator_channel.dart';

/// Keeping the Android service and the floating bubble in step with the
/// settings *and* with the permissions the user actually granted.
///
/// The rules encoded here are the ones a store reviewer would look for: no
/// service without the notification permission, and no window drawn over other
/// apps without an explicit system grant.
void main() {
  group('permission gating', () {
    test('an already-granted permission starts the service without asking '
        'again', () async {
      final channel = FakeIndicatorChannel(notificationsGranted: true);
      final controller = IndicatorController(channel: channel);

      await controller.sync(const AppSettings());

      expect(channel.calls, isNot(contains('requestNotificationPermission')));
      expect(channel.starts, hasLength(1));
      expect(controller.status.serviceRunning, isTrue);
    });

    test(
      'the permission is requested when the user asks for the indicator',
      () async {
        final channel = FakeIndicatorChannel(
          notificationsGranted: false,
          notificationRequestGranted: true,
        );
        final controller = IndicatorController(channel: channel);

        await controller.sync(const AppSettings());

        expect(channel.calls, contains('requestNotificationPermission'));
        expect(channel.starts, hasLength(1));
      },
    );

    test('a declined permission leaves the service stopped rather than '
        'starting one nobody can see', () async {
      // The status-bar indicator *is* the notification. Starting a foreground
      // service the user cannot see would be a permission the app took without
      // a reason the user could observe.
      final channel = FakeIndicatorChannel(
        notificationsGranted: false,
        notificationRequestGranted: false,
      );
      final controller = IndicatorController(channel: channel);

      await controller.sync(const AppSettings());

      expect(channel.starts, isEmpty);
      expect(controller.status.serviceRunning, isFalse);
      expect(controller.status.notificationsAllowed, isFalse);
    });

    test('turning the indicator off stops the service', () async {
      final channel = FakeIndicatorChannel();
      final controller = IndicatorController(channel: channel);
      await controller.sync(const AppSettings());
      expect(channel.serviceRunning, isTrue);

      await controller.sync(
        const AppSettings(notificationIndicatorEnabled: false),
      );

      expect(channel.calls, contains('stopIndicator'));
      expect(controller.status.serviceRunning, isFalse);
    });

    test(
      'requesting the permission directly refreshes what the UI shows',
      () async {
        final channel = FakeIndicatorChannel(
          notificationsGranted: false,
          notificationRequestGranted: true,
        );
        final controller = IndicatorController(channel: channel);

        final granted = await controller.requestNotificationPermission();

        expect(granted, isTrue);
        expect(controller.status.notificationsAllowed, isTrue);
      },
    );
  });

  group('overlay', () {
    test(
      'is never started without the system grant, even when switched on',
      () async {
        // Play policy targets apps that begin drawing over other apps the moment
        // a grant appears. The switch is a request, not a trigger.
        final channel = FakeIndicatorChannel(overlayGranted: false);
        final controller = IndicatorController(channel: channel);

        await controller.sync(const AppSettings(overlayEnabled: true));

        expect(channel.calls, isNot(contains('startOverlay')));
        expect(channel.calls, contains('stopOverlay'));
        expect(controller.status.overlayRunning, isFalse);
      },
    );

    test('starts once the user has both switched it on and granted the '
        'permission', () async {
      final channel = FakeIndicatorChannel(overlayGranted: true);
      final controller = IndicatorController(channel: channel);

      await controller.sync(const AppSettings(overlayEnabled: true));

      expect(channel.calls, contains('startOverlay'));
      expect(controller.status.overlayRunning, isTrue);
      expect(controller.status.overlayAllowed, isTrue);
    });

    test('stays off when the status-bar service is disabled, because that '
        'service supplies the live score and lifetime', () async {
      final channel = FakeIndicatorChannel(overlayGranted: true);
      final controller = IndicatorController(channel: channel);

      await controller.sync(
        const AppSettings(
          notificationIndicatorEnabled: false,
          overlayEnabled: true,
        ),
      );

      expect(channel.calls, isNot(contains('startOverlay')));
      expect(channel.overlayRunning, isFalse);
    });

    test('stops the moment it is switched off, grant or no grant', () async {
      final channel = FakeIndicatorChannel(overlayGranted: true);
      final controller = IndicatorController(channel: channel);
      await controller.sync(const AppSettings(overlayEnabled: true));
      expect(channel.overlayRunning, isTrue);

      await controller.sync(const AppSettings(overlayEnabled: false));

      expect(channel.overlayRunning, isFalse);
    });

    test('a revoked grant stops the bubble on the next sync', () async {
      // The user can take the permission away in system settings at any time.
      final channel = FakeIndicatorChannel(overlayGranted: true);
      final controller = IndicatorController(channel: channel);
      await controller.sync(const AppSettings(overlayEnabled: true));

      channel.overlayGranted = false;
      await controller.sync(const AppSettings(overlayEnabled: true));

      expect(channel.overlayRunning, isFalse);
    });

    test('opening the system settings screen is all the app can do', () async {
      final channel = FakeIndicatorChannel();
      final controller = IndicatorController(channel: channel);

      await controller.openOverlayPermissionSettings();

      expect(channel.calls, contains('openOverlaySettings'));
    });
  });

  group('service configuration', () {
    test(
      'the service is started with the settings actually in force',
      () async {
        final channel = FakeIndicatorChannel();
        final controller = IndicatorController(channel: channel);

        await controller.sync(
          const AppSettings(
            backgroundIntervalSeconds: 600,
            dailyBudgetMb: 50,
            barTheme: BarTheme.wave,
            measureOnCellular: false,
          ),
        );

        expect(channel.starts.single, {
          'theme': 'wave',
          'highContrast': true,
          'intervalSeconds': 600,
          'budgetLimitBytes': 50 * 1024 * 1024,
          'measureOnCellular': false,
          'uiActive': true,
        });
      },
    );

    test(
      'the service is started with the high-contrast choice, not a default',
      () async {
        // N4, the other end of the same wire: the fixture above leaves
        // `highContrastIndicator` at its default `true`, so it passes against a
        // hardcoded literal. This one cannot.
        final channel = FakeIndicatorChannel();
        final controller = IndicatorController(channel: channel);

        await controller.sync(
          const AppSettings(highContrastIndicator: false),
        );

        expect(channel.starts.single['highContrast'], isFalse);
      },
    );

    test('a free install starts the service on the free-tier values', () async {
      // `clampedForTier` is what the app passes here, so a lapsed Pro user's
      // one-second interval never reaches the service.
      final channel = FakeIndicatorChannel();
      final controller = IndicatorController(channel: channel);

      await controller.sync(
        const AppSettings(
          backgroundIntervalSeconds: 60,
          barTheme: BarTheme.dots,
        ).clampedForTier(isPro: false),
      );

      expect(
        channel.starts.single['intervalSeconds'],
        AppSettings.defaultBackgroundInterval,
      );
      expect(channel.starts.single['theme'], BarTheme.bars.name);
    });
  });

  group('platforms without an out-of-app indicator', () {
    test('report nothing available', () async {
      final channel = FakeIndicatorChannel(supported: false);
      final controller = IndicatorController(channel: channel);

      await controller.refresh();

      expect(controller.status.supported, isFalse);
      expect(controller.status.serviceRunning, isFalse);
      expect(channel.calls, isEmpty);
    });

    test('are never asked to start anything', () async {
      // On iOS every one of these calls is a no-op; syncing must not pretend
      // otherwise or the settings screen would show a service that cannot run.
      final channel = FakeIndicatorChannel(supported: false);
      final controller = IndicatorController(channel: channel);

      await controller.sync(const AppSettings(overlayEnabled: true));

      expect(channel.calls, isEmpty);
    });
  });

  test('refresh mirrors what the service reports', () async {
    final channel =
        FakeIndicatorChannel(notificationsGranted: true, overlayGranted: true)
          ..serviceRunning = true
          ..overlayRunning = true;
    final controller = IndicatorController(channel: channel);

    await controller.refresh();

    expect(controller.status.supported, isTrue);
    expect(controller.status.serviceRunning, isTrue);
    expect(controller.status.notificationsAllowed, isTrue);
    expect(controller.status.overlayAllowed, isTrue);
    expect(controller.status.overlayRunning, isTrue);
  });
}
