import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:honestsignal/features/purchases/data/iap_gateway.dart';
import 'package:honestsignal/features/purchases/data/purchase_controller.dart';

/// A store that answers on command.
///
/// `buyNonConsumable` deliberately does *not* emit a purchase: on both real
/// stores it only reports that the sheet opened, and every terminal outcome
/// arrives later on the purchase stream. Tests emit that outcome themselves.
class FakeIapGateway implements IapGateway {
  FakeIapGateway({this.available = true, this.productExists = true});

  bool available;
  bool productExists;
  bool buyReturnsTrue = true;

  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  int restoreCalls = 0;
  int completeCalls = 0;
  int queryCalls = 0;
  final List<String> bought = [];
  final List<String> completed = [];

  static final product = ProductDetails(
    id: PurchaseController.proProductId,
    title: 'Honest Signal Pro',
    description: 'Pro features',
    price: '£2.99',
    rawPrice: 2.99,
    currencyCode: 'GBP',
  );

  @override
  Future<bool> isAvailable() async => available;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queryCalls++;
    return ProductDetailsResponse(
      productDetails: productExists ? [product] : const [],
      notFoundIDs: productExists ? const [] : ids.toList(),
    );
  }

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) async {
    bought.add(param.productDetails.id);
    return buyReturnsTrue;
  }

  @override
  Future<void> restorePurchases() async => restoreCalls++;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completeCalls++;
    completed.add(purchase.productID);
  }

  /// Publishes a purchase without waiting for it to be delivered.
  ///
  /// Widget tests must use this rather than [emit]: `emit` awaits a
  /// zero-duration delay, and inside a widget test the clock is fake, so
  /// awaiting a timer that only `pump` can fire deadlocks the test. Follow this
  /// with `await tester.pump()`.
  void emitNow(
    PurchaseStatus status, {
    bool needsCompletion = false,
    String? productId,
  }) {
    controller.add([
      FakePurchase(
        status: status,
        needsCompletion: needsCompletion,
        productId: productId ?? PurchaseController.proProductId,
      ),
    ]);
  }

  /// Simulates the store answering on the purchase stream.
  ///
  /// Only for plain `test()` bodies — see [emitNow] for widget tests.
  Future<void> emit(
    PurchaseStatus status, {
    bool needsCompletion = false,
    String? productId,
    String? errorMessage,
  }) async {
    controller.add([
      FakePurchase(
        status: status,
        needsCompletion: needsCompletion,
        productId: productId ?? PurchaseController.proProductId,
        failure: errorMessage == null
            ? null
            : IAPError(
                source: 'test',
                code: 'purchase_error',
                message: errorMessage,
              ),
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
  }

  /// Simulates the plugin's stream itself failing, e.g. the billing service
  /// disconnecting mid-purchase.
  Future<void> emitStreamError() async {
    controller.addError(Exception('billing service disconnected'));
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() => controller.close();
}

class FakePurchase extends PurchaseDetails {
  FakePurchase({
    required super.status,
    required bool needsCompletion,
    String productId = PurchaseController.proProductId,
    IAPError? failure,
  }) : super(
          productID: productId,
          verificationData: PurchaseVerificationData(
            localVerificationData: 'local',
            serverVerificationData: 'server',
            source: 'test',
          ),
          transactionDate: null,
        ) {
    pendingCompletePurchase = needsCompletion;
    error = failure;
  }
}
