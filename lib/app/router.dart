import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/indicator/presentation/overlay_setup_screen.dart';
import '../features/measurement/presentation/screens/history_screen.dart';
import '../features/measurement/presentation/screens/home_screen.dart';
import '../features/measurement/presentation/screens/how_it_works_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/purchases/presentation/paywall_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Read rather than watch: rebuilding the router on every settings change
  // would rebuild the whole navigator, and the only thing that matters here is
  // where the very first frame lands.
  final seenOnboarding = ref.read(settingsProvider).hasSeenOnboarding;

  return GoRouter(
    initialLocation: seenOnboarding ? '/' : '/welcome',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/welcome',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/how-it-works',
        builder: (context, state) => const HowItWorksScreen(),
      ),
      GoRoute(path: '/pro', builder: (context, state) => const PaywallScreen()),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'overlay',
            builder: (context, state) => const OverlaySetupScreen(),
          ),
        ],
      ),
    ],
  );
});
