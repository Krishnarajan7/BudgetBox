import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
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
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/journal_repo.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Friday, 31 July" — the page's dateline.
String _longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// "12 Jul" — the earlier-pages column.
String _shortDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1].substring(0, 3)}';

// ————— pure arithmetic (testable, no widgets) —————

/// The blank page's wry questions; one per day, by day-of-month.
const _journalPrompts = [
  'What did to-day cost you, besides money?',
  'Who did you talk to?',
  'What would you skip next time?',
  'What kept its promise to-day?',
  'Where did the afternoon actually go?',
  'What did you put off, and how does it sit?',
  'What was worth what it cost?',
  'What will you want to remember about to-day?',
];

/// Deterministic: the same day of the month always asks the same question.
String journalPromptFor(int dayOfMonth) =>
    _journalPrompts[(dayOfMonth - 1) % _journalPrompts.length];

/// Consecutive written days counting back from today — or from yesterday, so
/// a page not yet written to-night doesn't snap the run at breakfast. A gap
/// ends it.
int journalStreakDays(Iterable<String> writtenDates, DateTime today) {
  final days = writtenDates.toSet();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(LedgerDates.dayKey(cursor))) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var run = 0;
  while (days.contains(LedgerDates.dayKey(cursor))) {
    run++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return run;
}

/// How many pages were written in [month]'s calendar month.
int journalPagesInMonth(Iterable<String> writtenDates, DateTime month) {
  final prefix = LedgerDates.dayKey(
    DateTime(month.year, month.month),
  ).substring(0, 8);
  return writtenDates.where((d) => d.startsWith(prefix)).toSet().length;
}

/// One slot per day of [month]'s calendar month: the recorded mark as
/// (pleasant, energy), or null. Energy stays null on pages marked before the
/// field existed.
List<(int, int?)?> monthMoodDots(
  Iterable<(String, int?, int?)> entries,
  DateTime month,
) {
  final prefix = LedgerDates.dayKey(
    DateTime(month.year, month.month),
  ).substring(0, 8);
  final dots = List<(int, int?)?>.filled(LedgerDates.daysInMonth(month), null);
  for (final (date, mood, energy) in entries) {
    if (mood == null || !date.startsWith(prefix)) continue;
    final day = int.tryParse(date.substring(8));
    if (day != null && day >= 1 && day <= dots.length) {
      dots[day - 1] = (mood, energy);
    }
  }
  return dots;
}

/// The one thing the mood grid and the money book can honestly say to each
/// other. Given this month's lived days as (mood, spent-paise), it returns a
/// flat sentence only when the gap is real: three days on each side and at
/// least a fifth of a difference. Otherwise silence — a coincidence dressed
/// up as an insight is worse than no line at all. Never a verdict, either
/// way: it reports the averages and stops.
String? moodMoneyWhisper(Iterable<(int, int)> days) {
  final rough = <int>[];
  final bright = <int>[];
  // Pleasantness runs 1…9 since v11; the outer thirds are the days with an
  // opinion, and the middle keeps its own counsel.
  for (final (mood, paise) in days) {
    if (mood <= 3) {
      rough.add(paise);
    } else if (mood >= 7) {
      bright.add(paise);
    }
  }
  if (rough.length < 3 || bright.length < 3) return null;
  final r = rough.reduce((a, b) => a + b) / rough.length;
  final b = bright.reduce((a, b) => a + b) / bright.length;
  String line(String which, double more, double less) =>
      'the $which days cost more, on average — '
      '${Inr.format(more.round())} against ${Inr.format(less.round())}.';
  if (r > b * 1.2) return line('rough', r, b);
  if (b > r * 1.2) return line('better', b, r);
  return null;
}

/// The same calendar date, one year back. 29 Feb quietly becomes 1 Mar.
String yearAgoKey(DateTime today) =>
    LedgerDates.dayKey(DateTime(today.year - 1, today.month, today.day));

/// An entry counts as written once it holds words or a mood.
bool _isWritten(JournalEntry e) => e.body.trim().isNotEmpty || e.mood != null;

/// Opens one earlier page, same quiet slide every caller uses.
void _openEditor(BuildContext context, String dateKey) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, _, _) => _EditorScreen(dateKey: dateKey),
      transitionsBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

/// The Journal book: today's page on top, half-written by the rest of the
/// box — the day's facts, every past year's echo of this date, the month's
/// moods — with every earlier page ruled beneath it, and a search that
/// reaches all of them.
class JournalPage extends ConsumerStatefulWidget {
  const JournalPage({super.key});

  @override
  ConsumerState<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends ConsumerState<JournalPage> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final now = DateTime.now();
    final todayKey = LedgerDates.dayKey(now);
    final query = _search.text.trim();
    return ModuleScaffold(
      title: 'Journal',
      trailing: Pressable(
        scale: 0.9,
        onTap: () => setState(() {
          _searching = !_searching;
          if (!_searching) _search.clear();
        }),
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: _searching
              ? PenCross(size: 15, color: c.inkFaint)
              : PenSearch(size: 17, color: c.inkFaint),
        ),
      ),
      child: Column(
        children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.rule)),
                ),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  style: LedgerType.bodyText.copyWith(color: c.ink),
                  cursorColor: c.quill,
                  decoration: InputDecoration(
                    hintText: 'a word from any page…',
                    hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: Gap.x2,
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: query.isNotEmpty
                ? _SearchResults(query: query)
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                    children: [
                      const SizedBox(height: Gap.x4),
                      _PageEditor(dateKey: todayKey),
                      const RuleHeader('the day, in facts'),
                      _DayFacts(day: now),
                      _OnThisDay(today: now),
                      _MonthMoods(today: now),
                      const RuleHeader('earlier pages'),
                      _EarlierPages(todayKey: todayKey),
                      const SizedBox(height: Gap.x8),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pages holding the searched word, newest first — each one tap from its
/// full editor.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return FutureBuilder<List<JournalEntry>>(
      // Keyed so a new query re-reads; a stale future never lingers.
      key: ValueKey(query),
      future: ref.read(journalRepoProvider).search(query),
      builder: (context, snap) {
        final rows = snap.data;
        if (rows == null) return const SizedBox.shrink();
        if (rows.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(Gap.page),
            child: Text(
              'No page holds that word.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          children: [
            const SizedBox(height: Gap.x3),
            Text(
              '${rows.length} ${rows.length == 1 ? 'page holds' : 'pages hold'} it',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x2),
            for (final (i, e) in rows.indexed)
              InkIn(
                delay: Duration(milliseconds: 30 * i),
                child: Pressable(
                  onTap: () => _openEditor(context, e.date),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                    decoration: BoxDecoration(
                      border: i == rows.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: c.rule)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          LedgerDates.dayLabel(DateTime.parse(e.date)),
                          style: LedgerType.amount.copyWith(
                            fontSize: 11,
                            color: c.inkFaint,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          e.body.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 14,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: Gap.x8),
          ],
        );
      },
    );
  }
}

/// One day's writing surface: dateline, the mood row, the words. Used at the
/// top of the book for today and full-screen for any earlier page. Everything
/// autosaves quietly — the page itself is the confirmation.
class _PageEditor extends ConsumerStatefulWidget {
  const _PageEditor({required this.dateKey});

  final String dateKey;

  @override
  ConsumerState<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<_PageEditor> {
  final _controller = TextEditingController();
  late final JournalRepo _repo;
  Timer? _debounce;
  int? _mood;
  int? _energy;
  String? _feelWord;
  String? _feelWhy;
  String? _feelTags;
  bool _dirty = false;

  /// Autosave is silent by design, but silence reads as "did that land?".
  /// The page answers the way paper does: the ink dries, briefly, and the
  /// mark fades off again. No toast, no tick, no "Saved".
  Timer? _dry;
  bool _dried = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(journalRepoProvider);
    // Seed once from the db; never clobber words already being typed.
    unawaited(
      _repo.watch(widget.dateKey).first.then((e) {
        if (!mounted || e == null) return;
        setState(() {
          _mood ??= e.mood;
          _energy ??= e.energy;
          _feelWord ??= e.feelWord;
          _feelWhy ??= e.feelWhy;
          _feelTags ??= e.feelTags;
          if (!_dirty && _controller.text.isEmpty) _controller.text = e.body;
        });
      }),
    );
  }

  @override
  void dispose() {
    _leaving = true;
    _debounce?.cancel();
    _dry?.cancel();
    _flush();
    _controller.dispose();
    super.dispose();
  }

  /// A beat after the write settles, the dateline notes that it dried; a
  /// second and a half later the note is gone again.
  void _markDried() {
    if (_leaving) return;
    _dry?.cancel();
    _dry = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _dried = true);
      _dry = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _dried = false);
      });
    });
  }

  void _onBodyChanged(String _) {
    _dirty = true;
    // Rebuild so the inked-in hint steps aside the moment words arrive.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    if (!_dirty) return;
    _dirty = false;
    unawaited(_repo.upsert(widget.dateKey, body: _controller.text));
    _markDried();
  }

  void _commitFelt(int pleasant, int energy, String word) {
    setState(() {
      _mood = pleasant;
      _energy = energy;
      _feelWord = word;
    });
    unawaited(
      _repo.upsert(
        widget.dateKey,
        mood: pleasant,
        energy: energy,
        feelWord: word,
      ),
    );
    _markDried();
  }

  void _detailFelt(String why, String tags) {
    setState(() {
      _feelWhy = why;
      _feelTags = tags;
    });
    unawaited(_repo.upsert(widget.dateKey, feelWhy: why, feelTags: tags));
    _markDried();
  }

  /// The prompt becomes the page's first line, cursor waiting on the next.
  void _usePrompt(String prompt) {
    _controller.text = '$prompt\n';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _onBodyChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final date = DateTime.parse(widget.dateKey);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final prompt = journalPromptFor(date.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _longDate(date),
              style: LedgerType.title.copyWith(color: c.ink),
            ),
            const SizedBox(width: Gap.x2),
            AnimatedOpacity(
              opacity: _dried ? 1 : 0,
              duration: still ? Duration.zero : Motion.settle,
              curve: Motion.curve,
              child: Text(
                '· saved',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
            const Spacer(),
            // The day's word sits on the dateline beside its own shape; a
            // tap opens the picker to re-mark. An unmarked page just offers.
            Pressable(
              haptic: false,
              onTap: () => showFeelPicker(
                context,
                mood: _mood,
                energy: _energy,
                feelWord: _feelWord,
                feelWhy: _feelWhy,
                feelTags: _feelTags,
                onCommit: _commitFelt,
                onDetail: _detailFelt,
              ),
              child: _feelWord != null && _mood != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FeelBlob(
                          word: _feelWord!,
                          color: feelBubbleColor(
                            from9(_mood!),
                            from9(_energy ?? 5),
                          ),
                          size: 18,
                        ),
                        const SizedBox(width: Gap.x2),
                        Text(
                          _feelWord!,
                          style: LedgerType.title.copyWith(
                            fontSize: 16,
                            color: c.ink,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      _mood != null ? 'marked' : 'mark the day',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 12,
                        color: c.quill,
                      ),
                    ),
            ),
          ],
        ),
        // The check-in's detail rides under the dateline, on the word's
        // side: the chips and the why, said back instead of swallowed.
        if (feltStoryLine(_feelTags, _feelWhy) case final story?)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                story,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 11,
                  color: c.inkFaint,
                ),
              ),
            ),
          ),
        const SizedBox(height: Gap.x2),
        Stack(
          children: [
            // The page invites, never demands: with no words yet, the
            // question surfaces a beat after the page opens.
            if (_controller.text.isEmpty)
              IgnorePointer(
                child: InkIn(
                  delay: const Duration(milliseconds: 400),
                  child: Text(
                    'How was it?',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 15,
                      height: 1.55,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ),
            TextField(
              controller: _controller,
              onChanged: _onBodyChanged,
              maxLines: null,
              minLines: 3,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              cursorColor: c.quill,
              style: LedgerType.bodyText.copyWith(
                fontSize: 15,
                height: 1.55,
                color: c.ink,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        // A blank page offers one question; a tap writes it as the first
        // line. The same date always asks the same thing.
        if (_controller.text.isEmpty) ...[
          const SizedBox(height: Gap.x3),
          InkIn(
            delay: const Duration(milliseconds: 650),
            child: Pressable(
              onTap: () => _usePrompt(prompt),
              child: Text(
                prompt,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

}

/// What the box already wrote on today's page — only the lines that happened.
class _DayFacts extends ConsumerStatefulWidget {
  const _DayFacts({required this.day});

  final DateTime day;

  @override
  ConsumerState<_DayFacts> createState() => _DayFactsState();
}

class _DayFactsState extends ConsumerState<_DayFacts> {
  late final Future<
    ({int spentPaise, int txnCount, int focusMinutes, int notesCount})
  >
  _facts;

  @override
  void initState() {
    super.initState();
    _facts = ref.read(journalRepoProvider).dayFacts(widget.day);
  }

  static String _focus(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return FutureBuilder(
      future: _facts,
      builder: (context, snapshot) {
        final f = snapshot.data;
        if (f == null) return const SizedBox(height: Gap.x6);
        final amountStyle = LedgerType.amount.copyWith(color: c.inkFaint);
        final lines = <(String, Widget)>[
          if (f.txnCount > 0)
            (
              'Spent',
              // The figure settles in mono rather than snapping.
              CountUp(
                value: f.spentPaise,
                format: (p) =>
                    '${Inr.format(p)} across ${f.txnCount} '
                    '${f.txnCount == 1 ? 'entry' : 'entries'}',
                style: amountStyle,
              ),
            ),
          if (f.focusMinutes > 0)
            ('Focused', Text(_focus(f.focusMinutes), style: amountStyle)),
          if (f.notesCount > 0)
            ('Notes written', Text('${f.notesCount}', style: amountStyle)),
        ];
        if (lines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'A quiet day, so far.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          );
        }
        // The facts write themselves onto the page top to bottom, once.
        return Column(
          children: [
            for (final (i, line) in lines.indexed)
              InkIn(
                key: ValueKey('fact-${line.$1}'),
                delay: Duration(milliseconds: 60 * i),
                child: LedgerLine(
                  title: line.$1,
                  amountWidget: line.$2,
                  last: i == lines.length - 1,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Every past year's page for this date — the Day One lesson: a journal is
/// an app, not a tab, when what was captured can come back. Each year is
/// two quiet quoted lines behind a hairline, one tap from its full page.
/// Absent entirely when the book doesn't reach back.
class _OnThisDay extends ConsumerStatefulWidget {
  const _OnThisDay({required this.today});

  final DateTime today;

  @override
  ConsumerState<_OnThisDay> createState() => _OnThisDayState();
}

class _OnThisDayState extends ConsumerState<_OnThisDay> {
  late final Future<List<JournalEntry>> _entries = ref
      .read(journalRepoProvider)
      .onThisDay(widget.today);

  static String _back(int years) =>
      years == 1 ? 'a year back' : '$years years back';

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return FutureBuilder<List<JournalEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <JournalEntry>[];
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RuleHeader('on this day'),
            const SizedBox(height: Gap.x2),
            for (final (i, e) in entries.indexed)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == entries.length - 1 ? 0 : Gap.x3,
                ),
                child: InkIn(
                  delay: Duration(milliseconds: 60 * i),
                  child: Pressable(
                    onTap: () => _openEditor(context, e.date),
                    child: Container(
                      padding: const EdgeInsets.only(
                        left: Gap.x3,
                        top: 2,
                        bottom: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: c.rule, width: 2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${DateTime.parse(e.date).year} · '
                            '${_back(widget.today.year - DateTime.parse(e.date).year)}',
                            style: LedgerType.amount.copyWith(
                              fontSize: 11,
                              color: c.inkFaint,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.body.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 14,
                              height: 1.5,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The month, one small circle per day: tinted by mood, hollow when nothing
/// was recorded, to-day ringed in quill. Beneath it, the running tallies.
class _MonthMoods extends ConsumerStatefulWidget {
  const _MonthMoods({required this.today});

  final DateTime today;

  @override
  ConsumerState<_MonthMoods> createState() => _MonthMoodsState();
}

class _MonthMoodsState extends ConsumerState<_MonthMoods> {
  /// This month's expense paise per day of the month, read once — the money
  /// half of the whisper under the grid.
  late final Future<Map<int, int>> _spentByDay;

  /// Latched on the first emission so the dots ink in once and every later
  /// rebuild renders an already-drawn month.
  bool _played = false;

  @override
  void initState() {
    super.initState();
    _spentByDay = _loadSpend();
  }

  Future<Map<int, int>> _loadSpend() async {
    final db = ref.read(dbProvider);
    final rows =
        await (db.select(db.txns)..where(
              (t) =>
                  t.type.equalsValue(TxnType.expense) &
                  t.at.isBiggerOrEqualValue(
                    LedgerDates.monthStart(widget.today),
                  ) &
                  t.at.isSmallerThanValue(LedgerDates.monthEnd(widget.today)),
            ))
            .get();
    final byDay = <int, int>{};
    for (final r in rows) {
      byDay.update(
        r.at.day,
        (p) => p + r.amountPaise,
        ifAbsent: () => r.amountPaise,
      );
    }
    return byDay;
  }

  /// Each day wears its own weather — the same colour the field showed when
  /// the mark was placed. Old marks without an energy sit on the mid line.
  Color _moodTint(int mood, int? energy) =>
      feelAtmosphere(from9(mood), from9(energy ?? 5));

  void _openDay(int day) {
    _openEditor(
      context,
      LedgerDates.dayKey(DateTime(widget.today.year, widget.today.month, day)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<JournalEntry>>(
      stream: ref.watch(journalRepoProvider).watchAll(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <JournalEntry>[];
        final dots = monthMoodDots(
          entries.map((e) => (e.date, e.mood, e.energy)),
          widget.today,
        );
        final written = [
          for (final e in entries)
            if (_isWritten(e)) e.date,
        ];
        final streak = journalStreakDays(written, widget.today);
        final pages = journalPagesInMonth(written, widget.today);
        // The dots write themselves across the month rather than all landing
        // at once — the same hand as the book's heat grid.
        final play = !_played && snapshot.hasData;
        if (snapshot.hasData) _played = true;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RuleHeader('the month in moods'),
            const SizedBox(height: Gap.x2),
            GridView.count(
              key: const ValueKey('mood-grid'),
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1.5,
              children: [
                for (final (i, mark) in dots.indexed)
                  InkIn(
                    key: ValueKey('mood-dot-$i'),
                    play: play,
                    delay: Duration(milliseconds: 10 * i),
                    child: _dayDot(c, i + 1, mark),
                  ),
              ],
            ),
            const SizedBox(height: Gap.x3),
            _tallyLine(c, streak, pages),
            _moodMoneyLine(c, dots),
          ],
        );
      },
    );
  }

  /// One factual sentence when the mood column and the money column actually
  /// disagree this month — and nothing at all when they don't.
  Widget _moodMoneyLine(LedgerColors c, List<(int, int?)?> dots) {
    return FutureBuilder<Map<int, int>>(
      future: _spentByDay,
      builder: (context, snapshot) {
        final spent = snapshot.data;
        if (spent == null) return const SizedBox.shrink();
        final line = moodMoneyWhisper([
          for (final (i, mark) in dots.indexed)
            if (mark != null && i < widget.today.day)
              (mark.$1, spent[i + 1] ?? 0),
        ]);
        if (line == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Gap.x2),
          child: InkIn(
            child: Text(
              line,
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dayDot(LedgerColors c, int day, (int, int?)? mark) {
    final isToday = day == widget.today.day;
    final isFuture = day > widget.today.day;
    Widget dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: mark == null ? null : _moodTint(mark.$1, mark.$2),
        border: mark == null
            ? Border.all(
                color: isFuture ? c.rule.withValues(alpha: 0.55) : c.rule,
                width: 1.2,
              )
            : null,
      ),
    );
    if (isToday) {
      dot = Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: c.quill, width: 1.2),
        ),
        child: dot,
      );
    }
    final cell = Center(child: dot);
    if (isFuture) return cell;
    // Any lived day opens its page.
    return Pressable(scale: 0.9, onTap: () => _openDay(day), child: cell);
  }

  /// "written 4 days running · 12 pages this month" — numbers settle, and
  /// the phrasing never pretends to a streak that isn't there.
  Widget _tallyLine(LedgerColors c, int streak, int pages) {
    final style = LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint);
    if (streak == 0 && pages == 0) {
      return Text(
        'nothing written this month, yet.',
        style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
      );
    }
    return Row(
      children: [
        if (streak > 0)
          CountUp(
            value: streak,
            format: (n) => 'written $n ${n == 1 ? 'day' : 'days'} running',
            style: style,
          ),
        if (streak > 0 && pages > 0) Text(' · ', style: style),
        if (pages > 0)
          CountUp(
            value: pages,
            format: (n) => '$n ${n == 1 ? 'page' : 'pages'} this month',
            style: style,
          ),
      ],
    );
  }
}

/// Every page before today, newest first. Tap a row to reopen that day.
class _EarlierPages extends ConsumerStatefulWidget {
  const _EarlierPages({required this.todayKey});

  final String todayKey;

  @override
  ConsumerState<_EarlierPages> createState() => _EarlierPagesState();
}

class _EarlierPagesState extends ConsumerState<_EarlierPages> {
  /// Latched after the first emission: the rows ink in once, then every
  /// later rebuild renders them as already-written pages.
  bool _played = false;

  /// A year of journalling is 365 ruled lines; the book opens on the recent
  /// ones and turns back a season at a time when he asks.
  static const _firstLeaf = 14;
  static const _nextLeaf = 30;
  int _shown = _firstLeaf;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<JournalEntry>>(
      stream: ref.watch(journalRepoProvider).watchAll(),
      builder: (context, snapshot) {
        final earlier = (snapshot.data ?? const <JournalEntry>[])
            .where((e) => e.date != widget.todayKey)
            .toList();
        final play = !_played && snapshot.hasData;
        if (snapshot.hasData) _played = true;
        if (earlier.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'The book starts to-day.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          );
        }
        final leaf = earlier.take(_shown).toList();
        final back = earlier.length - leaf.length;
        return Column(
          children: [
            for (final (i, e) in leaf.indexed)
              InkIn(
                key: ValueKey('earlier-${e.date}'),
                play: play,
                delay: Duration(milliseconds: 60 * math.min(i, 8)),
                child: _EarlierRow(
                  entry: e,
                  last: back == 0 && i == leaf.length - 1,
                ),
              ),
            if (back > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                child: Pressable(
                  onTap: () => setState(
                    () => _shown = math.min(_shown + _nextLeaf, earlier.length),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'further back — $back more ${back == 1 ? 'page' : 'pages'}',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 13,
                        color: c.quill,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EarlierRow extends StatelessWidget {
  const _EarlierRow({required this.entry, required this.last});

  final JournalEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final firstLine = entry.body.trim().split('\n').first.trim();
    final wordless = firstLine.isEmpty;
    return InkWell(
      onTap: () => _openEditor(context, entry.date),
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                _shortDate(DateTime.parse(entry.date)),
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
            Expanded(
              child: Text(
                wordless ? '(no words, mood only)' : firstLine,
                style: LedgerType.bodyText.copyWith(
                  color: wordless ? c.inkFaint : c.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.mood != null) ...[
              const SizedBox(width: Gap.x2),
              // The day's weather, small — same colour its month dot wears.
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: feelAtmosphere(
                    from9(entry.mood!),
                    from9(entry.energy ?? 5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full page from an earlier day — same surface as today's, back to pop.
class _EditorScreen extends StatelessWidget {
  const _EditorScreen({required this.dateKey});

  final String dateKey;

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Journal',
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        children: [
          const SizedBox(height: Gap.x4),
          _PageEditor(dateKey: dateKey),
          const SizedBox(height: Gap.x8),
        ],
      ),
    );
  }
}
