/// The vocabulary every endpoint file shares: how a wire value becomes a Dart
/// one, and what happens when it can't.
///
/// Three house rules live here, and nowhere else needs to remember them:
///
/// * **Money is integer paise.** A paise field that arrives as a fraction is a
///   contract break, not something to round.
/// * **A calendar day is a `String`** in 'yyyy-MM-dd'. It is not an instant and
///   must never become a [DateTime] — that is exactly how a Konkan-railway
///   midnight turns yesterday's chai into today's.
/// * **An instant is a [DateTime]**, parsed from ISO-8601 and moved to local
///   time so screens can show it without thinking.
///
/// Field names on the wire are snake_case; field names in Dart are not. Every
/// `fromJson` below spells the mapping out by hand, so the wire's shape stops
/// at this layer.
library;

import '../../tables.dart';

/// The wire said something the app cannot honestly read: an unknown enum
/// value, a day that isn't a day, paise that arrived as a fraction.
///
/// Never caught and defaulted away — a silent default is a wrong number on a
/// screen, which is worse than a loud failure.
class WireFormatException implements Exception {
  const WireFormatException(this.message);

  final String message;

  @override
  String toString() => 'wire format: $message';
}

final RegExp _dayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

Never _bad(String key, Object? value, String expected) {
  throw WireFormatException('$key: expected $expected, got ${_show(value)}');
}

String _show(Object? value) {
  if (value == null) return 'nothing';
  if (value is String) return '"$value"';
  return '$value (${value.runtimeType})';
}

/// A decoded JSON object, checked to actually be one.
Map<String, dynamic> wireObject(Object? body) {
  if (body is Map<String, dynamic>) return body;
  if (body is Map) return body.cast<String, dynamic>();
  throw WireFormatException('expected a JSON object, got ${_show(body)}');
}

/// A decoded JSON array of objects, checked and mapped in one step.
List<T> wireList<T>(Object? body, T Function(Map<String, dynamic>) read) {
  if (body is! List) {
    throw WireFormatException('expected a JSON array, got ${_show(body)}');
  }
  return [for (final item in body) read(wireObject(item))];
}

/// `{"key": "value"}` — the settings map, checked.
Map<String, String> wireStringMap(Object? body) {
  final raw = wireObject(body);
  return {
    for (final entry in raw.entries)
      entry.key: entry.value is String
          ? entry.value as String
          : _bad(entry.key, entry.value, 'a string'),
  };
}

/// Typed readers over a decoded JSON object. Each one names the key it failed
/// on, because "expected a whole number, got null" with no key is a bug report
/// nobody can act on.
extension WireJson on Map<String, dynamic> {
  /// A whole number — paise, minutes, counts. Deliberately refuses a double:
  /// money that arrived fractional is a contract break, not a rounding job.
  int whole(String key) {
    final value = this[key];
    if (value is int) return value;
    return _bad(key, value, 'a whole number');
  }

  int? wholeOrNull(String key) => this[key] == null ? null : whole(key);

  /// A fraction or ratio. Never used for money.
  double real(String key) {
    final value = this[key];
    if (value is num) return value.toDouble();
    return _bad(key, value, 'a number');
  }

  double? realOrNull(String key) => this[key] == null ? null : real(key);

  String text(String key) {
    final value = this[key];
    if (value is String) return value;
    return _bad(key, value, 'a string');
  }

  String? textOrNull(String key) => this[key] == null ? null : text(key);

  bool flag(String key) {
    final value = this[key];
    if (value is bool) return value;
    return _bad(key, value, 'a boolean');
  }

  bool? flagOrNull(String key) => this[key] == null ? null : flag(key);

  /// An ISO-8601 instant, brought into local time.
  DateTime instant(String key) {
    final raw = text(key);
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return _bad(key, raw, 'an ISO-8601 date-time');
    return parsed.toLocal();
  }

  DateTime? instantOrNull(String key) =>
      this[key] == null ? null : instant(key);

  /// A calendar day, kept as the 'yyyy-MM-dd' string it is.
  String day(String key) {
    final raw = text(key);
    if (!_dayPattern.hasMatch(raw)) {
      return _bad(key, raw, "a 'yyyy-MM-dd' day");
    }
    return raw;
  }

  String? dayOrNull(String key) => this[key] == null ? null : day(key);

  List<Object?> _array(String key) {
    final value = this[key];
    if (value is List) return value;
    return _bad(key, value, 'an array');
  }

  List<T> objects<T>(String key, T Function(Map<String, dynamic>) read) =>
      [for (final item in _array(key)) read(wireObject(item))];

  T object<T>(String key, T Function(Map<String, dynamic>) read) =>
      read(wireObject(this[key]));

  T? objectOrNull<T>(String key, T Function(Map<String, dynamic>) read) =>
      this[key] == null ? null : read(wireObject(this[key]));

  List<int> wholes(String key) => [
        for (final (i, item) in _array(key).indexed)
          item is int ? item : _bad('$key[$i]', item, 'a whole number'),
      ];

  /// Whole numbers with gaps in them — a month of mood dots, most of them
  /// unrecorded.
  List<int?> wholesOrNulls(String key) => [
        for (final (i, item) in _array(key).indexed)
          if (item == null)
            null
          else
            item is int ? item : _bad('$key[$i]', item, 'a whole number'),
      ];

  List<String> texts(String key) => [
        for (final (i, item) in _array(key).indexed)
          item is String ? item : _bad('$key[$i]', item, 'a string'),
      ];

  List<String> days(String key) => [
        for (final (i, item) in _array(key).indexed)
          if (item is! String)
            _bad('$key[$i]', item, "a 'yyyy-MM-dd' day")
          else if (_dayPattern.hasMatch(item))
            item
          else
            _bad('$key[$i]', item, "a 'yyyy-MM-dd' day"),
      ];

  List<bool> flags(String key) => [
        for (final (i, item) in _array(key).indexed)
          item is bool ? item : _bad('$key[$i]', item, 'a boolean'),
      ];

  /// `{"txn": ["id", …], "account": […]}` — the changes feed's shape.
  Map<String, List<String>> stringLists(String key) {
    final raw = this[key];
    if (raw is! Map) return _bad(key, raw, 'an object of string arrays');
    return {
      for (final entry in raw.entries)
        '${entry.key}': [
          for (final item in (entry.value is List
              ? entry.value as List
              : _bad('$key.${entry.key}', entry.value, 'an array')))
            item is String
                ? item
                : _bad('$key.${entry.key}[]', item, 'a string'),
        ],
    };
  }
}

/// The string↔enum bridge, kept here so `tables.dart` never learns the wire
/// spelling of anything.
///
/// The mapping is total in both directions: a value the app has never heard of
/// throws rather than quietly becoming the first case, because "unknown budget
/// status" silently reading as "on pace" is a lie the screen would tell.
class WireEnum<T> {
  WireEnum(this.what, Map<String, T> toDart)
      : _toDart = toDart,
        _toWire = {for (final e in toDart.entries) e.value: e.key};

  /// What this enum is called in an error message — 'txn type', 'goal kind'.
  final String what;
  final Map<String, T> _toDart;
  final Map<T, String> _toWire;

  T fromWire(Object? raw) {
    if (raw is! String) {
      throw WireFormatException('$what: expected a string, got ${_show(raw)}');
    }
    final value = _toDart[raw];
    if (value == null) {
      throw WireFormatException(
        'unknown $what "$raw" — expected one of ${_toDart.keys.join(', ')}',
      );
    }
    return value;
  }

  T? fromWireOrNull(Object? raw) => raw == null ? null : fromWire(raw);

  String toWire(T value) {
    final raw = _toWire[value];
    if (raw == null) {
      throw WireFormatException('$what $value has no wire spelling');
    }
    return raw;
  }

  String? toWireOrNull(T? value) => value == null ? null : toWire(value);
}

extension WireEnumJson on Map<String, dynamic> {
  T enumAt<T>(String key, WireEnum<T> codec) {
    final raw = this[key];
    if (raw is! String) {
      throw WireFormatException('$key: expected a string, got ${_show(raw)}');
    }
    return codec.fromWire(raw);
  }

  T? enumOrNullAt<T>(String key, WireEnum<T> codec) =>
      this[key] == null ? null : enumAt(key, codec);
}

// ————— the enums the ledger already has names for —————
//
// Spelled out by hand rather than leaning on `.name`, so renaming a Dart enum
// case is a compile error here instead of a silent protocol change.

final accountKindWire = WireEnum<AccountKind>('account kind', const {
  'bank': AccountKind.bank,
  'upi': AccountKind.upi,
  'cash': AccountKind.cash,
  'card': AccountKind.card,
  'asset': AccountKind.asset,
  'liability': AccountKind.liability,
});

final categoryKindWire = WireEnum<CategoryKind>('category kind', const {
  'expense': CategoryKind.expense,
  'income': CategoryKind.income,
});

final txnTypeWire = WireEnum<TxnType>('txn type', const {
  'expense': TxnType.expense,
  'income': TxnType.income,
  'transfer': TxnType.transfer,
});

final recurringKindWire = WireEnum<RecurringKind>('recurring kind', const {
  'bill': RecurringKind.bill,
  'subscription': RecurringKind.subscription,
});

final budgetPeriodWire = WireEnum<BudgetPeriod>('budget period', const {
  'month': BudgetPeriod.month,
  'fy': BudgetPeriod.fy,
  'custom': BudgetPeriod.custom,
});

final budgetKindWire = WireEnum<BudgetKind>('budget kind', const {
  'all': BudgetKind.all,
  'added': BudgetKind.added,
});

final goalKindWire = WireEnum<GoalKind>('goal kind', const {
  'save': GoalKind.save,
  'clear': GoalKind.clear,
});

final activityActionWire = WireEnum<ActivityAction>('activity action', const {
  'created': ActivityAction.created,
  'edited': ActivityAction.edited,
  'deleted': ActivityAction.deleted,
});

final focusKindWire = WireEnum<FocusKind>('focus kind', const {
  'work': FocusKind.work,
  'rest': FocusKind.rest,
});

final eventRepeatWire = WireEnum<EventRepeat>('event repeat', const {
  'none': EventRepeat.none,
  'yearly': EventRepeat.yearly,
});

/// An instant on its way back out: UTC and ISO-8601, so the server never has
/// to guess which midnight was meant.
String wireInstant(DateTime value) => value.toUtc().toIso8601String();

String? wireInstantOrNull(DateTime? value) =>
    value == null ? null : wireInstant(value);

/// The client only takes a query map on `GET`, so the handful of writes that
/// carry both a body and a query build their path here.
String pathWithQuery(String path, Map<String, dynamic> query) {
  final pairs = [
    for (final e in query.entries)
      if (e.value != null)
        '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent('${e.value}')}',
  ];
  return pairs.isEmpty ? path : '$path?${pairs.join('&')}';
}

/// A field the caller may leave alone.
///
/// `PATCH` bodies are applied with `exclude_unset`, so a key that is *present
/// and null* clears the field while a key that is *absent* leaves it as it
/// was. Plain `null` in Dart cannot say both, so the columns that can genuinely
/// be emptied — a transaction's category, a goal's target date, a session's
/// label — take an [Opt] instead:
///
/// ```dart
/// TxnPatch(title: 'chai')                  // category untouched
/// TxnPatch(categoryId: Opt(null))          // category cleared
/// TxnPatch(categoryId: Opt('018f…'))       // category moved
/// ```
///
/// Fields whose column is `NOT NULL` take a plain nullable instead: there,
/// null can only mean "leave it alone", so there is nothing to disambiguate.
class Opt<T> {
  const Opt(this.value);

  final T value;

  @override
  String toString() => 'Opt($value)';
}

/// Builds a request body, skipping the keys the caller never mentioned.
class WireBody {
  final Map<String, dynamic> _fields = {};

  /// Always sent, whatever it holds. Use for a `PUT`'s full replacement.
  void set(String key, Object? value) => _fields[key] = value;

  /// Sent only if the caller supplied it.
  void maybe(String key, Object? value) {
    if (value != null) _fields[key] = value;
  }

  /// Sent — null and all — only if the caller opted in.
  void opt(String key, Opt<Object?>? value) {
    if (value != null) _fields[key] = value.value;
  }

  Map<String, dynamic> build() => _fields;
}
