import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../calendar/calendar_page.dart';
import '../focus/focus_page.dart';
import '../journal/journal_page.dart';
import '../notes/notes_page.dart';
import '../vault/vault_page.dart';

/// Tap the wordmark: the box opens. Six books on one shelf, each spine
/// telling the truth about what's inside it right now.
Future<void> showShelf(BuildContext context) {
  final scrim = LedgerColors.of(context).ink.withValues(alpha: 0.32);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'shelf',
    barrierColor: scrim,
    transitionDuration: Motion.spring,
    pageBuilder: (context, a, b) => const _Shelf(),
    transitionBuilder: (context, anim, a, child) {
      final curved = CurvedAnimation(parent: anim, curve: Motion.curve);
      return SlideTransition(
        position: Tween(begin: const Offset(0, -0.06), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// What each book would say if you asked it how it's going — one short
/// truthful line per spine, read fresh every time the box opens.
final _shelfStatusProvider = FutureProvider.autoDispose<Map<String, String>>(
  (ref) async {
    final db = ref.watch(dbProvider);
    final now = DateTime.now();

    // Calendar: the next thing coming, or a clear road.
    final events = await (db.select(db.events)
          ..where((e) => e.archived.equals(false)))
        .get();
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
    final calendar = next == null
        ? 'clear ahead'
        : (LedgerDates.dayKey(next) == LedgerDates.dayKey(now)
            ? 'something to-day'
            : 'next · ${LedgerDates.ddMmm(next)}');

    // Notes: how many thoughts are held.
    final notes = await (db.select(db.notes)
          ..where((n) => n.archived.equals(false)))
        .get();
    final notesLine = notes.isEmpty
        ? 'blank'
        : '${notes.length} ${notes.length == 1 ? 'note' : 'notes'} held';

    // Focus: minutes sat this week.
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final sessions = await (db.select(db.focusSessions)
          ..where((s) => s.completed.equals(true)))
        .get();
    final weekMin = sessions
        .where((s) => !s.startedAt.isBefore(weekStart))
        .fold<int>(0, (a, s) => a + s.minutes);
    final focus = weekMin == 0
        ? 'quiet this week'
        : weekMin >= 60
            ? '${weekMin ~/ 60}h ${weekMin % 60 == 0 ? '' : '${weekMin % 60}m '}this week'
            : '${weekMin}m this week';

    // Journal: is to-day's page written?
    final today = await (db.select(db.journalEntries)
          ..where((j) => j.date.equals(LedgerDates.dayKey(now))))
        .get();
    final pages = await db.select(db.journalEntries).get();
    final journal = today.isNotEmpty &&
            (today.first.body.trim().isNotEmpty || today.first.mood != null)
        ? 'written to-day'
        : pages.isEmpty
            ? 'unwritten'
            : '${pages.length} ${pages.length == 1 ? 'page' : 'pages'}';

    // Vault: sealed, and how much it guards.
    final vaultCount =
        (await db.select(db.vaultItems).get()).length;
    final vault = vaultCount == 0
        ? 'sealed'
        : 'sealed · $vaultCount inside';

    return {
      'Calendar': calendar,
      'Notes': notesLine,
      'Focus': focus,
      'Journal': journal,
      'Vault': vault,
    };
  },
);

class _Spine {
  const _Spine(this.name, {this.builder, this.subIcon, this.thickness = 30});

  final String name;

  /// Null = Money (pop back to it). A builder routes to that book.
  final WidgetBuilder? builder;
  final IconData? subIcon;

  /// The spine's height — the daily book is the fattest on the shelf.
  final double thickness;
}

class _Shelf extends ConsumerWidget {
  const _Shelf();

  static final _spines = <_Spine>[
    const _Spine('Money', thickness: 38),
    _Spine('Calendar', builder: (_) => const CalendarPage()),
    _Spine('Notes', builder: (_) => const NotesPage()),
    _Spine('Focus', builder: (_) => const FocusPage()),
    _Spine('Journal', builder: (_) => const JournalPage(), thickness: 34),
    _Spine('Vault',
        subIcon: Icons.lock_outline,
        builder: (_) => const VaultPage(),
        thickness: 26),
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
            bottom: Radius.circular(Corner.sheet + 4)),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('the box',
                    style: LedgerType.label.copyWith(color: c.inkFaint)),
                const SizedBox(height: Gap.x2),
                for (final (i, s) in _spines.indexed)
                  InkIn(
                    delay: Duration(milliseconds: 36 * i),
                    child: Pressable(
                      scale: 0.985,
                      onTap: () => _go(context, s),
                      child: Container(
                        decoration: BoxDecoration(
                          border: i == _spines.length - 1
                              ? null
                              : Border(bottom: BorderSide(color: c.rule)),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                        child: Row(
                          children: [
                            // The spine itself: ink for a bound book, an
                            // outlined sleeve for the sealed one.
                            Container(
                              width: 16,
                              height: s.thickness,
                              decoration: BoxDecoration(
                                color: s.subIcon == null ? c.ink : null,
                                border: s.subIcon == null
                                    ? null
                                    : Border.all(color: c.inkFaint, width: 1.4),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              alignment: Alignment.center,
                              child: s.name == 'Money'
                                  ? Container(
                                      width: 16,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: c.quill,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: Gap.x3),
                            Text(
                              s.name,
                              style:
                                  LedgerType.bodyStrong.copyWith(color: c.ink),
                            ),
                            const Spacer(),
                            if (s.subIcon != null) ...[
                              Icon(s.subIcon, size: 12, color: c.inkFaint),
                              const SizedBox(width: 4),
                            ],
                            AnimatedSwitcher(
                              duration: Motion.quick,
                              child: Text(
                                s.builder == null
                                    ? 'this book'
                                    : status?[s.name] ?? '',
                                key: ValueKey(status?[s.name] ?? ''),
                                style: LedgerType.bodyText.copyWith(
                                    fontSize: 12, color: c.inkFaint),
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
      ),
    );
  }
}
