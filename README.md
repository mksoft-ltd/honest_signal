# Honest Signal

Honest Signal is a Flutter connectivity meter for iOS and Android. It measures
real latency, jitter, loss and download throughput, then turns those readings
into an honest 0–5 score instead of repeating the phone's radio bars.

The app is local-first: no account, backend, analytics, ads or tracking. Android
can keep an ongoing status-bar indicator and optional floating bubble alive;
iOS measures while the app is open. Pro is a one-time native in-app purchase
that unlocks history, indicator themes and custom sampling intervals.

## Development

Requirements: the current Flutter stable toolchain, Xcode for iOS, and Android
Studio/JDK 17 for Android.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Android native unit tests:

```sh
cd android
./gradlew :app:testDebugUnitTest
```

Release builds use `android/key.properties` and a per-app upload keystore when
present. Store and product details are documented in `docs/PRODUCT_SPEC.md`;
test coverage and device checks are in `docs/TEST_PLAN.md`.

Screenshot mode is compile-time only:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define=SCREENSHOT_MODE=true
```

© 2026 Froggy Eye Ltd
