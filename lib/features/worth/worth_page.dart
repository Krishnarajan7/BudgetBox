import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../settings/account_manager.dart';
import '../story/story_page.dart';

/// How far back the net-worth line is drawn. The chip is what's tapped; the
/// phrase is what the delta says underneath the hero.
enum WorthRange { month, halfYear, fy, all }

extension WorthRangeCopy on WorthRange {
  String get chip => switch (this) {
        WorthRange.month => '1M',
        WorthRange.halfYear => '6M',
        WorthRange.fy => 'FY',
        WorthRange.all => 'all',
      };

  /// Trailing days handed to `netWorthHistory(days:)`.
  int days(DateTime now) => switch (this) {
        WorthRange.month => 30,
        WorthRange.halfYear => 180,
        WorthRange.fy =>
          now.difference(LedgerDates.fyStart(now)).inDays + 1,
        WorthRange.all => 36500,
      };

  /// What the delta line calls this window, in the book's voice.
  String phrase(DateTime now) => switch (this) {
        WorthRange.month => 'over the past month',
        WorthRange.halfYear => 'over six months',
        WorthRange.fy => 'so far this ${LedgerDates.fyLabel(now)}',
        WorthRange.all => 'since the book opened',
      };
}

class WorthPage extends ConsumerStatefulWidget {
  const WorthPage({super.key});

  @override
  ConsumerState<WorthPage> createState() => _WorthPageState();
}

class _WorthPageState extends ConsumerState<WorthPage> {
  /// A balance change re-reads the history in place — the hero glides to its
  /// new figure and the chart keeps its drawn state. Only a *range* change
  /// bumps [_drawToken], which makes the line redraw itself from the left.
  List<int>? _history;
  int? _loadedNet;
  WorthRange? _loadedRange;
  int _drawToken = 0;

  WorthRange _range = WorthRange.halfYear;

  /// Guarded so it runs at most once per (net, range) pair — the read is
  /// kicked off from build and lands in state a frame later.
  void _ensureHistory(int net) {
    if (_loadedNet == net && _loadedRange == _range) return;
    _loadedNet = net;
    _loadedRange = _range;
    final wanted = _range;
    ref
        .read(accountRepoProvider)
        .netWorthHistory(days: wanted.days(DateTime.now()))
        .then((series) {
      if (!mounted || _range != wanted) return;
      setState(() => _history = series);
    });
  }

  void _pickRange(WorthRange r) {
    if (r == _range) return;
    HapticFeedback.selectionClick();
    setState(() {
      _range = r;
      _drawToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final accounts = ref.watch(accountRepoProvider);
    final now = DateTime.now();

    return StreamBuilder<List<Account>>(
      stream: accounts.watchAll(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Account>[];

        if (snapshot.hasData && all.isEmpty) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Gap.page),
                child: LedgerAppBar(title: 'Worth'),
              ),
              Expanded(
                child: EmptyPage(
                  line: 'Nothing on the shelf yet.',
                  sub: 'Add an account in the box and this page '
                      'starts keeping count.',
                  action: Pressable(
                    onTap: () => Navigator.of(context).push(
                      LedgerRoute<void>(
                        builder: (_) => const AccountManagerPage(),
                      ),
                    ),
                    child: Text(
                      'open the box ›',
                      style: LedgerType.bodyStrong
                          .copyWith(fontSize: 13, color: c.quill),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final assets =
            all.where((a) => a.kind != AccountKind.liability).toList();
        final owed = all.where((a) => a.kind == AccountKind.liability).toList();
        final net = assets.fold<int>(0, (s, a) => s + a.balancePaise) -
            owed.fold<int>(0, (s, a) => s + a.balancePaise);

        _ensureHistory(net);

        final fetched = _history;
        final history =
            (fetched == null || fetched.isEmpty) ? <int>[net] : fetched;
        final delta = net - history.first;

        // The high-water mark, and roughly when it was set: the series is one
        // reading per day, ending to-day.
        var peakIndex = 0;
        for (var i = 1; i < history.length; i++) {
          if (history[i] > history[peakIndex]) peakIndex = i;
        }
        final peak = history[peakIndex];
        final belowPeak = peak - net >= 100 && history.length > 2;
        final peakOn =
            now.subtract(Duration(days: history.length - 1 - peakIndex));

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          children: [
            LedgerAppBar(
              title: 'Worth',
              trailing: Pressable(
                onTap: () => Navigator.of(context).push(
                  LedgerRoute<void>(builder: (_) => const StoryPage()),
                ),
                child: Text('the month\'s story ›',
                    style: LedgerType.bodyStrong
                        .copyWith(fontSize: 13, color: c.quill)),
              ),
            ),
            const SizedBox(height: Gap.x4),
            CountHero(
              caption: 'net worth, as of to-day',
              paise: net,
              format: Inr.compact,
              size: 36,
              // The delta inks in once the chart has mostly drawn, and is
              // re-keyed per range so it rewrites itself alongside the line.
              sub: InkIn(
                key: ValueKey('delta-$_drawToken'),
                delay: const Duration(milliseconds: 450),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: delta == 0
                          ? 'level'
                          : '${delta > 0 ? 'up' : 'down'} '
                              '${Inr.format(delta.abs())}',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 13,
                        // Falling isn't a verdict — only a rise gets a mark.
                        color: delta > 0 ? c.jama : c.ink,
                      ),
                    ),
                    TextSpan(
                      text: ' ${_range.phrase(now)}',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 13, color: c.inkFaint),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: Gap.x3),
            Row(
              children: [
                for (final r in WorthRange.values) ...[
                  LedgerChip(
                    r.chip,
                    selected: r == _range,
                    onTap: () => _pickRange(r),
                  ),
                  const SizedBox(width: Gap.x2),
                ],
              ],
            ),
            const SizedBox(height: Gap.x3),
            _NetWorthChart(
              key: ValueKey('chart-$_drawToken'),
              history: history,
              peakIndex: belowPeak ? peakIndex : null,
            ),
            if (belowPeak) ...[
              const SizedBox(height: 6),
              Text(
                'highest it\'s ever been was ${Inr.compact(peak)}, '
                '${LedgerDates.ddMmm(peakOn)}',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 12, color: c.inkFaint),
              ),
            ],
            const RuleHeader('assets'),
            for (final (i, a) in assets.indexed)
              InkIn(
                delay: Duration(milliseconds: 45 * i),
                child: _AccountRow(
                    account: a, stagger: i, last: i == assets.length - 1),
              ),
            if (owed.isNotEmpty) ...[
              const RuleHeader('owed'),
              for (final (i, a) in owed.indexed)
                InkIn(
                  delay: Duration(milliseconds: 45 * (assets.length + i)),
                  child: _AccountRow(
                    account: a,
                    negative: true,
                    stagger: assets.length + i,
                    last: i == owed.length - 1,
                  ),
                ),
            ],
            const SizedBox(height: Gap.x6),
          ],
        );
      },
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({
    required this.account,
    this.negative = false,
    this.last = false,
    this.stagger = 0,
  });

  final Account account;
  final bool negative;
  final bool last;

  /// Row index across both sections, for the sparkline reveal stagger.
  final int stagger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final ageDays = DateTime.now().difference(account.asOf).inDays;
    final stale = ageDays >= 30;
    final asOf = ageDays <= 0
        ? 'as of to-day'
        : ageDays == 1
            ? 'as of yesterday'
            : 'as of ${LedgerDates.ddMmm(account.asOf)}';

    return Pressable(
      onTap: () => _correctBalance(context, ref),
      onLongPress: () {
        HapticFeedback.selectionClick();
        _historySheet(context, ref, asOf);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name,
                      style: LedgerType.bodyText.copyWith(color: c.ink)),
                  Text(
                    stale ? '$asOf — update?' : asOf,
                    style: LedgerType.bodyText.copyWith(
                        fontSize: 11, color: stale ? c.warn : c.inkFaint),
                  ),
                ],
              ),
            ),
            _SparkReveal(
              delayMs: 60 * stagger,
              child: FutureBuilder<List<double>>(
                key: ValueKey('spark-${account.id}-${account.balancePaise}'),
                future: ref.read(accountRepoProvider).spark(account.id),
                builder: (context, spark) => Sparkline(
                  spark.data ?? const [1, 1],
                ),
              ),
            ),
            const SizedBox(width: Gap.x3),
            // Settles to the new figure after an update, never snaps.
            CountUp(
              value: account.balancePaise,
              format: (p) => negative ? '− ${Inr.format(p)}' : Inr.format(p),
              style: LedgerType.amount.copyWith(color: c.ink),
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press: the readings behind the whisper, at a size worth reading.
  Future<void> _historySheet(
      BuildContext context, WidgetRef ref, String asOf) {
    final points = ref.read(accountRepoProvider).spark(account.id, points: 30);
    return showLedgerSheet<void>(
      context,
      scrollControlled: false,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(account.name,
                  style: LedgerType.title.copyWith(fontSize: 22, color: c.ink)),
              const SizedBox(height: 2),
              Text(asOf,
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 13, color: c.inkFaint)),
              const SizedBox(height: Gap.x4),
              FutureBuilder<List<double>>(
                future: points,
                builder: (context, snap) {
                  final data = snap.data ?? const <double>[];
                  final readings = data.length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, box) => DrawIn(
                          builder: (context, t) => ClipRect(
                            clipper: _RevealClipper(t),
                            child: Sparkline(
                              data.length < 2 ? const [1, 1] : data,
                              width: box.maxWidth,
                              height: 96,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: Gap.x3),
                      Container(height: 1, color: c.rule),
                      const SizedBox(height: Gap.x3),
                      if (readings < 2)
                        Text(
                          'Only one reading so far. Correct the balance a '
                          'few times and a shape shows up here.',
                          style: LedgerType.bodyText
                              .copyWith(fontSize: 13, color: c.inkFaint),
                        )
                      else
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: 'low ${Inr.format(data.reduce(math.min).round())}'
                                  '  ·  high ${Inr.format(data.reduce(math.max).round())}',
                              style: LedgerType.amount
                                  .copyWith(fontSize: 12, color: c.ink),
                            ),
                            TextSpan(
                              text: '  ·  $readings readings',
                              style: LedgerType.bodyText
                                  .copyWith(fontSize: 12, color: c.inkFaint),
                            ),
                          ]),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _correctBalance(BuildContext context, WidgetRef ref) async {
    final rupees = await showLedgerSheet<int>(
      context,
      builder: (context) => _CorrectBalanceSheet(account: account),
    );
    if (rupees != null) {
      await ref.read(accountRepoProvider).setBalance(account.id, rupees * 100);
    }
  }
}

/// "What's true right now?" — the figure is typed, then *stamped*: the seal
/// lands, the haptic fires, and only then does the sheet hand the number back
/// so the row's balance can count up to it.
class _CorrectBalanceSheet extends StatefulWidget {
  const _CorrectBalanceSheet({required this.account});

  final Account account;

  @override
  State<_CorrectBalanceSheet> createState() => _CorrectBalanceSheetState();
}

class _CorrectBalanceSheetState extends State<_CorrectBalanceSheet> {
  late final TextEditingController _field = TextEditingController(
      text: (widget.account.balancePaise ~/ 100).toString());
  bool _stamping = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  int? get _rupees => int.tryParse(_field.text.trim().replaceAll(',', ''));

  void _stamp() {
    if (_stamping || _rupees == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _stamping = true);
  }

  void _landed() {
    // The seal has pressed down; hand the figure back to the page.
    Future<void>.delayed(const Duration(milliseconds: 240), () {
      if (mounted) Navigator.of(context).pop(_rupees);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.page,
        right: Gap.page,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: Gap.x2),
          Text('${widget.account.name} — what\'s true right now?',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink)),
          Text('Rough is fine. This page can always be corrected again.',
              style: LedgerType.bodyText
                  .copyWith(fontSize: 13, color: c.inkFaint)),
          const SizedBox(height: Gap.x2),
          TextField(
            controller: _field,
            autofocus: true,
            enabled: !_stamping,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _stamp(),
            style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
            decoration: InputDecoration(
              prefixText: '₹',
              prefixStyle: LedgerType.heroAmount
                  .copyWith(fontSize: 32, color: c.inkFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: Gap.x2),
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedOpacity(
                  duration: Motion.quick,
                  opacity: _stamping ? 0.25 : 1,
                  child: Pressable(
                    // The stamp landing is the haptic; one is enough.
                    haptic: false,
                    onTap: _rupees == null ? null : _stamp,
                    child: AbsorbPointer(
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _rupees == null ? null : () {},
                          child: const Text('That\'s the number'),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_stamping)
                  IgnorePointer(
                    child: StampIn(size: 34, onStamped: _landed),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reveals its child left→right on first build — the whisper being drawn
/// into the row rather than appearing.
class _SparkReveal extends StatelessWidget {
  const _SparkReveal({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final total = 500 + delayMs;
    return DrawIn(
      duration: Duration(milliseconds: total),
      builder: (context, t) => ClipRect(
        clipper: _RevealClipper(((t * total - delayMs) / 500).clamp(0.0, 1.0)),
        child: child,
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.progress);

  final double progress;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_RevealClipper old) => old.progress != progress;
}

class _NetWorthChart extends StatelessWidget {
  const _NetWorthChart({super.key, required this.history, this.peakIndex});

  final List<int> history;

  /// When set, a faint watermark rule is ruled across the high-water mark —
  /// the line has been higher than it is now.
  final int? peakIndex;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      height: 80,
      width: double.infinity,
      child: DrawIn(
        duration: const Duration(milliseconds: 700),
        builder: (context, t) => CustomPaint(
          painter: _AreaPainter(
            points: [for (final v in history) v.toDouble()],
            line: c.quill,
            rule: c.rule,
            faint: c.inkFaint,
            peakIndex: peakIndex,
            progress: t,
          ),
        ),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({
    required this.points,
    required this.line,
    required this.rule,
    required this.faint,
    this.peakIndex,
    this.progress = 1,
  });

  final List<double> points;
  final Color line;
  final Color rule;
  final Color faint;
  final int? peakIndex;

  /// 0→1 draws the line pen-style and washes the fill in behind it.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final base = size.height - 8;
    canvas.drawLine(Offset(0, base), Offset(size.width, base),
        Paint()..color = rule..strokeWidth = 1);

    final min = points.reduce(math.min);
    final max = points.reduce(math.max);
    final range = (max - min) == 0 ? 1.0 : max - min;

    Offset at(int i) => Offset(
          size.width * i / (points.length - 1),
          base - (base - 10) * ((points[i] - min) / range) * 0.9 - 4,
        );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    // A flat quill wash under the line — the one place ink pools on paper.
    final fill = Path.from(path)
      ..lineTo(size.width, base)
      ..lineTo(0, base)
      ..close();
    canvas.drawPath(
      fill,
      Paint()..color = line.withValues(alpha: 0.10 * progress),
    );

    // The watermark: a dashed hairline ruled across the high-water mark.
    final peak = peakIndex;
    if (peak != null && peak >= 0 && peak < points.length) {
      final y = at(peak).dy;
      final mark = Paint()
        ..color = faint.withValues(alpha: 0.45 * progress)
        ..strokeWidth = 1;
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 3, size.width), y), mark);
        x += 7;
      }
    }

    // The line draws itself: clip the path to [progress] of its length.
    final drawn = Path();
    for (final metric in path.computeMetrics()) {
      drawn.addPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        Offset.zero,
      );
    }
    canvas.drawPath(
      drawn,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    if (progress >= 0.98) {
      canvas.drawCircle(at(points.length - 1), 3.4, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_AreaPainter old) =>
      old.points != points ||
      old.progress != progress ||
      old.peakIndex != peakIndex;
}
