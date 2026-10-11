import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';
import 'package:honestsignal/features/purchases/domain/pro_teaser.dart';
import 'package:honestsignal/features/review/review_prompter.dart';

class _FakeRequester implements ReviewRequester {
  bool available = true;
  int requests = 0;
  int listings = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;

  @override
  Future<void> openStoreListing() async => listings++;
}

SignalSample _sample(DateTime t, int bars) => SignalSample(
  timestamp: t,
  kind: NetworkKind.wifi,
  bars: bars,
  composite: bars / 5,
  lossRatio: 0,
  probesSent: 4,
  bytesUsed: 2800,
  latencyMs: 30,
);

void main() {
  group('review prompter', () {
    late LocalStore store;
    late _FakeRequester requester;
    late DateTime now;
    late ReviewPrompter prompter;

    setUp(() async {
      store = await LocalStore.openInMemory();
      requester = _FakeRequester();
      now = DateTime(2026, 10, 1, 9);
      prompter = ReviewPrompter(store.settings, requester, clock: () => now);
    });

    tearDown(() => store.close());

    /// Opens the app once a day for [days] days, then advances past the
    /// session-age floor.
    Future<void> useFor(int days) async {
      for (var i = 0; i < days; i++) {
        await prompter.recordUse();
        now = now.add(const Duration(days: 1));
      }
      await prompter.recordUse();
      now = now.add(ReviewPrompter.minSessionAge);
    }

    test('never asks a brand-new user', () async {
      await prompter.recordUse();
      now = now.add(const Duration(minutes: 5));
      expect(await prompter.maybePrompt(currentBars: 5), isFalse);
      expect(requester.requests, 0);
    });

    test('asks a returning user who is looking at a good reading', () async {
      await useFor(4);
      expect(await prompter.maybePrompt(currentBars: 5), isTrue);
      expect(requester.requests, 1);
    });

    test('never asks over a poor connection', () async {
      await useFor(4);
      expect(await prompter.maybePrompt(currentBars: 2), isFalse);
      expect(requester.requests, 0);
    });

    test('several opens on one day count as one day', () async {
      for (var i = 0; i < 10; i++) {
        await prompter.recordUse();
        now = now.add(const Duration(hours: 1));
      }
      now = now.add(const Duration(days: 5));
      await prompter.recordUse();
      now = now.add(ReviewPrompter.minSessionAge);
      expect(await prompter.maybePrompt(currentBars: 5), isFalse);
    });

    test('asks once a session and then respects the cooldown', () async {
      await useFor(4);
      expect(await prompter.maybePrompt(currentBars: 5), isTrue);
      expect(await prompter.maybePrompt(currentBars: 5), isFalse);

      // A new app process, a month later: still inside the cooldown.
      now = now.add(const Duration(days: 30));
      prompter = ReviewPrompter(store.settings, requester, clock: () => now);
      await prompter.recordUse();
      now = now.add(ReviewPrompter.minSessionAge);
      expect(await prompter.maybePrompt(currentBars: 5), isFalse);

      now = now.add(ReviewPrompter.cooldown);
      prompter = ReviewPrompter(store.settings, requester, clock: () => now);
      await prompter.recordUse();
      now = now.add(ReviewPrompter.minSessionAge);
      expect(await prompter.maybePrompt(currentBars: 5), isTrue);
      expect(requester.requests, 2);
    });

    test('a purchase skips the days-of-use wait but not the cooldown', () async {
      await prompter.recordUse();
      expect(
        await prompter.maybePrompt(currentBars: 5, afterPurchase: true),
        isTrue,
      );
      prompter = ReviewPrompter(store.settings, requester, clock: () => now);
      expect(
        await prompter.maybePrompt(currentBars: 5, afterPurchase: true),
        isFalse,
      );
    });

    test('an unavailable store sheet is not counted as a prompt', () async {
      requester.available = false;
      await useFor(4);
      expect(await prompter.maybePrompt(currentBars: 5), isFalse);
      requester.available = true;
      prompter = ReviewPrompter(store.settings, requester, clock: () => now);
      await prompter.recordUse();
      now = now.add(ReviewPrompter.minSessionAge);
      expect(await prompter.maybePrompt(currentBars: 5), isTrue);
    });
  });

  group('pro teaser', () {
    final start = DateTime(2026, 10, 1, 9);

    test('says nothing until there is enough history to be honest', () {
      final samples = [
        for (var i = 0; i < ProTeaser.minReadings - 1; i++)
          _sample(start.add(Duration(minutes: i)), 1),
      ];
      expect(ProTeaser.from(samples), isNull);
    });

    test('a run of poor readings is one drop-out, a recovery splits them', () {
      final bars = [5, 5, 1, 0, 1, 4, 4, 0, 0, 5, 5, 5];
      final samples = [
        for (var i = 0; i < bars.length; i++)
          _sample(start.add(Duration(minutes: i)), bars[i]),
      ];
      final teaser = ProTeaser.from(samples)!;
      expect(teaser.readings, bars.length);
      expect(teaser.dropouts, 2);
      expect(teaser.dropoutPhrase, '2 drop-outs');
    });

    test('a long gap between poor readings starts a new episode', () {
      final samples = [
        for (var i = 0; i < 10; i++)
          _sample(start.add(Duration(minutes: i)), 5),
        _sample(start.add(const Duration(minutes: 20)), 0),
        _sample(start.add(const Duration(minutes: 50)), 0),
      ];
      expect(ProTeaser.from(samples)!.dropouts, 2);
    });
  });
}
