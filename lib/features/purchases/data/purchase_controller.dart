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
  Future<void>? _initialising;
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    final active = _initialising;
    if (active != null) return active;
    final attempt = _init();
    _initialising = attempt;
    try {
      _initialised = await attempt;
    } finally {
      _initialising = null;
    }
  }

  Future<bool> _init() async {
    _subscription ??= _gateway.purchaseStream.listen(
      (purchases) => unawaited(_onPurchases(purchases)),
      onError: (Object error) => _set(
        _state.copyWith(busy: false, message: 'Store error', isError: true),
      ),
    );

    try {
      final available = await _gateway.isAvailable();
      if (!available) {
        _set(_state.copyWith(storeAvailable: false));
        return false;
      }

      final response = await _gateway.queryProductDetails({proProductId});
      final product = response.productDetails
          .where((p) => p.id == proProductId)
          .firstOrNull;
      _set(
        _state.copyWith(
          storeAvailable: true,
          priceLabel: product?.price,
          message: response.error?.message,
          isError: response.error != null,
          clearMessage: response.error == null,
        ),
      );
      await _gateway.restorePurchases();
      // A missing/failed product query may be transient. Restoration is still
      // attempted for existing owners, but a later init() may retry metadata.
      return response.error == null && product != null;
    } on Object {
      _set(
        _state.copyWith(
          storeAvailable: false,
          busy: false,
          message: 'The store could not be reached. Please try again.',
          isError: true,
        ),
      );
      return false;
    }
  }

  Future<void> buy() async {
    if (_state.busy || _state.isPro) return;
    _set(_state.copyWith(busy: true, clearMessage: true));

    try {
      final response = await _gateway.queryProductDetails({proProductId});
      final product = response.productDetails
          .where((p) => p.id == proProductId)
          .firstOrNull;
      if (product == null || response.error != null) {
        _set(
          _state.copyWith(
            busy: false,
            message:
                response.error?.message ??
                'Pro is not available from the store right now.',
            isError: true,
          ),
        );
        return;
      }

      final started = await _gateway.buyNonConsumable(
        PurchaseParam(productDetails: product),
      );
      if (!started) {
        _set(
          _state.copyWith(
            busy: false,
            message: 'Could not open the store.',
            isError: true,
          ),
        );
      }
    } on Object {
      _set(
        _state.copyWith(
          busy: false,
          message: 'The purchase could not be started. Please try again.',
          isError: true,
        ),
      );
    }
  }

  Future<void> restore() async {
    if (_state.restoring) return;
    _set(_state.copyWith(restoring: true, clearMessage: true));
    try {
      await _gateway.restorePurchases();
      _set(
        _state.copyWith(
          restoring: false,
          message: _state.isPro
              ? 'Pro restored.'
              : 'Restore requested. Any previous purchase will appear shortly.',
          isError: false,
        ),
      );
    } on Object {
      _set(
        _state.copyWith(
          restoring: false,
          message: 'Restore failed. Check your store connection and try again.',
          isError: true,
        ),
      );
    } finally {
      // A restore that finds nothing produces no stream event at all, so the
      // flag has to be cleared here rather than in the stream handler.
      if (_state.restoring) _set(_state.copyWith(restoring: false));
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
          if (purchase.productID != proProductId) {
            _set(
              _state.copyWith(
                busy: false,
                message: 'The store returned an unexpected product.',
                isError: true,
              ),
            );
          } else if (!_hasVerificationData(purchase)) {
            _set(
              _state.copyWith(
                busy: false,
                message: 'The store returned an unverifiable purchase.',
                isError: true,
              ),
            );
          } else {
            try {
              // A pending completion is store ownership work, not local
              // bookkeeping. Do it before granting the cached entitlement so
              // an acknowledgement failure can never unlock Pro.
              if (purchase.pendingCompletePurchase) {
                await _gateway.completePurchase(purchase);
              }
              await _unlock();
              _set(_state.copyWith(busy: false));
            } on Object {
              _set(
                _state.copyWith(
                  busy: false,
                  message:
                      'The purchase could not be safely saved. '
                      'Use Restore purchases to try again.',
                  isError: true,
                ),
              );
            }
          }
        case PurchaseStatus.error:
          _set(
            _state.copyWith(
              busy: false,
              message: purchase.error?.message ?? 'Purchase failed.',
              isError: true,
            ),
          );
        case PurchaseStatus.canceled:
          _set(_state.copyWith(busy: false, clearMessage: true));
      }
    }
  }

  bool _hasVerificationData(PurchaseDetails purchase) =>
      purchase.verificationData.localVerificationData.isNotEmpty ||
      purchase.verificationData.serverVerificationData.isNotEmpty;

  Future<void> _unlock() async {
    // This is a local consistency check, not cryptographic receipt validation.
    // Revocation-aware verification needs a store/server authority, which this
    // deliberately local-first app does not operate.
    await _settings.saveProUnlocked(true);
    _set(
      _state.copyWith(isPro: true, message: 'Pro unlocked.', isError: false),
    );
  }

  /// Used only by the screenshot harness, which needs the Pro screens visible
  /// without a store transaction.
  void debugForcePro() {
    assert(() {
      _set(
        _state.copyWith(isPro: true, storeAvailable: true, priceLabel: '£2.99'),
      );
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
