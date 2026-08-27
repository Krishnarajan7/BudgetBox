import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/inr.dart';
import '../../../core/tokens.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/ledger_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/widgets/sheets.dart';
import '../../../data/api/endpoints/endpoints.dart';
import '../../../data/providers.dart';
import '../../../data/sync/ids.dart';
import '../folio_page.dart';
import '../folio_providers.dart';

/// Add a holding. The scheme search is the whole point: type four words of a
/// fund's name and AMFI's own file answers, so the book learns the exact
/// scheme code and can price it every night without you ever opening a
/// statement again.
Future<void> addFundSheet(BuildContext context, WidgetRef ref) async {
  final added = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => const _AddFundSheet(),
  );
  if (added ?? false) {
    ref.invalidate(folioGateProvider);
    ref.invalidate(folioSeriesProvider);
  }
}

class _AddFundSheet extends ConsumerStatefulWidget {
  const _AddFundSheet();

  @override
  ConsumerState<_AddFundSheet> createState() => _AddFundSheetState();
}

class _AddFundSheetState extends ConsumerState<_AddFundSheet> {
  final _field = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _typed(String value) {
    _debounce?.cancel();
    // AMFI is a two-second download; searching on every keystroke would
    // pull it a dozen times for one fund.
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _take({String? code, required String name}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(folioWriterProvider)
          .addFund(newUuid7(), FundIn(name: name, schemeCode: code));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final hits = ref.watch(schemeSearchProvider(_query));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.page,
          0,
          Gap.page,
          Gap.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x2),
              child: Text(
                'which fund?',
                style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
              ),
            ),
            TextField(
              controller: _field,
              autofocus: true,
              onChanged: _typed,
              style: LedgerType.bodyText.copyWith(color: c.ink),
              cursorColor: c.quill,
              decoration: InputDecoration(
                hintText: 'parag parikh flexi direct growth',
                hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                isDense: true,
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: c.rule),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: c.quill),
                ),
              ),
            ),
            const SizedBox(height: Gap.x2),
            Text(
              'Every word has to appear — add "direct" and "growth" to land '
              'on the exact plan you hold.',
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: Gap.x3),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Gap.x4),
                child: Text('adding…'),
              )
            else
              Flexible(
                child: hits.when(
                  loading: () => _query.length < 3
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: Gap.x4,
                          ),
                          child: Text(
                            'asking AMFI…',
                            style: LedgerType.label.copyWith(
                              color: c.inkFaint,
                            ),
                          ),
                        ),
                  error: (_, _) => Text(
                    'AMFI would not answer — try again in a moment.',
                    style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  ),
                  data: (rows) => ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (i, s) in rows.indexed)
                        LedgerLine(
                          title: s.label,
                          detail: 'NAV ${s.navDate}',
                          amount: '₹${s.nav.toStringAsFixed(4)}',
                          last: i == rows.length - 1 && _query.length >= 3,
                          onTap: () => _take(code: s.code, name: s.label),
                        ),
                      if (_query.length >= 3)
                        Padding(
                          padding: const EdgeInsets.only(top: Gap.x3),
                          child: Pressable(
                            onTap: () => _take(name: _field.text.trim()),
                            child: Text(
                              rows.isEmpty
                                  ? 'not a mutual fund — keep "${_field.text.trim()}" '
                                        'and price it by hand'
                                  : 'none of these — price it by hand instead',
                              style: LedgerType.bodyStrong.copyWith(
                                fontSize: 13,
                                color: c.quill,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The stamp: money crossing from a bank into a fund, or back out.
Future<void> stampSheet(
  BuildContext context,
  WidgetRef ref, {
  required Fund fund,
  required FolioEntryKind kind,
}) async {
  final amount = TextEditingController();
  final note = TextEditingController();
  final accounts = await ref.read(accountRepoProvider).watchAll().first;
  if (!context.mounted) return;
  // A SIP leaves the bank; a redemption comes back to it. Either way the
  // pocket that is not the fund is the one being picked.
  var account = accounts.isEmpty ? null : accounts.first;
  var at = DateTime.now();
  final out = kind == FolioEntryKind.redeem;

  final done = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => _Sheet(
        title: switch (kind) {
          FolioEntryKind.sip => 'SIP into ${fund.name}',
          FolioEntryKind.lumpsum => 'lump sum into ${fund.name}',
          FolioEntryKind.redeem => 'take out of ${fund.name}',
        },
        fields: [
          _Money(controller: amount),
          const SizedBox(height: Gap.x3),
          _Row(
            label: out ? 'into' : 'from',
            value: account?.name ?? 'pick a pocket',
            onTap: () async {
              final picked = await pickLedgerAccount(
                sheet,
                accounts: accounts,
                selectedId: account?.id,
              );
              if (picked != null) setSheet(() => account = picked);
            },
          ),
          _Row(
            label: 'when',
            value: folioDateWord(at),
            onTap: () async {
              final picked = await showDatePicker(
                context: sheet,
                initialDate: at,
                firstDate: DateTime(2010),
                lastDate: DateTime.now(),
              );
              if (picked != null) setSheet(() => at = picked);
            },
          ),
          if (fund.nav != null) ...[
            const SizedBox(height: Gap.x2),
            _UnitsPreview(controller: amount, nav: fund.nav!, out: out),
          ],
          const SizedBox(height: Gap.x3),
          _Plain(controller: note, hint: 'a word about it — optional'),
        ],
        confirm: out ? 'take it out' : 'stamp it in',
        onConfirm: () async {
          final rupees = int.tryParse(amount.text.trim());
          final pocket = account;
          if (rupees == null || rupees <= 0 || pocket == null) return false;
          final remote = await SyncIds(
            ref.read(dbProvider),
          ).remoteFor(SyncKinds.account, pocket.id);
          if (remote == null) return false;
          final body = FolioMoveIn(
            amountPaise: rupees * 100,
            accountId: remote,
            kind: kind,
            at: at,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
          final writer = ref.read(folioWriterProvider);
          if (out) {
            await writer.redeem(fund.id, body);
          } else {
            await writer.stamp(fund.id, body);
          }
          return true;
        },
      ),
    ),
  );
  amount.dispose();
  note.dispose();
  if (done ?? false) _refresh(ref, fund.id);
}

/// The hand-given worth, for a fund AMFI does not price.
Future<void> valueSheet(
  BuildContext context,
  WidgetRef ref, {
  required Fund fund,
}) async {
  final amount = TextEditingController(
    text: fund.valuePaise > 0 ? (fund.valuePaise / 100).round().toString() : '',
  );
  final done = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => _Sheet(
      title: 'what is ${fund.name} worth?',
      fields: [
        _Money(controller: amount),
        const SizedBox(height: Gap.x3),
        Text(
          'AMFI does not price this one, so this figure stands until you '
          'change it. ${Inr.format(fund.costPaise)} went in.',
          style: LedgerType.bodyText.copyWith(
            fontSize: 13,
            height: 1.45,
            color: LedgerColors.of(sheet).inkFaint,
          ),
        ),
      ],
      confirm: 'set it',
      onConfirm: () async {
        final rupees = int.tryParse(amount.text.trim());
        if (rupees == null || rupees <= 0) return false;
        await ref.read(folioWriterProvider).setValue(fund.id, rupees * 100);
        return true;
      },
    ),
  );
  amount.dispose();
  if (done ?? false) _refresh(ref, fund.id);
}

void _refresh(WidgetRef ref, String fundId) {
  ref.invalidate(fundProvider(fundId));
  ref.invalidate(folioGateProvider);
  ref.invalidate(folioSeriesProvider);
}

/// What the money is about to buy, live as the amount is typed. Turns an
/// abstract transfer into an act of ownership — the thing that makes a fund
/// stamp feel unlike paying a bill.
class _UnitsPreview extends StatefulWidget {
  const _UnitsPreview({
    required this.controller,
    required this.nav,
    required this.out,
  });

  final TextEditingController controller;
  final double nav;
  final bool out;

  @override
  State<_UnitsPreview> createState() => _UnitsPreviewState();
}

class _UnitsPreviewState extends State<_UnitsPreview> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final rupees = int.tryParse(widget.controller.text.trim());
    if (rupees == null || rupees <= 0) return const SizedBox.shrink();
    final units = rupees / widget.nav;
    return Text(
      '${widget.out ? 'sells' : 'buys'} ${units.toStringAsFixed(3)} units '
      'at ₹${widget.nav.toStringAsFixed(4)}',
      style: LedgerType.label.copyWith(color: c.quill),
    );
  }
}

// ————— furniture —————

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.title,
    required this.fields,
    required this.confirm,
    required this.onConfirm,
  });

  final String title;
  final List<Widget> fields;
  final String confirm;
  final Future<bool> Function() onConfirm;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _busy = false;
  String? _problem;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final ok = await widget.onConfirm();
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _problem = 'check the amount and the pocket');
    } catch (_) {
      if (mounted) setState(() => _problem = 'the server would not take it');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.page,
          0,
          Gap.page,
          Gap.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x4),
              child: Text(
                widget.title,
                style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
              ),
            ),
            ...widget.fields,
            if (_problem != null) ...[
              const SizedBox(height: Gap.x3),
              Text(_problem!, style: LedgerType.label.copyWith(color: c.seal)),
            ],
            const SizedBox(height: Gap.x4),
            Pressable(
              onTap: _busy ? null : _go,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                decoration: BoxDecoration(
                  color: c.quill,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    _busy ? 'writing…' : widget.confirm,
                    style: LedgerType.bodyStrong.copyWith(color: c.paper),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
      cursorColor: c.quill,
      decoration: InputDecoration(
        prefixText: '₹',
        prefixStyle: LedgerType.heroAmount.copyWith(
          fontSize: 32,
          color: c.inkFaint,
        ),
        hintText: '0',
        hintStyle: LedgerType.heroAmount.copyWith(
          fontSize: 32,
          color: c.inkFaint.withValues(alpha: 0.45),
        ),
        isDense: true,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.rule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill),
        ),
      ),
    );
  }
}

class _Plain extends StatelessWidget {
  const _Plain({required this.controller, required this.hint});

  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return TextField(
      controller: controller,
      style: LedgerType.bodyText.copyWith(color: c.ink),
      cursorColor: c.quill,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
        isDense: true,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.rule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        child: Row(
          children: [
            Text(label, style: LedgerType.label.copyWith(color: c.inkFaint)),
            const Spacer(),
            Text(value, style: LedgerType.bodyStrong.copyWith(color: c.ink)),
          ],
        ),
      ),
    );
  }
}
