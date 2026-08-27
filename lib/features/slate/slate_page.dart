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
import 'person_page.dart';
import 'slate_providers.dart';
import 'widgets/person_sheets.dart';

/// The slate: what is out with people, and what is owed back.
///
/// This is not a room of its own the way the music book is — money belongs to
/// the ledger, so the slate wears the same paper and ink as every other page.
/// What makes it its own thing is the arithmetic, not the palette: lending is
/// never spending here, and the page says so.
class SlatePage extends ConsumerWidget {
  const SlatePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(slateGateProvider);
    return ModuleScaffold(
      title: 'Slate',
      trailing: gate.value is SlateOpen
          ? Pressable(
              scale: 0.9,
              onTap: () => addPersonSheet(context, ref),
              child: PenPlus(size: 18, color: LedgerColors.of(context).quill),
            )
          : null,
      child: gate.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const EmptyPage(
          line: 'The slate would not open.',
          sub: 'Something went wrong reading it. Step back and try again.',
        ),
        data: (g) => switch (g) {
          SlateUnwired() => const EmptyPage(
            line: 'The slate lives on the server.',
            sub: 'Wire the book to the server in Settings, and what is out '
                'with people can be kept there too.',
          ),
          SlateAway() => const EmptyPage(
            line: 'The server is away.',
            sub: 'What is out is safe — it just cannot be read right now.',
          ),
          SlateOpen(overview: final o, people: final people) => _Slate(
            overview: o,
            people: people,
          ),
        },
      ),
    );
  }
}

class _Slate extends ConsumerWidget {
  const _Slate({required this.overview, required this.people});

  final SlateOverview overview;
  final List<SlatePerson> people;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    if (people.isEmpty) {
      return EmptyPage(
        line: 'Nothing is out.',
        sub: 'When money goes to someone, it goes here — not into the '
            'month\'s spending, because it is still yours.',
        action: Pressable(
          onTap: () => addPersonSheet(context, ref),
          child: LedgerChip('add someone', selected: true),
        ),
      );
    }
    final standing = people.where((p) => !p.clean).toList();
    final clean = people.where((p) => p.clean).toList();
    return RefreshIndicator(
      color: c.quill,
      onRefresh: () async => ref.invalidate(slateGateProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x12),
        children: [
          _Head(overview: overview),
          if (standing.isNotEmpty) ...[
            const RuleHeader('standing'),
            for (final (i, p) in standing.indexed)
              InkIn(
                delay: Duration(milliseconds: 24 * i),
                child: _PersonLine(person: p, last: i == standing.length - 1),
              ),
          ],
          if (clean.isNotEmpty) ...[
            const RuleHeader('settled'),
            for (final (i, p) in clean.indexed)
              InkIn(
                delay: Duration(milliseconds: 24 * i),
                child: _PersonLine(person: p, last: i == clean.length - 1),
              ),
          ],
          if (!overview.balanced) _Disagreement(overview: overview),
        ],
      ),
    );
  }
}

/// The one figure the page exists for. When the slate runs both ways the
/// hero shows the net and the two sides sit beneath it — a single number
/// that hides "you owe Vikram" would be a comfortable lie.
class _Head extends StatelessWidget {
  const _Head({required this.overview});

  final SlateOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final o = overview;
    final bothWays = o.owedToYouPaise > 0 && o.youOwePaise > 0;
    final caption = o.netPaise >= 0 ? 'out with people' : 'owed by you';
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeroAmount(
            caption: caption,
            amount: Inr.format(o.netPaise.abs()),
            sub: Text(
              bothWays
                  ? '${Inr.format(o.owedToYouPaise)} out · '
                        '${Inr.format(o.youOwePaise)} owed'
                  : _peopleLine(o),
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
          ),
          const SizedBox(height: Gap.x3),
          // The sentence the whole module exists to make true.
          Text(
            'Still yours — parked, not spent.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  static String _peopleLine(SlateOverview o) {
    final n = o.netPaise >= 0 ? o.peopleInDebt : o.peopleYouOwe;
    if (n == 0) return 'everything settled';
    return n == 1 ? 'with 1 person' : 'with $n people';
  }
}

class _PersonLine extends ConsumerWidget {
  const _PersonLine({required this.person, required this.last});

  final SlatePerson person;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final p = person;
    return LedgerLine(
      title: p.name,
      detail: _detail(p),
      amount: p.clean ? '—' : Inr.format(p.balancePaise.abs()),
      // Owed to you is ordinary ink; money you owe is a mark that reads as
      // an obligation. Neither is a flood of colour.
      amountColor: p.clean
          ? c.inkFaint
          : (p.owesYou ? c.ink : c.warn),
      last: last,
      onTap: () => Navigator.of(context).push(
        LedgerRoute<void>(builder: (_) => PersonPage(personId: p.id)),
      ),
    );
  }

  /// Age, stated — never nagged. The fact is enough to make you remember;
  /// a badge or a red dot would be the app having an opinion about your
  /// sister.
  static String? _detail(SlatePerson p) {
    if (p.clean) {
      if (p.loopsTotal == 0) return p.relation;
      final tail = p.loopsClosed == p.loopsTotal
          ? 'always came back'
          : '${p.loopsClosed} of ${p.loopsTotal} came back';
      return p.relation == null ? tail : '${p.relation} · $tail';
    }
    final since = p.outstandingSince;
    final age = since == null ? null : _age(since);
    final side = p.owesYou ? null : 'you owe';
    return [?p.relation, ?side, ?age].join(' · ');
  }

  static String _age(DateTime since) {
    final days = DateTime.now().difference(since).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'a day';
    if (days < 14) return '$days days';
    if (days < 60) return '${(days / 7).floor()} weeks';
    return '${(days / 30).floor()} months';
  }
}

/// The invariant, broken. Every slate should add up to what the ledger parked
/// on the slate account; when it does not, the page says so plainly instead
/// of showing two numbers that disagree in silence.
class _Disagreement extends StatelessWidget {
  const _Disagreement({required this.overview});

  final SlateOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return LedgerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Gap.x3),
          Text(
            'The slates and the ledger disagree.',
            style: LedgerType.bodyStrong.copyWith(color: c.seal),
          ),
          const SizedBox(height: Gap.x2),
          Text(
            'These slates add to ${Inr.format(overview.netPaise)}, but the '
            'ledger has ${Inr.format(overview.slateAccountPaise)} parked on '
            'the slate account. A line was probably edited or struck out by '
            'hand.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared by the page and the person sheet: '4 Aug 2026'.
String slateDateWord(DateTime d) => '${LedgerDates.ddMmm(d)} ${d.year}';
