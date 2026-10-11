import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/settings/presentation/choice_tile.dart';

void main() {
  testWidgets('tapping anywhere on the row opens the choices', (tester) async {
    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChoiceTile<int>(
            title: 'After it lasts',
            value: 2,
            choices: const {1: '1 min', 2: '2 min', 5: '5 min'},
            onChanged: (value) => picked = value,
          ),
        ),
      ),
    );

    expect(find.text('2 min'), findsOneWidget);
    // The title, at the far end from the value.
    await tester.tap(find.text('After it lasts'));
    await tester.pumpAndSettle();

    expect(find.byType(SimpleDialog), findsOneWidget);
    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();

    expect(picked, 5);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('re-picking the current value changes nothing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChoiceTile<int>(
            title: 'Alert at',
            value: 1,
            choices: const {0: '0 bars', 1: '1 bar or less'},
            onChanged: (_) => calls++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Alert at'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 bar or less').last);
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
