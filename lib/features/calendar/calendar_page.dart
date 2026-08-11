import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/event_repo.dart';
import '../../data/repos/recurring_repo.dart';

/// A plan resolved onto a day.
typedef Occurrence = ({Event event, DateTime on});

/// A recurring charge resolved onto the day it lands.
typedef Charge = ({Recurring recurring, DateTime on});

/// What the ledger already says about one day.
typedef DayMoney = ({int spent, int earned});

/// The month as the spine writes it: lower case, the way a hand would.
String _monthWord(DateTime d) =>
    LedgerDates.monthsFull[d.month - 1].toLowerCase();

/// Every recurring charge landing in `[from, to)`.
///
/// The calendar borrows the money book's shelf so a day can show both what
/// was planned and what is owed. Pure math over the rows — no query per day.
List<Charge> chargesBetween(
  List<Recurring> rows,
  DateTime from,
  DateTime to,
) {
  final start = DateTime(from.year, from.month, from.day);
  final out = <Charge>[];
  for (final r in rows) {
    final step = r.everyMonths < 1 ? 1 : r.everyMonths;
    var due = RecurringRepo.nextDate(r.dayOfMonth, step, start);
    var guard = 0;
    while (due.isBefore(to) && guard++ < 60) {
      out.add((recurring: r, on: due));
      // Jump to the head of the next cadence month and let the repo clamp
      // the day again — the 31st still lands in February.
      due = RecurringRepo.nextDate(
        r.dayOfMonth,
        step,
        DateTime(due.year, due.month + step),
      );
    }
  }
  out.sort((a, b) {
    final byDate = a.on.compareTo(b.on);
    return byDate != 0 ? byDate : a.recurring.id.compareTo(b.recurring.id);
  });
  return out;
}

/// What went out and what came in, day by day. Transfers move money between
/// pockets rather than in or out, so they never reach a day's total.
Map<String, DayMoney> moneyByDay(List<Txn> txns) {
  final out = <String, DayMoney>{};
  for (final t in txns) {
    if (t.type == TxnType.transfer) continue;
    final key = LedgerDates.dayKey(t.at);
    final cur = out[key] ?? (spent: 0, earned: 0);
    out[key] = t.type == TxnType.expense
        ? (spent: cur.spent + t.amountPaise, earned: cur.earned)
        : (spent: cur.spent, earned: cur.earned + t.amountPaise);
  }
  return out;
}

/// The yearly days approaching: within [days] of [from] (to-day itself is
/// excluded — that page already shows them), soonest first, at most [limit].
/// Feeds the "counting down" lines under the agenda's first day.
List<({Event event, DateTime on, int daysAway})> countingDown(
  List<Event> events,
  DateTime from, {
  int days = 120,
  int limit = 3,
}) {
  final start = DateTime(from.year, from.month, from.day);
  final yearly = [
    for (final e in events)
      if (e.repeat == EventRepeat.yearly) e,
  ];
  final occ = EventRepo.upcoming(yearly, start, days: days + 1, limit: 1000);
  final out = <({Event event, DateTime on, int daysAway})>[];
  for (final o in occ) {
    final away = o.on.difference(start).inDays;
    if (away >= 1 && away <= days) {
      out.add((event: o.event, on: o.on, daysAway: away));
    }
  }
  return out.length <= limit ? out : out.sublist(0, limit);
}

/// "3 things this week · next: Rent, Monday" — or null when the week is
/// clear. The week runs Monday through Sunday around [selected]; "next" is
/// the first plan on or after the selected day, else the week's first.
String? weekSummary(List<Event> events, DateTime selected) {
  final day = DateTime(selected.year, selected.month, selected.day);
  final monday = day.subtract(Duration(days: day.weekday - 1));
  final occ = EventRepo.upcoming(events, monday, days: 7, limit: 1000);
  if (occ.isEmpty) return null;
  final next = occ.firstWhere(
    (o) => !o.on.isBefore(day),
    orElse: () => occ.first,
  );
  final n = occ.length;
  return '$n thing${n == 1 ? '' : 's'} this week · '
      'next: ${next.event.title}, '
      '${LedgerDates.weekdaysFull[next.on.weekday - 1]}';
}

/// The one write the repo doesn't offer: rewriting an event in place.
/// Editing is this page's own business, so the drift update lives here.
Future<void> _rewriteEvent(
  LedgerDb db,
  int id, {
  required String title,
  required DateTime date,
  required int? timeMinutes,
  required EventRepeat repeat,
}) {
  return (db.update(db.events)..where((e) => e.id.equals(id))).write(
    EventsCompanion(
      title: drift.Value(title),
      date: drift.Value(LedgerDates.dayKey(date)),
      timeMinutes: drift.Value(timeMinutes),
      repeat: drift.Value(repeat),
    ),
  );
}

/// The Calendar book as a running agenda: an ink spine down the left edge
/// carries the days (to-day inverted onto paper) and the month written
/// sideways; the page beside it holds each day's plans as tick-barred lines,
/// the bills it owes underneath, and what the ledger already spent that day
/// in the margin. Rent-the-plan and rent-the-bill share one page.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  final Set<int> _leaving = {};

  /// Event ids already written on the agenda — only genuinely new plans ink
  /// in; the first load renders an already-kept book.
  final Set<int> _seenEvents = {};
  bool _eventsPrimed = false;

  static const _spineWidth = 60.0;
  static const _horizon = 60;

  /// The day the agenda starts from — the week strip's business.
  late DateTime _selected;

  /// The month the grid is open at. It follows the selection, but a swipe
  /// can send it ahead without moving the chosen day.
  late DateTime _gridMonth;

  /// True while the page shows the whole month at once instead of the
  /// running agenda. The toggle lives in the week-strip row.
  bool _monthView = false;

  /// Which way the last month flip went, and how many flips deep the grid
  /// is — a flipped month slides in from the side it was reached from.
  double _flipDx = 1;
  int _flipSeq = 0;

  /// The money window the two ledger streams read. It is only re-cut when
  /// the visible months change; moving a day inside it keeps the streams.
  DateTime? _moneyFrom;
  DateTime? _moneyTo;
  Stream<List<Txn>>? _txnStream;
  Stream<List<Recurring>>? _recurringStream;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _gridMonth = LedgerDates.monthStart(_selected);
  }

  void _select(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = day;
      _aimGrid(LedgerDates.monthStart(day));
    });
  }

  /// Points the grid at [month], remembering which way it travelled.
  void _aimGrid(DateTime month) {
    if (month == _gridMonth) return;
    _flipDx = month.isAfter(_gridMonth) ? 1 : -1;
    _gridMonth = month;
    _flipSeq++;
  }

  void _flipGridMonth(int dir) {
    HapticFeedback.selectionClick();
    setState(() => _aimGrid(DateTime(_gridMonth.year, _gridMonth.month + dir)));
  }

  void _toggleView() {
    HapticFeedback.selectionClick();
    setState(() => _monthView = !_monthView);
  }

  void _pickFromGrid(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = day;
      _monthView = false;
      _aimGrid(LedgerDates.monthStart(day));
    });
  }

  Future<void> _archive(Event e) async {
    HapticFeedback.mediumImpact();
    setState(() => _leaving.add(e.id));
    await Future<void>.delayed(Motion.quick);
    if (!mounted) return;
    await ref.read(eventRepoProvider).archive(e.id);
    _leaving.remove(e.id);
  }

  Future<void> _openAddSheet({Event? event, DateTime? at}) async {
    HapticFeedback.lightImpact();
    final saved = await showLedgerSheet<DateTime>(
      context,
      builder: (_) => _AddEventSheet(
        initialDate: event == null
            ? (at ?? _selected)
            : DateTime.parse(event.date),
        event: event,
      ),
    );
    if (saved != null && mounted) _select(saved);
  }

  /// Cuts the ledger window the money layer reads: the months in view, plus
  /// enough of the future to cover the agenda's horizon.
  void _syncMoneyWindow() {
    final selMonth = LedgerDates.monthStart(_selected);
    final from = _gridMonth.isBefore(selMonth) ? _gridMonth : selMonth;
    final selEnd = DateTime(selMonth.year, selMonth.month + 3);
    final gridEnd = DateTime(_gridMonth.year, _gridMonth.month + 1);
    final to = gridEnd.isAfter(selEnd) ? gridEnd : selEnd;
    if (_moneyFrom == from && _moneyTo == to) return;
    _moneyFrom = from;
    _moneyTo = to;
    _txnStream = ref.read(txnRepoProvider).watchRange(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(eventRepoProvider);
    _recurringStream ??= ref.read(recurringRepoProvider).watchAll();
    _syncMoneyWindow();

    return ModuleScaffold(
      title: 'Calendar',
      fab: Pressable(
        onTap: _openAddSheet,
        haptic: false,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: c.quill,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: c.ink.withValues(alpha: 0.28),
                offset: const Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Icon(Icons.add, color: c.paper, size: 26),
        ),
      ),
      child: StreamBuilder<List<Event>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          final events = snap.data ?? const <Event>[];
          // Plans that were not in the book last emission ink into the
          // agenda; a plain rebuild moves nothing.
          final freshIds = <int>{
            if (_eventsPrimed)
              for (final e in events)
                if (!_seenEvents.contains(e.id)) e.id,
          };
          if (snap.hasData) {
            _eventsPrimed = true;
            _seenEvents.addAll(events.map((e) => e.id));
          }

          return StreamBuilder<List<Recurring>>(
            stream: _recurringStream,
            builder: (context, dueSnap) {
              return StreamBuilder<List<Txn>>(
                stream: _txnStream,
                builder: (context, txnSnap) => _page(
                  context,
                  events: events,
                  fresh: freshIds,
                  recurrings: dueSnap.data ?? const <Recurring>[],
                  txns: txnSnap.data ?? const <Txn>[],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _page(
    BuildContext context, {
    required List<Event> events,
    required Set<int> fresh,
    required List<Recurring> recurrings,
    required List<Txn> txns,
  }) {
    final c = LedgerColors.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final occ = EventRepo.upcoming(
      events,
      _selected,
      days: _horizon,
      limit: 400,
    );
    final horizonEnd = DateTime(
      _selected.year,
      _selected.month,
      _selected.day + _horizon,
    );
    final charges = chargesBetween(recurrings, _selected, horizonEnd);
    final money = moneyByDay(txns);

    // Group plans and charges by day; the chosen day always gets a page.
    final byDay = <String, List<Occurrence>>{
      LedgerDates.dayKey(_selected): [],
    };
    for (final o in occ) {
      byDay.putIfAbsent(LedgerDates.dayKey(o.on), () => []).add(o);
    }
    final billsByDay = <String, List<Charge>>{};
    for (final ch in charges) {
      final key = LedgerDates.dayKey(ch.on);
      billsByDay.putIfAbsent(key, () => []).add(ch);
      byDay.putIfAbsent(key, () => []);
    }
    final days = byDay.keys.map(DateTime.parse).toList()..sort();
    final blank = occ.isEmpty && charges.isEmpty;

    final countdown = countingDown(events, _selected);
    final summary = weekSummary(events, _selected);

    final rows = <Widget>[];
    int? shownMonth;
    var zebra = false;
    var dayIndex = 0;
    for (final day in days) {
      if (day.month != shownMonth) {
        shownMonth = day.month;
        rows.add(_MonthMarker(day: day));
      }
      final key = LedgerDates.dayKey(day);
      rows.add(
        _DayGroup(
          day: day,
          isToday: day == today,
          zebra: zebra,
          occurrences: byDay[key]!,
          bills: billsByDay[key] ?? const <Charge>[],
          money: money[key],
          // When the whole horizon is blank the page below speaks for it;
          // the day itself doesn't need to say "nothing" twice.
          sayEmpty: !blank,
          leaving: _leaving,
          fresh: fresh,
          onArchive: _archive,
          onEdit: (e) => _openAddSheet(event: e),
        ),
      );
      // The book counts its yearly days down under the first page.
      if (dayIndex == 0 && countdown.isNotEmpty) {
        rows.add(_CountdownSection(lines: countdown));
      }
      dayIndex++;
      zebra = !zebra;
    }
    rows.add(
      _SpineTail(
        child: blank
            ? const EmptyPage(
                line: 'The next $_horizon days are blank.',
                sub: 'The plus below is how a day stops being blank.',
              )
            : const SizedBox(height: Gap.x12),
      ),
    );

    final reduced = Motion.reduced(context);

    return Column(
      children: [
        _WeekStrip(
          selected: _selected,
          today: today,
          monthView: _monthView,
          onSelect: _select,
          onToggleView: _toggleView,
        ),
        if (summary != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x2),
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
          ),
        Expanded(
          // The whole month and the running agenda are two readings of the
          // same book — they cross-fade into each other.
          child: AnimatedSwitcher(
            duration: reduced ? Duration.zero : Motion.spring,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.curve,
            child: _monthView
                ? KeyedSubtree(
                    key: const ValueKey('view-grid'),
                    // A drag across the grid turns to the next month.
                    child: GestureDetector(
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 220) return;
                        _flipGridMonth(v < 0 ? 1 : -1);
                      },
                      child: AnimatedSwitcher(
                        duration: reduced ? Duration.zero : Motion.spring,
                        switchInCurve: Motion.curve,
                        switchOutCurve: Motion.curve,
                        transitionBuilder: (child, anim) {
                          final incoming =
                              child.key == ValueKey('grid-$_flipSeq');
                          final dx = (incoming ? _flipDx : -_flipDx) * 0.08;
                          return FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween(
                                begin: Offset(dx, 0),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          );
                        },
                        child: _MonthGrid(
                          key: ValueKey('grid-$_flipSeq'),
                          month: _gridMonth,
                          selected: _selected,
                          today: today,
                          events: events,
                          recurrings: recurrings,
                          money: money,
                          onPick: _pickFromGrid,
                          onAdd: (d) => _openAddSheet(at: d),
                        ),
                      ),
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey('view-agenda'),
                    // Refocusing on a day reads as turning to its page: the
                    // content fades and rises the smallest amount.
                    child: AnimatedSwitcher(
                      duration: reduced ? Duration.zero : Motion.quick,
                      switchInCurve: Motion.curve,
                      switchOutCurve: Motion.curve,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.01),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: ListView(
                        key: ValueKey('page-${LedgerDates.dayKey(_selected)}'),
                        padding: EdgeInsets.zero,
                        children: rows,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// The week under the day's name: letters over mono numbers, the chosen day
/// in a quill circle. The strip is a run of weeks — swipe it, or let the
/// chevrons walk it one page at a time.
class _WeekStrip extends StatefulWidget {
  const _WeekStrip({
    required this.selected,
    required this.today,
    required this.monthView,
    required this.onSelect,
    required this.onToggleView,
  });

  final DateTime selected;
  final DateTime today;
  final bool monthView;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onToggleView;

  @override
  State<_WeekStrip> createState() => _WeekStripState();
}

class _WeekStripState extends State<_WeekStrip> {
  /// Pages are weeks either side of the week the book opened on.
  static const _base = 1000;
  static const _stripHeight = 58.0;

  late final DateTime _origin = _mondayOf(widget.selected);
  final PageController _pages = PageController(initialPage: _base);

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  DateTime _mondayFor(int page) =>
      DateTime(_origin.year, _origin.month, _origin.day + 7 * (page - _base));

  int _pageFor(DateTime monday) =>
      _base + (monday.difference(_origin).inDays / 7).round();

  @override
  void didUpdateWidget(_WeekStrip old) {
    super.didUpdateWidget(old);
    // A day chosen elsewhere — the grid, "back to to-day" — carries the
    // strip to its week rather than snapping it there.
    final monday = _mondayOf(widget.selected);
    if (_mondayOf(old.selected) == monday || !_pages.hasClients) return;
    _turnTo(_pageFor(monday), Motion.spring);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _turnTo(int page, Duration duration) {
    if (!_pages.hasClients) return;
    if ((_pages.page ?? _base.toDouble()).round() == page) return;
    if (Motion.reduced(context)) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: duration, curve: Motion.curve);
    }
  }

  void _shift(int dir) {
    if (!_pages.hasClients) return;
    HapticFeedback.selectionClick();
    _turnTo((_pages.page ?? _base.toDouble()).round() + dir, Motion.quick);
  }

  /// A swiped week keeps the weekday under the thumb.
  void _onPage(int page) {
    final monday = _mondayFor(page);
    if (_mondayOf(widget.selected) == monday) return;
    widget.onSelect(
      DateTime(
        monday.year,
        monday.month,
        monday.day + widget.selected.weekday - 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final isToday = widget.selected == widget.today;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.x2, Gap.x3, Gap.x2, Gap.x3),
      child: Column(
        children: [
          Pressable(
            scale: 0.98,
            // The day's name is the way home.
            onTap: isToday ? null : () => widget.onSelect(widget.today),
            child: Column(
              children: [
                Text(
                  LedgerDates.weekdaysFull[widget.selected.weekday - 1]
                      .toLowerCase(),
                  style: LedgerType.title.copyWith(fontSize: 24, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.selected.day} ${_monthWord(widget.selected)} '
                  '${widget.selected.year}'
                  '${isToday ? '' : '  ·  back to to-day'}',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: isToday ? c.inkFaint : c.quill,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.x3),
          Row(
            children: [
              Pressable(
                scale: 0.86,
                haptic: false,
                onTap: () => _shift(-1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child: Icon(Icons.chevron_left, size: 18, color: c.inkFaint),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: _stripHeight,
                  child: PageView.builder(
                    controller: _pages,
                    onPageChanged: _onPage,
                    itemBuilder: (context, page) {
                      final monday = _mondayFor(page);
                      return Row(
                        children: [
                          for (var i = 0; i < 7; i++)
                            Builder(
                              builder: (context) {
                                final day = DateTime(
                                  monday.year,
                                  monday.month,
                                  monday.day + i,
                                );
                                return Expanded(
                                  child: _WeekDay(
                                    day: day,
                                    selected: day == widget.selected,
                                    isToday: day == widget.today,
                                    onTap: () => widget.onSelect(day),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Pressable(
                scale: 0.86,
                haptic: false,
                onTap: () => _shift(1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child: Icon(Icons.chevron_right, size: 18, color: c.inkFaint),
                ),
              ),
              Pressable(
                scale: 0.86,
                haptic: false,
                onTap: widget.onToggleView,
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child: AnimatedSwitcher(
                    duration: Motion.reduced(context)
                        ? Duration.zero
                        : Motion.quick,
                    switchInCurve: Motion.curve,
                    switchOutCurve: Motion.curve,
                    child: Icon(
                      widget.monthView ? Icons.view_agenda : Icons.grid_on,
                      key: ValueKey('view-toggle-${widget.monthView}'),
                      size: 16,
                      color: widget.monthView ? c.quill : c.inkFaint,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekDay extends StatelessWidget {
  const _WeekDay({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      scale: 0.92,
      haptic: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.x1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              LedgerDates.weekdays[day.weekday - 1][0],
              style: LedgerType.label.copyWith(
                fontSize: 10,
                color: selected ? c.quill : c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x1),
            AnimatedContainer(
              duration: Motion.reduced(context) ? Duration.zero : Motion.quick,
              curve: Motion.curve,
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.quill : c.quill.withValues(alpha: 0),
              ),
              child: Text(
                '${day.day}',
                style: LedgerType.amount.copyWith(
                  fontSize: 13,
                  color: selected
                      ? c.paper
                      : isToday
                      ? c.quill
                      : c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month written up the spine, the way it sits on a real ledger's edge.
class _MonthMarker extends StatelessWidget {
  const _MonthMarker({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _CalendarPageState._spineWidth,
            color: c.ink,
            alignment: Alignment.center,
            // The month writes itself up the spine as it first appears.
            child: InkIn(
              key: ValueKey('month-${day.year}-${day.month}'),
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  '${_monthWord(day)} ${day.year}',
                  style: LedgerType.label.copyWith(
                    fontSize: 11,
                    letterSpacing: 2.5,
                    color: c.paper.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }
}

/// One day: its spine cell and its page — plans first, then whatever the
/// shelf takes that day, with the ledger's own figure in the margin.
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.isToday,
    required this.zebra,
    required this.occurrences,
    required this.bills,
    required this.money,
    required this.sayEmpty,
    required this.leaving,
    required this.fresh,
    required this.onArchive,
    required this.onEdit,
  });

  final DateTime day;
  final bool isToday;
  final bool zebra;
  final List<Occurrence> occurrences;

  /// The recurring charges landing on this day — borrowed from the money
  /// book, read only.
  final List<Charge> bills;

  /// What the ledger already recorded here, if anything.
  final DayMoney? money;

  /// False when the page below already says the horizon is blank.
  final bool sayEmpty;

  final Set<int> leaving;

  /// Event ids new since the last emission — their lines ink in.
  final Set<int> fresh;

  final Future<void> Function(Event) onArchive;
  final ValueChanged<Event> onEdit;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final m = money;
    final spent = m?.spent ?? 0;
    final earned = m?.earned ?? 0;
    final empty = occurrences.isEmpty && bills.isEmpty;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: _CalendarPageState._spineWidth,
            color: c.ink,
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            alignment: Alignment.topCenter,
            child: _SpineDate(day: day, isToday: isToday),
          ),
          Expanded(
            child: Container(
              color: zebra ? c.paperRaised.withValues(alpha: 0.6) : c.paper,
              padding: const EdgeInsets.fromLTRB(
                Gap.x4,
                Gap.x3,
                Gap.page,
                Gap.x3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The day's own figure, kept in the margin the way a
                  // book-keeper tallies down the side.
                  if (spent > 0 || earned > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        spent > 0
                            ? '${Inr.format(spent)} out'
                            : '${Inr.format(earned, signed: true)} in',
                        style: LedgerType.amount.copyWith(
                          fontSize: 11,
                          color: spent > 0 ? c.inkFaint : c.jama,
                        ),
                      ),
                    ),
                  if (empty && sayEmpty)
                    Text(
                      spent > 0 || earned > 0
                          ? 'Nothing planned. The ledger still had a day.'
                          : 'Nothing on this page.',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  for (final o in occurrences)
                    InkIn(
                      key: ValueKey(
                        'ev-${o.event.id}-${LedgerDates.dayKey(o.on)}',
                      ),
                      play: fresh.contains(o.event.id),
                      child: _EventLine(
                        occurrence: o,
                        leaving: leaving.contains(o.event.id),
                        onArchive: () => onArchive(o.event),
                        onEdit: () => onEdit(o.event),
                      ),
                    ),
                  for (final b in bills) _ChargeLine(charge: b),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpineDate extends StatelessWidget {
  const _SpineDate({required this.day, required this.isToday});

  final DateTime day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final fg = isToday ? c.ink : c.paper;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          LedgerDates.weekdays[day.weekday - 1],
          style: LedgerType.label.copyWith(
            fontSize: 9,
            letterSpacing: 1.4,
            color: isToday ? c.ink : c.paper.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          '${day.day}',
          style: LedgerType.amountTotal.copyWith(fontSize: 19, color: fg),
        ),
      ],
    );
    if (!isToday) return column;
    // To-day steps out of the spine onto paper.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(10),
      ),
      child: column,
    );
  }
}

/// One plan: a small tick of ink, the words, the hour underneath. A tap
/// opens the line for rewriting; a long press strikes it off.
class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.occurrence,
    required this.leaving,
    required this.onArchive,
    required this.onEdit,
  });

  final Occurrence occurrence;
  final bool leaving;
  final VoidCallback onArchive;
  final VoidCallback onEdit;

  String get _timeLabel {
    final t = occurrence.event.timeMinutes;
    if (t == null) return 'all day';
    return '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final e = occurrence.event;
    final yearly = e.repeat == EventRepeat.yearly;
    final tick = yearly || e.timeMinutes != null ? c.quill : c.inkFaint;

    return AnimatedOpacity(
      duration: Motion.reduced(context) ? Duration.zero : Motion.quick,
      curve: Motion.curve,
      opacity: leaving ? 0 : 1,
      child: Pressable(
        scale: 0.99,
        haptic: false,
        onTap: onEdit,
        onLongPress: onArchive,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 30,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: tick,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Gap.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 14,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      yearly ? '$_timeLabel · every year' : _timeLabel,
                      style: LedgerType.amount.copyWith(
                        fontSize: 11,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              if (yearly)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(Icons.cake_outlined, size: 14, color: c.inkFaint),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bill the shelf will take that day: a short quill tick, the name, the
/// figure in mono. The money book keeps the write; this page only reads it.
class _ChargeLine extends StatelessWidget {
  const _ChargeLine({required this.charge});

  final Charge charge;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final r = charge.recurring;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: c.quill,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: r.title,
                children: [
                  TextSpan(
                    text: r.isBillLike ? '  due' : '  renews',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.ink),
            ),
          ),
          const SizedBox(width: Gap.x2),
          Text(
            Inr.format(r.amountPaise),
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Bills and subscriptions read differently on a page: one is owed, the
/// other simply comes round again.
extension on Recurring {
  bool get isBillLike => kind == RecurringKind.bill;
}

/// Lets the spine run past the last day instead of stopping dead.
class _SpineTail extends StatelessWidget {
  const _SpineTail({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: _CalendarPageState._spineWidth, color: c.ink),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// The yearly days drawing near, counted down under the agenda's first
/// page: "Amma's birthday · 47 days", at most three lines.
class _CountdownSection extends StatelessWidget {
  const _CountdownSection({required this.lines});

  final List<({Event event, DateTime on, int daysAway})> lines;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return _SpineTail(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x3, Gap.page, Gap.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'counting down',
              style: LedgerType.label.copyWith(fontSize: 10, color: c.inkFaint),
            ),
            const SizedBox(height: Gap.x2),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.x2),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 12,
                      decoration: BoxDecoration(
                        color: c.quill,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: Gap.x2),
                    Expanded(
                      child: Text(
                        l.event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.ink,
                        ),
                      ),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${l.daysAway}',
                            style: LedgerType.amount.copyWith(
                              fontSize: 12,
                              color: c.ink,
                            ),
                          ),
                          TextSpan(
                            text: ' day${l.daysAway == 1 ? '' : 's'}',
                          ),
                        ],
                      ),
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a day's dot stands for.
enum _Mark { plan, yearly, bill }

/// The whole month at one glance: Monday-first, mono digits, to-day circled
/// in the quill, the chosen day ringed, plans as filled dots and bills as
/// hollow ones (outlined = expected, not yet paid). Cells write themselves
/// in, top-left to bottom-right. A tap turns back to the agenda opened on
/// that day; a long press peeks at it without leaving the month.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.today,
    required this.events,
    required this.recurrings,
    required this.money,
    required this.onPick,
    required this.onAdd,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final List<Event> events;
  final List<Recurring> recurrings;
  final Map<String, DayMoney> money;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<DateTime> onAdd;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final occ = EventRepo.occurrencesInMonth(events, month);
    final bills = chargesBetween(
      recurrings,
      LedgerDates.monthStart(month),
      LedgerDates.monthEnd(month),
    );

    final plansByDay = <int, List<Occurrence>>{};
    final billsByDay = <int, List<Charge>>{};
    final marks = <int, List<_Mark>>{};
    for (final o in occ) {
      plansByDay.putIfAbsent(o.on.day, () => []).add(o);
      marks
          .putIfAbsent(o.on.day, () => [])
          .add(o.event.repeat == EventRepeat.yearly ? _Mark.yearly : _Mark.plan);
    }
    var billTotal = 0;
    for (final b in bills) {
      billsByDay.putIfAbsent(b.on.day, () => []).add(b);
      marks.putIfAbsent(b.on.day, () => []).add(_Mark.bill);
      billTotal += b.recurring.amountPaise;
    }

    final lead = DateTime(month.year, month.month).weekday - 1;
    final total = LedgerDates.daysInMonth(month);
    final cells = <int?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= total; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x6),
      child: Column(
        children: [
          // The month says its own name here — the spine is off duty while
          // the grid is open — and what it owes before it is over.
          Row(
            children: [
              Text(
                '${_monthWord(month)} ${month.year}',
                style: LedgerType.label.copyWith(fontSize: 11, color: c.ink),
              ),
              const Spacer(),
              if (billTotal > 0)
                Text(
                  '${Inr.format(billTotal)} due',
                  style: LedgerType.amount.copyWith(
                    fontSize: 11,
                    color: c.inkFaint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.x3),
          Row(
            children: [
              for (final d in LedgerDates.weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d[0],
                      style: LedgerType.label.copyWith(
                        fontSize: 10,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.x2),
          Container(height: 1, color: c.rule),
          for (var w = 0; w < cells.length ~/ 7; w++) ...[
            const SizedBox(height: Gap.x2),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: InkIn(
                      // Written in reading order, a hair apart.
                      delay: Duration(milliseconds: 12 * (w * 7 + i)),
                      child: _cell(
                        context,
                        c,
                        cells[w * 7 + i],
                        marks,
                        plansByDay,
                        billsByDay,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    LedgerColors c,
    int? d,
    Map<int, List<_Mark>> marks,
    Map<int, List<Occurrence>> plansByDay,
    Map<int, List<Charge>> billsByDay,
  ) {
    if (d == null) return const SizedBox(height: 44);
    final date = DateTime(month.year, month.month, d);
    final isToday = date == today;
    final isSelected = date == selected;
    final dayMarks = (marks[d] ?? const <_Mark>[]).take(3).toList();

    BoxDecoration? ring;
    if (isToday) {
      ring = BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? c.quillSoft : null,
        border: Border.all(color: c.quill, width: 1.5),
      );
    } else if (isSelected) {
      ring = BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.inkFaint),
      );
    }

    return Pressable(
      onTap: () => onPick(date),
      haptic: false,
      onLongPress: () => _peek(
        context,
        date,
        plansByDay[d] ?? const <Occurrence>[],
        billsByDay[d] ?? const <Charge>[],
      ),
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: ring,
              child: Text(
                '$d',
                style: LedgerType.amount.copyWith(
                  fontSize: 13,
                  color: isToday ? c.quill : c.ink,
                ),
              ),
            ),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final mark in dayMarks)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (mark) {
                          _Mark.plan => c.ink,
                          _Mark.yearly => c.quill,
                          _Mark.bill => null,
                        },
                        border: mark == _Mark.bill
                            ? Border.all(color: c.quill)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A quiet look at one day without leaving the month.
  Future<void> _peek(
    BuildContext context,
    DateTime day,
    List<Occurrence> plans,
    List<Charge> bills,
  ) async {
    HapticFeedback.selectionClick();
    final write = await showLedgerSheet<bool>(
      context,
      scrollControlled: false,
      builder: (context) => _DayPeek(
        day: day,
        plans: plans,
        bills: bills,
        money: money[LedgerDates.dayKey(day)],
      ),
    );
    if (write == true) onAdd(day);
  }
}

/// The peek: one day read out loud — what it holds, what it costs, what the
/// ledger already recorded on it.
class _DayPeek extends StatelessWidget {
  const _DayPeek({
    required this.day,
    required this.plans,
    required this.bills,
    required this.money,
  });

  final DateTime day;
  final List<Occurrence> plans;
  final List<Charge> bills;
  final DayMoney? money;

  static String _time(Event e) {
    final t = e.timeMinutes;
    if (t == null) return 'all day';
    return '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }

  String get _moneyLine {
    final spent = money?.spent ?? 0;
    final earned = money?.earned ?? 0;
    if (spent > 0 && earned > 0) {
      return '${Inr.format(spent)} out · ${Inr.format(earned)} in';
    }
    if (spent > 0) return '${Inr.format(spent)} out';
    if (earned > 0) return '${Inr.format(earned)} in';
    return 'nothing written down here';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final empty = plans.isEmpty && bills.isEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: Gap.x2),
          Text(
            '${LedgerDates.weekdaysFull[day.weekday - 1].toLowerCase()} '
            '${day.day} ${_monthWord(day)}',
            style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            _moneyLine,
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
          ),
          const SizedBox(height: Gap.x4),
          if (empty)
            Text(
              'A blank day. I would leave it that way, but the page is yours.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            )
          else ...[
            for (final (i, p) in plans.indexed)
              LedgerLine(
                leading: _time(p.event),
                title: p.event.title,
                detail: p.event.repeat == EventRepeat.yearly
                    ? 'every year'
                    : null,
                last: i == plans.length - 1 && bills.isEmpty,
              ),
            for (final (i, b) in bills.indexed)
              LedgerLine(
                leading: b.recurring.isBillLike ? 'due' : 'renews',
                title: b.recurring.title,
                amount: Inr.format(b.recurring.amountPaise),
                last: i == bills.length - 1,
              ),
          ],
          const SizedBox(height: Gap.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'write something here',
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 13,
                  color: c.quill,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEventSheet extends ConsumerStatefulWidget {
  const _AddEventSheet({required this.initialDate, this.event});

  final DateTime initialDate;

  /// When set, the sheet opens an existing line for rewriting instead of
  /// adding a new one.
  final Event? event;

  @override
  ConsumerState<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<_AddEventSheet> {
  final _title = TextEditingController();
  late DateTime _date;
  int? _timeMinutes;
  bool _yearly = false;
  bool _saving = false;

  /// The two inline pickers. Both stay shut for the common case — the day
  /// the sheet opened on is nearly always the right one.
  bool _pickingDate = false;
  bool _pickingTime = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    final e = widget.event;
    if (e != null) {
      _title.text = e.title;
      _timeMinutes = e.timeMinutes;
      _yearly = e.repeat == EventRepeat.yearly;
    }
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _setDate(DateTime d) {
    HapticFeedback.selectionClick();
    setState(() {
      _date = DateTime(d.year, d.month, d.day);
      _pickingDate = false;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    final e = widget.event;
    if (e == null) {
      await ref
          .read(eventRepoProvider)
          .create(
            title: title,
            date: _date,
            timeMinutes: _timeMinutes,
            repeat: _yearly ? EventRepeat.yearly : EventRepeat.none,
          );
    } else {
      await _rewriteEvent(
        ref.read(dbProvider),
        e.id,
        title: title,
        date: _date,
        timeMinutes: _timeMinutes,
        repeat: _yearly ? EventRepeat.yearly : EventRepeat.none,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(_date);
  }

  /// The ghost way out: the line leaves the page, the ink stays in the book.
  Future<void> _takeOff() async {
    final e = widget.event;
    if (e == null || _saving) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    await ref.read(eventRepoProvider).archive(e.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String get _dateLabel =>
      '${LedgerDates.weekdays[_date.weekday - 1].toLowerCase()} ${_date.day} '
      '${LedgerDates.months[_date.month - 1].toLowerCase()} ${_date.year}';

  String get _timeLabel {
    final t = _timeMinutes;
    if (t == null) return 'pick a time';
    return '${(t ~/ 60).toString().padLeft(2, '0')}:'
        '${(t % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final canSave = _title.text.trim().isNotEmpty && !_saving;
    final today = _today;
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final grow = Motion.reduced(context) ? Duration.zero : Motion.quick;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x3),
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.rule)),
              ),
              child: TextField(
                controller: _title,
                autofocus: true,
                maxLength: 120,
                style: LedgerType.bodyText.copyWith(color: c.ink),
                decoration: InputDecoration(
                  hintText: "what's happening?",
                  hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  border: InputBorder.none,
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
                ),
              ),
            ),
            const SizedBox(height: Gap.x3),
            // The day, without a dialog: two shortcuts and the book itself.
            Wrap(
              spacing: Gap.x2,
              runSpacing: Gap.x2,
              children: [
                LedgerChip(
                  'to-day',
                  selected: _date == today && !_pickingDate,
                  onTap: () => _setDate(today),
                ),
                LedgerChip(
                  'to-morrow',
                  selected: _date == tomorrow && !_pickingDate,
                  onTap: () => _setDate(tomorrow),
                ),
                LedgerChip(
                  _dateLabel,
                  icon: Icons.event_outlined,
                  selected: _pickingDate,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _pickingDate = !_pickingDate);
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: grow,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: _pickingDate
                  ? _DateGrid(selected: _date, onPick: _setDate)
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: Gap.x3),
            Wrap(
              spacing: Gap.x2,
              runSpacing: Gap.x2,
              children: [
                LedgerChip(
                  'all day',
                  selected: _timeMinutes == null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _timeMinutes = null;
                      _pickingTime = false;
                    });
                  },
                ),
                LedgerChip(
                  _timeLabel,
                  icon: Icons.schedule,
                  selected: _timeMinutes != null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _timeMinutes ??= 9 * 60;
                      _pickingTime = !_pickingTime;
                    });
                  },
                ),
                LedgerChip(
                  'every year',
                  icon: Icons.cake_outlined,
                  selected: _yearly,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _yearly = !_yearly);
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: grow,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: _pickingTime && _timeMinutes != null
                  ? _TimeDial(
                      minutes: _timeMinutes!,
                      onChanged: (m) => setState(() => _timeMinutes = m),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: Gap.x6),
            Pressable(
              onTap: canSave ? _save : null,
              child: AbsorbPointer(
                child: FilledButton(
                  onPressed: canSave ? () {} : null,
                  child: Text(
                    widget.event == null
                        ? 'Put it on the page'
                        : 'Rewrite the line',
                  ),
                ),
              ),
            ),
            if (widget.event != null) ...[
              const SizedBox(height: Gap.x2),
              TextButton(
                onPressed: _saving ? null : _takeOff,
                child: Text(
                  'take it off the page',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.seal,
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

/// The date picker as a page of the same book: a ruled month, mono numerals,
/// the chosen day in the quill. Months turn with the chevrons and slide in
/// from the side they were reached from.
class _DateGrid extends StatefulWidget {
  const _DateGrid({required this.selected, required this.onPick});

  final DateTime selected;
  final ValueChanged<DateTime> onPick;

  @override
  State<_DateGrid> createState() => _DateGridState();
}

class _DateGridState extends State<_DateGrid> {
  late DateTime _month = LedgerDates.monthStart(widget.selected);
  double _dx = 1;
  int _seq = 0;

  void _flip(int dir) {
    HapticFeedback.selectionClick();
    setState(() {
      _dx = dir.toDouble();
      _month = DateTime(_month.year, _month.month + dir);
      _seq++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final reduced = Motion.reduced(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x3),
      child: Column(
        children: [
          Row(
            children: [
              Pressable(
                scale: 0.86,
                haptic: false,
                onTap: () => _flip(-1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child: Icon(Icons.chevron_left, size: 16, color: c.inkFaint),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '${_monthWord(_month)} ${_month.year}',
                    style: LedgerType.label.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ),
              Pressable(
                scale: 0.86,
                haptic: false,
                onTap: () => _flip(1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child: Icon(Icons.chevron_right, size: 16, color: c.inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.x1),
          Row(
            children: [
              for (final d in LedgerDates.weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d[0],
                      style: LedgerType.label.copyWith(
                        fontSize: 9,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(height: 1, color: c.rule),
          AnimatedSize(
            duration: reduced ? Duration.zero : Motion.quick,
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: reduced ? Duration.zero : Motion.quick,
              switchInCurve: Motion.curve,
              switchOutCurve: Motion.curve,
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey('dategrid-$_seq');
                final dx = (incoming ? _dx : -_dx) * 0.06;
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset(dx, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey('dategrid-$_seq'),
                child: _grid(c),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(LedgerColors c) {
    final lead = DateTime(_month.year, _month.month).weekday - 1;
    final total = LedgerDates.daysInMonth(_month);
    final cells = <int?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= total; d++) d,
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      children: [
        for (var w = 0; w < cells.length ~/ 7; w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(child: _cell(c, cells[w * 7 + i], today)),
            ],
          ),
      ],
    );
  }

  Widget _cell(LedgerColors c, int? d, DateTime today) {
    if (d == null) return const SizedBox(height: 34);
    final date = DateTime(_month.year, _month.month, d);
    final chosen = date == widget.selected;
    return Pressable(
      scale: 0.9,
      haptic: false,
      onTap: () => widget.onPick(date),
      child: SizedBox(
        height: 34,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: chosen
                ? BoxDecoration(shape: BoxShape.circle, color: c.quill)
                : null,
            child: Text(
              '$d',
              style: LedgerType.amount.copyWith(
                fontSize: 12,
                color: chosen
                    ? c.paper
                    : date == today
                    ? c.quill
                    : c.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hour, set the way a counter turns: two drums of mono figures between
/// two rules. No dialog, no am/pm — the book keeps 24-hour time.
class _TimeDial extends StatefulWidget {
  const _TimeDial({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  State<_TimeDial> createState() => _TimeDialState();
}

class _TimeDialState extends State<_TimeDial> {
  static const _step = 5;
  static const _extent = 34.0;
  static const _height = 106.0;

  late int _hour = (widget.minutes ~/ 60).clamp(0, 23);
  late int _minute = widget.minutes % 60;

  late final FixedExtentScrollController _hours = FixedExtentScrollController(
    initialItem: _hour,
  );
  late final FixedExtentScrollController _mins = FixedExtentScrollController(
    initialItem: (_minute / _step).round() % (60 ~/ _step),
  );

  @override
  void dispose() {
    _hours.dispose();
    _mins.dispose();
    super.dispose();
  }

  void _emit() {
    HapticFeedback.selectionClick();
    widget.onChanged(_hour * 60 + _minute);
  }

  Widget _drum({
    required FixedExtentScrollController controller,
    required int count,
    required String Function(int) label,
    required bool Function(int) isCurrent,
    required ValueChanged<int> onSelected,
    required LedgerColors c,
  }) {
    return SizedBox(
      width: 58,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _extent,
        diameterRatio: 1.6,
        perspective: 0.004,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onSelected,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, i) => Center(
            child: Text(
              label(i),
              style: LedgerType.amountTotal.copyWith(
                fontSize: 20,
                color: isCurrent(i) ? c.ink : c.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    String two(int v) => v.toString().padLeft(2, '0');

    return SizedBox(
      height: _height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The two rules the chosen figure sits between.
          IgnorePointer(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(height: 1, color: c.rule),
                const SizedBox(height: _extent - 2),
                Container(height: 1, color: c.rule),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _drum(
                controller: _hours,
                count: 24,
                label: two,
                isCurrent: (i) => i == _hour,
                onSelected: (i) {
                  setState(() => _hour = i);
                  _emit();
                },
                c: c,
              ),
              Text(
                ':',
                style: LedgerType.amountTotal.copyWith(
                  fontSize: 20,
                  color: c.inkFaint,
                ),
              ),
              _drum(
                controller: _mins,
                count: 60 ~/ _step,
                label: (i) => two(i * _step),
                isCurrent: (i) => i * _step == _minute,
                onSelected: (i) {
                  setState(() => _minute = i * _step);
                  _emit();
                },
                c: c,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
