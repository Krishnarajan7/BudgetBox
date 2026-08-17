/// The keypad's brain: digits, one decimal point, and running arithmetic —
/// because real purchases are "120 + 60", and mental math is a stall point.
///
/// Behaviour: operators fold eagerly left-to-right (450 + 120 × 2 shows a
/// running expression and evaluates as a person types, not by precedence —
/// this is a shop counter, not a scientific calculator).
class AmountEngine {
  String _current = '';
  double? _accumulated;
  String? _pendingOp;

  /// The full expression as typed, e.g. "120 + 60" — the faint line above
  /// the amount. Empty when only a bare number is entered.
  final List<String> _story = [];

  bool get isEmpty => _current.isEmpty && _accumulated == null;

  /// Current value in paise (what the stamp saves).
  int get paise => (value * 100).round();

  double get value {
    final cur = _current.isEmpty ? null : double.parse(_current);
    if (_accumulated == null) return cur ?? 0;
    if (cur == null) return _accumulated!;
    return _apply(_accumulated!, _pendingOp!, cur);
  }

  /// The running expression line, e.g. "120 + 60". Empty for a bare number.
  String get expression => _story.isEmpty
      ? ''
      : [..._story, if (_current.isNotEmpty) _current].join(' ');

  void digit(String d) {
    assert(RegExp(r'^[0-9]$').hasMatch(d));
    // Amounts at chai scale don't need 10-digit entries.
    final digitsOnly = _current.replaceAll('.', '');
    if (digitsOnly.length >= 8) return;
    if (_current == '0') {
      _current = d;
    } else {
      _current += d;
    }
  }

  void point() {
    if (_current.contains('.')) return;
    _current = _current.isEmpty ? '0.' : '$_current.';
  }

  void op(String o) {
    assert(['+', '−', '×', '÷'].contains(o));
    if (_current.isEmpty && _accumulated == null) return;
    if (_current.isNotEmpty) {
      final cur = double.parse(_current);
      if (_accumulated == null) {
        _accumulated = cur;
        _story.add(_trimNum(cur));
      } else {
        _accumulated = _apply(_accumulated!, _pendingOp!, cur);
        _story.add(_trimNum(cur));
      }
      _current = '';
    }
    // Re-tapping an operator just swaps it.
    if (_pendingOp != null && _story.isNotEmpty && _current.isEmpty) {
      if (_story.last == _pendingOp) _story.removeLast();
    }
    _pendingOp = o;
    _story.add(o);
  }

  void backspace() {
    if (_current.isNotEmpty) {
      _current = _current.substring(0, _current.length - 1);
      return;
    }
    if (_pendingOp != null) {
      // Un-choose the operator; reopen the last number for editing.
      _story.removeLast(); // the operator
      _pendingOp = null;
      if (_story.isNotEmpty) {
        _current = _story.removeLast();
        _accumulated = null;
        // Re-fold whatever is left of the story.
        _refold();
      }
    }
  }

  /// Writes a whole figure in at once, replacing whatever was there — the
  /// recents whisper taps this, so it must land exactly, not append.
  void setPaise(int paise) {
    clear();
    if (paise <= 0) return;
    _current = paise % 100 == 0
        ? (paise ~/ 100).toString()
        : (paise / 100).toStringAsFixed(2);
  }

  void clear() {
    _current = '';
    _accumulated = null;
    _pendingOp = null;
    _story.clear();
  }

  void _refold() {
    final parts = List<String>.from(_story);
    _accumulated = null;
    _pendingOp = null;
    for (final p in parts) {
      if (['+', '−', '×', '÷'].contains(p)) {
        _pendingOp = p;
      } else {
        final n = double.parse(p);
        _accumulated = _accumulated == null
            ? n
            : _apply(_accumulated!, _pendingOp!, n);
      }
    }
  }

  static double _apply(double a, String op, double b) => switch (op) {
    '+' => a + b,
    '−' => a - b,
    '×' => a * b,
    '÷' => b == 0 ? a : a / b,
    _ => b,
  };

  static String _trimNum(double v) => v == v.roundToDouble()
      ? v.round().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}
