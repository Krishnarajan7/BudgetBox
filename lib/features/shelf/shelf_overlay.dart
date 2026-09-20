import 'package:drift/drift.dart' show BooleanExpressionOperators, ComparableExpr;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/alarm_repo.dart';
import '../../data/repos/diet_repo.dart';
import '../../data/repos/txn_repo.dart';
import '../../data/repos/work_repo.dart';
import '../../data/repos/habit_repo.dart';
import '../../data/repos/marks_repo.dart';
import '../alarm/alarm_page.dart';
import '../calendar/calendar_page.dart';
import '../daily/daily_page.dart';
import '../diet/diet_math.dart';
import '../diet/diet_page.dart';
import '../focus/focus_page.dart';
import '../journal/journal_page.dart';
import '../music/music_page.dart';
import '../slate/slate_page.dart';
import '../notes/notes_page.dart';
import '../notices/notices_page.dart';
import '../vault/vault_page.dart';
import '../work/work_math.dart';
import '../work/work_page.dart';

/// Tap the wordmark: the box opens. Every book on one shelf, each spine
/// telling the truth about what's inside it right now.
///
/// The shelf *descends* — the whole panel rides down from above the screen
/// and settles, the way a drawer is pulled open, instead of fading into
/// place while barely moving. Going back up it accelerates away.
Future<void> showShelf(BuildContext context) {
  final scrim = LedgerColors.of(context).ink.withValues(alpha: 0.32);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'shelf',
    barrierColor: scrim,
    transitionDuration: const Duration(milliseconds: 420),
    pageBuilder: (context, a, b) => const _Shelf(),
    transitionBuilder: (context, anim, a, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// What each book would say if you asked it how it's going — one short
/// truthful line per spine, read fresh every time the box opens.
final _shelfStatusProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  final db = ref.watch(dbProvider);
  final now = DateTime.now();

  // Calendar: the next thing coming, or a clear road.
  final events = await (db.select(
    db.events,
  )..where((e) => e.archived.equals(false))).get();
  DateTime? next;
  for (final e in events) {
    var d = DateTime.parse(e.date);
    if (e.repeat == EventRepeat.yearly) {
      d = DateTime(now.year, d.month, d.day);
      if (d.isBefore(DateTime(now.year, now.month, now.day))) {
        d = DateTime(now.year + 1, d.month, d.day);
      }
    }
    if (d.isBefore(DateTime(now.year, now.month, now.day))) continue;
    if (next == null || d.isBefore(next)) next = d;
  }
  // A yearly day just past rolls to next year — and must say so, or
  // "next · 18 Aug" on the 29th reads as a page nobody turned.
  final calendar = next == null
      ? 'clear ahead'
      : (LedgerDates.dayKey(next) == LedgerDates.dayKey(now)
            ? 'something to-day'
            : next.year == now.year
            ? 'next · ${LedgerDates.ddMmm(next)}'
            : "next · ${LedgerDates.ddMmm(next)} '${next.year % 100}");

  // Notes: how many thoughts are held.
  final notes = await (db.select(
    db.notes,
  )..where((n) => n.archived.equals(false))).get();
  final notesLine = notes.isEmpty
      ? 'blank'
      : '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} held';

  // Focus: minutes sat this week.
  final weekStart = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(Duration(days: now.weekday - 1));
  final sessions = await (db.select(
    db.focusSessions,
  )..where((s) => s.completed.equals(true))).get();
  final weekMin = sessions
      .where((s) => !s.startedAt.isBefore(weekStart))
      .fold<int>(0, (a, s) => a + s.minutes);
  final focus = weekMin == 0
      ? 'quiet this week'
      : weekMin >= 60
      ? '${weekMin ~/ 60}h ${weekMin % 60 == 0 ? '' : '${weekMin % 60}m '}this week'
      : '${weekMin}m this week';

  // Journal: is to-day's page written?
  final today = await (db.select(
    db.journalEntries,
  )..where((j) => j.date.equals(LedgerDates.dayKey(now)))).get();
  final pages = await db.select(db.journalEntries).get();
  final journal =
      today.isNotEmpty &&
          (today.first.body.trim().isNotEmpty || today.first.mood != null)
      ? 'written to-day'
      : pages.isEmpty
      ? 'unwritten'
      : '${pages.length} ${pages.length == 1 ? 'page' : 'pages'}';

  // Daily: the clean count leads; the checklist trails.
  final todayKey = LedgerDates.dayKey(now);
  final marks = await (db.select(
    db.dayMarks,
  )..where((m) => m.kind.equals('slip') | m.date.equals(todayKey))).get();
  final sinceRow = await (db.select(
    db.settings,
  )..where((s) => s.key.equals('marksSince'))).getSingleOrNull();
  final String daily;
  if (sinceRow == null) {
    daily = 'unopened';
  } else if (marks.any((m) => m.kind == 'slip' && m.date == todayKey)) {
    daily = 'slipped to-day';
  } else {
    final slipDates = {
      for (final m in marks)
        if (m.kind == 'slip') m.date,
    };
    final live = [
      for (final h in await HabitRepo(db).load())
        if (!h.archived) h,
    ];
    final kept = live
        .where((h) => countOn(marks, todayKey, h.kind) >= h.target)
        .length;
    final clean = cleanStreak(slipDates, sinceRow.value, now);
    daily =
        'day $clean clean${kept > 0 ? ' · $kept of ${live.length} kept' : ''}';
  }

  // Diet: to-day's plate against its line, or the door still shut.
  final dietProfile = await (db.select(
    db.settings,
  )..where((s) => s.key.equals('dietProfile'))).getSingleOrNull();
  final String diet;
  if (dietProfile == null) {
    diet = 'unopened';
  } else {
    final meals = await (db.select(
      db.meals,
    )..where((m) => m.date.equals(todayKey))).get();
    final entries = [for (final m in meals) DietRepo.entryOf(m)];
    final totals = totalsFor(todayKey, entries);
    final kcal = totals.nutrients.kcal.round();
    final missing = missingNow(totals, now);
    diet = kcal == 0 && totals.unmeasured == 0
        ? (missing.isEmpty
              ? 'nothing yet'
              : '${slotName(missing.first)} unwritten')
        : '$kcal kcal so far'
              '${missing.isEmpty ? '' : ' · ${slotName(missing.first)} unwritten'}';
  }

  // Work: what clients owe across open projects, or the door still shut.
  final projects = await db.select(db.projects).get();
  final String work;
  if (projects.isEmpty) {
    work = 'unopened';
  } else {
    final repo = WorkRepo(db, TxnRepo(db));
    final lines = await repo.watchAllLines().first;
    final revs = await db.select(db.quoteRevisions).get();
    var owed = 0;
    var open = 0;
    for (final p in projects) {
      if (p.status != ProjectStatus.active &&
          p.status != ProjectStatus.quoted) {
        continue;
      }
      open++;
      owed += summarise(
        p,
        [
          for (final r in revs)
            if (r.projectId == p.id) r,
        ],
        [
          for (final l in lines)
            if (l.link.projectId == p.id) l,
        ],
        now,
      ).owedPaise;
    }
    work = open == 0
        ? 'nothing open'
        : '$open open · ${owed > 0 ? '${_compact(owed)} owed' : 'all settled'}';
  }

  // Vault: sealed, and how much it guards.
  final vaultCount = (await db.select(db.vaultItems).get()).length;
  final vault = vaultCount == 0 ? 'sealed' : 'sealed · $vaultCount inside';

  // Alarms: the next one to ring, or silence.
  final alarmRows = await db.select(db.alarms).get();
  DateTime? nextAlarm;
  Alarm? nextRow;
  for (final a in alarmRows) {
    final at = nextRing(a, now);
    if (at == null) continue;
    if (nextAlarm == null || at.isBefore(nextAlarm)) {
      nextAlarm = at;
      nextRow = a;
    }
  }
  final alarms = nextRow == null
      ? (alarmRows.isEmpty ? 'none set' : 'all switched off')
      : '${clockLabel(nextRow.minuteOfDay)} · '
            '${untilPhrase(nextAlarm!.difference(now))}';

  // Music: the cached line the room writes on every visit — the shelf
  // never makes a network call of its own.
  final musicRow = await (db.select(
    db.settings,
  )..where((s) => s.key.equals('musicLine'))).getSingleOrNull();
  final music = musicRow?.value ?? 'unheard';

  // Slate: the same cached-line trick — what is out with people, without a
  // network call from the shelf.
  final slateRow = await (db.select(
    db.settings,
  )..where((s) => s.key.equals('slateLine'))).getSingleOrNull();
  final slate = slateRow?.value ?? 'nothing out';

  // Notifications: what was said to-day, and the next thing laid.
  final noticeRows =
      await (db.select(db.notices)..where(
            (n) => n.at.isBiggerOrEqualValue(
              DateTime(now.year, now.month, now.day),
            ),
          ))
          .get();
  final saidToday = noticeRows.where((n) => !n.at.isAfter(now)).length;
  Notice? nextNotice;
  for (final n in noticeRows) {
    if (!n.at.isAfter(now)) continue;
    if (nextNotice == null || n.at.isBefore(nextNotice.at)) nextNotice = n;
  }
  String clock(DateTime t) =>
      '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
  final notices = nextNotice == null
      ? (saidToday == 0 ? 'quiet' : '$saidToday said to-day')
      : '${saidToday == 0 ? '' : '$saidToday to-day · '}next ${clock(nextNotice.at)}';

  return {
    'Alarms': alarms,
    'Calendar': calendar,
    'Notes': notesLine,
    'Focus': focus,
    'Journal': journal,
    'Slate': slate,
    'Music': music,
    'Daily': daily,
    'Diet': diet,
    'Work': work,
    'Notifications': notices,
    'Vault': vault,
  };
});

class _Spine {
  const _Spine(this.name, this.icon, {this.builder});

  final String name;
  final IconData icon;

  /// Null = Money (pop back to it). A builder routes to that book.
  final WidgetBuilder? builder;
}

class _Shelf extends ConsumerWidget {
  const _Shelf();

  static final _spines = <_Spine>[
    const _Spine('Money', Icons.currency_rupee),
    _Spine('Alarms', Icons.alarm, builder: (_) => const AlarmPage()),
    _Spine(
      'Calendar',
      Icons.calendar_today_outlined,
      builder: (_) => const CalendarPage(),
    ),
    _Spine(
      'Notes',
      Icons.sticky_note_2_outlined,
      builder: (_) => const NotesPage(),
    ),
    _Spine('Focus', Icons.timer_outlined, builder: (_) => const FocusPage()),
    _Spine(
      'Journal',
      Icons.menu_book_outlined,
      builder: (_) => const JournalPage(),
    ),
    _Spine(
      'Slate',
      Icons.handshake_outlined,
      builder: (_) => const SlatePage(),
    ),
    _Spine('Music', Icons.graphic_eq, builder: (_) => const MusicPage()),
    _Spine('Daily', Icons.task_alt, builder: (_) => const DailyPage()),
    _Spine('Diet', Icons.restaurant_outlined, builder: (_) => const DietPage()),
    _Spine('Work', Icons.work_outline, builder: (_) => const WorkPage()),
    _Spine(
      'Notifications',
      Icons.notifications_none_outlined,
      builder: (_) => const NoticesPage(),
    ),
    _Spine('Vault', Icons.lock_outline, builder: (_) => const VaultPage()),
  ];

  void _go(BuildContext context, _Spine s) {
    // Close the shelf, then land in the chosen book. Money means "back to
    // the root shell" — pop any open module page beneath the shelf.
    Navigator.of(context).pop();
    if (s.builder != null) {
      Navigator.of(context).push(LedgerRoute<void>(builder: s.builder!));
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final status = ref.watch(_shelfStatusProvider).value;
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: c.paperRaised,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(Corner.sheet + 4),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              Gap.x4,
              Gap.page,
              Gap.x6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'the box',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: Gap.x2),
                // Twelve books is more than a short screen holds at once;
                // the list scrolls inside the drawer rather than pushing
                // the last spines off the bottom.
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (i, s) in _spines.indexed)
                          InkIn(
                            // The rows ink in only after the drawer has landed —
                            // two motions at once read as neither.
                            delay: Duration(milliseconds: 260 + 40 * i),
                            child: Pressable(
                              scale: 0.985,
                              onTap: () => _go(context, s),
                              child: Container(
                                decoration: BoxDecoration(
                                  border: i == _spines.length - 1
                                      ? null
                                      : Border(
                                          bottom: BorderSide(color: c.rule),
                                        ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: Gap.x3,
                                ),
                                child: Row(
                                  children: [
                                    // One simple mark per book — the open one in
                                    // moonlight, the rest in quiet ink.
                                    SizedBox(
                                      width: 26,
                                      child: Icon(
                                        s.icon,
                                        size: 20,
                                        color: s.builder == null
                                            ? c.quill
                                            : c.inkFaint,
                                      ),
                                    ),
                                    const SizedBox(width: Gap.x3),
                                    Text(
                                      s.name,
                                      style: LedgerType.bodyStrong.copyWith(
                                        color: c.ink,
                                      ),
                                    ),
                                    const Spacer(),
                                    AnimatedSwitcher(
                                      duration: Motion.quick,
                                      child: Text(
                                        s.builder == null
                                            ? 'this book'
                                            : status?[s.name] ?? '',
                                        key: ValueKey(status?[s.name] ?? ''),
                                        style: LedgerType.bodyText.copyWith(
                                          fontSize: 12,
                                          color: c.inkFaint,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _compact(int paise) => Inr.compact(paise);
