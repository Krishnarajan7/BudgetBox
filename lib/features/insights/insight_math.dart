/// The arithmetic behind the month's story — pure, no widgets, testable.
///
/// The intelligence rule: every judgement is against *this category's own
/// past*, never a generic yardstick. "₹2,400 on food" means nothing by
/// itself; "₹600 past its usual pace by the 12th" is something Krish can
/// act on before the month is over.
library;

import 'dart:math' as math;

/// One category's month, judged against its own history.
class CategoryStory {
  const CategoryStory({
    required this.categoryId,
    required this.paise,
    required this.count,
    required this.share,
    required this.biggestPaise,
    required this.biggestTitle,
    required this.usualPaise,
    required this.verdict,
  });

  final int? categoryId;
  final int paise;
  final int count;

  /// Of the month's spending, 0…1.
  final double share;
  final int biggestPaise;
  final String biggestTitle;

  /// The median of the previous months' spend *through the same day* —
  /// null when there is no history to judge against.
  final int? usualPaise;
  final CategoryVerdict verdict;

  /// paise - usual: positive is running hot. 0 when unjudgeable.
  int get overPaise => usualPaise == null ? 0 : paise - usualPaise!;
}

enum CategoryVerdict {
  /// No prior months carry this category: nothing to judge against.
  firstMonth,

  /// One entry is most of the category — a purchase, not a habit.
  oneBigLine,

  /// Meaningfully past its own usual pace.
  runningHot,

  /// Meaningfully under it.
  runningCool,

  /// Within a band of its usual self.
  steady,
}

/// How far from usual counts as news. A fifth, and at least ₹200 — a ₹40
/// swing on chai is not a story.
const _hotBand = 0.20;
const _hotFloorPaise = 20_000;

/// One entry holding this much of its category is the story of the category.
const _oneLineShare = 0.60;

/// Spend rows are (categoryId, amountPaise, title) — expenses only,
/// pre-filtered by the caller.
typedef SpendRow = (int? categoryId, int paise, String title);

/// The month, told category by category, heaviest first.
///
/// [priorMonths] are the same rows for each of the preceding months,
/// each already **cut to the same day-of-month** as [rows] when the month
/// under judgement is still running — pace compares like with like.
List<CategoryStory> categoryStories(
  List<SpendRow> rows,
  List<List<SpendRow>> priorMonths,
) {
  final total = rows.fold(0, (s, r) => s + r.$2);
  if (total <= 0) return const [];

  final byCat = <int?, List<SpendRow>>{};
  for (final r in rows) {
    byCat.putIfAbsent(r.$1, () => []).add(r);
  }

  // Each prior month's per-category totals, for the medians.
  final priorTotals = <Map<int?, int>>[];
  for (final month in priorMonths) {
    final totals = <int?, int>{};
    for (final r in month) {
      totals[r.$1] = (totals[r.$1] ?? 0) + r.$2;
    }
    priorTotals.add(totals);
  }

  final stories = <CategoryStory>[];
  for (final entry in byCat.entries) {
    final spent = entry.value.fold(0, (s, r) => s + r.$2);
    final biggest = entry.value.reduce((a, b) => a.$2 >= b.$2 ? a : b);

    // The usual: median of the prior months that *knew* this category.
    // Months without it are skipped rather than counted as zero — three
    // quiet months would otherwise teach the book that any spending at
    // all is "running hot".
    final past = priorTotals.map((m) => m[entry.key]).whereType<int>().toList()
      ..sort();
    final usual = past.isEmpty ? null : past[past.length ~/ 2];

    // Pace first, explanation second. "Mostly one line" is only worth
    // saying when it *explains a hot month* — one entry among several
    // carrying the overshoot. Blanket-labelling every single-entry
    // category "one big line" (the first cut here) buried the pace
    // verdicts, which are the ones that change behaviour.
    CategoryVerdict verdict;
    if (usual == null) {
      verdict = CategoryVerdict.firstMonth;
    } else if (spent - usual >= _hotFloorPaise &&
        spent >= usual * (1 + _hotBand)) {
      verdict = CategoryVerdict.runningHot;
    } else if (usual - spent >= _hotFloorPaise &&
        spent <= usual * (1 - _hotBand)) {
      verdict = CategoryVerdict.runningCool;
    } else {
      verdict = CategoryVerdict.steady;
    }
    if (verdict == CategoryVerdict.runningHot &&
        entry.value.length > 1 &&
        biggest.$2 / spent >= _oneLineShare) {
      verdict = CategoryVerdict.oneBigLine;
    }

    stories.add(
      CategoryStory(
        categoryId: entry.key,
        paise: spent,
        count: entry.value.length,
        share: spent / total,
        biggestPaise: biggest.$2,
        biggestTitle: biggest.$3,
        usualPaise: usual,
        verdict: verdict,
      ),
    );
  }
  stories.sort((a, b) => b.paise.compareTo(a.paise));
  return stories;
}

// ————— the shape of the month's days —————

/// Paise spent on each day of the month: rows are (dayOfMonth, paise),
/// expenses only, pre-filtered by the caller. Days outside the month are
/// dropped rather than crashing on a bad clock.
List<int> dailyTotals(Iterable<(int, int)> rows, int daysInMonth) {
  final days = List<int>.filled(daysInMonth, 0);
  for (final (day, paise) in rows) {
    if (day >= 1 && day <= daysInMonth) days[day - 1] += paise;
  }
  return days;
}

/// The day that carried the month — named only when it genuinely stands
/// out: at least twice an average elapsed day, and at least ₹500. A flat
/// month has no heaviest day worth a sentence.
(int day, int paise)? heaviestDay(List<int> daily, {required int elapsed}) {
  final n = elapsed < daily.length ? elapsed : daily.length;
  if (n < 2) return null;
  var top = 0;
  var total = daily[0];
  for (var i = 1; i < n; i++) {
    total += daily[i];
    if (daily[i] > daily[top]) top = i;
  }
  if (total <= 0) return null;
  final paise = daily[top];
  if (paise < 50_000 || paise * n < total * 2) return null;
  return (top + 1, paise);
}

/// The quietest seven-day stretch — spoken only when the month is old
/// enough to have one (14 elapsed days) and the stretch is genuinely
/// quiet: half or less of what an average week cost.
(int startDay, int paise)? quietestWeek(
  List<int> daily, {
  required int elapsed,
}) {
  final n = elapsed < daily.length ? elapsed : daily.length;
  if (n < 14) return null;
  var total = 0;
  for (var i = 0; i < n; i++) {
    total += daily[i];
  }
  if (total <= 0) return null;
  var window = 0;
  for (var i = 0; i < 7; i++) {
    window += daily[i];
  }
  var best = window;
  var bestStart = 0;
  for (var i = 7; i < n; i++) {
    window += daily[i] - daily[i - 7];
    if (window < best) {
      best = window;
      bestStart = i - 6;
    }
  }
  // Twice the average week or better stays unremarkable; half or less
  // earns the line.
  if (best * n * 2 > total * 7) return null;
  return (bestStart + 1, best);
}

/// Where the month lands at its current pace, judged against a usual
/// month — the median of the full prior-month totals. Null while the
/// month is too young to extrapolate honestly (under 7 days) or already
/// on its last day, when the figure above is no longer a projection.
({int projected, int? usual})? paceProjection({
  required int spentPaise,
  required int elapsedDays,
  required int daysInMonth,
  required List<int> priorMonthTotals,
}) {
  if (elapsedDays < 7 || elapsedDays >= daysInMonth || spentPaise <= 0) {
    return null;
  }
  final projected = (spentPaise / elapsedDays * daysInMonth).round();
  final priors = [...priorMonthTotals.where((t) => t > 0)]..sort();
  final usual = priors.isEmpty ? null : priors[priors.length ~/ 2];
  return (projected: projected, usual: usual);
}

// ————— what the book notices about *how* he writes —————

/// A line he keeps writing by hand that should be one tap: the same title
/// three or more times in the window, at a steady amount.
class PinCandidate {
  const PinCandidate({
    required this.title,
    required this.amountPaise,
    required this.count,
    required this.categoryId,
    required this.accountId,
  });

  final String title;

  /// The amount he writes most often for it.
  final int amountPaise;
  final int count;
  final int? categoryId;
  final int accountId;
}

/// Rows are (title, amountPaise, categoryId, accountId) — expenses only,
/// already cut to the window. [taken] are titles already pinned or passed
/// on, [categoryNames] the titles the add sheet writes when he leaves the
/// line blank (those are not habits, they are blanks). Most repeated first.
List<PinCandidate> pinCandidates(
  Iterable<(String, int, int?, int)> rows, {
  Set<String> taken = const {},
  Set<String> categoryNames = const {},
  int minCount = 3,
}) {
  final byTitle = <String, List<(String, int, int?, int)>>{};
  for (final r in rows) {
    final key = r.$1.trim().toLowerCase();
    if (key.isEmpty) continue;
    if (taken.contains(key)) continue;
    if (categoryNames.contains(key)) continue;
    // "rapido * 2" is not rapido.
    if (RegExp(r'[*×x]\s*\d|\d\s*[*×x]').hasMatch(key)) continue;
    byTitle.putIfAbsent(key, () => []).add(r);
  }
  final out = <PinCandidate>[];
  for (final e in byTitle.entries) {
    if (e.value.length < minCount) continue;
    // The mode of the amounts; on a tie, the most recent wins (rows arrive
    // newest first).
    final counts = <int, int>{};
    for (final r in e.value) {
      counts[r.$2] = (counts[r.$2] ?? 0) + 1;
    }
    var best = e.value.first.$2;
    var bestN = 0;
    for (final r in e.value) {
      final n = counts[r.$2]!;
      if (n > bestN) {
        bestN = n;
        best = r.$2;
      }
    }
    // A habit has a price; wildly different amounts each time is not one.
    if (bestN * 2 < e.value.length && e.value.length < 5) continue;
    final first = e.value.first;
    out.add(
      PinCandidate(
        title: first.$1.trim(),
        amountPaise: best,
        count: e.value.length,
        categoryId: first.$3,
        accountId: first.$4,
      ),
    );
  }
  out.sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// A line that reads like a standing charge but sits on no shelf: rent,
/// a premium, a membership, a renewal. Yearly when the title says so.
class RecurringCandidate {
  const RecurringCandidate({
    required this.title,
    required this.amountPaise,
    required this.day,
    required this.everyMonths,
    required this.categoryId,
    required this.accountId,
    required this.at,
  });

  final String title;
  final int amountPaise;
  final int day;
  final int everyMonths;
  final int? categoryId;
  final int accountId;
  final DateTime at;
}

final _standingWords = RegExp(
  r'\b(rent|pg|hostel|premium|membership|renew|renewal|subscription|'
  r'recharge|emi|netflix|spotify|prime|domain|wifi|broadband|electricity|'
  r'gym|insurance|sip)\b',
  caseSensitive: false,
);
final _yearlyWords = RegExp(
  r'\b(1 ?yr|year|yearly|annual|12 ?months)\b',
  caseSensitive: false,
);

/// Rows are (title, amountPaise, categoryId, categoryName, accountId, at).
/// [existing] are titles already on the recurring shelf. One candidate per
/// title, the latest instance, heaviest first.
List<RecurringCandidate> recurringCandidates(
  Iterable<(String, int, int?, String?, int, DateTime)> rows, {
  Set<String> existing = const {},
}) {
  final seen = <String, RecurringCandidate>{};
  for (final r in rows) {
    final title = r.$1.trim();
    final key = title.toLowerCase();
    if (key.isEmpty || existing.contains(key)) continue;
    final cat = (r.$4 ?? '').toLowerCase();
    final standing =
        _standingWords.hasMatch(title) ||
        cat.contains('rent') ||
        cat.contains('bills');
    if (!standing) continue;
    // A deposit or an advance is paid once, however much it looks like rent.
    if (RegExp(
      r'advance|deposit|caution',
      caseSensitive: false,
    ).hasMatch(title)) {
      continue;
    }
    // A small recharge is a top-up, and one "for mom" is a gift — neither
    // is a standing charge, whatever the category says.
    final recharge = RegExp(
      r'recharge|top ?up',
      caseSensitive: false,
    ).hasMatch(title);
    final forSomeone = RegExp(
      r'\bfor (mom|dad|amma|appa|papa|sis|bro|grand)',
      caseSensitive: false,
    ).hasMatch(title);
    if (forSomeone) continue;
    if ((recharge || cat.contains('bills')) && r.$2 < 30000) continue;
    final prior = seen[key];
    if (prior != null && !r.$6.isAfter(prior.at)) continue;
    seen[key] = RecurringCandidate(
      title: title,
      amountPaise: r.$2,
      day: r.$6.day,
      everyMonths: _yearlyWords.hasMatch(title) ? 12 : 1,
      categoryId: r.$3,
      accountId: r.$5,
      at: r.$6,
    );
  }
  return seen.values.toList()
    ..sort((a, b) => b.amountPaise.compareTo(a.amountPaise));
}

// ————— the budget, judged against the month it is actually in —————

/// One line the budget page should say about itself: a limit that no
/// longer matches how the month is going, or a category spending real
/// money with no line drawn for it.
class BudgetFit {
  const BudgetFit({
    required this.kind,
    required this.name,
    required this.categoryId,
    required this.budgetId,
    required this.limitPaise,
    required this.suggestedPaise,
    required this.projectedPaise,
    required this.spentPaise,
  });

  final BudgetFitKind kind;
  final String name;
  final int? categoryId;

  /// Null when the category has no budget yet.
  final int? budgetId;
  final int limitPaise;
  final int suggestedPaise;
  final int projectedPaise;
  final int spentPaise;
}

enum BudgetFitKind {
  /// The month will land well past the line: raise it to the truth.
  raise,

  /// The month will land well under it: lower it, free the rest.
  lower,

  /// Nothing has been written against it most of the way through.
  unused,

  /// Real spending, no line at all.
  missing,
}

/// A budget line with what the month has done against it.
typedef BudgetLine = ({
  int budgetId,
  int? categoryId,
  String name,
  int limitPaise,
  int spentPaise,

  /// How many entries the month has written against it. One or two
  /// (the rent, the premium) is a lump, not a pace — it is not projected.
  int count,
});

/// Round a rupee figure the way a person would set a budget: to ₹100
/// under ₹5,000, to ₹500 above it.
int roundBudget(int paise) {
  final step = paise >= 500000 ? 50000 : 10000;
  return (paise / step).round() * step;
}

/// Judge every line against the month so far, and every unbudgeted
/// category against the money it is already taking. [unbudgeted] maps a
/// category id to its name and month-to-date spend. Nothing is said before
/// the 7th — a week is the least a projection can stand on.
List<BudgetFit> budgetFits({
  required List<BudgetLine> lines,
  required Map<int, (String, int)> unbudgeted,
  required int elapsedDays,
  required int daysInMonth,
}) {
  if (elapsedDays < 7) return const [];
  int project(int spent) => (spent / elapsedDays * daysInMonth).round();
  final out = <BudgetFit>[];
  for (final l in lines) {
    final projected = l.count <= 2 ? l.spentPaise : project(l.spentPaise);
    if (l.limitPaise > 0 && l.spentPaise == 0 && elapsedDays >= 20) {
      out.add(
        BudgetFit(
          kind: BudgetFitKind.unused,
          name: l.name,
          categoryId: l.categoryId,
          budgetId: l.budgetId,
          limitPaise: l.limitPaise,
          suggestedPaise: 0,
          projectedPaise: 0,
          spentPaise: 0,
        ),
      );
      continue;
    }
    if (projected >= l.limitPaise * 1.35 && projected - l.limitPaise >= 50000) {
      out.add(
        BudgetFit(
          kind: BudgetFitKind.raise,
          name: l.name,
          categoryId: l.categoryId,
          budgetId: l.budgetId,
          limitPaise: l.limitPaise,
          suggestedPaise: roundBudget((projected * 1.05).round()),
          projectedPaise: projected,
          spentPaise: l.spentPaise,
        ),
      );
    } else if (l.spentPaise > 0 &&
        projected <= l.limitPaise * 0.65 &&
        l.limitPaise - projected >= 100000) {
      out.add(
        BudgetFit(
          kind: BudgetFitKind.lower,
          name: l.name,
          categoryId: l.categoryId,
          budgetId: l.budgetId,
          limitPaise: l.limitPaise,
          suggestedPaise: roundBudget((projected * 1.15).round()),
          projectedPaise: projected,
          spentPaise: l.spentPaise,
        ),
      );
    }
  }
  for (final e in unbudgeted.entries) {
    final (name, spent) = e.value;
    if (spent < 50000) continue;
    final projected = project(spent);
    out.add(
      BudgetFit(
        kind: BudgetFitKind.missing,
        name: name,
        categoryId: e.key,
        budgetId: null,
        limitPaise: 0,
        suggestedPaise: roundBudget(projected),
        projectedPaise: projected,
        spentPaise: spent,
      ),
    );
  }
  // The biggest money first, whichever way it points.
  out.sort(
    (a, b) => (b.projectedPaise - b.limitPaise).abs().compareTo(
      (a.projectedPaise - a.limitPaise).abs(),
    ),
  );
  return out;
}

/// A title he has filed two ways — 'rapido' under Getting around four
/// times and under Tickets & travel twice. The book never guesses which
/// is right; it offers to move the minority to where he files it most.
class SplitTitle {
  const SplitTitle({
    required this.title,
    required this.toCategoryId,
    required this.toName,
    required this.majority,
    required this.minorityIds,
    required this.fromNames,
  });

  final String title;
  final int toCategoryId;
  final String toName;
  final int majority;
  final List<int> minorityIds;
  final List<String> fromNames;
}

/// Rows are (txnId, title, categoryId, categoryName) — expenses with a
/// category. A title counts as split only when filed at least twice under
/// its main category, so one slip against one habit is never a lecture.
List<SplitTitle> splitTitles(Iterable<(int, String, int, String)> rows) {
  final byTitle = <String, Map<int, List<(int, String)>>>{};
  for (final (id, title, catId, catName) in rows) {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) continue;
    byTitle.putIfAbsent(key, () => {}).putIfAbsent(catId, () => []).add((
      id,
      catName,
    ));
  }
  final out = <SplitTitle>[];
  for (final e in byTitle.entries) {
    if (e.value.length < 2) continue;
    final ranked = e.value.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final main = ranked.first;
    if (main.value.length < 2) continue;
    final minority = [
      for (final r in ranked.skip(1))
        for (final (id, _) in r.value) id,
    ];
    final fromNames = {
      for (final r in ranked.skip(1)) r.value.first.$2,
    }.toList();
    out.add(
      SplitTitle(
        title: e.key,
        toCategoryId: main.key,
        toName: main.value.first.$2,
        majority: main.value.length,
        minorityIds: minority,
        fromNames: fromNames,
      ),
    );
  }
  out.sort((a, b) => b.minorityIds.length.compareTo(a.minorityIds.length));
  return out;
}

/// The month split into what it costs to *live* and what it cost *once* —
/// the question a first month somewhere new actually asks. Rows are
/// (title, amountPaise, categoryName).
class RunningMonth {
  const RunningMonth({
    required this.runningPaise,
    required this.oneOffPaise,
    required this.oneOffs,
  });

  final int runningPaise;
  final int oneOffPaise;

  /// The one-offs, heaviest first: (title, paise).
  final List<(String, int)> oneOffs;
}

final _oneOffCategories = RegExp(
  r'ticket|travel|gadget|gear|clothes|shoes|gift|family|fun|extras|games',
  caseSensitive: false,
);
final _oneOffTitles = RegExp(
  r'advance|deposit|flight|train|bus ticket|domain|for 1 ?yr|yearly|annual|'
  r'pillow|mattress|bucket|setup|set up|wedding|bday|birthday|gift',
  caseSensitive: false,
);

RunningMonth runningMonth(Iterable<(String, int, String?)> rows) {
  var running = 0;
  var once = 0;
  final ones = <(String, int)>[];
  for (final (title, paise, cat) in rows) {
    final isOnce =
        _oneOffCategories.hasMatch(cat ?? '') || _oneOffTitles.hasMatch(title);
    if (isOnce) {
      once += paise;
      ones.add((title, paise));
    } else {
      running += paise;
    }
  }
  ones.sort((a, b) => b.$2.compareTo(a.$2));
  return RunningMonth(runningPaise: running, oneOffPaise: once, oneOffs: ones);
}

/// The one sentence worth putting above everything: the hottest runner, or
/// the quiet verdict that nothing is unusual. Null when the month is empty.
(CategoryStory story, bool calm)? headline(List<CategoryStory> stories) {
  if (stories.isEmpty) return null;
  CategoryStory? hottest;
  for (final s in stories) {
    if (s.verdict != CategoryVerdict.runningHot) continue;
    if (hottest == null || s.overPaise > hottest.overPaise) hottest = s;
  }
  if (hottest != null) return (hottest, false);
  // Nothing hot: the heaviest category carries the calm verdict.
  return (stories.first, true);
}

// ————— in your hands: what in the month was his to move —————

/// The kinds of pattern the flexible spend can be read for.
enum HabitKind {
  /// A small thing bought again and again — rides, chai, a snack.
  often,

  /// One shop or one word carrying real money in a few visits.
  shop,

  /// Standing charges he could cancel: memberships, premiums, renewals.
  standing,

  /// Lines that carry only a category name — money the page can't read.
  unnamed,

  /// Weekends carrying most of what was in his hands.
  weekend,
}

/// One pattern, named from the lines, with its pace and the year it adds
/// up to. Every rupee traces to a line in the book.
class Habit {
  const Habit({
    required this.key,
    required this.kind,
    required this.label,
    required this.count,
    required this.paise,
    required this.days,
    required this.search,
  });

  /// Stable across months, so "that's fine" sticks: `often:rapido`.
  final String key;
  final HabitKind kind;
  final String label;
  final int count;
  final int paise;

  /// The days of evidence behind [paise].
  final int days;

  /// The word to open the book on.
  final String search;

  int get monthPaise => days <= 0 ? paise : (paise / days * 30.4).round();
  int get yearPaise => days <= 0 ? paise : (paise / days * 365).round();
}

/// The month split into what he cannot move and what he can, with the
/// habits found in the second half.
class Hands {
  const Hands({
    required this.fixedPaise,
    required this.flexiblePaise,
    required this.habits,
  });

  final int fixedPaise;
  final int flexiblePaise;
  final List<Habit> habits;

  int get totalPaise => fixedPaise + flexiblePaise;

  /// 0..1 of the month that was his to move.
  double get share => totalPaise == 0 ? 0 : flexiblePaise / totalPaise;
}

/// Round enough to say "about": to ₹100 above ₹1,000, to ₹10 below it.
/// A projection quoted to the rupee would be lying about its precision.
int roundNear(int paise) => paise >= 100_000
    ? (paise / 10_000).round() * 10_000
    : (paise / 1_000).round() * 1_000;

final _fixedCategories = RegExp(
  r'rent|bills|emi|loan|insurance|fees|tuition|health',
  caseSensitive: false,
);
final _fixedTitles = RegExp(
  r'\b(rent|pg|hostel|emi|electricity|wifi|broadband|water bill|gas bill|'
  r'maintenance|insurance|advance|deposit|domain|hosting|server)\b',
  caseSensitive: false,
);
final _standingTitles = RegExp(
  r'\b(membership|premium|subscription|renew|renewal|netflix|spotify|prime|'
  r'hotstar|youtube|icloud|gym)\b',
  caseSensitive: false,
);

/// Words that name a habit better than the word itself would.
const _habitGroups = <(String, String)>[
  (r'rapido|uber|ola|auto|cab|taxi', 'rides'),
  (r'tea|chai|coffee', 'chai and coffee'),
  (r'swiggy|zomato|blinkit|zepto|instamart|dunzo', 'ordered in'),
  (r'cigarette|cigs|smoke|smokes|vape|hookah', 'smokes'),
  (r'juice|shake|milkshake|pepsi|coke|cola|drinks?', 'drinks'),
];

const _stopWords = {
  'and', 'the', 'for', 'from', 'with', 'of', 'to', 'at', 'in', 'on', 'x', //
  'a', 'an', 'my', 'me', 'sir', 'bday', 'birthday', 'stuff', 'stuffs', //
  'etc', 'things', 'new', 'old', 'some', 'small', 'big', 'one', 'two',
};

String _stem(String w) {
  if (w.length > 4 && w.endsWith('s')) return w.substring(0, w.length - 1);
  return w;
}

/// Rows are (id, title, amountPaise, categoryName, at). [days] is the span
/// of evidence the rows cover, ending at [until] (the latest line when
/// null); [claimed] are ids a Work project owns — a client's domain is not
/// his habit. [muted] are habit keys he has called fine.
Hands hands(
  Iterable<(int, String, int, String?, DateTime)> rows, {
  required int days,
  DateTime? until,
  Set<int> claimed = const {},
  Set<String> muted = const {},
}) {
  var fixed = 0;
  var flexible = 0;
  final loose = <(int, String, int, String?, DateTime)>[];
  for (final r in rows) {
    if (claimed.contains(r.$1)) continue;
    final cat = r.$4 ?? '';
    final isFixed =
        _fixedCategories.hasMatch(cat) || _fixedTitles.hasMatch(r.$2);
    if (isFixed) {
      fixed += r.$3;
    } else {
      flexible += r.$3;
      loose.add(r);
    }
  }
  final habits = <Habit>[];

  // Lines that carry only a category name say nothing about a habit; they
  // are counted apart and named as the gap they are.
  final named = <(int, String, int, String?, DateTime)>[];
  var unnamedCount = 0;
  var unnamedPaise = 0;
  for (final r in loose) {
    final t = r.$2.trim().toLowerCase();
    final c = (r.$4 ?? '').trim().toLowerCase();
    if (t.isEmpty || t == c) {
      unnamedCount++;
      unnamedPaise += r.$3;
    } else {
      named.add(r);
    }
  }

  // ————— the words that keep coming back —————
  final byWord = <String, Set<int>>{};
  final labelFor = <String, String>{};
  final wordRows = <int, (int, String, int, String?, DateTime)>{
    for (final r in named) r.$1: r,
  };
  for (final r in named) {
    final words = r.$2
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((w) => w.length >= 3 && !_stopWords.contains(w))
        .map(_stem)
        .toSet();
    final keys = <String>{};
    for (final w in words) {
      String? group;
      for (final (re, label) in _habitGroups) {
        if (RegExp('^(?:$re)\$').hasMatch(w)) {
          group = label;
          break;
        }
      }
      final key = group ?? w;
      keys.add(key);
      labelFor[key] = group ?? w;
    }
    for (final k in keys) {
      byWord.putIfAbsent(k, () => {}).add(r.$1);
    }
  }
  final candidates = byWord.entries.toList()
    ..sort((a, b) {
      final c = b.value.length.compareTo(a.value.length);
      if (c != 0) return c;
      return a.key.compareTo(b.key);
    });
  final taken = <int>{};
  for (final e in candidates) {
    if (e.value.length < 3) break;
    final overlap = e.value.where(taken.contains).length;
    if (overlap * 2 >= e.value.length) continue;
    final ids = e.value.where((id) => !taken.contains(id)).toList();
    if (ids.length < 3) continue;
    var total = 0;
    var max = 0;
    for (final id in ids) {
      final p = wordRows[id]!.$3;
      total += p;
      if (p > max) max = p;
    }
    final isShop = total >= 200_000 && max >= 70_000;
    if (!isShop && total < 20_000) continue;
    taken.addAll(ids);
    // A small habit that began mid-window — the rides that started with
    // the move — is paced from its first line, or its pace would be told
    // thin. A shop's visits are lumpy and keep the whole window.
    var span = days;
    if (!isShop) {
      final first = ids
          .map((id) => wordRows[id]!.$5)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final end =
          until ??
          loose.map((r) => r.$5).reduce((a, b) => a.isAfter(b) ? a : b);
      final lived = end.difference(first).inDays + 1;
      span = math.min(days, math.max(7, lived));
    }
    final kind = isShop ? HabitKind.shop : HabitKind.often;
    final label = labelFor[e.key]!;
    final key = '${isShop ? 'shop' : 'often'}:${e.key}';
    if (muted.contains(key)) continue;
    // The word to search the book by: a group has many words, so the one
    // that names most of its lines carries the search.
    final search = _habitGroups.any((g) => g.$2 == label)
        ? _commonWord([for (final id in ids) wordRows[id]!.$2], e.key)
        : e.key;
    habits.add(
      Habit(
        key: key,
        kind: kind,
        label: label,
        count: ids.length,
        paise: total,
        days: span,
        search: search,
      ),
    );
  }

  // ————— standing charges he could cancel —————
  final standing = [
    for (final r in named)
      if (_standingTitles.hasMatch(r.$2)) r,
  ];
  if (standing.isNotEmpty && !muted.contains('standing')) {
    var year = 0;
    for (final r in standing) {
      year += _yearlyWords.hasMatch(r.$2) ? r.$3 : r.$3 * 12;
    }
    final titles = standing.map((r) => r.$2.trim()).toSet().take(3).join(', ');
    habits.add(
      Habit(
        key: 'standing',
        kind: HabitKind.standing,
        label: titles,
        count: standing.length,
        paise: year,
        // The year figure is already a year: no pace to project.
        days: 0,
        search: _firstWord(standing.first.$2, ''),
      ),
    );
  }

  // ————— weekends carrying the month —————
  if (!muted.contains('weekend')) {
    var weekend = 0;
    final weekendDays = <String>{};
    for (final r in named) {
      final wd = r.$5.weekday;
      if (wd == DateTime.saturday || wd == DateTime.sunday) {
        weekend += r.$3;
        weekendDays.add('${r.$5.year}-${r.$5.month}-${r.$5.day}');
      }
    }
    final namedTotal = named.fold(0, (s, r) => s + r.$3);
    if (weekendDays.length >= 3 &&
        namedTotal > 0 &&
        weekend * 2 > namedTotal &&
        weekend >= 200_000) {
      habits.add(
        Habit(
          key: 'weekend',
          kind: HabitKind.weekend,
          label: 'weekends',
          count: weekendDays.length,
          paise: weekend,
          days: days,
          search: '',
        ),
      );
    }
  }

  if (unnamedCount >= 3 && !muted.contains('unnamed')) {
    habits.add(
      Habit(
        key: 'unnamed',
        kind: HabitKind.unnamed,
        label: 'unnamed lines',
        count: unnamedCount,
        paise: unnamedPaise,
        days: 0,
        search: '',
      ),
    );
  }

  // Heaviest first, but the gap in the evidence goes last: it is a note
  // about the page, not a habit.
  habits.sort((a, b) {
    if (a.kind == HabitKind.unnamed) return 1;
    if (b.kind == HabitKind.unnamed) return -1;
    return b.paise.compareTo(a.paise);
  });
  return Hands(fixedPaise: fixed, flexiblePaise: flexible, habits: habits);
}

String _commonWord(List<String> titles, String fallback) {
  final tally = <String, int>{};
  for (final t in titles) {
    final w = _firstWord(t, '');
    if (w.isNotEmpty) tally[w] = (tally[w] ?? 0) + 1;
  }
  if (tally.isEmpty) return fallback;
  return tally.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

String _firstWord(String title, String fallback) {
  final words = title
      .toLowerCase()
      .split(RegExp(r'[^a-z]+'))
      .where((w) => w.length >= 3 && !_stopWords.contains(w));
  for (final w in words) {
    for (final (re, _) in _habitGroups) {
      if (RegExp('^(?:$re)\$').hasMatch(_stem(w))) return w;
    }
  }
  return words.isEmpty ? fallback : words.first;
}

/// The sentence under a habit: its pace, and what half of it back would
/// be over a year. Standing charges and the unnamed gap are told plainly.
String habitLine(Habit h) {
  String rs(int p) => _inr(p);
  switch (h.kind) {
    case HabitKind.often:
      return '${h.count} times in ${h.days} days — about '
          '${rs(roundNear(h.monthPaise))} a month at this pace, '
          '${rs(roundNear(h.yearPaise))} a year. half of it back is '
          '${rs(roundNear(h.yearPaise ~/ 2))}.';
    case HabitKind.shop:
      return '${h.count} visits in ${h.days} days — '
          '${rs(roundNear(h.yearPaise))} a year if it keeps this pace.';
    case HabitKind.standing:
      return '${h.count} standing ${h.count == 1 ? 'charge' : 'charges'} — '
          '${rs(h.paise)} a year to keep, or a tap to stop.';
    case HabitKind.weekend:
      return '${h.count} weekend days carried more than the weekdays did — '
          '${rs(h.paise)} of what was in your hands.';
    case HabitKind.unnamed:
      return '${h.count} lines this page cannot read — ${rs(h.paise)}. '
          'a word as you write is all it takes.';
  }
}

String _inr(int paise) {
  final r = paise ~/ 100;
  final s = r.toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}
