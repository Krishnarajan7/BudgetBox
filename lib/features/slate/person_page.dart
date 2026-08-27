import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../data/api/endpoints/endpoints.dart';
import 'slate_page.dart';
import 'slate_providers.dart';
import 'widgets/person_sheets.dart';

/// One person's slate: what stands, what moved, and the two buttons that
/// are almost always what you came for.
class PersonPage extends ConsumerWidget {
  const PersonPage({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(slatePersonProvider(personId));
    return ModuleScaffold(
      title: view.value?.$1.name ?? 'Slate',
      child: view.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const EmptyPage(
          line: 'This slate would not open.',
          sub: 'Step back and try again.',
        ),
        data: (data) => _Person(person: data.$1, entries: data.$2),
      ),
    );
  }
}

class _Person extends ConsumerWidget {
  const _Person({required this.person, required this.entries});

  final SlatePerson person;
  final List<SlateEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final p = person;
    return RefreshIndicator(
      color: c.quill,
      onRefresh: () async => ref.invalidate(slatePersonProvider(p.id)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x12),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Gap.x4),
            child: HeroAmount(
              caption: p.clean
                  ? 'settled'
                  : (p.owesYou ? 'owes you' : 'you owe'),
              amount: p.clean ? '—' : Inr.format(p.balancePaise.abs()),
              sub: _Sub(person: p),
            ),
          ),
          const SizedBox(height: Gap.x4),
          _Actions(person: p),
          if (entries.isNotEmpty) ...[
            const RuleHeader('the slate'),
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

/// The quiet reciprocity line. Not a score and not a badge — just what has
/// happened before, so the next decision is made with open eyes.
class _Sub extends StatelessWidget {
  const _Sub({required this.person});

  final SlatePerson person;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final p = person;
    final bits = <String>[];
    if (p.outstandingSince != null) {
      bits.add('since ${slateDateWord(p.outstandingSince!)}');
    }
    if (p.loopsTotal > 0) {
      bits.add(
        p.loopsClosed == p.loopsTotal
            ? '${p.loopsTotal} of ${p.loopsTotal} came back'
            : '${p.loopsClosed} of ${p.loopsTotal} came back',
      );
    }
    if (bits.isEmpty && p.relation != null) bits.add(p.relation!);
    return Text(
      bits.join(' · '),
      style: LedgerType.label.copyWith(color: c.inkFaint),
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.person});

  final SlatePerson person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = person;
    return Wrap(
      spacing: Gap.x2,
      runSpacing: Gap.x2,
      children: [
        // The common case leads: money coming back.
        if (!p.clean)
          Pressable(
            onTap: () => moveSheet(context, ref, person: p, move: MoveKind.back),
            child: LedgerChip(p.owesYou ? 'they paid back' : 'you paid back',
              selected: true,
            ),
          ),
        Pressable(
          onTap: () => moveSheet(context, ref, person: p, move: MoveKind.lend),
          child: const LedgerChip('lent more'),
        ),
        Pressable(
          onTap: () =>
              moveSheet(context, ref, person: p, move: MoveKind.borrow),
          child: const LedgerChip('borrowed'),
        ),
        Pressable(
          onTap: () => adoptSheet(context, ref, person: p),
          child: const LedgerChip('already in the book'),
        ),
        if (!p.clean)
          Pressable(
            onTap: () => letGoSheet(context, ref, person: p),
            child: const LedgerChip('let it go'),
          ),
      ],
    );
  }
}

class _EntryLine extends StatelessWidget {
  const _EntryLine({required this.entry, required this.last});

  final SlateEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final e = entry;
    final (word, out) = switch (e.kind) {
      SlateKind.lent => ('lent', true),
      SlateKind.repaid => ('came back', false),
      SlateKind.borrowed => ('borrowed', false),
      SlateKind.settled => ('paid back', true),
      SlateKind.forgiven => ('let go', false),
      SlateKind.writtenOff => ('written off', true),
    };
    final closing =
        e.kind == SlateKind.forgiven || e.kind == SlateKind.writtenOff;
    return LedgerLine(
      leading: slateDateWord(e.at),
      title: word,
      detail: e.note,
      amount: '${out ? '−' : '+'}${Inr.format(e.amountPaise)}',
      amountColor: closing ? c.seal : (out ? c.ink : c.jama),
      last: last,
    );
  }
}
