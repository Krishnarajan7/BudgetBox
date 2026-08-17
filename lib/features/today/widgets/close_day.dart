import 'dart:async' show unawaited;

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/inr.dart';
import '../../../core/tokens.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/pen_marks.dart';
import '../../../core/widgets/seal.dart';
import '../../../data/db.dart';
import '../../../data/providers.dart';
import 'ledger_rows.dart';

/// Small counts in the book's hand: 'three', not '3' — kept only for the
/// streak whisper, the one place the page still speaks softly.
String _spelled(int n) {
  const words = [
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
  ];
  return (n >= 2 && n <= 12) ? words[n - 2] : '$n';
}

/// The day ruled off — the page's signature moment, given the full motion
/// budget everything else on the screen gave up. One tap and the vermilion
/// rule draws across under today's entries, the day's total settles into
/// the amount column, and the seal presses down with its haptic. Reopened
/// later, the closed day renders already ruled: the ritual happened once.
class CloseDayRitual extends ConsumerStatefulWidget {
  const CloseDayRitual({
    super.key,
    required this.name,
    required this.dayTotalPaise,
  });

  final String name;
  final int dayTotalPaise;

  @override
  ConsumerState<CloseDayRitual> createState() => _CloseDayRitualState();
}

class _CloseDayRitualState extends ConsumerState<CloseDayRitual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;

  bool _ritual = false;
  bool _stampPhase = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  void _begin() {
    if (_ritual) return;
    // The tap's selection click came from Pressable; the medium impact
    // belongs to the stamp and fires inside StampIn when it lands.
    setState(() => _ritual = true);
    if (Motion.reduced(context)) {
      _ac.value = 1;
      setState(() => _stampPhase = true);
    } else {
      _ac.forward().whenComplete(() {
        if (mounted) setState(() => _stampPhase = true);
      });
    }
  }

  Future<void> _sealInDb() async {
    final db = ref.read(dbProvider);
    await db
        .into(db.daySeals)
        .insert(
          DaySealsCompanion(date: Value(LedgerDates.dayKey(DateTime.now()))),
          mode: InsertMode.insertOrIgnore,
        );
    if (!mounted) return;
    // A sealed day needs no evening nudge — the ritual already happened.
    unawaited(ref.read(nudgesProvider).resync());
  }

  /// Consecutive sealed days ending today (if sealed) or yesterday.
  static int _streak(Set<String> dates, DateTime now) {
    var day = DateTime(now.year, now.month, now.day);
    if (!dates.contains(LedgerDates.dayKey(day))) {
      day = DateTime(day.year, day.month, day.day - 1);
    }
    var n = 0;
    while (dates.contains(LedgerDates.dayKey(day))) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  String get _closedLine =>
      'day closed · ${DateTime.now().hour >= 17 ? 'good night' : 'the rest of it is yours'}, ${widget.name}';

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final db = ref.watch(dbProvider);
    final key = LedgerDates.dayKey(DateTime.now());

    return StreamBuilder<List<DaySeal>>(
      stream: db.select(db.daySeals).watch(),
      builder: (context, snapshot) {
        final dates = {
          for (final s in snapshot.data ?? const <DaySeal>[]) s.date,
        };
        final sealed = dates.contains(key);
        final streak = _streak(dates, DateTime.now());
        final whisper = streak >= 2
            ? Padding(
                padding: const EdgeInsets.only(top: Gap.x2),
                child: Text(
                  '${_spelled(streak)} evenings in a row',
                  textAlign: TextAlign.center,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 11,
                    color: c.inkFaint,
                  ),
                ),
              )
            : null;

        if (_ritual) return _running(c, whisper);
        if (sealed) return _closed(c, whisper);
        return _open(c, whisper);
      },
    );
  }

  /// The pill, before anything happened.
  Widget _open(LedgerColors c, Widget? whisper) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x4),
      child: Column(
        children: [
          Pressable(
            onTap: _begin,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.x4,
                vertical: Gap.x2,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: c.rule, width: 1),
                borderRadius: BorderRadius.circular(Corner.chip),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The chop before it lands — the mark this tap will make.
                  SealOutline(size: 15, color: c.inkFaint),
                  const SizedBox(width: Gap.x2),
                  Text(
                    'close the day',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ?whisper,
        ],
      ),
    );
  }

  /// The ritual mid-flight: rule draws, total settles, stamp lands.
  Widget _running(LedgerColors c, Widget? whisper) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x4),
      child: AnimatedBuilder(
        animation: _ac,
        builder: (context, _) {
          final ruleT = const Interval(
            0,
            0.55,
            curve: Curves.easeOutCubic,
          ).transform(_ac.value);
          final totalT = const Interval(
            0.45,
            0.8,
            curve: Curves.easeOutCubic,
          ).transform(_ac.value);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, box) => QuillStroke(
                  width: box.maxWidth,
                  thickness: 2.5,
                  color: c.seal,
                  progress: ruleT,
                  seed: 7,
                ),
              ),
              const SizedBox(height: Gap.x2),
              Opacity(
                opacity: totalT,
                child: Transform.translate(
                  offset: Offset(0, 6 * (1 - totalT)),
                  child: LeaderRow(
                    label: 'day total',
                    amount: Inr.format(widget.dayTotalPaise),
                    emphasized: true,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x3),
              SizedBox(
                height: 44,
                child: _stampPhase
                    ? Center(child: StampIn(size: 40, onStamped: _sealInDb))
                    : null,
              ),
              if (_stampPhase) ...[
                const SizedBox(height: Gap.x2),
                InkIn(
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    _closedLine,
                    textAlign: TextAlign.center,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ],
              ?whisper,
            ],
          );
        },
      ),
    );
  }

  /// A day that was closed before this page was opened: the finished
  /// composition, no re-performance.
  Widget _closed(LedgerColors c, Widget? whisper) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) => QuillStroke(
              width: box.maxWidth,
              thickness: 2.5,
              color: c.seal,
              seed: 7,
            ),
          ),
          const SizedBox(height: Gap.x2),
          LeaderRow(
            label: 'day total',
            amount: Inr.format(widget.dayTotalPaise),
            emphasized: true,
          ),
          const SizedBox(height: Gap.x3),
          const Center(child: Seal(size: 40)),
          const SizedBox(height: Gap.x2),
          Text(
            _closedLine,
            textAlign: TextAlign.center,
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
          ?whisper,
        ],
      ),
    );
  }
}
