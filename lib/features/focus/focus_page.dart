import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/seal.dart';
import '../../data/db.dart';
import '../../data/repos/focus_repo.dart';

/// Focus — one thing at a time, on its own page of the book.
///
/// A sitting is a line in the ledger like any other: start time, what for,
/// minutes in mono. Finishing earns the stamp; leaving early just writes the
/// truth ("left after 12m") with no sermon attached.
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

enum _Phase { idle, running, done }

class _FocusPageState extends ConsumerState<FocusPage> {
  _Phase _phase = _Phase.idle;
  int _preset = 25;
  final _labelCtrl = TextEditingController();

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

  late Stream<List<FocusSession>> _dayStream;
  late Future<
      ({int totalMinutes, int sessions, DateTime? bestDay, int bestDayMinutes})>
      _monthStats;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(focusRepoProvider);
    _dayStream = repo.watchDay(DateTime.now());
    _monthStats = repo.monthStats(DateTime.now());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _reveal?.cancel();
    _labelCtrl.dispose();
    super.dispose();
  }

  Duration get _remaining {
    if (_paused) return _pausedRemaining;
    final r = _endsAt.difference(DateTime.now());
    return r.isNegative ? Duration.zero : r;
  }

  // ————— the sitting —————

  void _start({required FocusKind kind, required int minutes, String? label}) {
    HapticFeedback.lightImpact();
    _ticker?.cancel();
    _reveal?.cancel();
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
    _ticker =
        Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
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
  }

  /// Leaving early writes what actually happened — a minute or more becomes
  /// an honest incomplete line; less than that never touched the page.
  Future<void> _giveUp() async {
    _ticker?.cancel();
    _ticker = null;
    final elapsedMinutes = (_total - _remaining).inMinutes;
    setState(() {
      _phase = _Phase.idle;
      _paused = false;
    });
    if (elapsedMinutes >= 1) {
      await ref.read(focusRepoProvider).record(
            startedAt: _startedAt,
            minutes: elapsedMinutes,
            kind: _kind,
            completed: false,
            label: _runLabel,
          );
    }
  }

  Future<void> _complete() async {
    _ticker?.cancel();
    _ticker = null;
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
    final repo = ref.read(focusRepoProvider);
    await repo.record(
      startedAt: _startedAt,
      minutes: minutes,
      kind: kind,
      completed: true,
      label: _runLabel,
    );
    if (mounted) {
      setState(() => _monthStats = repo.monthStats(DateTime.now()));
    }
  }

  void _settle() {
    _reveal?.cancel();
    setState(() => _phase = _Phase.idle);
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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _dayShort(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ————— build —————

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return ModuleScaffold(
      title: 'Focus',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x8),
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey(_phase),
              child: switch (_phase) {
                _Phase.idle => _idleView(c),
                _Phase.running => _runningView(c),
                _Phase.done => _doneView(c),
              },
            ),
          ),
          const RuleHeader('to-day'),
          _todayList(c),
          const RuleHeader('this month'),
          _monthLines(c),
        ],
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
  Widget _drainLine(LedgerColors c,
      {required double fraction, required Color color}) {
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

  Widget _idleView(LedgerColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('one thing at a time',
            style: LedgerType.label.copyWith(color: c.inkFaint)),
        const SizedBox(height: Gap.x1),
        Text(_clock(Duration(minutes: _preset)), style: _heroStyle(c.ink)),
        const SizedBox(height: Gap.x3),
        _drainLine(c, fraction: 1, color: c.quill),
        const SizedBox(height: Gap.x4),
        Row(
          children: [
            for (final m in const [15, 25, 45]) ...[
              LedgerChip(
                '$m min',
                selected: _preset == m,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _preset = m);
                },
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
            hintStyle: LedgerType.bodyText
                .copyWith(fontSize: 14, color: c.inkFaint),
            enabledBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
            focusedBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: c.quill)),
          ),
        ),
        const SizedBox(height: Gap.x6),
        FilledButton(
          onPressed: () => _start(
            kind: FocusKind.work,
            minutes: _preset,
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
        _drainLine(c, fraction: fraction, color: rest ? c.jama : c.quill),
        if (_paused) ...[
          const SizedBox(height: Gap.x2),
          Text('holding still',
              style:
                  LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint)),
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
            child: Text('give up',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 13, color: c.inkFaint)),
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
                      LedgerChip(
                        'back to it',
                        onTap: () => _start(
                          kind: FocusKind.work,
                          minutes: _preset,
                          label: _labelCtrl.text,
                        ),
                      )
                    else ...[
                      LedgerChip(
                        '5 min rest',
                        onTap: () =>
                            _start(kind: FocusKind.rest, minutes: 5),
                      ),
                      LedgerChip(
                        'again',
                        onTap: () => _start(
                          kind: FocusKind.work,
                          minutes: _preset,
                          label: _labelCtrl.text,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.x2),
                TextButton(
                  onPressed: _settle,
                  child: Text('done for now',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 13, color: c.inkFaint)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ————— the ledger below —————

  Widget _todayList(LedgerColors c) {
    return StreamBuilder<List<FocusSession>>(
      stream: _dayStream,
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? const <FocusSession>[];
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
              if (s.completed)
                _sessionLine(c, s, last: i == sessions.length - 1)
              else
                Opacity(
                  opacity: 0.55,
                  child: _sessionLine(c, s, last: i == sessions.length - 1),
                ),
            const SizedBox(height: Gap.x2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_hm(workMinutes)} to-day',
                style:
                    LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
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
          : 'left after ${s.minutes}m',
      amount: '${s.minutes}m',
      amountColor: rest ? c.jama : null,
      last: last,
    );
  }

  Widget _monthLines(LedgerColors c) {
    return FutureBuilder<
        ({int totalMinutes, int sessions, DateTime? bestDay, int bestDayMinutes})>(
      future: _monthStats,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        if (stats == null || stats.sessions == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'nothing sealed this month yet.',
              style: LedgerType.bodyText.copyWith(color: c.inkFaint),
            ),
          );
        }
        final best = stats.bestDay;
        return Column(
          children: [
            LedgerLine(title: 'focused', amount: _hm(stats.totalMinutes)),
            LedgerLine(
              title: 'sessions',
              amount: '${stats.sessions}',
              last: best == null,
            ),
            if (best != null)
              LedgerLine(
                title: 'best day',
                detail: _dayShort(best),
                amount: _hm(stats.bestDayMinutes),
                last: true,
              ),
          ],
        );
      },
    );
  }
}
