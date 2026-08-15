import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/feel.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/feel_glyph.dart';
import '../../core/widgets/feel_picker.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/event_repo.dart';
import '../../data/repos/focus_repo.dart';
import '../../data/repos/habit_repo.dart';
import '../../data/repos/journal_repo.dart';
import '../../data/repos/marks_repo.dart';
import '../journal/journal_page.dart';
import 'water_page.dart';

/// The Daily book: one day of a life, kept the way the ledger keeps money.
///
/// The page is a *day*, not a checklist — pick any of the last five weeks
/// and it all follows: the habits he keeps (ticked, or counted toward a
/// number), what he ate, how it felt, the clean count that is measured by
/// its absence, and — read-only, gathered from the other books in the box —
/// the thread of what that day actually contained: money spent, minutes sat
/// in focus, what the calendar had to say.
///
/// Wording rule for this page: no metaphors on interactive things. A person
/// mid-tap should never have to stop and decode.
class DailyPage extends ConsumerStatefulWidget {
  const DailyPage({super.key});

  @override
  ConsumerState<DailyPage> createState() => _DailyPageState();
}

/// How far back the page can be scrolled — five weeks of squares is a habit
/// you can see the shape of, and short enough to stay honest about it.
const _windowDays = 35;

class _DailyPageState extends ConsumerState<DailyPage> {
  final _food = TextEditingController();

  late final DateTime _today = _startOfToday();
  late DateTime _day = _today;

  List<Habit> _habits = startingHabits;
  List<DayMark> _marks = const [];
  Set<String> _slips = const {};
  List<String> _frequent = const [];
  String? _since;

  // The day's facts borrowed from the other books — re-read when the
  // selected day changes, never written to from here.
  JournalEntry? _journal;
  List<FocusSession> _focus = const [];
  List<Txn> _spend = const [];
  List<Event> _events = const [];

  final _subs = <StreamSubscription<void>>[];
  final _daySubs = <StreamSubscription<void>>[];

  static DateTime _startOfToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool get _isToday => LedgerDates.dayKey(_day) == LedgerDates.dayKey(_today);
  String get _key => LedgerDates.dayKey(_day);

  /// The habits still on the checklist, in his order.
  List<Habit> get _live => [
    for (final h in _habits)
      if (!h.archived) h,
  ];

  @override
  void initState() {
    super.initState();
    final marks = ref.read(marksRepoProvider);
    // Stamps the tracking-start day on first open, then holds it.
    marks.slipRecord().then((r) {
      if (mounted) setState(() => _since = r.$2);
    });
    _subs.add(
      ref.read(habitRepoProvider).watch().listen((h) {
        if (mounted) setState(() => _habits = h);
      }),
    );
    _subs.add(
      marks
          .watchSince(_today.subtract(const Duration(days: _windowDays - 1)))
          .listen((m) {
            if (mounted) setState(() => _marks = m);
          }),
    );
    _subs.add(
      marks.watchSlips().listen((s) {
        if (mounted) setState(() => _slips = {for (final m in s) m.date});
      }),
    );
    _loadFrequent();
    _watchDay();
  }

  Future<void> _loadFrequent() async {
    final list = await ref.read(marksRepoProvider).frequentMeals();
    if (mounted) setState(() => _frequent = list);
  }

  /// Re-points the borrowed streams at the selected day.
  void _watchDay() {
    for (final s in _daySubs) {
      s.cancel();
    }
    _daySubs.clear();
    final day = _day;
    _daySubs.add(
      ref.read(journalRepoProvider).watch(LedgerDates.dayKey(day)).listen((j) {
        if (mounted) setState(() => _journal = j);
      }),
    );
    _daySubs.add(
      ref.read(focusRepoProvider).watchDay(day).listen((f) {
        if (mounted) setState(() => _focus = f);
      }),
    );
    _daySubs.add(
      ref
          .read(txnRepoProvider)
          .watchRange(day, day.add(const Duration(days: 1)))
          .listen((t) {
            if (mounted) setState(() => _spend = t);
          }),
    );
    _daySubs.add(
      ref.read(eventRepoProvider).watchAll().listen((e) {
        if (mounted) setState(() => _events = e);
      }),
    );
  }

  void _pick(DateTime d) {
    if (d.isAfter(_today)) return;
    if (LedgerDates.dayKey(d) == _key) return;
    HapticFeedback.selectionClick();
    setState(() {
      _day = d;
      _journal = null;
      _focus = const [];
      _spend = const [];
    });
    _watchDay();
  }

  @override
  void dispose() {
    for (final s in [..._subs, ..._daySubs]) {
      s.cancel();
    }
    _food.dispose();
    super.dispose();
  }

  void _saveFelt(int pleasant, int energy, String word) {
    ref
        .read(journalRepoProvider)
        .upsert(_key, mood: pleasant, energy: energy, feelWord: word);
  }

  void _saveDetail(String why, String tags) {
    ref.read(journalRepoProvider).upsert(_key, feelWhy: why, feelTags: tags);
  }

  /// The day's mark, worn in the page's top corner: the ring of the four
  /// families while the day is unsaid, the word's own shape once it's
  /// marked. Either one opens the room.
  Widget _feltMark(BuildContext context) {
    final entry = _journal;
    final mood = entry?.mood;
    return Pressable(
      key: const ValueKey('felt-mark'),
      haptic: false,
      onTap: () => showFeelPicker(
        context,
        mood: entry?.mood,
        energy: entry?.energy,
        feelWord: entry?.feelWord,
        feelWhy: entry?.feelWhy,
        feelTags: entry?.feelTags,
        onCommit: _saveFelt,
        onDetail: _saveDetail,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: mood == null
            ? const CheckInRing(size: 26)
            : FeelBlob(
                word: entry?.feelWord ??
                    feelWordAt(from9(mood), from9(entry?.energy ?? 5)).word,
                color: feelBubbleColor(from9(mood), from9(entry?.energy ?? 5)),
                size: 24,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(marksRepoProvider);
    final live = _live;
    final kept = [
      for (final h in live)
        if (countOn(_marks, _key, h.kind) >= h.target) h,
    ].length;

    return ModuleScaffold(
      title: 'Daily',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _feltMark(context),
          const SizedBox(width: Gap.x3),
          Pressable(
            onTap: _openManage,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'habits',
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 13,
                  color: LedgerColors.of(context).inkFaint,
                ),
              ),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          MediaQuery.paddingOf(context).bottom + Gap.x6,
        ),
        children: [
          const SizedBox(height: Gap.x2),
          _DayStrip(
            today: _today,
            selected: _day,
            marks: _marks,
            habits: live,
            slips: _slips,
            onPick: _pick,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Gap.x2),
                _DayHero(
                  day: _day,
                  today: _today,
                  isToday: _isToday,
                  slips: _slips,
                  since: _since,
                  kept: kept,
                  of: live.length,
                  pledged: _marks.any(
                    (m) => m.date == _key && m.kind == 'pledge',
                  ),
                  onPledge: () {
                    HapticFeedback.mediumImpact();
                    repo.toggle(_day, 'pledge');
                  },
                  onSlip: () => _confirmSlip(context, repo),
                  onUndo: () => repo.setSlipped(_day, false),
                ),
                _DayNumbers(
                  spend: _spend,
                  focus: _focus,
                  marks: _marks,
                  habits: live,
                  dayKey: _key,
                ),
                _HabitsCard(
                  habits: live,
                  marks: _marks,
                  day: _day,
                  today: _today,
                  isToday: _isToday,
                  onTick: (h) {
                    // Water gets its own room: the vessel that fills, one
                    // glass at a time. Everything else keeps the quick mark.
                    if (h.counted && h.unit == 'glasses') {
                      Navigator.of(context).push(
                        LedgerRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => WaterPage(habit: h, day: _day),
                        ),
                      );
                      return;
                    }
                    final count = countOn(_marks, _key, h.kind);
                    if (h.counted) {
                      HapticFeedback.selectionClick();
                      if (count + 1 == h.target) HapticFeedback.mediumImpact();
                      repo.bump(_day, h.kind);
                    } else {
                      HapticFeedback.selectionClick();
                      repo.toggle(_day, h.kind);
                    }
                  },
                  onUndo: (h) {
                    if (countOn(_marks, _key, h.kind) == 0) return;
                    HapticFeedback.selectionClick();
                    h.counted
                        ? repo.unbump(_day, h.kind)
                        : repo.toggle(_day, h.kind);
                  },
                  onManage: _openManage,
                ),
                _MealsCard(
                  meals: [
                    for (final m in _marks)
                      if (m.date == _key && m.kind == 'meal') m,
                  ]..sort((a, b) => a.at.compareTo(b.at)),
                  frequent: _frequent,
                  controller: _food,
                  isToday: _isToday,
                  onAdd: (text) async {
                    await repo.addMeal(_day, text);
                    _loadFrequent();
                  },
                  onStrike: (id) => repo.removeMark(id),
                ),
                _PageLine(
                  entry: _journal,
                  onFelt: _saveFelt,
                  onDetail: _saveDetail,
                  onOpenJournal: () => Navigator.of(context).push(
                    LedgerRoute<void>(builder: (_) => const JournalPage()),
                  ),
                ),
                _DayThread(
                  day: _day,
                  marks: [
                    for (final m in _marks)
                      if (m.date == _key) m,
                  ],
                  habits: _habits,
                  focus: _focus,
                  spend: _spend,
                  events: _events,
                ),
                _WeekTable(
                  end: _day,
                  today: _today,
                  habits: live,
                  marks: _marks,
                  slips: _slips,
                  since: _since,
                ),
                _RecordGrid(
                  today: _today,
                  selected: _day,
                  habits: live,
                  marks: _marks,
                  slips: _slips,
                  since: _since,
                  onPick: _pick,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ————— the habit sheets —————

  Future<void> _openManage() async {
    await showLedgerSheet<void>(
      context,
      builder: (_) => _ManageHabits(repo: ref.read(habitRepoProvider)),
    );
  }

  Future<void> _confirmSlip(BuildContext context, MarksRepo repo) async {
    final when = _isToday ? 'to-day' : LedgerDates.dayLabel(_day);
    final sure = await showLedgerSheet<bool>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                'Mark $when as a slip?',
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                _isToday
                    ? 'The clean count restarts to-morrow. Writing it down '
                          'honestly is the whole point — the record only works '
                          'if it\'s true.'
                    : 'The clean count is recounted from the record, so an '
                          'older slip written in now moves it. That is the '
                          'point — a true record beats a flattering one.',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x4),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Yes — mark it'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(_isToday ? 'No, to-day is clean' : 'No, leave it'),
              ),
            ],
          ),
        );
      },
    );
    if (sure == true) {
      HapticFeedback.mediumImpact();
      await repo.setSlipped(_day, true);
    }
  }
}

// ————— the day strip —————

/// Five weeks of days, to-day at the right, scrolling back into the past.
/// Each leaf carries its own evidence: a filled mark for a day fully kept,
/// a hollow one for a day half-kept, the seal for a slip. Nothing is claimed
/// about days before the book was watching.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.today,
    required this.selected,
    required this.marks,
    required this.habits,
    required this.slips,
    required this.onPick,
  });

  final DateTime today;
  final DateTime selected;
  final List<DayMark> marks;
  final List<Habit> habits;
  final Set<String> slips;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      height: 58,
      child: ListView.builder(
        reverse: true,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.page - 6),
        itemCount: _windowDays,
        itemBuilder: (context, i) {
          final d = today.subtract(Duration(days: i));
          final key = LedgerDates.dayKey(d);
          final isSelected = key == LedgerDates.dayKey(selected);
          final isToday = i == 0;
          final weight = dayWeight(marks, habits, key);
          final slipped = slips.contains(key);
          return Pressable(
            haptic: false,
            scale: 0.94,
            onTap: () => onPick(d),
            child: SizedBox(
              width: 42,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    LedgerDates.weekdays[d.weekday - 1][0],
                    style: LedgerType.label.copyWith(
                      fontSize: 9,
                      color: isSelected ? c.ink : c.inkFaint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d.day.toString(),
                    style: LedgerType.amount.copyWith(
                      fontSize: 15,
                      color: isSelected
                          ? c.ink
                          : (isToday ? c.ink : c.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 3),
                  // The day's evidence, three pixels of it.
                  SizedBox(
                    height: 5,
                    child: slipped
                        ? Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: c.seal,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          )
                        : weight <= 0
                        ? null
                        : Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: weight >= 1
                                  ? c.jama
                                  : c.jama.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                  ),
                  const SizedBox(height: 4),
                  // The selected day is underlined by hand, not boxed.
                  AnimatedContainer(
                    duration: Motion.quick,
                    curve: Motion.curve,
                    height: 2,
                    width: isSelected ? 20 : 0,
                    color: c.quill,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ————— the hero —————

/// The clean count: days without the habit, counted as wins. The number is
/// the hero because the number is the achievement; the slip affordance is
/// small because it should take intent, never an accident. On a past day the
/// hero steps aside and the page reports on that day instead — the record
/// stays correctable, which is the only way it stays true.
class _DayHero extends StatelessWidget {
  const _DayHero({
    required this.day,
    required this.today,
    required this.isToday,
    required this.slips,
    required this.since,
    required this.kept,
    required this.of,
    required this.pledged,
    required this.onPledge,
    required this.onSlip,
    required this.onUndo,
  });

  final DateTime day;
  final DateTime today;
  final bool isToday;
  final Set<String> slips;
  final String? since;
  final int kept;
  final int of;
  final bool pledged;
  final VoidCallback onPledge;
  final VoidCallback onSlip;
  final VoidCallback onUndo;

  /// One line back for the pledge, rotating by date — deterministic, so the
  /// day keeps its line.
  static const _lines = [
    'one clean day at a time',
    'mornings are where streaks are built',
    'you kept yesterday — keep to-day',
    'the count only moves forward from here',
    'said out loud, it holds better',
  ];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final s = since;
    if (s == null) return const SizedBox(height: 96);
    final key = LedgerDates.dayKey(day);
    final slipped = slips.contains(key);
    final tracked = !day.isBefore(DateTime.parse(s));

    if (!isToday) return _pastDay(context, c, key, slipped, tracked);

    final streak = cleanStreak(slips, s, today);
    final best = bestCleanRun(slips, s, today);
    if (slipped) return _slippedToday(c, best);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'clean streak',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CountUp(
              value: streak,
              format: (n) => 'day $n',
              style: LedgerType.heroAmount.copyWith(fontSize: 44, color: c.ink),
            ),
            const SizedBox(width: Gap.x3),
            if (streak >= best && streak > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Transform.rotate(
                  angle: -0.028,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.x2,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: c.jama.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'your best yet',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 11,
                        color: c.jama,
                      ),
                    ),
                  ),
                ),
              )
            else if (best > streak)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'best: $best days',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          of == 0
              ? 'a clean day is a day you didn\'t give in'
              : kept == of
              ? 'clean, and everything on the list is kept'
              : 'clean so far · $kept of $of kept to-day',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x3),
        AnimatedSwitcher(
          duration: Motion.spring,
          child: pledged
              ? Row(
                  key: const ValueKey('pledged'),
                  children: [
                    SealOutline(size: 14, color: c.jama),
                    const SizedBox(width: Gap.x2),
                    Text(
                      'pledged — ${_lines[day.day % _lines.length]}',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                )
              : Pressable(
                  key: const ValueKey('pledge'),
                  onTap: onPledge,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.x3,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.rule),
                      borderRadius: BorderRadius.circular(Corner.stamp),
                    ),
                    child: Text(
                      'pledge: staying clean to-day',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 12,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
        ),
        const SizedBox(height: Gap.x2),
        Pressable(
          onTap: onSlip,
          child: Text(
            'I slipped to-day',
            style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.seal),
          ),
        ),
      ],
    );
  }

  Widget _slippedToday(LedgerColors c, int best) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'clean streak',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        Text(
          'slipped to-day',
          style: LedgerType.title.copyWith(fontSize: 26, color: c.ink),
        ),
        const SizedBox(height: 2),
        Text(
          'it happens. to-morrow is day 1 — best run so far: '
          '$best ${best == 1 ? 'day' : 'days'}',
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x2),
        Pressable(
          onTap: onUndo,
          child: Text(
            'marked by mistake? tap to undo',
            style: LedgerType.bodyStrong.copyWith(fontSize: 12, color: c.quill),
          ),
        ),
      ],
    );
  }

  Widget _pastDay(
    BuildContext context,
    LedgerColors c,
    String key,
    bool slipped,
    bool tracked,
  ) {
    final days = today.difference(day).inDays;
    final ago = days == 1 ? 'yesterday' : '$days days back';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${LedgerDates.dayLabel(day)} · $ago',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        Text(
          !tracked
              ? 'before the book watched'
              : slipped
              ? 'a slip'
              : of == 0
              ? 'a clean day'
              : '$kept of $of kept',
          style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
        ),
        const SizedBox(height: 2),
        Text(
          !tracked
              ? 'nothing is claimed about days before tracking began'
              : slipped
              ? 'written down, and left written down'
              : 'clean — fill anything in below that the day missed',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
        ),
        if (tracked) ...[
          const SizedBox(height: Gap.x2),
          Pressable(
            onTap: slipped ? onUndo : onSlip,
            child: Text(
              slipped ? 'that was wrong — take it back' : 'I slipped that day',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: slipped ? c.quill : c.seal,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ————— the checklist —————

/// The habits, each one a line: a plain word, its run so far, and the mark
/// on the right. A tick habit takes the box; a counted habit fills a row of
/// small squares one tap at a time and only then takes the box.
class _HabitsCard extends StatelessWidget {
  const _HabitsCard({
    required this.habits,
    required this.marks,
    required this.day,
    required this.today,
    required this.isToday,
    required this.onTick,
    required this.onUndo,
    required this.onManage,
  });

  final List<Habit> habits;
  final List<DayMark> marks;
  final DateTime day;
  final DateTime today;
  final bool isToday;
  final ValueChanged<Habit> onTick;
  final ValueChanged<Habit> onUndo;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final key = LedgerDates.dayKey(day);
    final kept = [
      for (final h in habits)
        if (countOn(marks, key, h.kind) >= h.target) h,
    ].length;

    return _Open(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RuleHeader(
            isToday ? 'to-day' : 'that day',
            trailing: habits.isEmpty
                ? null
                : Text(
                    '$kept of ${habits.length}',
                    style: LedgerType.amount.copyWith(
                      fontSize: 12,
                      color: kept == habits.length ? c.jama : c.inkFaint,
                    ),
                  ),
          ),
          if (habits.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'no habits on the list',
                    style: LedgerType.bodyText.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'add the two or three that actually decide a day.',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final (i, h) in habits.indexed)
              _HabitRow(
                habit: h,
                count: countOn(marks, key, h.kind),
                run: keptRun(daysKept(marks, h), today),
                last: i == habits.length - 1,
                onTap: () => onTick(h),
                onUndo: () => onUndo(h),
              ),
          Padding(
            padding: const EdgeInsets.only(top: Gap.x3),
            child: Pressable(
              onTap: onManage,
              child: Row(
                children: [
                  PenPlus(size: 11, color: c.inkFaint),
                  const SizedBox(width: Gap.x2),
                  Text(
                    habits.isEmpty ? 'add a habit' : 'add or edit habits',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One habit line. Tap keeps it (or adds one toward the count); hold takes
/// the last one back — an undo that never needs a menu.
class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.habit,
    required this.count,
    required this.run,
    required this.last,
    required this.onTap,
    required this.onUndo,
  });

  final Habit habit;
  final int count;
  final int run;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final done = count >= habit.target;
    return Pressable(
      haptic: false,
      scale: 0.99,
      onTap: onTap,
      onLongPress: onUndo,
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    habit.name,
                    style: LedgerType.bodyText.copyWith(
                      color: done ? c.inkFaint : c.ink,
                    ),
                  ),
                  if (run > 1) ...[
                    const SizedBox(height: 1),
                    Text(
                      '$run days running',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 11,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (habit.counted) ...[
              _CountMeter(count: count, target: habit.target),
              const SizedBox(width: Gap.x3),
              Text(
                '$count/${habit.target}',
                style: LedgerType.amount.copyWith(
                  fontSize: 13,
                  color: done ? c.jama : c.ink,
                ),
              ),
              const SizedBox(width: Gap.x3),
            ],
            AnimatedContainer(
              duration: Motion.quick,
              curve: Motion.curve,
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: done ? c.jama.withValues(alpha: 0.14) : null,
                border: Border.all(color: done ? c.jama : c.rule, width: 1.4),
                borderRadius: BorderRadius.circular(Corner.stamp),
              ),
              child: done ? Center(child: PenTick(size: 15, color: c.jama)) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A counted habit's progress as squares, not a bar — the same square the
/// tick box uses, one per glass. Above twelve the squares stop being
/// countable at a glance, so the number carries it alone.
class _CountMeter extends StatelessWidget {
  const _CountMeter({required this.count, required this.target});

  final int count;
  final int target;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    if (target > 12) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < target; i++)
          AnimatedContainer(
            duration: Motion.quick,
            curve: Motion.curve,
            margin: const EdgeInsets.only(left: 3),
            width: 6,
            height: i < count ? 14 : 8,
            decoration: BoxDecoration(
              color: i < count ? c.jama : c.rule,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }
}

// ————— what he ate —————

/// The day's food, written as it happens. The row of usuals across the top
/// is the whole point: chai gets written a thousand times in a life, and it
/// should cost one tap, not five letters.
class _MealsCard extends StatelessWidget {
  const _MealsCard({
    required this.meals,
    required this.frequent,
    required this.controller,
    required this.isToday,
    required this.onAdd,
    required this.onStrike,
  });

  final List<DayMark> meals;
  final List<String> frequent;
  final TextEditingController controller;
  final bool isToday;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onStrike;

  /// Which part of the day a mark belongs to — the book groups food the way
  /// a person remembers it, not by the clock alone.
  static String slot(DateTime at) {
    final h = at.hour;
    if (h < 11) return 'morning';
    if (h < 16) return 'afternoon';
    if (h < 21) return 'evening';
    return 'night';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    String? shown;
    final rows = <Widget>[];
    for (final (i, m) in meals.indexed) {
      final s = slot(m.at);
      if (s != shown) {
        shown = s;
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? Gap.x2 : Gap.x3, bottom: 2),
            child: Text(
              s,
              style: LedgerType.label.copyWith(fontSize: 10, color: c.inkFaint),
            ),
          ),
        );
      }
      rows.add(
        LedgerLine(
          key: ValueKey('meal-${m.id}'),
          leading: _hhmm(m.at),
          title: m.note ?? '',
          last: i == meals.length - 1,
          amountWidget: Pressable(
            onTap: () => onStrike(m.id),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: PenCross(size: 11, color: c.inkFaint),
            ),
          ),
        ),
      );
    }

    return _Open(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RuleHeader(
            'what I ate',
            trailing: meals.isEmpty
                ? null
                : Text(
                    '${meals.length}',
                    style: LedgerType.amount.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
          ),
          if (frequent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Wrap(
                spacing: Gap.x2,
                runSpacing: Gap.x2,
                children: [
                  for (final food in frequent)
                    Pressable(
                      onTap: () => onAdd(food),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.x3,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: c.rule),
                          borderRadius: BorderRadius.circular(Corner.stamp),
                        ),
                        child: Text(
                          food,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 12,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ...rows,
          if (meals.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x3),
              child: Text(
                isToday
                    ? 'nothing written yet to-day'
                    : 'nothing was written that day',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: Gap.x2),
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) {
                onAdd(v);
                controller.clear();
              },
              style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink),
              cursorColor: c.quill,
              decoration: InputDecoration(
                hintText: 'idli, chai… press done to add',
                hintStyle: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint.withValues(alpha: 0.6),
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ————— how it felt —————

/// The day's mood, on the same row of squares the rest of the page speaks
/// in. It writes to the journal's page for that date — one mood per day in
/// the whole box, whichever book he happens to be holding.
/// The day in three numbers, set big the way the money screens set money:
/// what went out, what was sat, what was drunk — captions small, numerals
/// in the spotlight, no boxes anywhere near them.
class _DayNumbers extends StatelessWidget {
  const _DayNumbers({
    required this.spend,
    required this.focus,
    required this.marks,
    required this.habits,
    required this.dayKey,
  });

  final List<Txn> spend;
  final List<FocusSession> focus;
  final List<DayMark> marks;
  final List<Habit> habits;
  final String dayKey;

  @override
  Widget build(BuildContext context) {
    var spent = 0;
    for (final t in spend) {
      if (t.type == TxnType.expense) spent += t.amountPaise;
    }
    var minutes = 0;
    for (final f in focus) {
      if (f.completed) minutes += f.minutes;
    }
    final water = habits.where((h) => h.unit == 'glasses').firstOrNull;
    final glasses = water == null ? null : countOn(marks, dayKey, water.kind);
    // Spread edge to edge — the row owns its whole line, no dead right
    // margin. Each number takes only its own width; the space between
    // carries the rhythm.
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          HeroAmount(
            caption: 'spent',
            amount: Inr.format(spent),
            size: 30,
          ),
          HeroAmount(caption: 'focus', amount: '${minutes}m', size: 30),
          if (water != null && glasses != null)
            HeroAmount(
              caption: 'water',
              amount: '$glasses of ${water.target}',
              size: 30,
            ),
        ],
      ),
    );
  }
}

/// Daily reads as one page, not a stack of plates: each section sits
/// straight on the paper, ruled apart by its header's hand-drawn line and
/// nothing else. The plate stays in the kit for the money screens.
class _Open extends StatelessWidget {
  const _Open({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The page's own line: the day's word (when the day is marked) and the
/// first line of what was written, each an open row, each a way in.
class _PageLine extends StatelessWidget {
  const _PageLine({
    required this.entry,
    required this.onFelt,
    required this.onDetail,
    required this.onOpenJournal,
  });

  final JournalEntry? entry;
  final void Function(int pleasant, int energy, String word) onFelt;
  final void Function(String why, String tags) onDetail;
  final VoidCallback onOpenJournal;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final mood = entry?.mood;
    final word = mood == null
        ? null
        : entry?.feelWord ??
            feelWordAt(from9(mood), from9(entry?.energy ?? 5)).word;
    final written = (entry?.body ?? '').trim();
    return _Open(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RuleHeader('the page'),
          if (word != null) ...[
            const SizedBox(height: Gap.x2),
            Pressable(
              haptic: false,
              onTap: () => showFeelPicker(
                context,
                mood: entry?.mood,
                energy: entry?.energy,
                feelWord: entry?.feelWord,
                feelWhy: entry?.feelWhy,
                feelTags: entry?.feelTags,
                onCommit: onFelt,
                onDetail: onDetail,
              ),
              child: Row(
                children: [
                  FeelBlob(
                    word: word,
                    color: feelBubbleColor(
                      from9(mood!),
                      from9(entry?.energy ?? 5),
                    ),
                    size: 30,
                  ),
                  const SizedBox(width: Gap.x3),
                  Text(
                    word,
                    style:
                        LedgerType.title.copyWith(fontSize: 22, color: c.ink),
                  ),
                  const Spacer(),
                  Text(
                    're-mark',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 12,
                      color: c.quill,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Gap.x3),
          Pressable(
            onTap: onOpenJournal,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    written.isEmpty
                        ? 'the page for this day is unwritten'
                        : written.split('\n').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: Gap.x2),
                Text(
                  written.isEmpty ? 'write it' : 'open',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 12,
                    color: c.quill,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ————— what the day contained —————

/// Everything the box knows about this one day, on a single timeline: what
/// he ate, what he kept, what he spent, what he sat down to focus on, what
/// the calendar had marked. Read-only on purpose — the thread is the day's
/// evidence, and each book stays the place its own entries are edited.
class _DayThread extends StatelessWidget {
  const _DayThread({
    required this.day,
    required this.marks,
    required this.habits,
    required this.focus,
    required this.spend,
    required this.events,
  });

  final DateTime day;
  final List<DayMark> marks;
  final List<Habit> habits;
  final List<FocusSession> focus;
  final List<Txn> spend;
  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final names = {for (final h in habits) h.kind: h.name};
    final items = <({DateTime at, String title, String detail, String amount})>[
      for (final m in marks)
        if (m.kind == 'meal')
          (at: m.at, title: m.note ?? '', detail: 'ate', amount: '')
        else if (m.kind == 'slip')
          (at: m.at, title: 'a slip, written down', detail: '', amount: '')
        else if (names.containsKey(m.kind))
          (at: m.at, title: names[m.kind]!, detail: 'kept', amount: ''),
      for (final f in focus)
        (
          at: f.startedAt,
          title: f.label?.trim().isNotEmpty == true ? f.label! : 'focus',
          detail: f.completed
              ? '${f.minutes}m sat'
              : '${f.minutes}m, left early',
          amount: '',
        ),
      for (final t in spend)
        (
          at: t.at,
          title: t.title,
          detail: switch (t.type) {
            TxnType.expense => 'spent',
            TxnType.income => 'came in',
            TxnType.transfer => 'moved',
          },
          amount: Inr.format(t.amountPaise),
        ),
      for (final e in _eventsOn(day))
        (
          at: e.$2,
          title: e.$1.title,
          detail: e.$1.timeMinutes == null ? 'all day' : 'on the calendar',
          amount: '',
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    return _Open(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RuleHeader('the day so far'),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x4),
              child: Text(
                'this day hasn\'t said anything yet.',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            )
          else
            for (final (i, it) in items.indexed)
              LedgerLine(
                leading: _hhmm(it.at),
                title: it.title,
                detail: it.detail.isEmpty ? null : it.detail,
                amount: it.amount,
                last: i == items.length - 1,
              ),
        ],
      ),
    );
  }

  /// The calendar's entries for this day, yearly repeats resolved onto it.
  List<(Event, DateTime)> _eventsOn(DateTime day) {
    final out = <(Event, DateTime)>[];
    for (final e in events) {
      if (e.archived) continue;
      var d = DateTime.parse(e.date);
      if (e.repeat == EventRepeat.yearly) d = DateTime(day.year, d.month, d.day);
      if (LedgerDates.dayKey(d) != LedgerDates.dayKey(day)) continue;
      final mins = e.timeMinutes;
      out.add((
        e,
        DateTime(day.year, day.month, day.day, mins == null ? 8 : mins ~/ 60,
            mins == null ? 0 : mins % 60),
      ));
    }
    return out;
  }
}

// ————— the week —————

/// Seven days, one row per habit, plus the clean line on top. Ticks and
/// crosses only for days the book was actually watching; a counted habit
/// that got some of the way shows a half mark, because half is not nothing
/// and it is not the same as done either.
class _WeekTable extends StatelessWidget {
  const _WeekTable({
    required this.end,
    required this.today,
    required this.habits,
    required this.marks,
    required this.slips,
    required this.since,
  });

  final DateTime end;
  final DateTime today;
  final List<Habit> habits;
  final List<DayMark> marks;
  final Set<String> slips;
  final String? since;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final start = since == null ? null : DateTime.parse(since!);
    final days = [
      for (var i = 6; i >= 0; i--) end.subtract(Duration(days: i)),
    ];

    Widget cell(DateTime d, Habit? habit) {
      final key = LedgerDates.dayKey(d);
      final tracked = start != null && !d.isBefore(start);
      final future = d.isAfter(today);
      if (!tracked || future) {
        return Text(
          '·',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.rule),
        );
      }
      final isToday = LedgerDates.dayKey(d) == LedgerDates.dayKey(today);
      if (habit == null) {
        // The clean line: the absence of a slip is the achievement.
        final clean = !slips.contains(key);
        if (clean && isToday) {
          return PenTick(size: 12, color: c.jama.withValues(alpha: 0.45));
        }
        return clean
            ? PenTick(size: 12, color: c.jama)
            : PenCross(size: 10, color: c.seal.withValues(alpha: 0.75));
      }
      final count = countOn(marks, key, habit.kind);
      if (count >= habit.target) return PenTick(size: 12, color: c.jama);
      if (count > 0) {
        // Part of the way there — a hollow square, not a verdict.
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            border: Border.all(color: c.jama.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }
      if (isToday) {
        return Text(
          '·',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
        );
      }
      return PenCross(size: 10, color: c.inkFaint.withValues(alpha: 0.55));
    }

    TableRow row(String label, Habit? habit) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            label,
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final d in days)
          Center(child: SizedBox(height: 16, child: Center(child: cell(d, habit)))),
      ],
    );

    return _Open(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RuleHeader('the week'),
          const SizedBox(height: Gap.x3),
          Table(
            columnWidths: const {0: FixedColumnWidth(76)},
            children: [
              TableRow(
                children: [
                  const SizedBox.shrink(),
                  for (final d in days)
                    Center(
                      child: Text(
                        LedgerDates.weekdays[d.weekday - 1][0],
                        style: LedgerType.label.copyWith(
                          fontSize: 9,
                          color: LedgerDates.dayKey(d) == LedgerDates.dayKey(end)
                              ? c.ink
                              : c.inkFaint,
                        ),
                      ),
                    ),
                ],
              ),
              row('clean', null),
              for (final h in habits.take(8)) row(h.name.toLowerCase(), h),
            ],
          ),
          const SizedBox(height: Gap.x2),
          Text(
            'tick = kept · hollow = part way · cross = missed',
            style: LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}

// ————— the record —————

/// Five weeks as squares: the darker the square, the more of the list that
/// day kept. A slip wears the seal. Tapping a square opens that day, so the
/// grid is the way back into the record as well as the picture of it.
class _RecordGrid extends StatelessWidget {
  const _RecordGrid({
    required this.today,
    required this.selected,
    required this.habits,
    required this.marks,
    required this.slips,
    required this.since,
    required this.onPick,
  });

  final DateTime today;
  final DateTime selected;
  final List<Habit> habits;
  final List<DayMark> marks;
  final Set<String> slips;
  final String? since;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final s = since;
    // Whole weeks, ending with the one to-day sits in.
    final lastRowStart = today.subtract(Duration(days: today.weekday - 1));
    final first = lastRowStart.subtract(const Duration(days: 28));
    final start = s == null ? null : DateTime.parse(s);

    var kept = 0;
    var counted = 0;
    for (var i = 0; i < 35; i++) {
      final d = first.add(Duration(days: i));
      if (d.isAfter(today)) break;
      if (start != null && d.isBefore(start)) continue;
      counted++;
      if (dayWeight(marks, habits, LedgerDates.dayKey(d)) >= 1) kept++;
    }
    final clean = s == null ? 0 : cleanStreak(slips, s, today);
    final best = s == null ? 0 : bestCleanRun(slips, s, today);

    return _Open(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RuleHeader('the record'),
          const SizedBox(height: Gap.x3),
          Row(
            children: [
              for (final w in LedgerDates.weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w[0],
                      style: LedgerType.label.copyWith(
                        fontSize: 9,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var week = 0; week < 5; week++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (var dow = 0; dow < 7; dow++)
                    Expanded(
                      child: _RecordCell(
                        day: first.add(Duration(days: week * 7 + dow)),
                        today: today,
                        selected: selected,
                        trackedFrom: start,
                        weight: dayWeight(
                          marks,
                          habits,
                          LedgerDates.dayKey(
                            first.add(Duration(days: week * 7 + dow)),
                          ),
                        ),
                        slipped: slips.contains(
                          LedgerDates.dayKey(
                            first.add(Duration(days: week * 7 + dow)),
                          ),
                        ),
                        onPick: onPick,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: Gap.x2),
          Text(
            counted == 0
                ? 'the record starts to-day'
                : 'clean $clean · best $best · '
                      'every habit kept on $kept of $counted days',
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _RecordCell extends StatelessWidget {
  const _RecordCell({
    required this.day,
    required this.today,
    required this.selected,
    required this.trackedFrom,
    required this.weight,
    required this.slipped,
    required this.onPick,
  });

  final DateTime day;
  final DateTime today;
  final DateTime selected;
  final DateTime? trackedFrom;
  final double weight;
  final bool slipped;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final future = day.isAfter(today);
    final tracked = trackedFrom != null && !day.isBefore(trackedFrom!);
    final isSelected = LedgerDates.dayKey(day) == LedgerDates.dayKey(selected);
    final fill = !tracked || future
        ? Colors.transparent
        : slipped
        ? c.seal.withValues(alpha: 0.22)
        : weight <= 0
        ? c.rule.withValues(alpha: 0.45)
        : c.heat.withValues(alpha: 0.18 + 0.62 * weight);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Pressable(
        haptic: false,
        scale: 0.9,
        onTap: future ? null : () => onPick(day),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(
                color: isSelected
                    ? c.quill
                    : (!tracked || future ? c.rule.withValues(alpha: 0.4) : Colors.transparent),
                width: isSelected ? 1.4 : 1,
              ),
            ),
            child: slipped
                ? Center(child: SealOutline(size: 9, color: c.seal))
                : null,
          ),
        ),
      ),
    );
  }
}

// ————— managing the checklist —————

/// The habits themselves: rename, retarget, reorder, retire. Held apart from
/// the day so the page stays a page — this is the workshop behind it.
class _ManageHabits extends StatefulWidget {
  const _ManageHabits({required this.repo});

  final HabitRepo repo;

  @override
  State<_ManageHabits> createState() => _ManageHabitsState();
}

class _ManageHabitsState extends State<_ManageHabits> {
  List<Habit>? _habits;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await widget.repo.load();
    if (mounted) setState(() => _habits = list);
  }

  List<Habit> get _live => [
    for (final h in _habits ?? const <Habit>[])
      if (!h.archived) h,
  ];

  Future<void> _save(List<Habit> live) async {
    final archived = [
      for (final h in _habits ?? const <Habit>[])
        if (h.archived) h,
    ];
    await widget.repo.save([...live, ...archived]);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final live = _live;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'The habits',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'Hold and drag to reorder. Retiring one keeps its history — the '
              'record never loses a day it watched.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x3),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: true,
                itemCount: live.length,
                onReorderItem: (from, to) {
                  final list = [...live];
                  list.insert(to, list.removeAt(from));
                  HapticFeedback.selectionClick();
                  _save(list);
                },
                itemBuilder: (context, i) {
                  final h = live[i];
                  return Padding(
                    key: ValueKey(h.kind),
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Pressable(
                            onTap: () => _edit(h),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      h.name,
                                      style: LedgerType.bodyText.copyWith(
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    h.counted
                                        ? '${h.target}${h.unit == null ? '' : ' ${h.unit}'}'
                                        : 'a tick',
                                    style: LedgerType.bodyText.copyWith(
                                      fontSize: 12,
                                      color: c.inkFaint,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Gap.x3),
                        Pressable(
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            await widget.repo.update(h.kind, archived: true);
                            await _reload();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: PenCross(size: 11, color: c.inkFaint),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Gap.x2),
            FilledButton(
              onPressed: () => _edit(null),
              child: const Text('Add a habit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(Habit? existing) async {
    final saved = await showLedgerSheet<bool>(
      context,
      builder: (_) => _HabitEditor(repo: widget.repo, existing: existing),
    );
    if (saved == true) await _reload();
  }
}

/// One habit, written or rewritten: a name, and whether it's a tick or a
/// number to reach.
class _HabitEditor extends StatefulWidget {
  const _HabitEditor({required this.repo, this.existing});

  final HabitRepo repo;
  final Habit? existing;

  @override
  State<_HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<_HabitEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _unit = TextEditingController(text: widget.existing?.unit ?? '');
  late int _target = widget.existing?.target ?? 1;

  @override
  void dispose() {
    _name.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.mediumImpact();
    if (widget.existing == null) {
      await widget.repo.add(
        name: name,
        target: _target,
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      );
    } else {
      await widget.repo.update(
        widget.existing!.kind,
        name: name,
        target: _target,
        unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.page,
          0,
          Gap.page,
          Gap.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              widget.existing == null ? 'A new habit' : 'This habit',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: Gap.x3),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              style: LedgerType.bodyText.copyWith(fontSize: 16, color: c.ink),
              cursorColor: c.quill,
              decoration: InputDecoration(
                hintText: 'Reading, Steps, Water…',
                hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                border: UnderlineInputBorder(
                  borderSide: BorderSide(color: c.rule),
                ),
              ),
            ),
            const SizedBox(height: Gap.x4),
            Text(
              'how it\'s kept',
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: Gap.x2),
            Row(
              children: [
                Pressable(
                  onTap: () => setState(() => _target = 1),
                  child: _Choice(label: 'a tick', selected: _target == 1),
                ),
                const SizedBox(width: Gap.x2),
                Pressable(
                  onTap: () => setState(() => _target = _target > 1 ? _target : 8),
                  child: _Choice(label: 'a count', selected: _target > 1),
                ),
              ],
            ),
            if (_target > 1) ...[
              const SizedBox(height: Gap.x4),
              Row(
                children: [
                  Pressable(
                    onTap: () => setState(() {
                      if (_target > 2) _target--;
                    }),
                    child: _Step(label: '−'),
                  ),
                  const SizedBox(width: Gap.x3),
                  Text(
                    '$_target',
                    style: LedgerType.heroAmount.copyWith(
                      fontSize: 28,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: Gap.x3),
                  Pressable(
                    onTap: () => setState(() {
                      if (_target < 99) _target++;
                    }),
                    child: _Step(label: '+'),
                  ),
                  const SizedBox(width: Gap.x4),
                  Expanded(
                    child: TextField(
                      controller: _unit,
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 14,
                        color: c.ink,
                      ),
                      cursorColor: c.quill,
                      decoration: InputDecoration(
                        hintText: 'glasses, sets, pages',
                        hintStyle: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint,
                        ),
                        border: UnderlineInputBorder(
                          borderSide: BorderSide(color: c.rule),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Gap.x6),
            FilledButton(
              onPressed: _save,
              child: Text(widget.existing == null ? 'Add it' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return AnimatedContainer(
      duration: Motion.quick,
      curve: Motion.curve,
      padding: const EdgeInsets.symmetric(horizontal: Gap.x4, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? c.quill.withValues(alpha: 0.16) : null,
        border: Border.all(color: selected ? c.quill : c.rule),
        borderRadius: BorderRadius.circular(Corner.stamp),
      ),
      child: Text(
        label,
        style: LedgerType.bodyStrong.copyWith(
          fontSize: 13,
          color: selected ? c.ink : c.inkFaint,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: c.rule),
        borderRadius: BorderRadius.circular(Corner.stamp),
      ),
      child: Text(
        label,
        style: LedgerType.bodyStrong.copyWith(fontSize: 16, color: c.ink),
      ),
    );
  }
}

String _hhmm(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
