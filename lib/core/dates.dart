/// Calendar helpers. A "day" is always a local-date string ('yyyy-MM-dd') so
/// timezones can never shift an entry across midnight.
abstract final class LedgerDates {
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

  /// Exclusive end.
  static DateTime monthEnd(DateTime d) => DateTime(d.year, d.month + 1);

  static int daysInMonth(DateTime d) => monthEnd(d).difference(monthStart(d)).inDays;

  /// Indian financial year: April–March. `fyStart(2026-07-31)` = 2026-04-01;
  /// `fyStart(2026-02-10)` = 2025-04-01.
  static DateTime fyStart(DateTime d) =>
      DateTime(d.month >= DateTime.april ? d.year : d.year - 1, DateTime.april);

  static DateTime fyEnd(DateTime d) {
    final s = fyStart(d);
    return DateTime(s.year + 1, DateTime.april);
  }

  /// "FY 26-27" label for the year containing [d].
  static String fyLabel(DateTime d) {
    final s = fyStart(d);
    final a = s.year % 100;
    final b = (s.year + 1) % 100;
    return 'FY ${a.toString().padLeft(2, '0')}-${b.toString().padLeft(2, '0')}';
  }

  static const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const monthsFull = [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static const weekdaysFull = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];

  /// '14 Jul' — the book's date form, DD MMM, never MM/DD.
  static String ddMmm(DateTime d) => '${d.day} ${months[d.month - 1]}';

  /// 'Wed 30 Jul'
  static String dayLabel(DateTime d) => '${weekdays[d.weekday - 1]} ${ddMmm(d)}';
}
