import 'package:flutter/foundation.dart';

/// Everything the paywall and the Pro gates need to know.
@immutable
class PurchaseState {
  const PurchaseState({
    this.isPro = false,
    this.storeAvailable = false,
    this.priceLabel,
    this.busy = false,
    this.restoring = false,
    this.message,
    this.isError = false,
  });

  final bool isPro;

  /// False when the device cannot reach the store at all. The paywall shows a
  /// plain explanation instead of a dead button.
  final bool storeAvailable;

  /// Localised price straight from the store, never a hardcoded "£2.99" —
  /// Apple and Google both reject hardcoded prices that disagree with the
  /// storefront the user is actually in.
  final String? priceLabel;

  final bool busy;
  final bool restoring;

  /// User-facing status, e.g. after a restore that found nothing.
  final String? message;
  final bool isError;

  PurchaseState copyWith({
    bool? isPro,
    bool? storeAvailable,
    String? priceLabel,
    bool? busy,
    bool? restoring,
    String? message,
    bool? isError,
    bool clearMessage = false,
  }) =>
      PurchaseState(
        isPro: isPro ?? this.isPro,
        storeAvailable: storeAvailable ?? this.storeAvailable,
        priceLabel: priceLabel ?? this.priceLabel,
        busy: busy ?? this.busy,
        restoring: restoring ?? this.restoring,
        message: clearMessage ? null : (message ?? this.message),
        isError: clearMessage ? false : (isError ?? this.isError),
      );
}
