import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/purchases/data/purchase_controller.dart';
import 'package:honestsignal/features/settings/data/settings_repository.dart';

import 'fakes/fake_iap_gateway.dart';

/// The states the paywall can be left in.
///
/// `purchase_controller_test.dart` covers the happy paths; this file covers the
/// ones that strand a user: a spinner that never stops, an entitlement granted
/// by the wrong product, or a transaction the store keeps re-delivering because
/// nobody completed it.
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

  group('stream transitions', () {
    test('a pending purchase keeps the spinner up', () async {
      // Slow-card and ask-a-parent flows sit in `pending` for minutes; the UI
      // has to keep showing that something is happening.
      await controller.init();
      await gateway.emit(PurchaseStatus.pending);

      expect(controller.state.busy, isTrue);
      expect(controller.state.isPro, isFalse);
    });

    test('pending then purchased ends busy and unlocks', () async {
      await controller.init();
      await controller.buy();
      await gateway.emit(PurchaseStatus.pending);
      expect(controller.state.busy, isTrue);

      await gateway.emit(PurchaseStatus.purchased);

      expect(controller.state.busy, isFalse);
      expect(controller.state.isPro, isTrue);
    });

    test('an error carries the store\'s own message', () async {
      await controller.init();
      await controller.buy();

      await gateway.emit(PurchaseStatus.error, errorMessage: 'Card declined');

      expect(controller.state.busy, isFalse);
      expect(controller.state.isError, isTrue);
      expect(controller.state.message, 'Card declined');
    });

    test('an error with no message still says something', () async {
      await controller.init();
      await controller.buy();

      await gateway.emit(PurchaseStatus.error);

      expect(controller.state.message, isNotEmpty);
      expect(controller.state.isError, isTrue);
    });

    test('a cancelled purchase leaves no message to apologise for', () async {
      // The user dismissed the sheet on purpose; telling them it "failed" reads
      // as an error they caused.
      await controller.init();
      await controller.buy();

      await gateway.emit(PurchaseStatus.canceled);

      expect(controller.state.busy, isFalse);
      expect(controller.state.message, isNull);
      expect(controller.state.isError, isFalse);
    });

    test('the stream itself failing does not strand the paywall', () async {
      // The billing service can disconnect mid-purchase.
      await controller.init();
      await controller.buy();
      expect(controller.state.busy, isTrue);

      await gateway.emitStreamError();

      expect(controller.state.busy, isFalse);
      expect(controller.state.isError, isTrue);
      expect(controller.state.message, 'Store error');
    });

    test('a purchase of some other product never grants Pro', () async {
      // Nothing else is sold today, but an entitlement that keys off anything
      // but the product ID is the classic way a paid unlock leaks.
      await controller.init();

      await gateway.emit(
        PurchaseStatus.purchased,
        productId: 'com.froggyeye.honestsignal.somethingelse',
      );

      expect(controller.state.isPro, isFalse);
      expect(settings.loadProUnlocked(), isFalse);
    });

    test('a foreign purchase is still completed, so the store stops '
        're-delivering it', () async {
      await controller.init();

      await gateway.emit(
        PurchaseStatus.purchased,
        productId: 'com.froggyeye.honestsignal.somethingelse',
        needsCompletion: true,
      );

      expect(gateway.completeCalls, 1);
    });

    test('a failed purchase awaiting completion is completed too', () async {
      // An unacknowledged Android purchase is auto-refunded after three days,
      // whatever its status.
      await controller.init();

      await gateway.emit(PurchaseStatus.error, needsCompletion: true);

      expect(gateway.completeCalls, 1);
    });

    test('two initialisations do not subscribe twice', () async {
      // A second listener would acknowledge every purchase twice and double
      // every state change.
      await controller.init();
      await controller.init();

      await gateway.emit(PurchaseStatus.purchased, needsCompletion: true);

      expect(gateway.completeCalls, 1);
    });
  });

  group('guards', () {
    test('buying while a purchase is already in flight is ignored', () async {
      await controller.init();
      await controller.buy();
      final firstAttempt = gateway.bought.length;

      await controller.buy();

      expect(gateway.bought, hasLength(firstAttempt));
    });

    test('buying when Pro is already owned does nothing', () async {
      await settings.saveProUnlocked(true);
      final owned = PurchaseController(gateway: gateway, settings: settings);
      await owned.init();

      await owned.buy();

      expect(gateway.bought, isEmpty);
      owned.dispose();
    });

    test('restoring while a restore is running is ignored', () async {
      await controller.init();
      final before = gateway.restoreCalls;

      final first = controller.restore();
      final second = controller.restore();
      await Future.wait([first, second]);

      expect(gateway.restoreCalls, before + 1);
    });

    test('a restore that found the purchase says so', () async {
      await controller.init();
      await gateway.emit(PurchaseStatus.restored);

      await controller.restore();

      expect(controller.state.isPro, isTrue);
      expect(controller.state.restoring, isFalse);
      expect(controller.state.message, 'Pro restored.');
      expect(controller.state.isError, isFalse);
    });

    test('dismissing a message clears the error with it', () async {
      await controller.init();
      await controller.buy();
      await gateway.emit(PurchaseStatus.error, errorMessage: 'Card declined');
      expect(controller.state.isError, isTrue);

      controller.clearMessage();

      expect(controller.state.message, isNull);
      expect(controller.state.isError, isFalse);
    });

    test('an unreachable store never leaves a dead button spinning', () async {
      gateway.available = false;
      await controller.init();

      expect(controller.state.storeAvailable, isFalse);
      expect(controller.state.busy, isFalse);
      expect(controller.state.priceLabel, isNull);
    });
  });

  group('screenshot harness', () {
    test('forcing Pro shows the Pro screens without writing an entitlement',
        () async {
      // The harness must never leave a real unlock behind in the settings box.
      controller.debugForcePro();

      expect(controller.state.isPro, isTrue);
      expect(controller.state.priceLabel, isNotNull);
      expect(settings.loadProUnlocked(), isFalse);
    });
  });

  group('monetisation invariants', () {
    test('the product ID is the one registered with both stores', () {
      // House convention com.froggyeye.<appname>.<product>; changing this
      // string orphans the purchase every existing customer made.
      expect(PurchaseController.proProductId, 'com.froggyeye.honestsignal.pro');
    });

    test('the price shown always comes from the store, never from the app', () {
      // Both stores reject a hardcoded price that disagrees with the user's
      // storefront.
      expect(controller.state.priceLabel, isNull);
    });

    test('the price appears once the store answers', () async {
      await controller.init();
      expect(controller.state.priceLabel, FakeIapGateway.product.price);
    });
  });
}
