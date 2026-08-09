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

  test('an unreachable store is reported rather than left looking broken',
      () async {
    gateway.available = false;
    await controller.init();

    expect(controller.state.storeAvailable, isFalse);
    expect(controller.state.isPro, isFalse);
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

  test('a store that refuses to open the sheet does not leave a spinner',
      () async {
    gateway.buyReturnsTrue = false;
    await controller.init();
    await controller.buy();

    expect(controller.state.busy, isFalse);
    expect(controller.state.isError, isTrue);
  });

  test('a missing product is reported instead of silently doing nothing',
      () async {
    gateway.productExists = false;
    await controller.init();
    await controller.buy();

    expect(controller.state.busy, isFalse);
    expect(controller.state.isError, isTrue);
    expect(gateway.bought, isEmpty);
  });

  test('a restore that finds nothing still stops the spinner', () async {
    // No stream event is emitted for a restore with no purchases, so the flag
    // has to be cleared by the caller rather than the stream handler.
    await controller.init();
    await controller.restore();

    expect(controller.state.restoring, isFalse);
    expect(controller.state.message, 'No previous purchase found.');
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
  });

  test('a previously unlocked install starts in Pro before the store answers',
      () async {
    await settings.saveProUnlocked(true);
    final restored = PurchaseController(gateway: gateway, settings: settings);

    expect(restored.state.isPro, isTrue);
    restored.dispose();
  });
}
