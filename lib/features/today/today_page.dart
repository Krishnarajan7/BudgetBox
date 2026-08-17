import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cat_inks.dart';
import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tabs.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/db.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints/coaching_api.dart';
import '../../data/providers.dart';
import '../../data/repos/budget_math.dart';
import '../../data/repos/journal_repo.dart' show journalRepoProvider;
import '../book/book_page.dart' show whereItWent;
import '../insights/insights_page.dart';
import '../../core/widgets/feel_picker.dart';
import 'widgets/close_day.dart';
import 'widgets/digit_roll.dart';
import 'widgets/sections.dart';

/// The day's page: it greets, it counts, it knows what yesterday looked
/// like and when salary lands, and at night it takes the stamp. The screen
/// the whole app answers to.
///
/// Composed as a single ledger page, not a stack of cards: the hero figure
/// leads, today's entries sit directly under it, the day is ruled off in
/// vermilion when it closes, and the review sections follow as quiet ruled
/// sections. The page opens settled — motion happens when the book changes,
/// not when it is looked at.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  String _name = 'Krish';
  int _salaryDay = 1;
  bool _yesterdaySealed = false;
  (int, int)? _birthday;
  bool _burst = false;
  final Set<int> _seenTxnIds = {};
  final Set<String> _hiddenCoachingIds = {};
  bool _firstEmission = true;

  /// The hero total as it stood when the page first rendered. While the
  /// figure still matches, the underline sits settled; when an entry moves
  /// it, the pen crosses the page again.
  int? _firstHeroPaise;

  /// Bumped when the spine turns back to this page: the underline re-crosses
  /// under the hero — a page opened is a page the pen touches once.
  int _visitSeq = 0;

  /// A one-breath acknowledgment when fresh money lands on a past page —
  /// shown in place of the subline, then it lets the normal line back.
  String? _pastNote;
  Timer? _pastTimer;

  @override
  void dispose() {
    _pastTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFacts();
  }

  Future<void> _loadFacts() async {
    final settings = ref.read(settingsRepoProvider);
    final db = ref.read(dbProvider);
    final name = await settings.name();
    final salaryDay = await settings.salaryDay();
    final birthday = await settings.birthday();
    final now = DateTime.now();
    // The one day a year the book celebrates — once, then it composes itself.
    var burst = false;
    if (birthday != null &&
        now.day == birthday.$1 &&
        now.month == birthday.$2 &&
        await settings.birthdayBurstDue(now.year)) {
      burst = true;
      await settings.markBirthdayBurst(now.year);
    }
    final yKey = LedgerDates.dayKey(DateTime(now.year, now.month, now.day - 1));
    final ySeal = await (db.select(
      db.daySeals,
    )..where((s) => s.date.equals(yKey))).getSingleOrNull();
    if (mounted) {
      setState(() {
        _name = name;
        _salaryDay = salaryDay;
        _yesterdaySealed = ySeal != null;
        _birthday = birthday;
        _burst = burst;
      });
    }
  }

  Future<void> _dismissCoaching(CoachingInsight insight) async {
    // Move the note away first. The feed already carries several candidates,
    // so waiting for a round-trip here only turns a small choice into a stuck
    // loading state on an ordinary mobile connection.
    setState(() => _hiddenCoachingIds.add(insight.id));

    final config = await ref.read(settingsRepoProvider).serverConfig();
    if (!config.wired) {
      if (mounted) setState(() => _hiddenCoachingIds.remove(insight.id));
      return;
    }

    final client = BbxClient(config);
    try {
      await CoachingApi(client).dismiss(insight.id);
      if (mounted) ref.invalidate(coachingFeedProvider);
    } on Object {
      // A dismissal that never reached the server must not silently lose the
      // advice. Put it back and let the person retry when signal returns.
      if (mounted) setState(() => _hiddenCoachingIds.remove(insight.id));
    } finally {
      client.close();
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'up late';
    if (h < 12) return 'good morning';
    if (h < 17) return 'good afternoon';
    return 'good evening';
  }

  /// One line that occasionally knows things: salary landing beats the date,
  /// a closed yesterday gets a quiet nod, and most days it's just the date.
  String _greetingLine(DateTime now) {
    final base = '$_greeting, $_name';
    final bd = _birthday;
    if (bd != null && now.day == bd.$1 && now.month == bd.$2) {
      return 'happy birthday, $_name';
    }
    if (now.day == _salaryDay) return '$base — salary lands today';
    if (_daysToSalary(now) == 1) return '$base — salary lands tomorrow';
    if (_yesterdaySealed) return '$base — yesterday is sealed';
    return '$base — ${_dateLabel(now)}';
  }

  static String _dateLabel(DateTime d) {
    const days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    const months = [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  int _daysToSalary(DateTime now) {
    var next = DateTime(now.year, now.month, _salaryDay);
    if (!next.isAfter(DateTime(now.year, now.month, now.day))) {
      next = DateTime(now.year, now.month + 1, _salaryDay);
    }
    return next.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final txns = ref.watch(txnRepoProvider);
    final budgets = ref.watch(budgetRepoProvider);
    final coaching = ref.watch(coachingFeedProvider);
    // Watched, not loaded once: changing the answer in Settings reorders
    // this page on the very next frame.
    final intent = ref.watch(intentProvider);
    final now = DateTime.now();

    ref.listen(activeTabProvider, (prev, next) {
      if (next == LedgerTab.today && prev != null && prev != next) {
        setState(() => _visitSeq++);
      }
    });

    return StreamBuilder<List<Budget>>(
      stream: budgets.watchAll(),
      builder: (context, budgetSnap) {
        final monthLimit = (budgetSnap.data ?? const <Budget>[]).fold<int>(
          0,
          (s, b) => s + b.limitPaise,
        );
        return StreamBuilder<List<Txn>>(
          // Two months, one stream: last month rides along so the pulse can
          // say how this month compares at the same day.
          stream: txns.watchRange(
            LedgerDates.monthStart(DateTime(now.year, now.month - 1, 1)),
            LedgerDates.monthEnd(now),
          ),
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <Txn>[];
            final month = [
              for (final t in all)
                if (t.at.year == now.year && t.at.month == now.month) t,
            ];
            final prevMonth = DateTime(now.year, now.month - 1, 1);
            final prevThroughPaise = all
                .where(
                  (t) =>
                      t.type == TxnType.expense &&
                      t.at.year == prevMonth.year &&
                      t.at.month == prevMonth.month &&
                      t.at.day <= now.day,
                )
                .fold(0, (s, t) => s + t.amountPaise);
            final expenses = month
                .where((t) => t.type == TxnType.expense)
                .toList();
            final today = expenses.where((t) => t.at.day == now.day).toList()
              ..sort((a, b) => b.at.compareTo(a.at));
            final todayPaise = today.fold(0, (s, t) => s + t.amountPaise);
            final yesterdayPaise = now.day > 1
                ? expenses
                      .where((t) => t.at.day == now.day - 1)
                      .fold(0, (s, t) => s + t.amountPaise)
                : null;
            final monthPaise = expenses.fold(0, (s, t) => s + t.amountPaise);

            // Which of the month's lines are genuinely new since last frame.
            // Today's fresh lines ink into the list below; fresh lines on
            // PAST days (the catch-up sheet, a back-dated entry) get spoken
            // instead — the hero counts only today, and money written onto
            // an old page with no acknowledgment reads as money lost.
            final freshIds = <int>{};
            if (snapshot.hasData) {
              _firstHeroPaise ??= todayPaise;
              final freshPast = <Txn>[];
              for (final t in month) {
                if (_seenTxnIds.contains(t.id) || _firstEmission) continue;
                if (t.at.day == now.day) {
                  freshIds.add(t.id);
                } else if (t.type == TxnType.expense) {
                  freshPast.add(t);
                }
              }
              _seenTxnIds.addAll(all.map((t) => t.id));
              _firstEmission = false;
              if (freshPast.isNotEmpty) {
                final paise = freshPast.fold(0, (s, t) => s + t.amountPaise);
                final days = {for (final t in freshPast) t.at.day};
                _pastNote = days.length == 1
                    ? '${Inr.format(paise)} added to '
                          '${LedgerDates.ddMmm(freshPast.first.at)}'
                    : '${Inr.format(paise)} added to earlier days';
                _pastTimer?.cancel();
                _pastTimer = Timer(const Duration(seconds: 6), () {
                  if (mounted) setState(() => _pastNote = null);
                });
              }
            }

            final pace = BudgetPace(
              spentPaise: monthPaise,
              limitPaise: monthLimit,
              elapsedDays: now.day,
              totalDays: LedgerDates.daysInMonth(now),
            );
            final monthBalance = budgetBalance(
              limitPaise: monthLimit,
              spentPaise: monthPaise,
            );

            // One color language for the whole page: a category's ink is
            // assigned by its rank in the month and reused everywhere — the
            // chip on its entry, its segment of the bar, its dot on the
            // calendar.
            final slices = whereItWent([
              for (final t in expenses) (t.categoryId, t.amountPaise),
            ], top: 4);
            final catColor = catInks([
              for (final t in expenses) (t.categoryId, t.amountPaise),
            ], c.chartInks);
            final lately = ([
              ...expenses,
            ]..sort((a, b) => b.at.compareTo(a.at))).take(4).toList();

            final coachingNote = coaching.maybeWhen(
              data: (items) {
                final visible = items
                    .where((item) => !_hiddenCoachingIds.contains(item.id))
                    .firstOrNull;
                return visible == null
                    ? null
                    : CoachingNote(
                        key: ValueKey(visible.id),
                        insight: visible,
                        onDismiss: () => _dismissCoaching(visible),
                      );
              },
              orElse: () => null,
            );

            // The one persistent stroke of vermilion the open page carries.
            // It renders settled on open; only a change in the figure above
            // makes the pen cross the page again.
            final settledUnderline =
                todayPaise == (_firstHeroPaise ?? todayPaise) && _visitSeq == 0;
            final underline = settledUnderline
                ? QuillStroke(width: 72, color: c.seal)
                : DrawIn(
                    key: ValueKey('underline-$todayPaise-$_visitSeq'),
                    duration: const Duration(milliseconds: 280),
                    builder: (context, p) =>
                        QuillStroke(width: 72, progress: p, color: c.seal),
                  );

            final page = ListView(
              // Room for the floating glass bar: the page scrolls under
              // it, but its last line must still be able to rise above it.
              padding: EdgeInsets.fromLTRB(
                Gap.page,
                0,
                Gap.page,
                MediaQuery.paddingOf(context).bottom + Gap.x4,
              ),
              children: [
                const LedgerAppBar(),
                const SizedBox(height: Gap.x4),
                Text(
                  _greetingLine(now),
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: 2),
                // The hero and its answer, side by side: the figure is the
                // object, "spent today · N entries" is the caption.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DigitRoll(
                      paise: todayPaise,
                      style: LedgerType.heroAmount
                          .copyWith(fontSize: 64, color: c.ink)
                          .copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                    const SizedBox(width: Gap.x4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'spent today',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 13,
                              color: c.inkFaint,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _reactiveSubline(
                            c,
                            today.length,
                            todayPaise,
                            yesterdayPaise,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.x2),
                Align(alignment: Alignment.centerLeft, child: underline),
                const SizedBox(height: Gap.x3),
                const PinStrip(),
                ?coachingNote,
                MonthPulse(
                  monthPaise: monthPaise,
                  monthLimit: monthLimit,
                  balance: monthBalance,
                  pace: pace,
                  now: now,
                  daysToSalary: _daysToSalary(now),
                  prevThroughPaise: prevThroughPaise,
                ),
                LatelySection(
                  recent: lately,
                  catColor: catColor,
                  freshIds: freshIds,
                  now: now,
                ),
                if (intent == 'goal') const GoalSection(),
                WhereSection(
                  slices: slices,
                  monthPaise: monthPaise,
                  catColor: catColor,
                  trailing: Pressable(
                    onTap: () => Navigator.of(context).push(
                      LedgerRoute<void>(builder: (_) => const InsightsPage()),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'see all',
                          style: LedgerType.bodyStrong.copyWith(
                            fontSize: 11,
                            color: c.quill,
                          ),
                        ),
                        const SizedBox(width: 3),
                        PenArrow(size: 11, color: c.quill),
                      ],
                    ),
                  ),
                ),
                const UpcomingSection(),
                if (intent != 'goal') const GoalSection(),
                CalendarSection(
                  expenses: expenses,
                  monthTxns: month,
                  month: now,
                  today: now.day,
                  catColor: catColor,
                ),
                CloseDayRitual(name: _name, dayTotalPaise: todayPaise),
                const SizedBox(height: Gap.x6),
                const _UnmarkedLine(),
                const SizedBox(height: Gap.x4),
              ],
            );
            if (!_burst) return page;
            // Once a year, and only with motion allowed: the seals rain.
            if (Motion.reduced(context)) return page;
            return Stack(
              children: [
                page,
                Positioned.fill(
                  child: IgnorePointer(
                    child: _BirthdayRain(
                      onDone: () => setState(() => _burst = false),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _reactiveSubline(
    LedgerColors c,
    int count,
    int todayPaise,
    int? yesterdayPaise,
  ) {
    final String line;
    if (_pastNote != null) {
      // Money just landed on an old page — say so before anything else.
      line = _pastNote!;
    } else if (count == 0) {
      final n = _daysToSalary(DateTime.now());
      line = n <= 5
          ? 'no entries yet · salary in $n ${n == 1 ? 'day' : 'days'}'
          : 'no entries yet';
    } else {
      final entries = '$count ${count == 1 ? 'entry' : 'entries'}';
      if (yesterdayPaise == null || yesterdayPaise == 0) {
        line = '$entries so far';
      } else if (todayPaise < yesterdayPaise) {
        line =
            '$entries · ${Inr.format(yesterdayPaise - todayPaise)} lighter than yesterday';
      } else if (todayPaise > yesterdayPaise) {
        line =
            '$entries · ${Inr.format(todayPaise - yesterdayPaise)} past yesterday';
      } else {
        line = '$entries · dead even with yesterday';
      }
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Text(
        line,
        key: ValueKey(line),
        style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
      ),
    );
  }
}

/// Forty small things falling once a year: seals, paper squares, a few
/// status-ink dots. Deterministic per index — no randomness source, same
/// shower every birthday, which is exactly the kind of joke this book tells.
class _BirthdayRain extends StatelessWidget {
  const _BirthdayRain({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final colors = [c.seal, c.jama, c.warn, c.quill];
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 2800),
      onEnd: onDone,
      builder: (context, t, _) {
        return LayoutBuilder(
          builder: (context, box) {
            double n(int i, double salt) =>
                (math.sin(i * 127.1 + salt * 311.7) + 1) / 2;
            return Stack(
              children: [
                for (var i = 0; i < 40; i++)
                  Positioned(
                    left:
                        n(i, 1) * box.maxWidth +
                        math.sin(t * 6.28 * (1 + n(i, 2)) + i) * 18,
                    top:
                        -40 +
                        (box.maxHeight + 80) *
                            Curves.easeIn.transform(
                              ((t * (0.7 + 0.5 * n(i, 3))).clamp(0.0, 1.0)),
                            ),
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0) * 0.9,
                      child: Transform.rotate(
                        angle: t * 6.28 * (n(i, 4) - 0.5) * 3,
                        child: Container(
                          width: 6 + 6 * n(i, 5),
                          height: 6 + 6 * n(i, 5),
                          decoration: BoxDecoration(
                            color: colors[i % colors.length].withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(
                              i % 3 == 0 ? 99 : 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// One quiet line in the evening when the day carries no felt-mark yet.
/// Never a module, never a picker — the field lives in the Daily book; this
/// line only points there, and only after six, and only until it's done.
class _UnmarkedLine extends ConsumerWidget {
  const _UnmarkedLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    if (now.hour < 18) return const SizedBox.shrink();
    return StreamBuilder<JournalEntry?>(
      stream: ref.watch(journalRepoProvider).watch(LedgerDates.dayKey(now)),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.active ||
            snap.data?.mood != null) {
          return const SizedBox.shrink();
        }
        final c = LedgerColors.of(context);
        final key = LedgerDates.dayKey(now);
        return Padding(
          padding: const EdgeInsets.only(bottom: Gap.x4),
          child: Pressable(
            haptic: false,
            // Straight into the picker — the offer and the act, one tap
            // apart.
            onTap: () => showFeelPicker(
              context,
              onCommit: (p, e, w) => ref
                  .read(journalRepoProvider)
                  .upsert(key, mood: p, energy: e, feelWord: w),
              onDetail: (why, tags) => ref
                  .read(journalRepoProvider)
                  .upsert(key, feelWhy: why, feelTags: tags),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "the day's not marked yet",
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(width: Gap.x2),
                Text(
                  'mark it',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: c.quill,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
