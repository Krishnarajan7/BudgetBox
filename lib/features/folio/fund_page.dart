import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../data/api/endpoints/endpoints.dart';
import 'folio_page.dart';
import 'folio_providers.dart';
import 'widgets/fund_sheets.dart';

/// One holding: what it is worth, what it cost, and every stamp that built it.
class FundPage extends ConsumerWidget {
  const FundPage({super.key, required this.fundId});

  final String fundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(fundProvider(fundId));
    return ModuleScaffold(
      title: view.value?.$1.name ?? 'Fund',
      child: view.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const EmptyPage(
          line: 'This fund would not open.',
          sub: 'Step back and try again.',
        ),
        data: (d) => _Fund(fund: d.$1, entries: d.$2),
      ),
    );
  }
}

class _Fund extends ConsumerWidget {
  const _Fund({required this.fund, required this.entries});

  final Fund fund;
  final List<FolioEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final f = fund;
    final tone = f.up ? c.jama : c.seal;
    return RefreshIndicator(
      color: c.quill,
      onRefresh: () async => ref.invalidate(fundProvider(f.id)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x12),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Gap.x4),
            child: HeroAmount(
              caption: 'worth to-day',
              amount: Inr.format(f.valuePaise),
              sub: Text(
                '${f.up ? '+' : '−'}${Inr.format(f.gainPaise.abs())}'
                '${f.returnRatio == null ? '' : '  ${f.up ? '+' : '−'}${(f.returnRatio!.abs() * 100).toStringAsFixed(1)}%'}',
                style: LedgerType.amountTotal.copyWith(color: tone),
              ),
            ),
          ),
          const SizedBox(height: Gap.x4),
          _Facts(fund: f),
          const SizedBox(height: Gap.x4),
          Wrap(
            spacing: Gap.x2,
            runSpacing: Gap.x2,
            children: [
              Pressable(
                onTap: () => stampSheet(
                  context,
                  ref,
                  fund: f,
                  kind: FolioEntryKind.sip,
                ),
                child: const LedgerChip('stamp a SIP', selected: true),
              ),
              Pressable(
                onTap: () => stampSheet(
                  context,
                  ref,
                  fund: f,
                  kind: FolioEntryKind.lumpsum,
                ),
                child: const LedgerChip('lump sum'),
              ),
              if (f.units > 0 || f.valuePaise > 0)
                Pressable(
                  onTap: () => stampSheet(
                    context,
                    ref,
                    fund: f,
                    kind: FolioEntryKind.redeem,
                  ),
                  child: const LedgerChip('take some out'),
                ),
              if (!f.priced)
                Pressable(
                  onTap: () => valueSheet(context, ref, fund: f),
                  child: const LedgerChip('set its worth'),
                ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            const RuleHeader('what went in'),
            for (final (i, e) in entries.indexed)
              InkIn(
                delay: Duration(milliseconds: 20 * i),
                child: _EntryLine(entry: e, last: i == entries.length - 1),
              ),
          ],
        ],
      ),
    );
  }
}

/// The facts a spend row never has: units held, the price they are marked at,
/// and how much of this was built by the monthly habit.
class _Facts extends StatelessWidget {
  const _Facts({required this.fund});

  final Fund fund;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final f = fund;
    return LedgerCard(
      child: Column(
        children: [
          const SizedBox(height: Gap.x3),
          _Fact(label: 'put in', value: Inr.format(f.costPaise)),
          if (f.units > 0)
            _Fact(label: 'units', value: f.units.toStringAsFixed(5)),
          if (f.nav != null)
            _Fact(
              label: 'NAV',
              value: '₹${f.nav!.toStringAsFixed(4)}'
                  '${f.navDate == null ? '' : ' · ${f.navDate}'}',
            ),
          if (f.sipCount > 0)
            _Fact(
              label: 'by SIP',
              value: '${Inr.format(f.sipPaise)} over ${f.sipCount}',
            ),
          if (!f.priced)
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Text(
                'AMFI does not price this one — its worth is whatever you '
                'last set.',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(label, style: LedgerType.label.copyWith(color: c.inkFaint)),
          const Spacer(),
          Text(value, style: LedgerType.amount.copyWith(color: c.ink)),
        ],
      ),
    );
  }
}

class _EntryLine extends StatelessWidget {
  const _EntryLine({required this.entry, required this.last});

  final FolioEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final e = entry;
    final out = e.kind == FolioEntryKind.redeem;
    return LedgerLine(
      leading: folioDateWord(e.at),
      title: switch (e.kind) {
        FolioEntryKind.sip => 'SIP',
        FolioEntryKind.lumpsum => 'lump sum',
        FolioEntryKind.redeem => 'taken out',
      },
      // The units are the point: this is what the money actually bought.
      detail: e.units == null
          ? e.note
          : '${e.units!.toStringAsFixed(3)} units'
                '${e.nav == null ? '' : ' @ ₹${e.nav!.toStringAsFixed(4)}'}',
      amount: '${out ? '−' : '+'}${Inr.format(e.amountPaise)}',
      amountColor: out ? c.warn : c.ink,
      last: last,
    );
  }
}
