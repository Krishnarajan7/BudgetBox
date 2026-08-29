/// The arithmetic behind the month's story — pure, no widgets, testable.
///
/// The intelligence rule: every judgement is against *this category's own
/// past*, never a generic yardstick. "₹2,400 on food" means nothing by
/// itself; "₹600 past its usual pace by the 12th" is something Krish can
/// act on before the month is over.
library;

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
    final past =
        priorTotals
            .map((m) => m[entry.key])
            .whereType<int>()
            .toList()
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
