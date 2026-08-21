import 'package:budgetbox/features/add/amount_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AmountEngine type(String keys) {
    final e = AmountEngine();
    for (final k in keys.split(' ')) {
      switch (k) {
        case '+' || '−' || '×' || '÷':
          e.op(k);
        case '.':
          e.point();
        case '<':
          e.backspace();
        default:
          for (final ch in k.split('')) {
            if (ch == '.') {
              e.point();
            } else {
              e.digit(ch);
            }
          }
      }
    }
    return e;
  }

  test('bare number', () {
    final e = type('180');
    expect(e.paise, 18000);
    expect(e.expression, '');
  });

  test('sum shows the running expression', () {
    final e = type('120 + 60');
    expect(e.value, 180);
    expect(e.expression, '120 + 60');
  });

  test('folds left to right like a shop counter', () {
    final e = type('450 + 120 + 60');
    expect(e.value, 630);
  });

  test('mixed operators fold eagerly', () {
    final e = type('100 + 100 × 2');
    expect(e.value, 400); // (100+100)×2, not precedence
  });

  test('decimal entry', () {
    final e = type('10 . 5');
    expect(e.paise, 1050);
  });

  test('division by zero is ignored, not a crash', () {
    final e = type('100 ÷ 0');
    expect(e.value, 100);
  });

  test('backspace edits the current number', () {
    final e = type('185 <');
    expect(e.paise, 1800);
  });

  test('backspace over an operator reopens the last number', () {
    final e = type('120 + <');
    expect(e.value, 120);
    expect(e.expression, '');
    e.digit('5');
    expect(e.value, 1205);
  });

  test('swapping operators keeps one', () {
    final e = type('120 + ×');
    e.digit('2');
    expect(e.value, 240);
    expect(e.expression, '120 × 2');
  });

  test('clear resets everything', () {
    final e = type('120 + 60');
    e.clear();
    expect(e.isEmpty, isTrue);
    expect(e.paise, 0);
  });

  test('caps runaway digit entry', () {
    final e = type('123456789012');
    expect(e.paise, lessThan(10000000000 * 100));
  });

  test('the display echoes the point the moment it is pressed', () {
    final e = type('120');
    expect(e.display, '₹120');
    e.point();
    expect(e.display, '₹120.', reason: 'a dead-looking key is a broken key');
    e.digit('0');
    expect(e.display, '₹120.0');
    e.digit('5');
    expect(e.display, '₹120.05');
    expect(e.paise, 12005);
  });

  test('a bare point starts at zero and groups stay Indian', () {
    final e = AmountEngine();
    e.point();
    expect(e.display, '₹0.');
    e.digit('5');
    expect(e.paise, 50);

    final big = type('123456.7');
    expect(big.display, '₹1,23,456.7');
  });

  test('paise stop at two decimals — the third key is refused', () {
    final e = type('12.34');
    e.digit('5');
    expect(e.display, '₹12.34');
    expect(e.paise, 1234);
  });

  test('once operators fold, the running total takes the display', () {
    final e = type('120.5 + 60');
    expect(e.display, '₹180.50');
  });
}
