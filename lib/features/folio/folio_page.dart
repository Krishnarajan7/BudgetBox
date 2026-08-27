import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/api/endpoints/endpoints.dart';
import 'fund_page.dart';
import 'folio_providers.dart';
import 'widgets/fund_sheets.dart';
import 'widgets/growth_chart.dart';

/// The folio. Money that left a bank and did not get spent.
///
/// It wears the ledger's paper, because it is money — but nothing on this
/// page is shaped like a spend row, because nothing here behaves like one. A
/// spend is one number and it is over. A fund is two numbers in tension, and
/// the tension is the story.
class FolioPage extends ConsumerWidget {
  const FolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(folioGateProvider);
    return ModuleScaffold(
      title: 'Folio',
      trailing: gate.value is FolioOpen
          ? Pressable(
              scale: 0.9,
              onTap: () => addFundSheet(context, ref),
              child: PenPlus(size: 18, color: LedgerColors.of(context).quill),
            )
          : null,
      child: gate.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const EmptyPage(
          line: 'The folio would not open.',
          sub: 'Step back and try again.',
        ),
        data: (g) => switch (g) {
          FolioUnwired() => const EmptyPage(
            line: 'The folio lives on the server.',
            sub: 'Wire the book to the server in Settings and what you have '
                'put away can be kept — and priced — there.',
          ),
          FolioAway() => const EmptyPage(
            line: 'The server is away.',
            sub: 'What you own is safe; it just cannot be read right now.',
          ),
          FolioOpen(overview: final o, funds: final funds) =>
            _Folio(overview: o, funds: funds),
        },
      ),
    );
  }
}

class _Folio extends ConsumerWidget {
  const _Folio({required this.overview, required this.funds});

  final FolioOverview overview;
  final List<Fund> funds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    if (funds.isEmpty) {
      return EmptyPage(
        line: 'Nothing put away yet.',
        sub: 'A SIP is not spending — the money changes shape, not owner. '
            'Add a fund and stamp what goes in.',
        action: Pressable(
          onTap: () => addFundSheet(context, ref),
          child: const LedgerChip('add a fund', selected: true),
        ),
      );
    }
    final series = ref.watch(folioSeriesProvider);
    return RefreshIndicator(
      color: c.quill,
      onRefresh: () async {
        await ref.read(folioWriterProvider).refresh().catchError((_) {});
        ref.invalidate(folioGateProvider);
        ref.invalidate(folioSeriesProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x12),
        children: [
          _Head(overview: overview),
          const SizedBox(height: Gap.x4),
          series.when(
            loading: () => const SizedBox(height: 168),
            error: (_, _) => const SizedBox(height: 0),
            data: (points) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GrowthChart(points: points),
                const SizedBox(height: Gap.x3),
                GrowthKey(up: overview.up),
              ],
            ),
          ),
          const RuleHeader('holdings'),
          for (final (i, f) in funds.indexed)
            InkIn(
              delay: Duration(milliseconds: 24 * i),
              child: _FundRow(fund: f, last: i == funds.length - 1),
            ),
          if (overview.pricedUpto != null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x4),
              child: Text(
                'priced to ${_dayWord(overview.pricedUpto!)}'
                '${overview.unpricedFunds > 0 ? ' · ${overview.unpricedFunds} valued by hand' : ''}',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

/// Two numbers, one under the other, because they are not the same thing and
/// showing only the bigger one would be the comfortable lie every investing
/// app tells.
class _Head extends StatelessWidget {
  const _Head({required this.overview});

  final FolioOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final o = overview;
    final tone = o.up ? c.jama : c.seal;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroAmount(
            caption: 'worth to-day',
            amount: Inr.format(o.valuePaise),
            sub: Row(
              children: [
                Text(
                  '${o.up ? '+' : '−'}${Inr.format(o.gainPaise.abs())}',
                  style: LedgerType.amountTotal.copyWith(color: tone),
                ),
                if (o.returnRatio != null) ...[
                  const SizedBox(width: Gap.x2),
                  Text(
                    '${o.up ? '+' : '−'}'
                    '${(o.returnRatio!.abs() * 100).toStringAsFixed(1)}%',
                    style: LedgerType.label.copyWith(color: tone),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Gap.x3),
          Text(
            '${Inr.format(o.costPaise)} put in'
            '${o.monthPaise > 0 ? ' · ${Inr.format(o.monthPaise)} this month' : ''}',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// A holding's row. Not a ledger line: a spend row ends in one figure, and
/// this one has to carry worth, gain and the units behind both.
class _FundRow extends StatelessWidget {
  const _FundRow({required this.fund, required this.last});

  final Fund fund;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final f = fund;
    final tone = f.up ? c.jama : c.seal;
    return Pressable(
      scale: 0.99,
      onTap: () => Navigator.of(context).push(
        LedgerRoute<void>(builder: (_) => FundPage(fundId: f.id)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: c.rule, width: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    f.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LedgerType.bodyStrong.copyWith(color: c.ink),
                  ),
                ),
                const SizedBox(width: Gap.x3),
                Text(
                  Inr.format(f.valuePaise),
                  style: LedgerType.amountTotal.copyWith(color: c.ink),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _left(f),
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
                ),
                Text(
                  '${f.up ? '+' : '−'}${Inr.format(f.gainPaise.abs())}'
                  '${f.returnRatio == null ? '' : '  ${f.up ? '+' : '−'}${(f.returnRatio!.abs() * 100).toStringAsFixed(1)}%'}',
                  style: LedgerType.amount.copyWith(fontSize: 12, color: tone),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // The gain as a length, not just a figure: how far the worth bar
            // runs past what was put in.
            _GainBar(fund: f, tone: tone, rule: c.rule),
          ],
        ),
      ),
    );
  }

  static String _left(Fund f) {
    final bits = <String>['${Inr.format(f.costPaise)} in'];
    if (f.units > 0) bits.add('${f.units.toStringAsFixed(3)} units');
    if (!f.priced) bits.add('by hand');
    return bits.join(' · ');
  }
}

/// Cost fills the bar; worth overshoots it (or falls short). One glance says
/// whether this holding is ahead, without reading a number.
class _GainBar extends StatelessWidget {
  const _GainBar({required this.fund, required this.tone, required this.rule});

  final Fund fund;
  final Color tone;
  final Color rule;

  @override
  Widget build(BuildContext context) {
    final f = fund;
    final top = f.valuePaise > f.costPaise ? f.valuePaise : f.costPaise;
    if (top <= 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: 3,
        child: Stack(
          children: [
            Container(
              width: box.maxWidth * (f.costPaise / top),
              decoration: BoxDecoration(
                color: rule,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            Container(
              width: box.maxWidth * (f.valuePaise / top),
              height: 3,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _dayWord(String yyyyMMdd) {
  final d = DateTime.parse(yyyyMMdd);
  return LedgerDates.ddMmm(d);
}

/// Shared with the fund page.
String folioDateWord(DateTime d) => '${LedgerDates.ddMmm(d)} ${d.year}';
