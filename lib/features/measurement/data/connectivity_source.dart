import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../domain/network_kind.dart';

/// What transport the OS thinks is in use, and when that changes.
///
/// A seam rather than a direct plugin call so the controller can be driven from
/// a scripted stream in tests.
abstract class ConnectivitySource {
  Future<NetworkKind> current();
  Stream<NetworkKind> get changes;
  void dispose();
}

class PluginConnectivitySource implements ConnectivitySource {
  PluginConnectivitySource({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<NetworkKind> current() async => _reduce(await _connectivity.checkConnectivity());

  @override
  Stream<NetworkKind> get changes =>
      _connectivity.onConnectivityChanged.map(_reduce).distinct();

  /// The plugin reports every active transport. Report the physical one the
  /// traffic actually rides, so a VPN over Wi-Fi still reads as Wi-Fi — the
  /// user cares which network is letting them down.
  static NetworkKind _reduce(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return NetworkKind.none;
    }
    if (results.contains(ConnectivityResult.wifi)) return NetworkKind.wifi;
    if (results.contains(ConnectivityResult.ethernet)) return NetworkKind.ethernet;
    if (results.contains(ConnectivityResult.mobile)) return NetworkKind.cellular;
    if (results.contains(ConnectivityResult.vpn)) return NetworkKind.vpn;
    return NetworkKind.other;
  }

  @override
  void dispose() {}
}
