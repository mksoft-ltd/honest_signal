import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

class HonestSignalApp extends ConsumerStatefulWidget {
  const HonestSignalApp({super.key});

  @override
  ConsumerState<HonestSignalApp> createState() => _HonestSignalAppState();
}

class _HonestSignalAppState extends ConsumerState<HonestSignalApp> {
  @override
  void initState() {
    super.initState();
    // Android 15 draws every app edge to edge; opting in explicitly keeps
    // pre-API-35 devices consistent and clears Play's edge-to-edge warning.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(purchaseControllerProvider).init();
      ref.read(indicatorControllerProvider).sync(ref.read(effectiveSettingsProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(effectiveSettingsProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
