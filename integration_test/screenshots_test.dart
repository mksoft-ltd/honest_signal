import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:honestsignal/core/demo/screenshot_mode.dart';
import 'package:honestsignal/main.dart' as app;

/// Store-screenshot harness.
///
/// Run with the demo data switched on, otherwise it captures whatever the real
/// network happens to be doing on the build machine:
///
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/screenshots_test.dart \
///     --dart-define=SCREENSHOT_MODE=true
///
/// Add `--dart-define=SCREENSHOT_TIER=free` for the paywall and locked states.
///
/// `flutter drive` rather than `flutter test`: only the driver writes the PNGs
/// to disk. Capture on Android — `convertFlutterSurfaceToImage` is Android-only
/// and the iOS simulator hands `takeScreenshot` the launch-screen layer for
/// every shot while the widget assertions still pass. See docs/TEST_PLAN.md.
///
/// `pumpAndSettle` is deliberately never used: the home screen runs a periodic
/// measurement timer and the freshness line ticks every five seconds, so
/// settling never completes and the harness would hang instead of failing.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  // `convertFlutterSurfaceToImage` asserts it has not already run
  // (`!_isSurfaceRendered`), so it converts once for the whole run rather than
  // once per shot. Calling it per shot throws "Surface already converted to an
  // image" on the second capture, which silently leaves a store submission with
  // exactly one screenshot.
  var surfaceConverted = false;

  Future<void> shoot(WidgetTester tester, String name) async {
    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
    }
    await tester.pump();
    await binding.takeScreenshot(name);
  }

  /// Reports which tier these captures came from, so the driver can record it
  /// as `raw/tier.txt`.
  ///
  /// `render.sh` refuses to frame the marketing set from a free-tier capture: on
  /// a free run the history route renders the Pro lock, and framing that under a
  /// headline promising a chart would ship a listing that advertises a graph and
  /// shows a paywall. Only the device knows which tier it was built with.
  ///
  /// This rides `reportData` rather than `takeScreenshot`'s `args`, which is
  /// implemented for web only — on Android and iOS it asserts `args == null`.
  void reportTier() {
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!['tier'] = ScreenshotMode.isPro ? 'pro' : 'free';
  }

  /// Fails with the name of the thing that could not be found.
  ///
  /// The default "found 0 widgets" says nothing about which screen the harness
  /// was on, and this runs unattended in the publish stage.
  void require(Finder finder, String what) {
    if (finder.evaluate().isEmpty) {
      fail('Screenshot harness could not find $what. The UI copy or icon it '
          'keys off has changed — update this harness alongside it.');
    }
  }

  Future<void> tapIcon(WidgetTester tester, IconData icon, String what) async {
    final finder = find.byIcon(icon);
    require(finder, what);
    await tester.tap(finder);
    await settle(tester);
  }

  /// Leaves the current route.
  ///
  /// `Icons.arrow_back` is the Android back chevron only; on iOS the AppBar
  /// inserts `arrow_back_ios_new`, so keying off the icon would break every
  /// iOS run. `pageBack` finds whichever one the platform used.
  Future<void> goBack(WidgetTester tester) async {
    await tester.pageBack();
    await settle(tester);
  }

  testWidgets('capture store screenshots', (tester) async {
    reportTier();
    await app.main();
    await settle(tester, 30);

    // The app may open on onboarding depending on the seeded settings box.
    final start = find.text('Measure my connection');
    if (start.evaluate().isNotEmpty) {
      await shoot(tester, '00_onboarding');
      await tester.tap(start);
      await settle(tester, 20);
    }

    require(find.text('Honest Signal'), 'the home screen app bar');
    await shoot(tester, '01_home');

    await tapIcon(tester, Icons.show_chart, 'the History button');
    await shoot(tester, '02_history');
    await goBack(tester);

    await tapIcon(tester, Icons.settings_outlined, 'the Settings button');
    await shoot(tester, '03_settings');

    final howItWorks = find.text('How the score works');
    await tester.scrollUntilVisible(
      howItWorks,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    require(howItWorks, 'the "How the score works" row in Settings');
    await tester.tap(howItWorks);
    await settle(tester);
    await shoot(tester, '04_how_it_works');
    await goBack(tester);

    // Back to the home screen so a later run in the same session starts from a
    // known route — the router outlives an individual drive test.
    await goBack(tester);

    // Only the free tier shows the Pro entry point, so this is the shot that
    // needs --dart-define=SCREENSHOT_TIER=free.
    final pro = find.text('Honest Signal Pro');
    if (pro.evaluate().isNotEmpty) {
      await tester.tap(pro.first);
      await settle(tester);
      await shoot(tester, '05_pro');
      await goBack(tester);
    }
  });
}
