import 'package:budgetbox/core/inr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Inr.format', () {
    test('zero and small amounts', () {
      expect(Inr.format(0), '₹0');
      expect(Inr.format(100), '₹1');
      expect(Inr.format(2000), '₹20');
      expect(Inr.format(64300), '₹643');
    });

    test('Indian 2-2-3 grouping', () {
      expect(Inr.format(123400), '₹1,234');
      expect(Inr.format(8745000), '₹87,450');
      expect(Inr.format(10000000), '₹1,00,000');
      expect(Inr.format(12345600), '₹1,23,456');
      expect(Inr.format(123456700), '₹12,34,567');
      expect(Inr.format(1000000000), '₹1,00,00,000');
    });

    test('paise hidden when zero, two digits when not', () {
      expect(Inr.format(123456), '₹1,234.56');
      expect(Inr.format(105), '₹1.05');
      expect(Inr.format(1050), '₹10.50');
    });

    test('negative uses a true minus before the rupee sign', () {
      expect(Inr.format(-2800000), '−₹28,000');
    });

    test('signed marks income with a plus', () {
      expect(Inr.format(300000, signed: true), '+₹3,000');
      expect(Inr.format(-100, signed: true), '−₹1');
    });
  });

  group('Inr.compact', () {
    test('below a lakh falls back to full form', () {
      expect(Inr.compact(8745000), '₹87,450');
      expect(Inr.compact(9999900), '₹99,999');
    });

    test('lakhs', () {
      expect(Inr.compact(10000000), '₹1L');
      expect(Inr.compact(52000000), '₹5.2L');
      expect(Inr.compact(46000000), '₹4.6L');
      expect(Inr.compact(999000000), '₹99.9L');
    });

    test('crores', () {
      expect(Inr.compact(1000000000), '₹1Cr');
      expect(Inr.compact(1400000000), '₹1.4Cr');
      expect(Inr.compact(15000000000), '₹15Cr');
    });

    test('never K or M', () {
      expect(Inr.compact(50000000).contains('K'), isFalse);
      expect(Inr.compact(150000000).contains('M'), isFalse);
    });

    test('negative compact', () {
      expect(Inr.compact(-52000000), '−₹5.2L');
    });
  });
}
