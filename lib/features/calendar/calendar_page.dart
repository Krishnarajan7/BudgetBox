import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/db.dart';
import '../../data/repos/event_repo.dart';

const _daysCaps = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const _daysShort = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const _monthsFull = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];
const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The Calendar book as a running agenda: an ink spine down the left edge
/// carries the days (to-day inverted onto paper) and the month written
/// sideways; the page beside it holds each day's plans as tick-barred
/// lines. Birthdays repeat yearly and wear the seal's vermilion.
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  final Set<int> _leaving = {};

  static const _spineWidth = 60.0;
  static const _horizon = 60;

  /// The day the agenda starts from — the week strip's business.
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
  }

  void _select(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() => _selected = day);
  }

  void _shiftWeek(int dir) {
    HapticFeedback.selectionClick();
    setState(() => _selected = _selected.add(Duration(days: 7 * dir)));
  }

  Future<void> _archive(Event e) async {
    HapticFeedback.mediumImpact();
    setState(() => _leaving.add(e.id));
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;
    await ref.read(eventRepoProvider).archive(e.id);
    _leaving.remove(e.id);
  }

  Future<void> _openAddSheet() async {
    HapticFeedback.lightImpact();
    final saved = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddEventSheet(initialDate: _selected),
    );
    if (saved != null && mounted) _select(saved);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(eventRepoProvider);

    return ModuleScaffold(
      title: 'Calendar',
      fab: GestureDetector(
        onTap: _openAddSheet,
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
          final events = snap.data ?? const [];
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final occ = EventRepo.upcoming(events, _selected,
              days: _horizon, limit: 400);

          // Group occurrences by day; the chosen day always gets a page.
          final byDay = <String, List<({Event event, DateTime on})>>{
            LedgerDates.dayKey(_selected): [],
          };
          for (final o in occ) {
            byDay.putIfAbsent(LedgerDates.dayKey(o.on), () => []).add(o);
          }
          final days = byDay.keys.map(DateTime.parse).toList()..sort();

          final rows = <Widget>[];
          int? shownMonth;
          var zebra = false;
          for (final day in days) {
            if (day.month != shownMonth) {
              shownMonth = day.month;
              rows.add(_MonthMarker(day: day));
            }
            rows.add(_DayGroup(
              day: day,
              isToday: day == today,
              zebra: zebra,
              occurrences: byDay[LedgerDates.dayKey(day)]!,
              leaving: _leaving,
              onArchive: _archive,
            ));
            zebra = !zebra;
          }
          rows.add(_SpineTail(
            child: occ.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        Gap.x4, Gap.x4, Gap.page, Gap.x6),
                    child: Text(
                      'The next $_horizon days are clear. The plus below '
                      'can change that.',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 13, color: c.inkFaint),
                    ),
                  )
                : const SizedBox(height: Gap.x12),
          ));

          return Column(
            children: [
              _WeekStrip(
                selected: _selected,
                today: today,
                onSelect: _select,
                onShiftWeek: _shiftWeek,
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: rows,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The week under the day's name: letters over mono numbers, the chosen day
/// in a quill circle, chevrons sliding the week.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onShiftWeek,
  });

  final DateTime selected;
  final DateTime today;
  final ValueChanged<DateTime> onSelect;
  final ValueChanged<int> onShiftWeek;

  static const _dayNames = [
    'monday', 'tuesday', 'wednesday', 'thursday',
    'friday', 'saturday', 'sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final monday =
        selected.subtract(Duration(days: selected.weekday - 1));
    final week = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];
    final isToday = selected == today;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.x2, Gap.x3, Gap.x2, Gap.x3),
      child: Column(
        children: [
          InkWell(
            // The day's name is the way home.
            onTap: isToday ? null : () => onSelect(today),
            child: Column(
              children: [
                Text(
                  _dayNames[selected.weekday - 1],
                  style: LedgerType.title.copyWith(fontSize: 24, color: c.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '${selected.day} ${_monthsFull[selected.month - 1]} '
                  '${selected.year}'
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
              InkResponse(
                radius: 18,
                onTap: () => onShiftWeek(-1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child:
                      Icon(Icons.chevron_left, size: 18, color: c.inkFaint),
                ),
              ),
              for (final day in week)
                Expanded(child: _WeekDay(
                  day: day,
                  selected: day == selected,
                  isToday: day == today,
                  onTap: () => onSelect(day),
                )),
              InkResponse(
                radius: 18,
                onTap: () => onShiftWeek(1),
                child: Padding(
                  padding: const EdgeInsets.all(Gap.x1),
                  child:
                      Icon(Icons.chevron_right, size: 18, color: c.inkFaint),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Corner.key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.x1),
        child: Column(
          children: [
            Text(
              _daysCaps[day.weekday - 1][0],
              style: LedgerType.label.copyWith(
                fontSize: 10,
                color: selected ? c.quill : c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x1),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.quill : Colors.transparent,
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
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                '${_monthsFull[day.month - 1]} ${day.year}',
                style: LedgerType.label.copyWith(
                  fontSize: 11,
                  letterSpacing: 2.5,
                  color: c.paper.withValues(alpha: 0.75),
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

/// One day: its spine cell and its page of plans.
class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.isToday,
    required this.zebra,
    required this.occurrences,
    required this.leaving,
    required this.onArchive,
  });

  final DateTime day;
  final bool isToday;
  final bool zebra;
  final List<({Event event, DateTime on})> occurrences;
  final Set<int> leaving;
  final Future<void> Function(Event) onArchive;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
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
              color: zebra
                  ? c.paperRaised.withValues(alpha: 0.6)
                  : Colors.transparent,
              padding: const EdgeInsets.fromLTRB(
                  Gap.x4, Gap.x3, Gap.page, Gap.x3),
              child: occurrences.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nothing on this page.',
                        style: LedgerType.bodyText
                            .copyWith(fontSize: 12, color: c.inkFaint),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final o in occurrences)
                          _EventLine(
                            occurrence: o,
                            leaving: leaving.contains(o.event.id),
                            onArchive: () => onArchive(o.event),
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
          _daysCaps[day.weekday - 1],
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

/// One plan: a small tick of ink, the words, the hour underneath.
class _EventLine extends StatelessWidget {
  const _EventLine({
    required this.occurrence,
    required this.leaving,
    required this.onArchive,
  });

  final ({Event event, DateTime on}) occurrence;
  final bool leaving;
  final VoidCallback onArchive;

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
    final tick = yearly
        ? c.seal
        : e.timeMinutes != null
            ? c.quill
            : c.inkFaint;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: leaving ? 0 : 1,
      child: InkWell(
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
                      style: LedgerType.bodyStrong
                          .copyWith(fontSize: 14, color: c.ink),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      yearly ? '$_timeLabel · every year' : _timeLabel,
                      style: LedgerType.amount
                          .copyWith(fontSize: 11, color: c.inkFaint),
                    ),
                  ],
                ),
              ),
              if (yearly)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child:
                      Icon(Icons.cake_outlined, size: 14, color: c.inkFaint),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

class _AddEventSheet extends ConsumerStatefulWidget {
  const _AddEventSheet({required this.initialDate});

  final DateTime initialDate;

  @override
  ConsumerState<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<_AddEventSheet> {
  final _title = TextEditingController();
  late DateTime _date;
  int? _timeMinutes;
  bool _yearly = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(
          () => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _pickTime() async {
    final t = _timeMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: t == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: t ~/ 60, minute: t % 60),
    );
    if (picked != null && mounted) {
      setState(() => _timeMinutes = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    await ref.read(eventRepoProvider).create(
          title: title,
          date: _date,
          timeMinutes: _timeMinutes,
          repeat: _yearly ? EventRepeat.yearly : EventRepeat.none,
        );
    if (!mounted) return;
    Navigator.of(context).pop(_date);
  }

  String get _dateLabel =>
      '${_daysShort[_date.weekday - 1]} ${_date.day} '
      '${_monthsShort[_date.month - 1].toLowerCase()} ${_date.year}';

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

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.rule,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: Gap.x4),
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
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: Gap.x2),
                ),
              ),
            ),
            const SizedBox(height: Gap.x3),
            InkWell(
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.x1),
                child: Row(
                  children: [
                    Icon(Icons.event_outlined, size: 14, color: c.inkFaint),
                    const SizedBox(width: Gap.x2),
                    Text(
                      _dateLabel,
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 13, color: c.ink),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.expand_more, size: 13, color: c.inkFaint),
                  ],
                ),
              ),
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
                    setState(() => _timeMinutes = null);
                  },
                ),
                LedgerChip(
                  _timeLabel,
                  icon: Icons.schedule,
                  selected: _timeMinutes != null,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _pickTime();
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
            const SizedBox(height: Gap.x6),
            FilledButton(
              onPressed: canSave ? _save : null,
              child: const Text('Put it on the page'),
            ),
          ],
        ),
      ),
    );
  }
}
