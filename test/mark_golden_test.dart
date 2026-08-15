import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/widgets/pen_marks.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/features/splash/splash_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the character and its line render on the splash',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: ledgerNightTheme(),
        home: const SplashScreen(),
      ),
    ));
    // One frame to let the post-frame kickoff start the ticker, then run to
    // the still moment: character seated, slogan inked, wink not yet begun
    // (it starts at 0.60 of 1600ms), hand-off not yet fired.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 380));
    expect(find.text('made for Krish · population, one'), findsOneWidget);
    expect(tester.widget<MarkFace>(find.byType(MarkFace)).wink, 0);
    await expectLater(
      find.byType(SplashScreen),
      matchesGoldenFile('goldens/mark.png'),
    );

    // And then it winks: by the hold, the left eye is fully shut.
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<MarkFace>(find.byType(MarkFace)).wink,
        greaterThan(0.35));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  });
}
