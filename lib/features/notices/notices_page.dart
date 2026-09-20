import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/notifications.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/plates.dart';
import '../../data/db.dart';
import '../../data/repos/notice_repo.dart';
import '../alarm/alarm_page.dart';
import '../calendar/calendar_page.dart';
import '../diet/diet_page.dart';
import '../focus/focus_page.dart';
import '../journal/journal_page.dart';
import '../notes/notes_page.dart';
import '../today/widgets/ledger_rows.dart';
import '../weather/weather_page.dart';
import '../work/work_page.dart';

/// Every book's voice, read back in one place.
///
/// What is coming in the next day sits at the top, then each day's lines
/// newest first — the diet book's nine o'clock next to the ledger's
/// nine-thirty next to the sky's warning — so "did it tell me?" has one
/// page to answer it. A row opens the book that spoke.
class NoticesPage extends ConsumerStatefulWidget {
  const NoticesPage({super.key});

  @override
  ConsumerState<NoticesPage> createState() => _NoticesPageState();
}

/// The books, in the order the chips show them. The key is the module
/// written on each notice by `LedgerReminders.moduleFor`.
const _books = <(String key, String name, IconData icon)>[
  ('money', 'money', Icons.currency_rupee),
  ('diet', 'diet', Icons.restaurant_outlined),
  ('sky', 'sky', Icons.umbrella_outlined),
  ('felt', 'felt', Icons.menu_book_outlined),
  ('alarm', 'alarms', Icons.alarm),
  ('notes', 'notes', Icons.sticky_note_2_outlined),
  ('calendar', 'calendar', Icons.calendar_today_outlined),
  ('focus', 'focus', Icons.timer_outlined),
  ('work', 'work', Icons.work_outline),
];

(String, IconData) bookOf(String module) {
  for (final b in _books) {
    if (b.$1 == module) return (b.$2, b.$3);
  }
  return (module, Icons.notifications_none_outlined);
}

/// The page a notice's book opens on. Money's reminders live on the
/// shell itself, so they pop back to it.
WidgetBuilder? _pageFor(String module) => switch (module) {
  'diet' => (_) => const DietPage(),
  'sky' => (_) => const WeatherPage(),
  'felt' => (_) => const JournalPage(),
  'alarm' => (_) => const AlarmPage(),
  'notes' => (_) => const NotesPage(),
  'calendar' => (_) => const CalendarPage(),
  'focus' => (_) => const FocusPage(),
  'work' => (_) => const WorkPage(),
  _ => null,
};

class _NoticesPageState extends ConsumerState<NoticesPage> {
  String? _only;

  @override
  void initState() {
    super.initState();
    // Opening the page is the moment to ask the phone what became of the
    // lines since the app was last forward.
    unawaited(LedgerReminders.reconcile());
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(noticeRepoProvider);
    return ModuleScaffold(
      title: 'Notifications',
      child: StreamBuilder<List<Notice>>(
        stream: repo.watch(),
        builder: (context, snap) {
          final all = snap.data ?? const <Notice>[];
          if (snap.hasData && all.isEmpty) {
            return const EmptyPage(
              line: 'Nothing said yet.',
              sub:
                  'Every reminder any book lays down — the evening line, a '
                  'sitting missed, rain on the way, an alarm — is written '
                  'here as it is scheduled, said, or opened.',
            );
          }
          return _body(context, c, all);
        },
      ),
    );
  }

  Widget _body(BuildContext context, LedgerColors c, List<Notice> all) {
    final now = DateTime.now();
    final present = {for (final n in all) n.module};
    final books = [
      for (final b in _books)
        if (present.contains(b.$1)) b,
    ];
    final rows = _only == null
        ? all
        : [
            for (final n in all)
              if (n.module == _only) n,
          ];
    final soon = now.add(const Duration(days: 1));
    final coming = [
      for (final n in rows)
        if (n.at.isAfter(now)) n,
    ]..sort((a, b) => a.at.compareTo(b.at));
    final next = [
      for (final n in coming)
        if (!n.at.isAfter(soon)) n,
    ];
    final later = coming.length - next.length;
    final said = [
      for (final n in rows)
        if (!n.at.isAfter(now)) n,
    ];
    final todayKey = LedgerDates.dayKey(now);
    final yesterdayKey = LedgerDates.dayKey(
      now.subtract(const Duration(days: 1)),
    );
    final saidToday = said.where((n) => LedgerDates.dayKey(n.at) == todayKey);
    final opened = said.where((n) => n.openedAt != null).length;
    final stuck = said.where((n) => n.fate == 'stuck').length;

    // Days, newest first, each holding its lines newest first.
    final days = <String, List<Notice>>{};
    for (final n in said) {
      days.putIfAbsent(LedgerDates.dayKey(n.at), () => []).add(n);
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        Gap.x3,
        Gap.page,
        MediaQuery.paddingOf(context).bottom + Gap.x8,
      ),
      children: [
        StatTiles(
          tiles: [
            StatTile(
              label: 'said to-day',
              value: '${saidToday.length}',
              tone: saidToday.isEmpty ? c.inkFaint : c.ink,
              sub: saidToday.isEmpty
                  ? 'quiet so far'
                  : '${saidToday.where((n) => n.openedAt != null).length} opened',
            ),
            StatTile(
              label: 'next',
              value: coming.isEmpty ? '—' : _clock(coming.first.at),
              tone: coming.isEmpty ? c.inkFaint : c.ink,
              sub: coming.isEmpty
                  ? 'nothing laid'
                  : '${bookOf(coming.first.module).$1} · ${_when(coming.first.at, now)}',
            ),
            StatTile(
              label: 'opened',
              value: said.isEmpty
                  ? '—'
                  : '${(opened / said.length * 100).round()}%',
              tone: c.inkFaint,
              sub: 'of the last ${said.length}',
            ),
          ],
        ),
        if (stuck > 0)
          Padding(
            padding: const EdgeInsets.only(top: Gap.x3),
            child: Text(
              '$stuck ${stuck == 1 ? 'line is' : 'lines are'} past ${stuck == 1 ? 'its' : 'their'} hour and still '
              'waiting on the phone — battery saving or a muted channel usually holds them back.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12.5,
                height: 1.4,
                color: c.warn,
              ),
            ),
          ),
        if (books.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: Gap.x3),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip(
                    key: const ValueKey('notice-chip-all'),
                    label: 'all',
                    on: _only == null,
                    onTap: () => setState(() => _only = null),
                  ),
                  for (final b in books)
                    _Chip(
                      key: ValueKey('notice-chip-${b.$1}'),
                      label: b.$2,
                      icon: b.$3,
                      on: _only == b.$1,
                      onTap: () =>
                          setState(() => _only = _only == b.$1 ? null : b.$1),
                    ),
                ],
              ),
            ),
          ),
        if (next.isNotEmpty || later > 0) ...[
          const SectionHead('coming up'),
          if (next.isNotEmpty)
            Plate(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, n) in next.indexed)
                    _NoticeRow(
                      key: ValueKey('notice-${n.id}'),
                      notice: n,
                      now: now,
                      last: i == next.length - 1,
                      onTap: _open(context, n),
                    ),
                ],
              ),
            ),
          if (later > 0)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Text(
                next.isEmpty
                    ? 'nothing in the next day · $later laid further out'
                    : 'and $later more laid further out',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12.5,
                  color: c.inkFaint,
                ),
              ),
            ),
        ],
        for (final MapEntry(key: day, value: lines) in days.entries) ...[
          SectionHead(
            day == todayKey
                ? 'to-day'
                : day == yesterdayKey
                ? 'yesterday'
                : LedgerDates.dayLabel(lines.first.at).toLowerCase(),
          ),
          Plate(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, n) in lines.indexed)
                  _NoticeRow(
                    key: ValueKey('notice-${n.id}'),
                    notice: n,
                    now: now,
                    last: i == lines.length - 1,
                    onTap: _open(context, n),
                  ),
              ],
            ),
          ),
        ],
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gap.x4),
            child: Text(
              'nothing from this book in the last month.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          ),
      ],
    );
  }

  VoidCallback _open(BuildContext context, Notice n) {
    final page = _pageFor(n.module);
    if (page == null) {
      return () => Navigator.of(context).popUntil((r) => r.isFirst);
    }
    return () => Navigator.of(context).push(LedgerRoute<void>(builder: page));
  }
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
}

/// 'in 40 min', 'to-night', 'to-morrow', '23 Sep'.
String _when(DateTime at, DateTime now) {
  final diff = at.difference(now);
  if (diff.inMinutes < 60 && !diff.isNegative) {
    return 'in ${diff.inMinutes} min';
  }
  final today = LedgerDates.dayKey(now);
  if (LedgerDates.dayKey(at) == today) {
    return at.hour >= 18 ? 'to-night' : 'to-day';
  }
  if (LedgerDates.dayKey(at) ==
      LedgerDates.dayKey(now.add(const Duration(days: 1)))) {
    return 'to-morrow';
  }
  return LedgerDates.ddMmm(at);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    super.key,
    required this.notice,
    required this.now,
    required this.last,
    required this.onTap,
  });

  final Notice notice;
  final DateTime now;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final n = notice;
    final (name, icon) = bookOf(n.module);
    final future = n.at.isAfter(now);
    final tag = n.repeat == 'weekly'
        ? 'every ${_weekdays[n.at.weekday - 1]}'
        : n.openedAt != null
        ? 'opened'
        : switch (n.fate) {
            'shown' => 'shown',
            'said' => 'said',
            'stuck' => 'still waiting',
            _ => null,
          };
    final body = Padding(
      padding: EdgeInsets.only(top: 8, bottom: last ? 4 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Medallion(
            icon: icon,
            ink: future ? c.quill : c.inkFaint,
            size: 34,
            iconSize: 16,
          ),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: c.ink,
                  ),
                ),
                if (n.body.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      n.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12.5,
                        height: 1.35,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    tag == null ? name : '$name · $tag',
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _clock(n.at),
                style: LedgerType.amount.copyWith(
                  fontSize: 13,
                  color: future ? c.ink : c.inkFaint,
                ),
              ),
              if (future)
                Text(
                  _when(n.at, now),
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
            ],
          ),
        ],
      ),
    );
    final row = Pressable(
      scale: 0.99,
      haptic: false,
      onTap: onTap,
      child: body,
    );
    if (last) return row;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: row,
    );
  }
}

/// A filter chip in the book's hand: ink on paper when off, paper on ink
/// when on — no third colour.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: Gap.x2),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? c.ink : c.paperRaised,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: on ? c.paper : c.inkFaint),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 12.5,
                  color: on ? c.paper : c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
