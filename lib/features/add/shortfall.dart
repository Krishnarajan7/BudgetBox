/// The moment the book notices you are spending money you do not have.
///
/// Cash says ₹50 and the entry says ₹80. The old behaviour wrote −₹30 onto
/// the Worth screen and said nothing, which is the one number on that page
/// that is never true: nobody has minus thirty rupees in their pocket. The
/// figure is a symptom, and there are only three things it can mean —
///
/// * it was paid from somewhere else (the usual one: the hand reached for
///   the phone, not the wallet),
/// * cash was topped up first and the book was not told, or
/// * the cash figure itself was stale.
///
/// Each of those has a *true* entry behind it, and this sheet's only job is
/// to find out which, then write that entry as well. What it will not do is
/// invent one: the last line is still "write it as it stands", because a book
/// that refuses to record something that really happened is worse than a
/// book with an awkward number in it.
library;

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';


/// What the answer was. Each variant carries everything needed to act on it.
sealed class ShortfallAnswer {
  const ShortfallAnswer();
}

/// It came out of a different pocket. The entry moves, wholesale.
class PaidFrom extends ShortfallAnswer {
  const PaidFrom(this.accountId);

  final int accountId;
}

/// The pocket was refilled first. A real transfer of exactly the shortfall
/// goes in ahead of the entry, which leaves the pocket at precisely zero —
/// the honest version of "the cash should be 0".
class ToppedUpFrom extends ShortfallAnswer {
  const ToppedUpFrom(this.accountId);

  final int accountId;
}

/// The reading was stale. The true figure is stamped first, and every entry
/// already written for an older day stays where it is.
class FigureWasWrong extends ShortfallAnswer {
  const FigureWasWrong(this.balancePaise);

  final int balancePaise;
}

/// Write it as it stands. An overdraft can be real — this is the door out,
/// deliberately the quietest one on the sheet.
class WriteAnyway extends ShortfallAnswer {
  const WriteAnyway();
}

/// Checks whether [amountPaise] against [accountId] would overdraw the pocket
/// and, if it would, asks what actually happened and carries out the answer.
///
/// Returns the account the entry should now be written against, or null when
/// the answer was to write nothing at all (the sheet was dismissed). Callers
/// need one line: `final id = await settleShortfall(...); if (id == null)
/// return;` — everything else is done by the time it returns.
Future<int?> settleShortfall(
  BuildContext context,
  WidgetRef ref, {
  required int accountId,
  required int amountPaise,
  DateTime? at,
}) async {
  final accounts = ref.read(accountRepoProvider);
  final short = await accounts.shortfall(
    accountId: accountId,
    amountPaise: amountPaise,
    at: at,
  );
  if (short == null) return accountId;
  if (!context.mounted) return null;

  HapticFeedback.mediumImpact();
  final answer = await showLedgerSheet<ShortfallAnswer>(
    context,
    builder: (_) => _ShortfallSheet(
      account: short.account,
      amountPaise: amountPaise,
      shortPaise: short.shortPaise,
    ),
  );

  switch (answer) {
    case null:
      return null;
    case WriteAnyway():
      return accountId;
    case PaidFrom(:final accountId):
      return accountId;
    case FigureWasWrong(:final balancePaise):
      await accounts.setBalance(short.account.id, balancePaise);
      return accountId;
    case ToppedUpFrom(:final accountId):
      // Exactly the shortfall, so the pocket lands on zero rather than on
      // some rounder number nobody moved. Dated *now* even when the entry
      // itself is backdated: the top-up is the thing that has to sit on the
      // near side of the anchor for the arithmetic to come out.
      await ref
          .read(txnRepoProvider)
          .addTransfer(
            amountPaise: short.shortPaise,
            fromAccountId: accountId,
            toAccountId: short.account.id,
            title: 'Topped up ${short.account.name}',
          );
      return short.account.id;
  }
}

class _ShortfallSheet extends ConsumerStatefulWidget {
  const _ShortfallSheet({
    required this.account,
    required this.amountPaise,
    required this.shortPaise,
  });

  final Account account;
  final int amountPaise;
  final int shortPaise;

  @override
  ConsumerState<_ShortfallSheet> createState() => _ShortfallSheetState();
}

class _ShortfallSheetState extends ConsumerState<_ShortfallSheet> {
  final _figure = TextEditingController();

  List<Account> _others = const [];

  /// Which of the three questions is open. Null while the sheet is still
  /// asking the first one — what happened — rather than the second.
  _Route? _route;

  @override
  void initState() {
    super.initState();
    _figure.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    // A one-shot read, not `watchAll().first`: a stream's first event stalls
    // under widget-test fake async, and this sheet has no use for updates
    // arriving mid-question anyway.
    final db = ref.read(dbProvider);
    final rows = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
        .get();
    if (!mounted) return;
    setState(() {
      _others = [
        for (final a in rows)
          if (a.id != widget.account.id &&
              a.kind != AccountKind.liability &&
              !a.keptAside)
            a,
      ];
    });
  }

  @override
  void dispose() {
    _figure.dispose();
    super.dispose();
  }

  int? get _typedPaise {
    final text = _figure.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value.isNegative) return null;
    return (value * 100).round();
  }

  void _answer(ShortfallAnswer answer) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final held = widget.account.balancePaise;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'more than the pocket holds',
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: 6),
            // The whole problem in one line, in figures, before any choice
            // is offered — the sheet explains itself before it asks.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: widget.account.name,
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 16,
                      color: c.ink,
                    ),
                  ),
                  TextSpan(
                    text: ' holds ${Inr.format(held)}. '
                        'This is ${Inr.format(widget.amountPaise)}.',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 16,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'So ${Inr.format(widget.shortPaise)} of it came from '
              'somewhere. Where?',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x4),
            AnimatedSize(
              duration: Motion.reduced(context)
                  ? Duration.zero
                  : Motion.quick,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: switch (_route) {
                null => _chooser(c),
                _Route.paidFrom => _pockets(
                  c,
                  lead: 'which pocket paid?',
                  onPick: (id) => _answer(PaidFrom(id)),
                ),
                _Route.toppedUp => _pockets(
                  c,
                  lead: 'topped up from where?',
                  note:
                      'A transfer of ${Inr.format(widget.shortPaise)} goes in '
                      'first, so ${widget.account.name} ends at '
                      '${Inr.format(0)}.',
                  onPick: (id) => _answer(ToppedUpFrom(id)),
                ),
                _Route.wrongFigure => _correction(c),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chooser(LedgerColors c) {
    return Column(
      key: const ValueKey('chooser'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ordered by how often each is the true answer, not by how tidy it
        // is: the phone comes out more often than the wallet gets refilled.
        if (_others.isNotEmpty) ...[
          _Choice(
            key: const ValueKey('shortfall-paid-from'),
            label: 'it was paid from another pocket',
            detail: 'the entry moves there whole — this one is untouched',
            onTap: () => setState(() => _route = _Route.paidFrom),
          ),
          _Choice(
            key: const ValueKey('shortfall-topped-up'),
            label: 'I topped ${widget.account.name} up first',
            detail:
                '${Inr.format(widget.shortPaise)} moves in, then this goes '
                'out — it ends at zero',
            onTap: () => setState(() => _route = _Route.toppedUp),
          ),
        ],
        _Choice(
          key: const ValueKey('shortfall-wrong-figure'),
          label: 'the ${widget.account.name} figure was stale',
          detail: 'stamp what was really in it, then write this',
          onTap: () => setState(() => _route = _Route.wrongFigure),
        ),
        const SizedBox(height: Gap.x3),
        // The escape. Overdrafts happen; a book that cannot write one down
        // is lying in the other direction.
        Pressable(
          key: const ValueKey('shortfall-anyway'),
          onTap: () => _answer(const WriteAnyway()),
          child: Text(
            'none of these — write it as it stands',
            textAlign: TextAlign.center,
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pockets(
    LedgerColors c, {
    required String lead,
    required ValueChanged<int> onPick,
    String? note,
  }) {
    return Column(
      key: ValueKey('pockets-$lead'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Back(onTap: () => setState(() => _route = null)),
        const SizedBox(height: Gap.x2),
        Text(lead, style: LedgerType.label.copyWith(color: c.inkFaint)),
        const SizedBox(height: Gap.x2),
        Wrap(
          spacing: Gap.x2,
          runSpacing: Gap.x2,
          children: [
            for (final a in _others)
              Pressable(
                key: Key('shortfall-pocket-${a.id}'),
                onTap: () => onPick(a.id),
                child: LedgerChip(
                  '${a.name}  ${Inr.compact(a.balancePaise)}',
                  icon: LedgerIcons.account[a.kind.name],
                ),
              ),
          ],
        ),
        if (note != null) ...[
          const SizedBox(height: Gap.x3),
          Text(
            note,
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ],
      ],
    );
  }

  Widget _correction(LedgerColors c) {
    final typed = _typedPaise;
    final enough = typed != null && typed >= widget.amountPaise;
    return Column(
      key: const ValueKey('correction'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Back(onTap: () => setState(() => _route = null)),
        const SizedBox(height: Gap.x2),
        Text(
          'what was really in ${widget.account.name}?',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x1),
        TextField(
          key: const ValueKey('shortfall-figure'),
          controller: _figure,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle: LedgerType.heroAmount.copyWith(
              fontSize: 32,
              color: c.inkFaint,
            ),
            border: InputBorder.none,
            hintText: '0',
            hintStyle: LedgerType.heroAmount.copyWith(
              fontSize: 32,
              color: c.rule,
            ),
          ),
        ),
        Container(height: 1, color: c.rule),
        const SizedBox(height: Gap.x2),
        Text(
          // Saying so up front beats stamping a figure and re-opening this
          // same sheet a heartbeat later.
          typed == null
              ? 'before this entry came out of it'
              : enough
              ? 'then this leaves ${Inr.format(typed - widget.amountPaise)} in it'
              : 'still short by ${Inr.format(widget.amountPaise - typed)} — '
                    'try again, or go back',
          style: LedgerType.bodyText.copyWith(
            fontSize: 12,
            color: enough || typed == null ? c.inkFaint : c.warn,
          ),
        ),
        const SizedBox(height: Gap.x3),
        Pressable(
          key: const ValueKey('shortfall-stamp-figure'),
          onTap: enough ? () => _answer(FigureWasWrong(typed)) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: enough ? c.quill : c.paperRaised,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'stamp it',
              textAlign: TextAlign.center,
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 14,
                color: enough ? c.paper : c.rule,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _Route { paidFrom, toppedUp, wrongFigure }

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: LedgerType.bodyStrong.copyWith(fontSize: 15, color: c.ink),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: onTap,
        child: Text(
          '‹ back',
          style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
        ),
      ),
    );
  }
}
