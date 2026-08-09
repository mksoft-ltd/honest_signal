import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../settings/data/settings_repository.dart';
import '../domain/purchase_state.dart';
import 'iap_gateway.dart';

/// Owns the Pro entitlement.
///
/// A `ChangeNotifier` rather than a Riverpod notifier so the same object can be
/// unit-tested directly with a fake gateway; Riverpod exposes it through a
/// `ChangeNotifierProvider`.
class PurchaseController extends ChangeNotifier {
  PurchaseController({required this._gateway, required this._settings}) {
    _state = PurchaseState(isPro: _settings.loadProUnlocked());
  }

  /// House convention: `com.froggyeye.<appname>.<product>`.
  static const String proProductId = 'com.froggyeye.honestsignal.pro';

  final IapGateway _gateway;
  final SettingsRepository _settings;

  late PurchaseState _state;
  PurchaseState get state => _state;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<void> init() async {
    _subscription ??= _gateway.purchaseStream.listen(
      _onPurchases,
      onError: (Object error) => _set(
        _state.copyWith(busy: false, message: 'Store error', isError: true),
      ),
    );

    final available = await _gateway.isAvailable();
    if (!available) {
      _set(_state.copyWith(storeAvailable: false));
      return;
    }

    final response = await _gateway.queryProductDetails({proProductId});
    final product = response.productDetails
        .where((p) => p.id == proProductId)
        .firstOrNull;
    _set(_state.copyWith(
      storeAvailable: true,
      priceLabel: product?.price,
    ));

    // Restoring on launch keeps a reinstall or a new device in the tier the
    // user already paid for without them having to find the button.
    await _gateway.restorePurchases();
  }

  Future<void> buy() async {
    if (_state.busy || _state.isPro) return;
    _set(_state.copyWith(busy: true, clearMessage: true));

    final response = await _gateway.queryProductDetails({proProductId});
    final product =
        response.productDetails.where((p) => p.id == proProductId).firstOrNull;
    if (product == null) {
      _set(_state.copyWith(
        busy: false,
        message: 'Pro is not available from the store right now.',
        isError: true,
      ));
      return;
    }

    final started = await _gateway.buyNonConsumable(
      PurchaseParam(productDetails: product),
    );
    // `buyNonConsumable` only reports whether the sheet was *launched*. Every
    // terminal outcome — bought, cancelled, declined — arrives on the purchase
    // stream, so `busy` stays set here and is cleared in `_onPurchases`.
    // Clearing it on a `true` return would hide the spinner before the sheet
    // even appears; never clearing it on `false` would spin forever.
    if (!started) {
      _set(_state.copyWith(
        busy: false,
        message: 'Could not open the store.',
        isError: true,
      ));
    }
  }

  Future<void> restore() async {
    if (_state.restoring) return;
    _set(_state.copyWith(restoring: true, clearMessage: true));
    try {
      await _gateway.restorePurchases();
    } finally {
      // A restore that finds nothing produces no stream event at all, so the
      // flag has to be cleared here rather than in the stream handler.
      _set(_state.copyWith(
        restoring: false,
        message: _state.isPro ? 'Pro restored.' : 'No previous purchase found.',
        isError: false,
      ));
    }
  }

  void clearMessage() => _set(_state.copyWith(clearMessage: true));

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _set(_state.copyWith(busy: true));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.productID == proProductId) await _unlock();
          _set(_state.copyWith(busy: false));
        case PurchaseStatus.error:
          _set(_state.copyWith(
            busy: false,
            message: purchase.error?.message ?? 'Purchase failed.',
            isError: true,
          ));
        case PurchaseStatus.canceled:
          _set(_state.copyWith(busy: false, clearMessage: true));
      }

      // Required on both stores: an uncompleted purchase is re-delivered on
      // every launch and, on Android, is refunded automatically after three
      // days.
      if (purchase.pendingCompletePurchase) {
        await _gateway.completePurchase(purchase);
      }
    }
  }

  Future<void> _unlock() async {
    await _settings.saveProUnlocked(true);
    _set(_state.copyWith(isPro: true, message: 'Pro unlocked.', isError: false));
  }

  /// Used only by the screenshot harness, which needs the Pro screens visible
  /// without a store transaction.
  void debugForcePro() {
    assert(() {
      _set(_state.copyWith(isPro: true, storeAvailable: true, priceLabel: '£2.99'));
      return true;
    }());
  }

  void _set(PurchaseState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
