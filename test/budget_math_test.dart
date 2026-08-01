import 'package:budgetbox/data/repos/budget_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('on pace: run rate lands under the limit', () {
    const p = BudgetPace(
      spentPaise: 612000, // ₹6,120 of ₹9,000
      limitPaise: 900000,
      elapsedDays: 23,
      totalDays: 31,
    );
    expect(p.status, BudgetStatus.onPace);
    expect(p.remainingPaise, 288000);
  });

  test('projected over: current rate crosses the line before month end', () {
    const p = BudgetPace(
      spentPaise: 314000, // ₹3,140 of ₹3,500 by day 23
      limitPaise: 350000,
      elapsedDays: 23,
      totalDays: 31,
    );
    expect(p.status, BudgetStatus.projectedOver);
    expect(p.projectedPaise, greaterThan(p.limitPaise));
    expect(p.projectedOverspendPaise, greaterThan(0));
  });

  test('already over beats projection', () {
    const p = BudgetPace(
      spentPaise: 484000,
      limitPaise: 400000,
      elapsedDays: 23,
      totalDays: 31,
    );
    expect(p.status, BudgetStatus.over);
  });

  test('pending: nothing spent but a bill is coming (outlined bar)', () {
    const p = BudgetPace(
      spentPaise: 0,
      limitPaise: 1500000,
      elapsedDays: 23,
      totalDays: 31,
      upcomingPaise: 1500000,
    );
    expect(p.status, BudgetStatus.pending);
  });

  test('upcoming charges count toward the projection', () {
    const without = BudgetPace(
      spentPaise: 100000,
      limitPaise: 400000,
      elapsedDays: 15,
      totalDays: 30,
    );
    expect(without.status, BudgetStatus.onPace);

    const with_ = BudgetPace(
      spentPaise: 100000,
      limitPaise: 400000,
      elapsedDays: 15,
      totalDays: 30,
      upcomingPaise: 250000,
    );
    expect(with_.status, BudgetStatus.projectedOver);
  });

  test('day one never divides by zero', () {
    const p = BudgetPace(
      spentPaise: 5000,
      limitPaise: 900000,
      elapsedDays: 0,
      totalDays: 31,
    );
    expect(p.status, BudgetStatus.onPace);
  });
}
