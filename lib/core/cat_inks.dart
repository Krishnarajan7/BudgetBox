import 'dart:ui';

/// The one place category color is decided. A category's ink is assigned by
/// its rank in the viewed month's spending — heaviest first — and the same
/// map is used everywhere a category shows color: the chip on an entry, its
/// segment of the month bar, its dot on the calendar. Categories past the
/// top ranks (and uncategorised spend) get no ink; callers fall back to
/// faint, so color always means "one of the month's main characters".
Map<int?, Color> catInks(
  Iterable<(int?, int)> expensesByCat,
  List<Color> inks, {
  int top = 4,
}) {
  final totals = <int?, int>{};
  for (final (id, paise) in expensesByCat) {
    totals[id] = (totals[id] ?? 0) + paise;
  }
  final ranked = totals.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final map = <int?, Color>{};
  for (final (i, e) in ranked.take(top).indexed) {
    map[e.key] = inks[i % inks.length];
  }
  return map;
}
