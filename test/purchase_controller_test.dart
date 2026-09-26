import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/purchases/data/purchase_controller.dart';
import 'package:honestsignal/features/settings/data/settings_repository.dart';

import 'fakes/fake_iap_gateway.dart';

void main() {
  late LocalStore store;
  late SettingsRepository settings;
  late FakeIapGateway gateway;
  late PurchaseController controller;

  setUp(() async {
    store = await LocalStore.openInMemory();
    settings = SettingsRepository(store.settings);
    gateway = FakeIapGateway();
    controller = PurchaseController(gateway: gateway, settings: settings);
  });

  tearDown(() async {
    controller.dispose();
    gateway.dispose();
    await store.close();
  });

  test('init reads the store price and restores silently', () async {
    await controller.init();

    expect(controller.state.storeAvailable, isTrue);
    expect(controller.state.priceLabel, '£2.99');
    // Restoring on launch is what keeps a reinstall in the tier it paid for.
    expect(gateway.restoreCalls, 1);
  });

  test(
    'an unreachable store is reported rather than left looking broken',
    () async {
      gateway.available = false;
      await controller.init();

      expect(controller.state.storeAvailable, isFalse);
      expect(controller.state.isPro, isFalse);
    },
  );

  test('an init exception becomes a recoverable store error', () async {
    gateway.availabilityError = StateError('billing disconnected');

    await controller.init();

    expect(controller.state.storeAvailable, isFalse);
    expect(controller.state.isError, isTrue);
    expect(controller.state.busy, isFalse);

    gateway.availabilityError = null;
    await controller.init();
    expect(controller.state.storeAvailable, isTrue);
    expect(gateway.restoreCalls, 1);
    expect(controller.state.message, isNull);
    expect(controller.state.isError, isFalse);
  });

  test('a completed purchase unlocks Pro and persists it', () async {
    await controller.init();
    await controller.buy();
    await gateway.emit(PurchaseStatus.purchased);

    expect(controller.state.isPro, isTrue);
    expect(controller.state.busy, isFalse);
    expect(settings.loadProUnlocked(), isTrue);
  });

  test('cancelling the store sheet clears the busy flag', () async {
    // buyNonConsumable only reports that the sheet opened; every terminal
    // outcome arrives on the stream. If cancel did not clear `busy` the paywall
    // would spin forever behind a dismissed dialog.
    await controller.init();
    await controller.buy();
    expect(controller.state.busy, isTrue);

    await gateway.emit(PurchaseStatus.canceled);

    expect(controller.state.busy, isFalse);
    expect(controller.state.isPro, isFalse);
  });

  test('a declined purchase clears busy and surfaces the error', () async {
    await controller.init();
    await controller.buy();

    await gateway.emit(PurchaseStatus.error);

    expect(controller.state.busy, isFalse);
    expect(controller.state.isError, isTrue);
    expect(controller.state.message, isNotNull);
  });

  test(
    'a store that refuses to open the sheet does not leave a spinner',
    () async {
      gateway.buyReturnsTrue = false;
      await controller.init();
      await controller.buy();

      expect(controller.state.busy, isFalse);
      expect(controller.state.isError, isTrue);
    },
  );

  test('a buy exception does not leave a spinner', () async {
    gateway.buyError = StateError('sheet failed');
    await controller.init();

    await controller.buy();

    expect(controller.state.busy, isFalse);
    expect(controller.state.isError, isTrue);
  });

  test(
    'a missing product is reported instead of silently doing nothing',
    () async {
      gateway.productExists = false;
      await controller.init();
      await controller.buy();

      expect(controller.state.busy, isFalse);
      expect(controller.state.isError, isTrue);
      expect(gateway.bought, isEmpty);
    },
  );

  test('a restore request stops the spinner without claiming no purchase', () async {
    // The store can emit the restored purchase after restorePurchases returns.
    await controller.init();
    await controller.restore();

    expect(controller.state.restoring, isFalse);
    expect(
      controller.state.message,
      'Restore requested. Any previous purchase will appear shortly.',
    );
    await gateway.emit(PurchaseStatus.restored);
    expect(controller.state.isPro, isTrue);
    expect(controller.state.message, 'Pro unlocked.');
  });

  test('a restore exception is surfaced and stops the spinner', () async {
    await controller.init();
    gateway.restoreError = StateError('restore failed');

    await controller.restore();

    expect(controller.state.restoring, isFalse);
    expect(controller.state.isError, isTrue);
  });

  test('a restored purchase unlocks Pro', () async {
    await controller.init();
    await gateway.emit(PurchaseStatus.restored);

    expect(controller.state.isPro, isTrue);
  });

  test('purchases awaiting completion are acknowledged', () async {
    // An unacknowledged Android purchase is auto-refunded after three days.
    await controller.init();
    await gateway.emit(PurchaseStatus.purchased, needsCompletion: true);

    expect(gateway.completeCalls, 1);
    expect(controller.state.isPro, isTrue);
  });

  test('an acknowledgement exception is surfaced', () async {
    await controller.init();
    gateway.completionError = StateError('ack failed');

    await gateway.emit(PurchaseStatus.purchased, needsCompletion: true);

    expect(controller.state.isPro, isFalse);
    expect(controller.state.isError, isTrue);
    expect(controller.state.busy, isFalse);
  });

  test('an unverifiable purchase is neither completed nor unlocked', () async {
    await controller.init();
    await gateway.emit(
      PurchaseStatus.purchased,
      needsCompletion: true,
      hasVerificationData: false,
    );

    expect(controller.state.isPro, isFalse);
    expect(gateway.completeCalls, 0);
    expect(settings.loadProUnlocked(), isFalse);
  });

  test('a wrong-product purchase is neither completed nor unlocked', () async {
    await controller.init();
    await gateway.emit(
      PurchaseStatus.purchased,
      needsCompletion: true,
      productId: 'com.example.unexpected',
    );

    expect(controller.state.isPro, isFalse);
    expect(gateway.completeCalls, 0);
  });

  test('an entitlement persistence failure never unlocks Pro', () async {
    final failingGateway = FakeIapGateway();
    addTearDown(failingGateway.dispose);
    final failingSettings = SettingsRepository(
      store.settings,
      proEntitlementWriter: (_) async => throw StateError('disk full'),
    );
    final failingController = PurchaseController(
      gateway: failingGateway,
      settings: failingSettings,
    );
    addTearDown(failingController.dispose);
    await failingController.init();

    await failingGateway.emit(PurchaseStatus.purchased, needsCompletion: true);

    expect(failingGateway.completeCalls, 1);
    expect(failingController.state.isPro, isFalse);
    expect(failingController.state.isError, isTrue);
  });

  test(
    'a previously unlocked install starts in Pro before the store answers',
    () async {
      await settings.saveProUnlocked(true);
      final restored = PurchaseController(gateway: gateway, settings: settings);

      expect(restored.state.isPro, isTrue);
      restored.dispose();
    },
  );
}
