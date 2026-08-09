import 'package:in_app_purchase/in_app_purchase.dart';

/// Thin adapter over `in_app_purchase` so the purchase controller can be tested
/// without a store connection.
///
/// House rule: the native plugin only — no RevenueCat or other wrapper SDKs.
abstract class IapGateway {
  Future<bool> isAvailable();
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids);
  Future<bool> buyNonConsumable(PurchaseParam param);
  Future<void> restorePurchases();
  Future<void> completePurchase(PurchaseDetails purchase);
}

class PluginIapGateway implements IapGateway {
  PluginIapGateway({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) =>
      _iap.queryProductDetails(ids);

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) =>
      _iap.buyNonConsumable(purchaseParam: param);

  @override
  Future<void> restorePurchases() => _iap.restorePurchases();

  @override
  Future<void> completePurchase(PurchaseDetails purchase) =>
      _iap.completePurchase(purchase);
}
