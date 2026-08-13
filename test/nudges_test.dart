import 'package:budgetbox/data/nudges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evening wording rotates while keeping the day facts', () {
    final first = eveningNudgeCopy(
      DateTime(2026, 8, 13),
      expenseCount: 2,
      spentPaise: 119200,
    );
    final next = eveningNudgeCopy(
      DateTime(2026, 8, 14),
      expenseCount: 2,
      spentPaise: 119200,
    );

    expect(first, isNot(next));
    expect('${first.title} ${first.body}', contains('₹1,192'));
    expect('${first.title} ${first.body}', contains('two entries'));
    expect('${next.title} ${next.body}', contains('₹1,192'));
    expect('${next.title} ${next.body}', contains('two entries'));
  });

  test('standing fallback changes each day and never claims a total', () {
    final copies = [
      for (var day = 13; day <= 16; day++)
        standingNudgeCopy(DateTime(2026, 8, day)),
    ];

    expect(copies.toSet(), hasLength(4));
    for (final copy in copies) {
      expect('${copy.title} ${copy.body}', isNot(contains('₹')));
    }
  });

  test('an empty page gets rotating zero-day wording', () {
    final first = eveningNudgeCopy(
      DateTime(2026, 8, 13),
      expenseCount: 0,
      spentPaise: 0,
    );
    final next = eveningNudgeCopy(
      DateTime(2026, 8, 14),
      expenseCount: 0,
      spentPaise: 0,
    );

    expect(first, isNot(next));
    expect('${first.title} ${first.body}', contains('₹0'));
  });
}
