import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/demo/screenshot_mode.dart';
import 'core/storage/local_store.dart';
import 'features/measurement/data/background_host.dart';
import 'features/measurement/data/history_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = ScreenshotMode.isEnabled
      ? await LocalStore.openInMemory()
      : await LocalStore.open();

  final overrides = <Override>[localStoreProvider.overrideWithValue(store)];

  if (ScreenshotMode.isEnabled) {
    await ScreenshotMode.seedHistory(HistoryRepository(store.history));
    overrides.addAll(ScreenshotMode.overrides());
  }

  runApp(ProviderScope(overrides: overrides, child: const HonestSignalApp()));
}

/// Entry point for the background Flutter engine hosted by the Android
/// foreground service.
///
/// Named rather than a callback handle so the Kotlin side can start it with
/// `DartEntrypoint(bundlePath, "honestSignalBackgroundMain")`. The pragma keeps
/// it from being tree-shaken out of the release AOT snapshot — without it the
/// service starts an engine that immediately does nothing.
@pragma('vm:entry-point')
void honestSignalBackgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();
  BackgroundMeasurementHost().attach();
}
