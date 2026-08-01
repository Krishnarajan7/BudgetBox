/// The one money formatter. Amounts live as integer paise everywhere;
/// this is the only place they become text.
///
/// Rules (identity-critical, see design/design-system.md):
/// - `₹` before the number, no space; Indian 2-2-3 grouping: ₹1,23,456
/// - compact only from a lakh up: ₹5.2L, ₹1.4Cr — never K/M
/// - paise hidden when zero, shown as two digits when not: ₹1,234.56
abstract final class Inr {
  static const _rupee = '₹';
  static const _minus = '−'; // proper minus, not hyphen

  static const int paisePerRupee = 100;
  static const int _lakh = 100000; // in rupees
  static const int _crore = 10000000; // in rupees

  /// Full form: ₹1,23,456 or ₹1,234.56. Set [signed] to prefix `+` on
  /// positive amounts (income marks).
  static String format(int paise, {bool signed = false}) {
    final negative = paise < 0;
    final abs = paise.abs();
    final rupees = abs ~/ paisePerRupee;
    final p = abs % paisePerRupee;

    final body = p == 0
        ? _group(rupees)
        : '${_group(rupees)}.${p.toString().padLeft(2, '0')}';

    final sign = negative
        ? _minus
        : signed
            ? '+'
            : '';
    return '$sign$_rupee$body';
  }

  /// Compact form for lakh+ magnitudes: ₹5.2L, ₹1.4Cr. Below a lakh it
  /// falls back to [format] — people read ₹87,450 fine.
  static String compact(int paise) {
    final negative = paise < 0;
    final rupees = paise.abs() ~/ paisePerRupee;
    if (rupees < _lakh) return format(paise);

    final String body;
    if (rupees >= _crore) {
      body = '${_trim(rupees / _crore)}Cr';
    } else {
      body = '${_trim(rupees / _lakh)}L';
    }
    return '${negative ? _minus : ''}$_rupee$body';
  }

  /// 2-2-3 grouping: 1234567 -> 12,34,567
  static String _group(int rupees) {
    final s = rupees.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var head = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (head.length > 2) {
      parts.insert(0, head.substring(head.length - 2));
      head = head.substring(0, head.length - 2);
    }
    parts.insert(0, head);
    return '${parts.join(',')},$last3';
  }

  /// One decimal, trailing .0 trimmed: 5.0 -> "5", 5.25 -> "5.2"
  static String _trim(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
  }
}
