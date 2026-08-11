import 'dart:convert';

import 'package:drift/drift.dart' hide Column, Table;
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
import '../../data/db.dart';
import '../../data/providers.dart';

/// One stroke of the pen, read back out of the activity table: what was done,
/// to which entry, for how much, and when.
class Stroke {
  const Stroke({
    required this.id,
    required this.action,
    required this.at,
    required this.title,
    required this.amountPaise,
    required this.type,
  });

  final int id;
  final ActivityAction action;
  final DateTime at;
  final String title;
  final int amountPaise;
  final TxnType type;

  bool get isStrike => action == ActivityAction.deleted;
}

/// The past tense of every stroke — short enough for the left column.
String strokeWord(ActivityAction action) => switch (action) {
      ActivityAction.created => 'wrote',
      ActivityAction.edited => 'fixed',
      ActivityAction.deleted => 'struck',
    };

/// Reads one activity row's JSON snapshot back into a [Stroke]. A snapshot
/// this book can't parse is dropped rather than half-drawn.
Stroke? strokeFrom(Activity row) {
  try {
    final s = jsonDecode(row.snapshot) as Map<String, dynamic>;
    final typeIndex = s['type'] as int? ?? 0;
    return Stroke(
      id: row.id,
      action: row.action,
      at: row.at,
      title: (s['title'] as String?)?.trim().isNotEmpty == true
          ? s['title'] as String
          : 'untitled',
      amountPaise: s['amountPaise'] as int? ?? 0,
      type: typeIndex >= 0 && typeIndex < TxnType.values.length
          ? TxnType.values[typeIndex]
          : TxnType.expense,
    );
  } catch (_) {
    return null;
  }
}

/// Groups strokes into day blocks, newest day first, keeping each day's own
/// newest-first order. The page is a book read backwards.
List<(String dayKey, List<Stroke> strokes)> strokesByDay(List<Stroke> all) {
  final out = <(String, List<Stroke>)>[];
  for (final s in all) {
    final key = LedgerDates.dayKey(s.at);
    if (out.isNotEmpty && out.last.$1 == key) {
      out.last.$2.add(s);
    } else {
      out.add((key, [s]));
    }
  }
  return out;
}

/// 'to-day' · 'yesterday' · 'Wed 30 Jul' — the day a block of strokes belongs
/// to, said the way the book says dates.
String strokeDayLabel(String dayKey, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime.parse(dayKey);
  if (dayKey == LedgerDates.dayKey(today)) return 'to-day';
  if (dayKey ==
      LedgerDates.dayKey(today.subtract(const Duration(days: 1)))) {
    return 'yesterday';
  }
  return LedgerDates.dayLabel(day);
}

/// Every stroke the ledger has taken, in reverse. The newest strike is the
/// one the book can still take back.
class ActivityLogPage extends ConsumerStatefulWidget {
  const ActivityLogPage({super.key});

  @override
  ConsumerState<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends ConsumerState<ActivityLogPage> {
  /// Stroke ids already on the page — only genuinely new lines ink in.
  final _seen = <int>{};
  bool _primed = false;
  bool _undoing = false;

  Stream<List<Activity>> _watch() {
    final db = ref.read(dbProvider);
    return (db.select(db.activities)
          ..orderBy([(a) => OrderingTerm.desc(a.at), (a) => OrderingTerm.desc(a.id)])
          ..limit(200))
        .watch();
  }

  Future<void> _bringItBack() async {
    if (_undoing) return;
    setState(() => _undoing = true);
    try {
      final restored = await ref.read(txnRepoProvider).undoLastDelete();
      if (restored != null) HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _undoing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);

    return ModuleScaffold(
      title: 'Activity',
      child: StreamBuilder<List<Activity>>(
        stream: _watch(),
        builder: (context, snapshot) {
          final strokes = [
            for (final row in snapshot.data ?? const <Activity>[])
              ?strokeFrom(row),
          ];

          // Which lines are new to this page — those, and only those, ink in.
          final fresh = <int>{
            if (_primed)
              for (final s in strokes)
                if (!_seen.contains(s.id)) s.id,
          };
          if (snapshot.hasData) {
            _seen
              ..clear()
              ..addAll(strokes.map((s) => s.id));
            _primed = true;
          }

          if (snapshot.hasData && strokes.isEmpty) {
            return const EmptyPage(
              line: 'Nothing to confess. The book is as written.',
              sub: 'Every entry, correction and strike lands here.',
            );
          }

          // Only the newest strike can be walked back — that's what the
          // ledger keeps a snapshot for.
          Stroke? undoable;
          for (final s in strokes) {
            if (s.isStrike) {
              undoable = s;
              break;
            }
          }

          final days = strokesByDay(strokes);
          var index = 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Gap.page, 0, Gap.page, Gap.x8),
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Gap.x2),
                child: Text(
                  'every stroke this book has taken',
                  style:
                      LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
                ),
              ),
              for (final (dayKey, dayStrokes) in days) ...[
                RuleHeader(strokeDayLabel(dayKey)),
                for (final (i, s) in dayStrokes.indexed)
                  InkIn(
                    key: ValueKey(s.id),
                    play: !_primed || fresh.contains(s.id),
                    delay: Duration(milliseconds: 26 * (index++).clamp(0, 12)),
                    child: _StrokeLine(
                      stroke: s,
                      last: i == dayStrokes.length - 1,
                      canUndo: undoable != null && undoable.id == s.id,
                      undoing: _undoing,
                      onUndo: _bringItBack,
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One ruled line of the log: what was done · the entry · the figure · the
/// time. The newest strike carries its own way back.
class _StrokeLine extends StatelessWidget {
  const _StrokeLine({
    required this.stroke,
    required this.last,
    required this.canUndo,
    required this.undoing,
    required this.onUndo,
  });

  final Stroke stroke;
  final bool last;
  final bool canUndo;
  final bool undoing;
  final VoidCallback onUndo;

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final line = LedgerLine(
      leading: strokeWord(stroke.action),
      title: stroke.title,
      detail: '${LedgerDates.ddMmm(stroke.at)} · ${_time(stroke.at)}',
      amount: Inr.format(stroke.amountPaise),
      amountColor: stroke.type == TxnType.income ? c.jama : c.ink,
      struck: stroke.isStrike,
      last: last && !canUndo,
    );
    if (!canUndo) return line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        line,
        Container(
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: c.rule)),
          ),
          padding: const EdgeInsets.only(bottom: Gap.x2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              scale: 0.97,
              onTap: undoing ? null : onUndo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.x1),
                child: Text(
                  undoing ? 'bringing it back…' : 'bring it back',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: undoing ? c.inkFaint : c.quill,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
