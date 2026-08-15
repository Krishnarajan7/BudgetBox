import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/tokens.dart';
import 'package:budgetbox/core/typography.dart';
import 'package:budgetbox/core/widgets/ledger_app_bar.dart';
import 'package:budgetbox/core/widgets/pen_marks.dart';
import 'package:budgetbox/core/widgets/sky_marks.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// The top bar, drawn at the size it actually ships at — the only way to
/// judge chrome this small is to look at it.
void main() {
  // The book's own faces, loaded off disk — a chrome golden rendered in the
  // fallback font is measuring the wrong thing entirely.
  setUpAll(() async {
    for (final family in const {
      'Fraunces': 'assets/fonts/Fraunces.ttf',
      'Hanken Grotesk': 'assets/fonts/HankenGrotesk.ttf',
      'Spline Sans Mono': 'assets/fonts/SplineSansMono.ttf',
    }.entries) {
      final loader = FontLoader(family.key)
        ..addFont(
          File(family.value).readAsBytes().then(
            (bytes) => bytes.buffer.asByteData(),
          ),
        );
      await loader.load();
    }
  });

  testWidgets('the bar reads at real size', (tester) async {
    tester.view.physicalSize = const Size(1170, 300);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ledgerNightTheme(),
        home: Builder(
          builder: (context) {
            final c = LedgerColors.of(context);
            return Scaffold(
              backgroundColor: c.paper,
              body: RepaintBoundary(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.page,
                    vertical: Gap.x4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Krish Space',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: LedgerType.wordmark.copyWith(
                                  color: c.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            PenChevron(size: 12, color: c.inkFaint),
                          ],
                        ),
                      ),
                      const SizedBox(width: Gap.x2),
                      DayLeaf(day: DateTime(2026, 8, 15)),
                      const SizedBox(width: Gap.x3),
                      SkyMark(
                        shape: SkyShape.cloud,
                        color: c.inkFaint,
                        size: 20,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '16°',
                        style: LedgerType.amount.copyWith(
                          fontSize: 12,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'overcast',
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 11,
                          color: c.inkFaint,
                        ),
                      ),
                      const SizedBox(width: Gap.x3),
                      PenSliders(size: 17, color: c.inkFaint),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/app_bar.png'),
    );
  });
}
