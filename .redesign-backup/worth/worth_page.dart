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
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/goal_repo.dart';
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
    WorthRange.fy => now.difference(LedgerDates.fyStart(now)).inDays + 1,
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
                  sub:
                      'Add an account in the box and this page '
                      'starts keeping count.',
                  action: Pressable(
                    onTap: () => Navigator.of(context).push(
                      LedgerRoute<void>(
                        builder: (_) => const _WorthSetupPage(existing: []),
                      ),
                    ),
                    child: Text(
                      'set up what you have ›',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 13,
                        color: c.quill,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final assets = all
            .where((a) => a.kind != AccountKind.liability)
            .toList();
        final owed = all.where((a) => a.kind == AccountKind.liability).toList();
        final assetTotal = assets.fold<int>(0, (s, a) => s + a.balancePaise);
        final owedTotal = owed.fold<int>(0, (s, a) => s + a.balancePaise);
        final net = assetTotal - owedTotal;

        // Each account keeps its ink for as long as it sits on the shelf —
        // colour follows the entity, never this month's ranking. Beyond the
        // four inks in the drawer, the book files the rest in rule grey.
        Color inkFor(int i) => i < c.chartInks.length ? c.chartInks[i] : c.rule;

        _ensureHistory(net);

        final fetched = _history;
        final history = (fetched == null || fetched.isEmpty)
            ? <int>[net]
            : fetched;
        final delta = net - history.first;

        // A young book has one reading — an empty 80px chart and range
        // chips that do nothing are dead paper. The line and its chips
        // appear only once there are two mornings to join.
        final hasLine = history.length > 1;

        // The high-water mark, and roughly when it was set: the series is one
        // reading per day, ending to-day.
        var peakIndex = 0;
        for (var i = 1; i < history.length; i++) {
          if (history[i] > history[peakIndex]) peakIndex = i;
        }
        final peak = history[peakIndex];
        final belowPeak = peak - net >= 100 && history.length > 2;
        final peakOn = now.subtract(
          Duration(days: history.length - 1 - peakIndex),
        );

        return ListView(
          // Room for the floating glass bar: the page scrolls under it,
          // but its last line must still be able to rise above it.
          padding: EdgeInsets.fromLTRB(
            Gap.page,
            0,
            Gap.page,
            MediaQuery.paddingOf(context).bottom + Gap.x4,
          ),
          children: [
            LedgerAppBar(
              title: 'Worth',
              trailing: Pressable(
                onTap: () => Navigator.of(
                  context,
                ).push(LedgerRoute<void>(builder: (_) => const StoryPage())),
                child: Text(
                  // The finished story belongs to a finished month; until
                  // then the door says exactly what it opens onto.
                  now.day == LedgerDates.daysInMonth(now)
                      ? 'the month\'s story ›'
                      : 'the month, so far ›',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: c.quill,
                  ),
                ),
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
                  TextSpan(
                    children: [
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
                        text: hasLine
                            ? ' ${_range.phrase(now)}'
                            : ' — first reading taken to-day',
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // The reading everything counts from: until the shelf holds
            // real declared money, Worth leads with its own setup ritual
            // instead of a negative number and a shrug.
            if (assetTotal <= 0 || all.length <= 1)
              LedgerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const RuleHeader('start here'),
                    const SizedBox(height: Gap.x2),
                    Text(
                      'Tell the book what you actually have — cash in hand, '
                      'each bank, GPay/PhonePe, anything kept aside. To-day '
                      'becomes the reading everything counts from; spending '
                      'already written for older days won\'t touch it.',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 13,
                        color: c.inkFaint,
                      ),
                    ),
                    const SizedBox(height: Gap.x3),
                    Pressable(
                      onTap: () => Navigator.of(context).push(
                        LedgerRoute<void>(
                          builder: (_) => _WorthSetupPage(existing: all),
                        ),
                      ),
                      child: Text(
                        'set up what you have ›',
                        style: LedgerType.bodyStrong.copyWith(
                          fontSize: 14,
                          color: c.quill,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Gap.x3),
            if (!hasLine)
              Text(
                'the book takes one reading a day — the line below begins '
                'when there are mornings to join',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              )
            else ...[
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
              Row(
                children: [
                  Text(
                    LedgerDates.ddMmm(
                      now.subtract(Duration(days: history.length - 1)),
                    ),
                    style: LedgerType.amount.copyWith(
                      fontSize: 9,
                      color: c.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'to-day',
                    style: LedgerType.amount.copyWith(
                      fontSize: 9,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            ],
            if (belowPeak) ...[
              const SizedBox(height: 6),
              Text(
                'highest it\'s ever been was ${Inr.compact(peak)}, '
                '${LedgerDates.ddMmm(peakOn)}',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ],
            LedgerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RuleHeader(
                    'assets',
                    trailing: Text(
                      Inr.compact(assetTotal),
                      style: LedgerType.amount.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                  if (assetTotal > 0) ...[
                    const SizedBox(height: Gap.x3),
                    // Where it sits: one strip, each account's share in its
                    // own ink — the rows beneath are the legend. One account
                    // still gets its full-width stroke of ink: the shelf is
                    // small, not colourless.
                    _CompositionStrip(
                      parts: [
                        for (final (i, a) in assets.indexed)
                          (a.balancePaise, inkFor(i)),
                      ],
                    ),
                    const SizedBox(height: Gap.x1),
                  ] else if (assets.isNotEmpty) ...[
                    const SizedBox(height: Gap.x2),
                    Text(
                      'below zero usually means an opening balance was '
                      'never set — tap the line and stamp what\'s true',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                  for (final (i, a) in assets.indexed)
                    InkIn(
                      delay: Duration(milliseconds: 45 * i),
                      child: _AccountRow(
                        account: a,
                        ink: assetTotal > 0 ? inkFor(i) : null,
                        stagger: i,
                        last: i == assets.length - 1,
                      ),
                    ),
                ],
              ),
            ),
            if (owed.isNotEmpty)
              LedgerCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RuleHeader(
                      'owed',
                      trailing: Text(
                        '− ${Inr.compact(owedTotal)}',
                        style: LedgerType.amount.copyWith(
                          fontSize: 12,
                          color: c.inkFaint,
                        ),
                      ),
                    ),
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
                ),
              ),
            const _GoalsCard(),
            const SizedBox(height: Gap.x6),
          ],
        );
      },
    );
  }
}

/// One strip, every asset's share laid end to end in its own ink, a 2px
/// breath of the card between neighbours. It draws itself in left to right
/// like everything the pen puts down.
class _CompositionStrip extends StatelessWidget {
  const _CompositionStrip({required this.parts});

  /// (paise, ink) per account, in shelf order.
  final List<(int, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<int>(0, (s, p) => s + p.$1);
    if (total <= 0) return const SizedBox.shrink();
    final visible = parts.where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 12,
        child: DrawIn(
          duration: const Duration(milliseconds: 550),
          builder: (context, t) => ClipRect(
            clipper: _RevealClipper(t),
            child: Row(
              children: [
                for (final (i, p) in visible.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: p.$1,
                    child: ColoredBox(color: p.$2),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every unfinished goal, each with the stroke it has earned so far — what
/// the worth is being built toward, not just what it is.
class _GoalsCard extends ConsumerWidget {
  const _GoalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<GoalView>>(
      stream: ref.watch(goalRepoProvider).watchViews(),
      builder: (context, snap) {
        final goals = (snap.data ?? const <GoalView>[])
            .where((g) => !g.reached)
            .toList();
        if (goals.isEmpty) {
          // Nothing while still loading; once the answer is truly "no
          // goals", the card stays and says so — a vanished module reads
          // as a bug, an invitation reads as a page with plans for itself.
          if (!snap.hasData) return const SizedBox.shrink();
          return LedgerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RuleHeader('being built'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                  child: Text(
                    'nothing being built yet — a goal in plans gives '
                    'this page a direction',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final put = goals.fold<int>(0, (s, g) => s + g.donePaise);
        return LedgerCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RuleHeader(
                'being built',
                trailing: Text(
                  '${Inr.compact(put)} put away',
                  style: LedgerType.amount.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x2),
              for (final (i, g) in goals.indexed)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == goals.length - 1 ? 0 : Gap.x3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              g.goal.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LedgerType.bodyText.copyWith(
                                fontSize: 14,
                                color: c.ink,
                              ),
                            ),
                          ),
                          Text(
                            '${Inr.compact(g.donePaise)} of '
                            '${Inr.compact(g.goal.targetPaise)}',
                            style: LedgerType.amount.copyWith(
                              fontSize: 12,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      DrawIn(
                        builder: (context, p) => SizedBox(
                          height: 6,
                          child: Row(
                            children: [
                              Expanded(
                                flex:
                                    ((g.fraction * p).clamp(0.004, 1.0) * 1000)
                                        .round(),
                                child: ColoredBox(color: c.quill),
                              ),
                              Expanded(
                                flex:
                                    1000 -
                                    ((g.fraction * p).clamp(0.004, 1.0) * 1000)
                                        .round(),
                                child: ColoredBox(
                                  color: c.rule.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({
    required this.account,
    this.ink,
    this.negative = false,
    this.last = false,
    this.stagger = 0,
  });

  final Account account;

  /// The account's ink from the drawer — the swatch that ties its row to
  /// its share of the strip above. Null when there is nothing to tie to.
  final Color? ink;
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
            if (ink != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: Gap.x2),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LedgerType.bodyText.copyWith(color: c.ink),
                        ),
                      ),
                      // A holding wears its protection on the row: daily
                      // spending never sees this line.
                      if (account.keptAside) ...[
                        const SizedBox(width: Gap.x2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: c.rule),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'kept aside',
                            style: LedgerType.label.copyWith(
                              fontSize: 9,
                              color: c.inkFaint,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    stale ? '$asOf — update?' : asOf,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: stale ? c.warn : c.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            _SparkReveal(
              delayMs: 60 * stagger,
              child: FutureBuilder<List<double>>(
                key: ValueKey('spark-${account.id}-${account.balancePaise}'),
                future: ref.read(accountRepoProvider).spark(account.id),
                builder: (context, spark) =>
                    Sparkline(spark.data ?? const [1, 1]),
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
  Future<void> _historySheet(BuildContext context, WidgetRef ref, String asOf) {
    final points = ref
        .read(accountRepoProvider)
        .balanceReadings(account.id, points: 30);
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
              Text(
                account.name,
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 2),
              Text(
                asOf,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x4),
              FutureBuilder<List<double>>(
                future: points,
                builder: (context, snap) {
                  final data = snap.data ?? const <double>[];
                  final readings = data.length;
                  final moved = readings > 1 && data.toSet().length > 1;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (moved) ...[
                        LayoutBuilder(
                          builder: (context, box) => DrawIn(
                            builder: (context, t) => ClipRect(
                              clipper: _RevealClipper(t),
                              child: Sparkline(
                                data,
                                width: box.maxWidth,
                                height: 96,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Gap.x3),
                        Container(height: 1, color: c.rule),
                        const SizedBox(height: Gap.x3),
                      ],
                      if (readings < 2)
                        Text(
                          'One reading so far — ${Inr.format(account.balancePaise)}. '
                          'The line begins after the balance changes.',
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            color: c.inkFaint,
                          ),
                        )
                      else if (!moved)
                        Text(
                          'No movement across $readings readings — '
                          '${Inr.format(data.first.round())} each time.',
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            color: c.inkFaint,
                          ),
                        )
                      else
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text:
                                    'low ${Inr.format(data.reduce(math.min).round())}'
                                    '  ·  high ${Inr.format(data.reduce(math.max).round())}',
                                style: LedgerType.amount.copyWith(
                                  fontSize: 12,
                                  color: c.ink,
                                ),
                              ),
                              TextSpan(
                                text: '  ·  $readings readings',
                                style: LedgerType.bodyText.copyWith(
                                  fontSize: 12,
                                  color: c.inkFaint,
                                ),
                              ),
                            ],
                          ),
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
    // The sheet hands back paise, already resolved under whichever meaning
    // of the typed figure was chosen ("in it now" vs "before the spending").
    final paise = await showLedgerSheet<int>(
      context,
      builder: (context) => _CorrectBalanceSheet(account: account),
    );
    if (paise != null) {
      await ref.read(accountRepoProvider).setBalance(account.id, paise);
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
    text: (widget.account.balancePaise ~/ 100).toString(),
  );
  bool _stamping = false;

  /// True when the typed figure means "what I HAD, before the spending the
  /// book already holds" — the number every fresh book actually knows. The
  /// recorded spending is then taken out of it, instead of being erased by
  /// a flat overwrite. Offered only while the balance sits below zero,
  /// because that is exactly the sign of spending with no money behind it.
  bool _beforeSpending = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// The typed figure in paise — paise included. A balance is the one
  /// number in this book that is copied off a bank screen digit for digit,
  /// so ₹1,58,097.45 has to survive being typed.
  int? get _typedPaise => Inr.parsePaise(_field.text);

  /// What the account will actually read, in paise, under the chosen
  /// meaning of the typed figure.
  int? get _resultPaise {
    final typed = _typedPaise;
    if (typed == null) return null;
    return _beforeSpending ? typed + widget.account.balancePaise : typed;
  }

  void _stamp() {
    if (_stamping || _resultPaise == null) return;
    FocusScope.of(context).unfocus();
    setState(() => _stamping = true);
  }

  void _landed() {
    // The seal has pressed down; hand the figure back to the page.
    Future<void>.delayed(const Duration(milliseconds: 240), () {
      if (mounted) Navigator.of(context).pop(_resultPaise);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final owes = widget.account.balancePaise < 0;
    final result = _resultPaise;
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
          Text(
            '${widget.account.name} — set the balance',
            style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: Gap.x2),
          TextField(
            controller: _field,
            autofocus: true,
            enabled: !_stamping,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            // The point has to be typeable — and only one of it.
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]')),
              TextInputFormatter.withFunction((old, fresh) {
                final dots = '.'.allMatches(fresh.text).length;
                return dots > 1 ? old : fresh;
              }),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _stamp(),
            style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
            decoration: InputDecoration(
              prefixText: '₹',
              prefixStyle: LedgerType.heroAmount.copyWith(
                fontSize: 32,
                color: c.inkFaint,
              ),
              border: InputBorder.none,
            ),
          ),
          if (owes) ...[
            const SizedBox(height: Gap.x2),
            // The number below zero is spending the book saw with no money
            // behind it. The typed figure can mean two things — say which.
            Wrap(
              spacing: Gap.x2,
              runSpacing: Gap.x2,
              children: [
                LedgerChip(
                  'what\'s in it right now',
                  selected: !_beforeSpending,
                  onTap: () => setState(() => _beforeSpending = false),
                ),
                LedgerChip(
                  'what I had before the spending',
                  selected: _beforeSpending,
                  onTap: () => setState(() => _beforeSpending = true),
                ),
              ],
            ),
          ],
          const SizedBox(height: Gap.x2),
          // The preview is the explanation: no guessing what the stamp does.
          AnimatedSwitcher(
            duration: Motion.quick,
            child: Text(
              result == null
                  ? 'type the amount'
                  : _beforeSpending
                  ? '${widget.account.name} will read '
                        '${Inr.format(result)} — the '
                        '${Inr.format(-widget.account.balancePaise)} '
                        'already written comes out of it'
                  : '${widget.account.name} will read '
                        '${Inr.format(result)}',
              key: ValueKey('$result-$_beforeSpending'),
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
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
                    onTap: _resultPaise == null ? null : _stamp,
                    child: AbsorbPointer(
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _resultPaise == null ? null : () {},
                          child: const Text('That\'s the number'),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_stamping)
                  IgnorePointer(child: StampIn(size: 34, onStamped: _landed)),
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
    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = rule
        ..strokeWidth = 1,
    );

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
          Offset(x, y),
          Offset(math.min(x + 3, size.width), y),
          mark,
        );
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

/// The Worth setup: one full screen, plain questions — how much, and where it
/// sits. Each filled line becomes (or re-reads) an account anchored to
/// to-day, so the anchor rule in the ledger keeps every already-written
/// past day from draining what was just counted.
class _WorthSetupPage extends ConsumerStatefulWidget {
  const _WorthSetupPage({required this.existing});

  final List<Account> existing;

  @override
  ConsumerState<_WorthSetupPage> createState() => _WorthSetupPageState();
}

class _WorthSetupPageState extends ConsumerState<_WorthSetupPage> {
  final _cash = TextEditingController();
  final _upi = TextEditingController();
  final _sip = TextEditingController();
  final _emergency = TextEditingController();
  final _bankNames = <TextEditingController>[TextEditingController()];
  final _bankAmounts = <TextEditingController>[TextEditingController()];
  bool _saving = false;

  @override
  void dispose() {
    _cash.dispose();
    _upi.dispose();
    _sip.dispose();
    _emergency.dispose();
    for (final c in [..._bankNames, ..._bankAmounts]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _paiseOf(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v < 0) return null;
    return (v * 100).round();
  }

  /// Creates the account, or re-reads an existing one by name — either way
  /// the balance is a declared reading anchored to now.
  Future<void> _declare(String name, AccountKind kind, int paise) async {
    final repo = ref.read(accountRepoProvider);
    final match = widget.existing
        .where((a) => a.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (match != null) {
      await repo.setBalance(match.id, paise);
    } else {
      await repo.create(name: name, kind: kind, openingBalancePaise: paise);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    final cash = _paiseOf(_cash);
    if (cash != null) await _declare('Cash', AccountKind.cash, cash);
    final upi = _paiseOf(_upi);
    if (upi != null) await _declare('GPay / PhonePe', AccountKind.upi, upi);
    for (var i = 0; i < _bankNames.length; i++) {
      final name = _bankNames[i].text.trim();
      final paise = _paiseOf(_bankAmounts[i]);
      if (name.isNotEmpty && paise != null) {
        await _declare(name, AccountKind.bank, paise);
      }
    }
    final sip = _paiseOf(_sip);
    if (sip != null) {
      await _declare('SIP / mutual funds', AccountKind.asset, sip);
    }
    final emergency = _paiseOf(_emergency);
    if (emergency != null) {
      await _declare('Emergency fund', AccountKind.asset, emergency);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _moneyRow(
    LedgerColors c,
    String label,
    TextEditingController ctrl, {
    String? sub,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: LedgerType.bodyText.copyWith(color: c.ink)),
                if (sub != null)
                  Text(
                    sub,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              onChanged: (_) => setState(() {}),
              style: LedgerType.amount.copyWith(fontSize: 16, color: c.ink),
              cursorColor: c.quill,
              decoration: InputDecoration(
                prefixText: '₹',
                prefixStyle: LedgerType.amount.copyWith(
                  fontSize: 16,
                  color: c.inkFaint,
                ),
                hintText: '0',
                hintStyle: LedgerType.amount.copyWith(
                  fontSize: 16,
                  color: c.inkFaint.withValues(alpha: 0.45),
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final anything =
        _paiseOf(_cash) != null ||
        _paiseOf(_upi) != null ||
        _paiseOf(_sip) != null ||
        _paiseOf(_emergency) != null ||
        [
          for (var i = 0; i < _bankNames.length; i++)
            if (_bankNames[i].text.trim().isNotEmpty &&
                _paiseOf(_bankAmounts[i]) != null)
              true,
        ].isNotEmpty;
    return ModuleScaffold(
      title: 'What I have',
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.page,
          0,
          Gap.page,
          MediaQuery.of(context).viewInsets.bottom + Gap.x8,
        ),
        children: [
          const SizedBox(height: Gap.x3),
          Text(
            'What do you have right now?',
            style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'Count it as it stands to-day. To-day becomes the reading '
            'everything counts from — spending already written for older '
            'days won\'t touch these numbers. Leave blank whatever you '
            'don\'t have; blank writes nothing.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
          const RuleHeader('in hand'),
          const SizedBox(height: Gap.x2),
          _moneyRow(c, 'Cash in hand', _cash),
          _moneyRow(c, 'GPay / PhonePe', _upi),
          const RuleHeader('banks'),
          const SizedBox(height: Gap.x2),
          for (var i = 0; i < _bankNames.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.x3),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _bankNames[i],
                      onChanged: (_) => setState(() {}),
                      style: LedgerType.bodyText.copyWith(color: c.ink),
                      cursorColor: c.quill,
                      decoration: InputDecoration(
                        hintText: 'bank name (SBI, HDFC…)',
                        hintStyle: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint.withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _bankAmounts[i],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      onChanged: (_) => setState(() {}),
                      style: LedgerType.amount.copyWith(
                        fontSize: 16,
                        color: c.ink,
                      ),
                      cursorColor: c.quill,
                      decoration: InputDecoration(
                        prefixText: '₹',
                        prefixStyle: LedgerType.amount.copyWith(
                          fontSize: 16,
                          color: c.inkFaint,
                        ),
                        hintText: '0',
                        hintStyle: LedgerType.amount.copyWith(
                          fontSize: 16,
                          color: c.inkFaint.withValues(alpha: 0.45),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_bankNames.length < 4)
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: () => setState(() {
                  _bankNames.add(TextEditingController());
                  _bankAmounts.add(TextEditingController());
                }),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gap.x3),
                  child: Text(
                    '+ another bank',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 12,
                      color: c.quill,
                    ),
                  ),
                ),
              ),
            ),
          const RuleHeader('kept aside'),
          const SizedBox(height: Gap.x2),
          _moneyRow(
            c,
            'SIP / mutual funds',
            _sip,
            sub: 'kept aside — daily spending never touches it',
          ),
          _moneyRow(
            c,
            'Emergency fund',
            _emergency,
            sub: 'kept aside — daily spending never touches it',
          ),
          const SizedBox(height: Gap.x2),
          FilledButton(
            onPressed: anything && !_saving ? _save : null,
            child: const Text('That\'s what I have'),
          ),
        ],
      ),
    );
  }
}
