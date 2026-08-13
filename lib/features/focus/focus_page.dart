import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/notifications.dart';
import '../../core/typography.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/focus_repo.dart';

// ————— pure arithmetic (testable, no widgets) —————

/// The all-time shape of the focus book, computed in one pass.
typedef FocusRecordStats = ({
  int totalMinutes,
  int sessions,
  int longestMinutes,
  DateTime? longestAt,
  int bestDayMinutes,
  DateTime? bestDay,
  int streakDays,
});

/// Mon–Sun completed-work minutes for the week containing [anchor].
List<int> weekWorkMinutes(
  Iterable<(DateTime, int)> completedWork,
  DateTime anchor,
) {
  final monday = DateTime(
    anchor.year,
    anchor.month,
    anchor.day - (anchor.weekday - 1),
  );
  final bars = List<int>.filled(7, 0);
  for (final (startedAt, minutes) in completedWork) {
    final day = DateTime(startedAt.year, startedAt.month, startedAt.day);
    final ix = day.difference(monday).inDays;
    if (ix >= 0 && ix < 7) bars[ix] += minutes;
  }
  return bars;
}

/// Consecutive days with at least one completed work sitting, counting back
/// from today — or from yesterday, so a not-yet-started to-day doesn't snap
/// the thread at breakfast. Any gap ends the run.
int focusStreakDays(Iterable<DateTime> daysWithWork, DateTime today) {
  final days = {for (final d in daysWithWork) DateTime(d.year, d.month, d.day)};
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(cursor)) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  var run = 0;
  while (days.contains(cursor)) {
    run++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  return run;
}

/// Every completed work sitting ever, folded into the record: total minutes,
/// sittings, the longest single sitting, the best day, and the streak.
/// Ties go to the earlier occasion — the first time it happened counts.
FocusRecordStats focusRecord(
  Iterable<(DateTime, int)> completedWork,
  DateTime today,
) {
  var totalMinutes = 0;
  var sessions = 0;
  var longestMinutes = 0;
  DateTime? longestAt;
  final byDay = <DateTime, int>{};
  for (final (startedAt, minutes) in completedWork) {
    totalMinutes += minutes;
    sessions++;
    final day = DateTime(startedAt.year, startedAt.month, startedAt.day);
    byDay.update(day, (m) => m + minutes, ifAbsent: () => minutes);
    if (minutes > longestMinutes ||
        (minutes == longestMinutes &&
            longestAt != null &&
            startedAt.isBefore(longestAt))) {
      longestMinutes = minutes;
      longestAt = startedAt;
    }
  }
  DateTime? bestDay;
  var bestDayMinutes = 0;
  for (final e in byDay.entries) {
    if (e.value > bestDayMinutes ||
        (e.value == bestDayMinutes &&
            bestDay != null &&
            e.key.isBefore(bestDay))) {
      bestDay = e.key;
      bestDayMinutes = e.value;
    }
  }
  return (
    totalMinutes: totalMinutes,
    sessions: sessions,
    longestMinutes: longestMinutes,
    longestAt: longestAt,
    bestDayMinutes: bestDayMinutes,
    bestDay: bestDay,
    streakDays: focusStreakDays(byDay.keys, today),
  );
}

/// The three preset chips, read from settings keys focusPreset1..3; anything
/// missing or unreadable falls back to the stock 15 / 25 / 45.
List<int> focusPresetsFromSettings(Map<String, String> settings) {
  const defaults = [15, 25, 45];
  return [
    for (var i = 0; i < 3; i++)
      switch (int.tryParse(settings['focusPreset${i + 1}'] ?? '')) {
        final m? when m >= 1 && m <= 240 => m,
        _ => defaults[i],
      },
  ];
}

/// Focus — one thing at a time, on its own page of the book.
///
/// A sitting is a line in the ledger like any other: start time, what for,
/// minutes in mono. Finishing earns the stamp; leaving early just writes the
/// truth ("left after 12m") with no sermon attached. Beneath the timer: the
/// day's lines, the week's bars, and the all-time record.
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

enum _Phase { idle, running, done }

class _FocusPageState extends ConsumerState<FocusPage>
    with SingleTickerProviderStateMixin {
  _Phase _phase = _Phase.idle;

  /// The three chips, editable by long-press and persisted in settings.
  List<int> _presets = const [15, 25, 45];
  int _presetIx = 1;
  final _labelCtrl = TextEditingController();

  /// The drain line's breath while a sitting runs: a slow 0.85–1.0 opacity
  /// swell. Runs ONLY while the timer does — idle, paused, and done leave
  /// no live ticker behind. Created in [initState], disposed in [dispose].
  late final AnimationController _breath;

  /// Session ids already on the page — only genuinely new lines ink in.
  final _seenSessions = <int>{};
  bool _sessionsPrimed = false;

  // The running sitting. Remaining time is always derived from [_endsAt] —
  // never a decremented counter — so backgrounding can't make the clock lie.
  Timer? _ticker;
  Timer? _reveal;
  FocusKind _kind = FocusKind.work;
  DateTime _startedAt = DateTime.now();
  DateTime _endsAt = DateTime.now();
  Duration _total = const Duration(minutes: 25);
  Duration _pausedRemaining = Duration.zero;
  bool _paused = false;
  String? _runLabel;

  // The just-finished sitting, for the stamp view.
  int _doneMinutes = 0;
  FocusKind _doneKind = FocusKind.work;
  bool _chipsIn = false;

  /// Minutes sat before walking away, held just long enough to say so once.
  int? _leftAfter;
  bool _ackIn = false;
  Timer? _ack;

  late Stream<List<FocusSession>> _dayStream;
  late Future<List<int>> _weekBars;
  late Future<FocusRecordStats> _record;
  late Future<_MonthOfSittings> _month;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      lowerBound: 0.85,
      upperBound: 1.0,
      value: 1.0,
    );
    _dayStream = ref.read(focusRepoProvider).watchDay(DateTime.now());
    _weekBars = _loadWeek();
    _record = _loadRecord();
    _month = _loadMonth();
    unawaited(_loadPresets());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _reveal?.cancel();
    _ack?.cancel();
    _breath.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  bool get _still => Motion.reduced(context);

  void _breathe() {
    if (_still) {
      _breath.value = 1;
    } else {
      _breath.repeat(reverse: true);
    }
  }

  void _holdBreath() {
    _breath.stop();
    _breath.value = 1;
  }

  Duration get _remaining {
    if (_paused) return _pausedRemaining;
    final r = _endsAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  // ————— reading the book (drift queries live here, not in the repo) —————

  /// This week's completed work sittings, folded to Mon–Sun minutes.
  Future<List<int>> _loadWeek() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final sunday = DateTime(monday.year, monday.month, monday.day + 7);
    final rows =
        await (db.select(db.focusSessions)..where(
              (s) =>
                  s.kind.equalsValue(FocusKind.work) &
                  s.completed.equals(true) &
                  s.startedAt.isBiggerOrEqualValue(monday) &
                  s.startedAt.isSmallerThanValue(sunday),
            ))
            .get();
    return weekWorkMinutes(rows.map((r) => (r.startedAt, r.minutes)), now);
  }

  /// Every completed work sitting ever, folded into the record.
  Future<FocusRecordStats> _loadRecord() async {
    final db = ref.read(dbProvider);
    final rows =
        await (db.select(db.focusSessions)..where(
              (s) =>
                  s.kind.equalsValue(FocusKind.work) & s.completed.equals(true),
            ))
            .get();
    return focusRecord(
      rows.map((r) => (r.startedAt, r.minutes)),
      DateTime.now(),
    );
  }

  /// This month, day by day: minutes per date for the grid, plus the month's
  /// tally from the repo — the same figures the rest of the box counts.
  Future<_MonthOfSittings> _loadMonth() async {
    final now = DateTime.now();
    final stats = await ref.read(focusRepoProvider).monthStats(now);
    final db = ref.read(dbProvider);
    final rows =
        await (db.select(db.focusSessions)..where(
              (s) =>
                  s.kind.equalsValue(FocusKind.work) &
                  s.completed.equals(true) &
                  s.startedAt.isBiggerOrEqualValue(
                    LedgerDates.monthStart(now),
                  ) &
                  s.startedAt.isSmallerThanValue(LedgerDates.monthEnd(now)),
            ))
            .get();
    final days = List<int>.filled(LedgerDates.daysInMonth(now), 0);
    for (final r in rows) {
      days[r.startedAt.day - 1] += r.minutes;
    }
    return (
      days: days,
      totalMinutes: stats.totalMinutes,
      sessions: stats.sessions,
      bestDay: stats.bestDay,
      bestDayMinutes: stats.bestDayMinutes,
    );
  }

  Future<void> _loadPresets() async {
    final db = ref.read(dbProvider);
    final rows =
        await (db.select(db.settings)..where(
              (s) => s.key.isIn(const [
                'focusPreset1',
                'focusPreset2',
                'focusPreset3',
              ]),
            ))
            .get();
    final loaded = focusPresetsFromSettings({
      for (final r in rows) r.key: r.value,
    });
    if (!mounted || listEquals(loaded, _presets)) return;
    setState(() => _presets = loaded);
  }

  /// A fresh sitting just landed — the week and the record move with it.
  void _refreshTallies() {
    if (!mounted) return;
    setState(() {
      _weekBars = _loadWeek();
      _record = _loadRecord();
      _month = _loadMonth();
    });
  }

  // ————— the sitting —————

  void _start({required FocusKind kind, required int minutes, String? label}) {
    HapticFeedback.lightImpact();
    _ticker?.cancel();
    _reveal?.cancel();
    // Beginning again answers the last line better than the line does.
    _ack?.cancel();
    _leftAfter = null;
    _ackIn = false;
    final now = DateTime.now();
    final trimmed = label?.trim();
    setState(() {
      _phase = _Phase.running;
      _kind = kind;
      _paused = false;
      _startedAt = now;
      _total = Duration(minutes: minutes);
      _endsAt = now.add(_total);
      _runLabel = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      _chipsIn = false;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    // The finish line is told to the phone itself, so the session ends out
    // loud even if the app is killed with the clock running.
    unawaited(LedgerReminders.scheduleFocusEnd(minutes, now.add(_total)));
    _breathe();
  }

  void _tick() {
    if (!mounted || _paused) return;
    if (_remaining <= Duration.zero) {
      _complete();
    } else {
      setState(() {});
    }
  }

  void _togglePause() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_paused) {
        _endsAt = DateTime.now().add(_pausedRemaining);
        _paused = false;
      } else {
        _pausedRemaining = _remaining;
        _paused = true;
      }
    });
    // A paused clock has no finish line; resuming draws a fresh one.
    if (_paused) {
      unawaited(LedgerReminders.cancelFocusEnd());
    } else {
      unawaited(
        LedgerReminders.scheduleFocusEnd(
          _total.inMinutes,
          DateTime.now().add(_pausedRemaining),
        ),
      );
    }
    // The line holds its breath with the clock.
    if (_paused) {
      _holdBreath();
    } else {
      _breathe();
    }
  }

  /// Leaving early writes what actually happened — a minute or more becomes
  /// an honest incomplete line; less than that never touched the page.
  Future<void> _giveUp() async {
    _ticker?.cancel();
    _ticker = null;
    unawaited(LedgerReminders.cancelFocusEnd());
    _holdBreath();
    final elapsedMinutes = (_total - _remaining).inMinutes;
    setState(() {
      _phase = _Phase.idle;
      _paused = false;
      _leftAfter = elapsedMinutes;
      _ackIn = true;
    });
    // The acknowledgement is a line, not a verdict: it says its piece and
    // then dries off the page again.
    _ack?.cancel();
    _ack = Timer(const Duration(milliseconds: 4500), () {
      if (!mounted) return;
      setState(() => _ackIn = false);
      _ack = Timer(Motion.spring, () {
        if (mounted) setState(() => _leftAfter = null);
      });
    });
    if (elapsedMinutes >= 1) {
      await ref
          .read(focusRepoProvider)
          .record(
            startedAt: _startedAt,
            minutes: elapsedMinutes,
            kind: _kind,
            completed: false,
            label: _runLabel,
          );
      _refreshTallies();
    }
  }

  Future<void> _complete() async {
    _ticker?.cancel();
    _ticker = null;
    // The page saw the finish itself — the phone needn't repeat it.
    unawaited(LedgerReminders.cancelFocusEnd());
    _holdBreath();
    HapticFeedback.mediumImpact();
    final minutes = _total.inMinutes;
    final kind = _kind;
    setState(() {
      _phase = _Phase.done;
      _doneMinutes = minutes;
      _doneKind = kind;
      _chipsIn = false;
    });
    // The stamp lands first; the suggestions arrive a beat later.
    _reveal = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _chipsIn = true);
    });
    await ref
        .read(focusRepoProvider)
        .record(
          startedAt: _startedAt,
          minutes: minutes,
          kind: kind,
          completed: true,
          label: _runLabel,
        );
    _refreshTallies();
  }

  void _settle() {
    _reveal?.cancel();
    setState(() => _phase = _Phase.idle);
  }

  // ————— the presets —————

  /// Long-press a chip and it opens the small sheet: one figure, one button.
  Future<void> _editPreset(int index) async {
    HapticFeedback.selectionClick();
    final entered = await showLedgerSheet<int>(
      context,
      builder: (_) => _PresetSheet(minutes: _presets[index]),
    );
    if (entered == null || !mounted) return;
    final minutes = entered.clamp(1, 240);
    final next = [..._presets];
    next[index] = minutes;
    setState(() => _presets = next);
    final db = ref.read(dbProvider);
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: 'focusPreset${index + 1}',
            value: '$minutes',
          ),
        );
  }

  // ————— formatting —————

  static String _clock(Duration d) {
    final secs = (d.inMilliseconds / 1000).ceil();
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static String _hm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ————— build —————

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final still = _still;
    return ModuleScaffold(
      title: 'Focus',
      // A page of fixed sections, not a feed — it's laid out whole so the
      // record and the month are written even before they're scrolled to.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Idle, running and done are three different heights. The page
            // grows and shrinks on the book's spring instead of snapping the
            // ledger below up and down.
            AnimatedSize(
              duration: still ? Duration.zero : Motion.spring,
              curve: Motion.curve,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : Motion.spring,
                switchInCurve: Motion.curve,
                switchOutCurve: Motion.curve,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey(_phase),
                  child: switch (_phase) {
                    _Phase.idle => _idleView(c),
                    _Phase.running => _runningView(c),
                    _Phase.done => _doneView(c),
                  },
                ),
              ),
            ),
            const RuleHeader('to-day'),
            _todayList(c),
            const RuleHeader('this week'),
            _weekSection(c),
            const RuleHeader('this month'),
            _monthSection(c),
            const RuleHeader('the record'),
            _recordLines(c),
          ],
        ),
      ),
    );
  }

  TextStyle _heroStyle(Color color) => LedgerType.heroAmount.copyWith(
    fontSize: 64,
    color: color,
    // Tabular figures: the digits hold their columns, no jitter.
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// The thin line under the timer. It drains — depletion, not completion:
  /// the emptied part grows from the left as the remaining ink recedes.
  Widget _drainLine(
    LedgerColors c, {
    required double fraction,
    required Color color,
  }) {
    return SizedBox(
      height: 2.5,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.rule)),
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.linear,
                width: box.maxWidth * fraction.clamp(0.0, 1.0),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The quiet line under the idle timer: the thread, still running.
  Widget _streakWhisper(LedgerColors c) {
    return FutureBuilder<FocusRecordStats>(
      future: _record,
      builder: (context, snapshot) {
        final streak = snapshot.data?.streakDays ?? 0;
        if (streak == 0) return const SizedBox(height: Gap.x4);
        return Padding(
          padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x3),
          child: Text(
            '$streak ${streak == 1 ? 'day' : 'days'} running — keep the thread.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        );
      },
    );
  }

  /// Walking away is still a line in the book. One sentence, no sermon —
  /// it inks in, sits for a breath, and dries off the page again.
  Widget _ackLine(LedgerColors c) {
    final m = _leftAfter!;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x3),
      child: InkIn(
        child: AnimatedOpacity(
          opacity: _ackIn ? 1 : 0,
          duration: _still ? Duration.zero : Motion.spring,
          curve: Motion.curve,
          child: Text(
            m < 1
                ? 'Too short to write down. Nothing lost.'
                : '$m ${m == 1 ? 'minute' : 'minutes'} still counted.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ),
      ),
    );
  }

  Widget _idleView(LedgerColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'one thing at a time',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x1),
        // A fresh preset inks its time onto the page rather than snapping.
        InkIn(
          key: ValueKey('preset-${_presets[_presetIx]}'),
          child: Text(
            _clock(Duration(minutes: _presets[_presetIx])),
            style: _heroStyle(c.ink),
          ),
        ),
        const SizedBox(height: Gap.x3),
        _drainLine(c, fraction: 1, color: c.quill),
        if (_leftAfter != null) _ackLine(c) else _streakWhisper(c),
        Row(
          children: [
            for (final (i, m) in _presets.indexed) ...[
              Pressable(
                onTap: () => setState(() => _presetIx = i),
                onLongPress: () => _editPreset(i),
                child: LedgerChip('$m min', selected: _presetIx == i),
              ),
              const SizedBox(width: Gap.x2),
            ],
          ],
        ),
        const SizedBox(height: Gap.x4),
        TextField(
          controller: _labelCtrl,
          style: LedgerType.bodyText.copyWith(color: c.ink),
          cursorColor: c.quill,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
            hintText: 'what for? (optional)',
            hintStyle: LedgerType.bodyText.copyWith(
              fontSize: 14,
              color: c.inkFaint,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.rule),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.quill),
            ),
          ),
        ),
        const SizedBox(height: Gap.x6),
        FilledButton(
          onPressed: () => _start(
            kind: FocusKind.work,
            minutes: _presets[_presetIx],
            label: _labelCtrl.text,
          ),
          child: const Text('Begin'),
        ),
      ],
    );
  }

  Widget _runningView(LedgerColors c) {
    final rest = _kind == FocusKind.rest;
    final remaining = _remaining;
    final fraction = _total.inMilliseconds == 0
        ? 0.0
        : remaining.inMilliseconds / _total.inMilliseconds;
    // The last minute of work leans quietly from quill toward the seal —
    // urgency as a slow change of ink, never a flash.
    final base = rest ? c.jama : c.quill;
    final secs = remaining.inSeconds;
    final lineColor = !rest && secs <= 60
        ? Color.lerp(c.seal, base, (secs / 60).clamp(0.0, 1.0))!
        : base;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _runLabel ?? (rest ? 'rest' : 'focus'),
          style: LedgerType.label.copyWith(color: c.inkFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Gap.x1),
        Text(_clock(remaining), style: _heroStyle(c.ink)),
        const SizedBox(height: Gap.x3),
        // The line breathes while the sitting runs.
        FadeTransition(
          opacity: _breath,
          child: _drainLine(c, fraction: fraction, color: lineColor),
        ),
        if (_paused) ...[
          const SizedBox(height: Gap.x2),
          Text(
            'holding still',
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ],
        const SizedBox(height: Gap.x6),
        FilledButton(
          onPressed: _togglePause,
          child: Text(_paused ? 'Resume' : 'Pause'),
        ),
        const SizedBox(height: Gap.x2),
        Center(
          child: TextButton(
            onPressed: _giveUp,
            child: Text(
              'stop early',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _doneView(LedgerColors c) {
    final rest = _doneKind == FocusKind.rest;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        const SizedBox(height: Gap.x6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Transform.rotate(
            angle: (1 - t) * 0.12,
            child: Transform.scale(scale: 1.6 + (1.0 - 1.6) * t, child: child),
          ),
          child: const Seal(size: 72),
        ),
        const SizedBox(height: Gap.x4),
        Text(
          rest
              ? '$_doneMinutes minutes, rested.'
              : '$_doneMinutes minutes, yours.',
          style: LedgerType.title.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: Gap.x6),
        AnimatedOpacity(
          opacity: _chipsIn ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !_chipsIn,
            child: Column(
              children: [
                Wrap(
                  spacing: Gap.x2,
                  alignment: WrapAlignment.center,
                  children: [
                    if (rest)
                      _settleIn(
                        0,
                        LedgerChip(
                          'back to it',
                          onTap: () => _start(
                            kind: FocusKind.work,
                            minutes: _presets[_presetIx],
                            label: _labelCtrl.text,
                          ),
                        ),
                      )
                    else ...[
                      _settleIn(
                        0,
                        LedgerChip(
                          '5 min rest',
                          onTap: () => _start(kind: FocusKind.rest, minutes: 5),
                        ),
                      ),
                      _settleIn(
                        1,
                        LedgerChip(
                          'again',
                          onTap: () => _start(
                            kind: FocusKind.work,
                            minutes: _presets[_presetIx],
                            label: _labelCtrl.text,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.x2),
                _settleIn(
                  2,
                  TextButton(
                    onPressed: _settle,
                    child: Text(
                      'done for now',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 13,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ————— the ledger below —————

  /// The stamp lands, then the suggestions arrive one beat apart.
  Widget _settleIn(int index, Widget child) {
    return InkIn(
      key: ValueKey('after-$index-$_chipsIn'),
      play: _chipsIn,
      delay: Duration(milliseconds: 120 * index),
      child: child,
    );
  }

  Widget _todayList(LedgerColors c) {
    return StreamBuilder<List<FocusSession>>(
      stream: _dayStream,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <FocusSession>[];
        // Only lines that were not on the page last emission ink in;
        // the first load renders as an already-written page.
        final fresh = <int>{
          if (_sessionsPrimed)
            for (final s in sessions)
              if (!_seenSessions.contains(s.id)) s.id,
        };
        if (snapshot.hasData) {
          _sessionsPrimed = true;
          _seenSessions.addAll(sessions.map((s) => s.id));
        }
        if (sessions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'no minutes written yet.',
              style: LedgerType.bodyText.copyWith(color: c.inkFaint),
            ),
          );
        }
        final workMinutes = sessions
            .where((s) => s.kind == FocusKind.work)
            .fold(0, (sum, s) => sum + s.minutes);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, s) in sessions.indexed)
              InkIn(
                key: ValueKey('session-${s.id}'),
                play: fresh.contains(s.id),
                child: s.completed
                    ? _sessionLine(c, s, last: i == sessions.length - 1)
                    : Opacity(
                        opacity: 0.55,
                        child: _sessionLine(
                          c,
                          s,
                          last: i == sessions.length - 1,
                        ),
                      ),
              ),
            const SizedBox(height: Gap.x2),
            Align(
              alignment: Alignment.centerRight,
              child: CountUp(
                value: workMinutes,
                format: (m) => '${_hm(m)} to-day',
                style: LedgerType.amount.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sessionLine(LedgerColors c, FocusSession s, {required bool last}) {
    final rest = s.kind == FocusKind.rest;
    return LedgerLine(
      leading: _hhmm(s.startedAt),
      title: s.label ?? (rest ? 'rest' : 'focus'),
      detail: s.completed
          ? (rest ? 'rest' : null)
          : 'stopped after ${s.minutes}m',
      amount: '${s.minutes}m',
      amountColor: rest ? c.jama : null,
      last: last,
    );
  }

  // ————— this week —————

  static const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  /// Seven thin ink bars on a rule baseline, today's in quill; the bars draw
  /// themselves up once when the week first arrives.
  Widget _weekSection(LedgerColors c) {
    return FutureBuilder<List<int>>(
      future: _weekBars,
      builder: (context, snapshot) {
        final bars = snapshot.data;
        if (bars == null) return const SizedBox(height: 96);
        final todayIx = DateTime.now().weekday - 1;
        final total = bars.fold(0, (a, b) => a + b);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.x2),
            SizedBox(
              height: 64,
              child: DrawIn(
                builder: (context, t) => CustomPaint(
                  painter: _WeekBarsPainter(
                    minutes: bars,
                    todayIx: todayIx,
                    ink: c.ink,
                    quill: c.quill,
                    rule: c.rule,
                    progress: _still ? 1 : t,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                for (final (i, letter) in _dayLetters.indexed)
                  Expanded(
                    child: Center(
                      child: Text(
                        letter,
                        style: LedgerType.label.copyWith(
                          fontSize: 10,
                          color: i == todayIx ? c.quill : c.inkFaint,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: Gap.x2),
              Align(
                alignment: Alignment.centerRight,
                child: CountUp(
                  value: total,
                  format: (m) => '${_hm(m)} this week',
                  style: LedgerType.amount.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  // ————— this month —————

  /// The month as the book's own heat grid: one cell per date, minutes for
  /// intensity, cells inking in one after another. Quiet days stay hollow —
  /// a blank square is a fact, not a scolding.
  Widget _monthSection(LedgerColors c) {
    return FutureBuilder<_MonthOfSittings>(
      future: _month,
      builder: (context, snapshot) {
        final m = snapshot.data;
        if (m == null) return const SizedBox(height: 120);
        if (m.sessions == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'no sessions this month, yet.',
              style: LedgerType.bodyText.copyWith(color: c.inkFaint),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Gap.x2),
            HeatGrid(dayTotalsPaise: m.days, stagger: !_still),
            const SizedBox(height: Gap.x2),
            Align(
              alignment: Alignment.centerRight,
              child: CountUp(
                value: m.totalMinutes,
                format: (mins) => m.bestDay == null
                    ? '${_hm(mins)} this month'
                    : '${_hm(mins)} this month · best on '
                          '${LedgerDates.ddMmm(m.bestDay!)}',
                style: LedgerType.amount.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ————— the record —————

  /// All-time, in ruled lines: hours, sittings, the longest sitting, the
  /// best day, and the streak.
  Widget _recordLines(LedgerColors c) {
    return FutureBuilder<FocusRecordStats>(
      future: _record,
      builder: (context, snapshot) {
        final r = snapshot.data;
        if (r == null || r.sessions == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'nothing on the record yet.',
              style: LedgerType.bodyText.copyWith(color: c.inkFaint),
            ),
          );
        }
        final amountStyle = LedgerType.amount.copyWith(color: c.ink);
        return Column(
          children: [
            LedgerLine(
              title: 'focused, all-time',
              amountWidget: CountUp(
                value: r.totalMinutes,
                format: _hm,
                style: amountStyle,
              ),
            ),
            LedgerLine(
              title: 'sessions',
              amountWidget: CountUp(
                value: r.sessions,
                format: (n) => '$n',
                style: amountStyle,
              ),
            ),
            LedgerLine(
              title: 'longest session',
              amountWidget: _onDate(
                c,
                r.longestAt,
                Text('${r.longestMinutes}m', style: amountStyle),
              ),
            ),
            LedgerLine(
              title: 'best day',
              amountWidget: _onDate(
                c,
                r.bestDay,
                Text(_hm(r.bestDayMinutes), style: amountStyle),
              ),
            ),
            LedgerLine(
              title: 'the streak',
              amountWidget: r.streakDays == 0
                  ? Text(
                      'none running',
                      style: LedgerType.amount.copyWith(color: c.inkFaint),
                    )
                  : CountUp(
                      value: r.streakDays,
                      format: (n) => '$n ${n == 1 ? 'day' : 'days'} running',
                      style: amountStyle,
                    ),
              last: true,
            ),
          ],
        );
      },
    );
  }

  /// The amount column with the occasion written just before it, the way a
  /// ledger keeps its date column: "31 Jul   47m".
  Widget _onDate(LedgerColors c, DateTime? on, Widget figure) {
    if (on == null) return figure;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          LedgerDates.ddMmm(on),
          style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
        ),
        const SizedBox(width: Gap.x3),
        figure,
      ],
    );
  }
}

/// One month of the focus book, read in a single pass.
typedef _MonthOfSittings = ({
  List<int> days,
  int totalMinutes,
  int sessions,
  DateTime? bestDay,
  int bestDayMinutes,
});

/// The preset editor: one figure, one button. It owns its controller so the
/// sheet's own exit animation can't outlive it.
class _PresetSheet extends StatefulWidget {
  const _PresetSheet({required this.minutes});

  final int minutes;

  @override
  State<_PresetSheet> createState() => _PresetSheetState();
}

class _PresetSheetState extends State<_PresetSheet> {
  late final _ctrl = TextEditingController(text: '${widget.minutes}');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _keep() => Navigator.of(context).pop(int.tryParse(_ctrl.text.trim()));

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        Gap.x6 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: Gap.x3),
          Text(
            'preset length, in minutes',
            style: LedgerType.label.copyWith(color: c.inkFaint),
          ),
          const SizedBox(height: Gap.x3),
          TextField(
            key: const ValueKey('preset-minutes'),
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: LedgerType.amountTotal.copyWith(fontSize: 26, color: c.ink),
            cursorColor: c.quill,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.rule),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.quill),
              ),
            ),
            onSubmitted: (_) => _keep(),
          ),
          const SizedBox(height: Gap.x6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _keep, child: const Text('Keep')),
          ),
        ],
      ),
    );
  }
}

/// The week's seven bars: thin ink on a rule baseline, today in quill.
/// [progress] 0→1 grows the bars from the baseline — pair with [DrawIn].
class _WeekBarsPainter extends CustomPainter {
  _WeekBarsPainter({
    required this.minutes,
    required this.todayIx,
    required this.ink,
    required this.quill,
    required this.rule,
    required this.progress,
  });

  final List<int> minutes;
  final int todayIx;
  final Color ink;
  final Color quill;
  final Color rule;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height - 1;
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );
    var maxMinutes = 1;
    for (final m in minutes) {
      if (m > maxMinutes) maxMinutes = m;
    }
    final colWidth = size.width / 7;
    const barWidth = 5.0;
    for (var i = 0; i < minutes.length && i < 7; i++) {
      final h = (base - 4) * (minutes[i] / maxMinutes) * progress.clamp(0, 1);
      if (h <= 0) continue;
      final x = colWidth * i + colWidth / 2;
      canvas.drawRect(
        Rect.fromLTRB(x - barWidth / 2, base - h, x + barWidth / 2, base),
        Paint()..color = i == todayIx ? quill : ink,
      );
    }
  }

  @override
  bool shouldRepaint(_WeekBarsPainter old) =>
      old.minutes != minutes ||
      old.progress != progress ||
      old.ink != ink ||
      old.quill != quill;
}
