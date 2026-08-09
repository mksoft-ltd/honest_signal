/// The transport the device believes it is using.
///
/// This is deliberately kept separate from the measured score: the whole point
/// of Honest Signal is that "connected via WiFi" and "WiFi actually works" are
/// different claims.
enum NetworkKind {
  wifi,
  cellular,
  ethernet,
  vpn,
  other,
  none;

  String get label => switch (this) {
        NetworkKind.wifi => 'Wi-Fi',
        NetworkKind.cellular => 'Cellular',
        NetworkKind.ethernet => 'Ethernet',
        NetworkKind.vpn => 'VPN',
        NetworkKind.other => 'Other',
        NetworkKind.none => 'Offline',
      };

  bool get isOnline => this != NetworkKind.none;

  static NetworkKind fromStorage(String? value) => NetworkKind.values
      .firstWhere((k) => k.name == value, orElse: () => NetworkKind.other);
}
