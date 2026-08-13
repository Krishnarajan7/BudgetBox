import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/marks_repo.dart';

/// The Daily book: the small truths of a day, kept the way the ledger keeps
/// money. A checklist in plain words (bath, running, push-ups…), the day's
/// food written down as it happens, and the clean count — the one habit
/// tracked by its absence, where an unmarked day is the win.
///
/// Wording rule for this page: no metaphors on interactive things. A person
/// mid-tap should never have to stop and decode.
class DailyPage extends ConsumerStatefulWidget {
  const DailyPage({super.key});

  @override
  ConsumerState<DailyPage> createState() => _DailyPageState();
}

class _DailyPageState extends ConsumerState<DailyPage> {
  final _food = TextEditingController();
  String? _since;

  @override
  void initState() {
    super.initState();
    // Stamps the tracking-start day on first open, then holds it.
    ref.read(marksRepoProvider).slipRecord().then((r) {
      if (mounted) setState(() => _since = r.$2);
    });
  }

  @override
  void dispose() {
    _food.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(marksRepoProvider);
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day - 6);

    return ModuleScaffold(
      title: 'Daily',
      child: StreamBuilder<List<DayMark>>(
        stream: repo.watchSince(weekStart),
        builder: (context, weekSnap) {
          final week = weekSnap.data ?? const <DayMark>[];
          final today = [
            for (final m in week)
              if (m.date == LedgerDates.dayKey(now)) m,
          ];
          return StreamBuilder<List<DayMark>>(
            stream: repo.watchSlips(),
            builder: (context, slipSnap) {
              final slips = {
                for (final s in slipSnap.data ?? const <DayMark>[]) s.date,
              };
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  Gap.page,
                  0,
                  Gap.page,
                  MediaQuery.paddingOf(context).bottom + Gap.x6,
                ),
                children: [
                  const SizedBox(height: Gap.x3),
                  _CleanCount(
                    slips: slips,
                    since: _since,
                    now: now,
                    slippedToday: slips.contains(LedgerDates.dayKey(now)),
                    pledged: today.any((m) => m.kind == 'pledge'),
                    onPledge: () {
                      HapticFeedback.mediumImpact();
                      repo.toggle(now, 'pledge');
                    },
                    onSlip: () => _confirmSlip(context, repo, now),
                    onUndo: () => repo.setSlipped(now, false),
                  ),
                  LedgerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RuleHeader('to-day'),
                        for (final (i, (kind, label)) in habitKinds.indexed)
                          _HabitRow(
                            label: label,
                            done: today.any((m) => m.kind == kind),
                            last: i == habitKinds.length - 1,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              repo.toggle(now, kind);
                            },
                          ),
                      ],
                    ),
                  ),
                  LedgerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RuleHeader('what I ate'),
                        for (final m in today.where((m) => m.kind == 'meal'))
                          LedgerLine(
                            leading:
                                '${m.at.hour.toString().padLeft(2, '0')}:${m.at.minute.toString().padLeft(2, '0')}',
                            title: m.note ?? '',
                            amountWidget: Pressable(
                              onTap: () => repo.removeMark(m.id),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: PenCross(size: 11, color: c.inkFaint),
                              ),
                            ),
                            last: false,
                            key: ValueKey('meal-${m.id}'),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: Gap.x2),
                          child: TextField(
                            controller: _food,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (v) {
                              repo.addMeal(now, v);
                              _food.clear();
                            },
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 14,
                              color: c.ink,
                            ),
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
                  ),
                  LedgerCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RuleHeader('the week'),
                        const SizedBox(height: Gap.x3),
                        _WeekTruth(
                          week: week,
                          slips: slips,
                          since: _since,
                          now: now,
                        ),
                        const SizedBox(height: Gap.x2),
                        Text(
                          'tick = done · cross = missed · clean means no slip',
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 11,
                            color: c.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmSlip(
    BuildContext context,
    MarksRepo repo,
    DateTime now,
  ) async {
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
                'Mark to-day as a slip?',
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'The clean count restarts to-morrow. Writing it down honestly '
                'is the whole point — the record only works if it\'s true.',
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
                child: const Text('No, to-day is clean'),
              ),
            ],
          ),
        );
      },
    );
    if (sure == true) {
      HapticFeedback.mediumImpact();
      await repo.setSlipped(now, true);
    }
  }
}

/// The clean count: days without the habit, counted as wins. The number is
/// the hero because the number is the achievement; the slip affordance is
/// small because it should take intent, never an accident.
class _CleanCount extends StatelessWidget {
  const _CleanCount({
    required this.slips,
    required this.since,
    required this.now,
    required this.slippedToday,
    required this.pledged,
    required this.onPledge,
    required this.onSlip,
    required this.onUndo,
  });

  final Set<String> slips;
  final String? since;
  final DateTime now;
  final bool slippedToday;

  /// The morning beat: a pledge taken at the start of the day, answered at
  /// once with one line back — a commitment with a reward, not a checkbox.
  /// (The evening beat is the week table and the honest slip flow.)
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
    final streak = cleanStreak(slips, s, now);
    final best = bestCleanRun(slips, s, now);

    if (slippedToday) {
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
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(height: Gap.x2),
          Pressable(
            onTap: onUndo,
            child: Text(
              'marked by mistake? tap to undo',
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 12,
                color: c.quill,
              ),
            ),
          ),
        ],
      );
    }

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
          'a clean day is a day you didn\'t give in — nothing to tap, '
          'just keep going',
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
                      'pledged — ${_lines[now.day % _lines.length]}',
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
                      borderRadius: BorderRadius.circular(Corner.chip),
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
}

/// One habit line: plain word left, a tick box right. The box is the same
/// square the catch-up sheet stamps — one visual language for "done".
class _HabitRow extends StatelessWidget {
  const _HabitRow({
    required this.label,
    required this.done,
    required this.last,
    required this.onTap,
  });

  final String label;
  final bool done;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      haptic: false,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: LedgerType.bodyText.copyWith(
                  color: done ? c.inkFaint : c.ink,
                ),
              ),
            ),
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
              child: done
                  ? Center(child: PenTick(size: 15, color: c.jama))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Seven days, three truths: clean, bath, exercise. Ticks and crosses only
/// for days the book was actually watching — nothing is claimed about the
/// time before tracking began.
class _WeekTruth extends StatelessWidget {
  const _WeekTruth({
    required this.week,
    required this.slips,
    required this.since,
    required this.now,
  });

  final List<DayMark> week;
  final Set<String> slips;
  final String? since;
  final DateTime now;

  static const _exercise = {'run', 'push', 'pull', 'squat'};

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final start = since == null ? null : DateTime.parse(since!);
    final days = [
      for (var i = 6; i >= 0; i--) DateTime(now.year, now.month, now.day - i),
    ];
    final byDay = <String, Set<String>>{};
    for (final m in week) {
      byDay.putIfAbsent(m.date, () => {}).add(m.kind);
    }

    Widget mark(
      DateTime d,
      bool Function(Set<String> kinds) done, {
      bool absence = false,
    }) {
      final key = LedgerDates.dayKey(d);
      final tracked = start != null && !d.isBefore(start);
      if (!tracked) {
        return Text(
          '·',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.rule),
        );
      }
      final kinds = byDay[key] ?? const <String>{};
      final isToday = d.day == now.day && d.month == now.month;
      final ok = absence ? !slips.contains(key) : done(kinds);
      if (ok && absence && isToday) {
        // To-day's clean mark is provisional — faint until the day ends.
        return PenTick(size: 12, color: c.jama.withValues(alpha: 0.45));
      }
      if (ok) return PenTick(size: 12, color: c.jama);
      if (isToday && !absence) {
        // Not done *yet* — the day is still open, no verdict.
        return Text(
          '·',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
        );
      }
      return PenCross(size: 10, color: c.inkFaint.withValues(alpha: 0.55));
    }

    TableRow row(String label, Widget Function(DateTime d) cell) => TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(
            label,
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ),
        for (final d in days)
          Center(
            child: SizedBox(height: 16, child: Center(child: cell(d))),
          ),
      ],
    );

    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Table(
      columnWidths: const {0: FixedColumnWidth(64)},
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            for (final d in days)
              Center(
                child: Text(
                  initials[d.weekday - 1],
                  style: LedgerType.label.copyWith(
                    fontSize: 9,
                    color: d.day == now.day ? c.ink : c.inkFaint,
                  ),
                ),
              ),
          ],
        ),
        row('clean', (d) => mark(d, (_) => true, absence: true)),
        row('bath', (d) => mark(d, (k) => k.contains('bath'))),
        row(
          'exercise',
          (d) => mark(d, (k) => k.intersection(_exercise).isNotEmpty),
        ),
      ],
    );
  }
}
