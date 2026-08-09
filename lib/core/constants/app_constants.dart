/// Fixed strings that also appear in store metadata. Keep them identical to
/// what release-manager writes into `ios/fastlane/metadata/` and
/// `android/fastlane/metadata/android/` — a privacy URL that differs between
/// the binary and the listing is a store-review finding.
class AppConstants {
  const AppConstants._();

  static const String appName = 'Honest Signal';
  static const String publisher = 'Froggy Eye Ltd';

  /// House convention (house-facts #5): raw GitHub URL of the repo's
  /// PRIVACY_POLICY.md. Must return 200 before submission.
  static const String privacyPolicyUrl =
      'https://raw.githubusercontent.com/mksoft-ltd/honest_signal/refs/heads/main/PRIVACY_POLICY.md';

  static const String supportUrl = 'https://honestsignal.froggyeye.com';

  static const String supportEmail = 'info@froggyeye.com';
}
