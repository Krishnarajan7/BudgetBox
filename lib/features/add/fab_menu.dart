import 'package:drift/drift.dart' show ComparableExpr, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import 'money_moves.dart';

/// Long-press the ＋: the power menu. Pinned repeats stamp instantly —
/// the true sub-second path — with transfer/income/catch-up behind it.
Future<void> showFabMenu(BuildContext context) {
  return showLedgerSheet<void>(
    context,
    builder: (_) => const _FabMenu(),
  );
}

class _FabMenu extends ConsumerStatefulWidget {
  const _FabMenu();

  @override
  ConsumerState<_FabMenu> createState() => _FabMenuState();
}

class _FabMenuState extends ConsumerState<_FabMenu> {
  /// The pin currently taking its seal — one at a time, and only briefly.
  int? _stampedId;

  /// This month's expense lines, kept only to count how often each pin has
  /// been written. Read-only; the whisper never changes anything.
  List<Txn> _thisMonth = const [];

  @override
  void initState() {
    super.initState();
    _loadUses();
  }

  Future<void> _loadUses() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final rows = await (db.select(db.txns)
          ..where((t) => t.at.isBiggerOrEqualValue(DateTime(now.year, now.month)))
          ..orderBy([(t) => OrderingTerm.desc(t.at)]))
        .get();
    if (!mounted) return;
    setState(() => _thisMonth = rows);
  }

  /// How many times this pin's line has been written this month.
  int _uses(Pinned p) {
    var n = 0;
    for (final t in _thisMonth) {
      if (t.type == TxnType.expense &&
          t.title == p.title &&
          t.categoryId == p.categoryId) {
        n++;
      }
    }
    return n;
  }

  String? _whisper(Pinned p) {
    final n = _uses(p);
    if (n == 0) return null;
    return n == 1 ? 'stamped once this month' : 'stamped $n times this month';
  }

  Future<void> _stampPin(Pinned p) async {
    if (_stampedId != null) return;
    setState(() => _stampedId = p.id);
    HapticFeedback.lightImpact();
    await ref.read(pinnedRepoProvider).stamp(p);
    // The seal lands before the menu leaves — the entry is witnessed.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final pins = ref.watch(pinnedRepoProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: StreamBuilder(
          stream: pins.watchAll(),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <Pinned>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                Text(
                  'pinned — one tap, stamped',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: Gap.x2),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                    child: Text(
                      'Nothing pinned yet. Long-press any entry in the Book '
                      'to pin it here.',
                      style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                    ),
                  ),
                // The pins write themselves onto the sheet, top down.
                for (final (i, p) in items.indexed)
                  InkIn(
                    key: ValueKey('pin-ink-${p.id}'),
                    delay: Duration(milliseconds: 30 * i),
                    child: Pressable(
                      haptic: false,
                      onTap: () => _stampPin(p),
                      child: LedgerLine(
                        mark: SealOutline(size: 13, color: c.inkFaint),
                        title: p.title,
                        detail: _whisper(p),
                        amount: Inr.format(p.amountPaise),
                        amountWidget: _stampedId == p.id
                            ? const StampIn(size: 26, haptic: false)
                            : null,
                        last: i == items.length - 1,
                      ),
                    ),
                  ),
                const SizedBox(height: Gap.x4),
                Text(
                  'more',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: Gap.x3),
                Wrap(
                  spacing: Gap.x4,
                  runSpacing: Gap.x3,
                  children: const [
                    _Move('transfer', 'pocket to pocket',
                        showTransferSheet),
                    _Move('fix', 'make the book match',
                        showFixBalanceSheet),
                    _Move('income', 'money that came in',
                        showIncomeSheet),
                    _Move('catch-up',
                        'the days I skipped', showCatchUpSheet),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One of the four money moves: a one-word chip with a quiet line under it
/// saying what it does. Closes the menu first, then opens its sheet from the
/// navigator's own context — the menu never stacks under it.
class _Move extends StatelessWidget {
  const _Move(this.label, this.sub, this.open);

  final String label;
  final String sub;
  final Future<void> Function(BuildContext) open;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      onTap: () {
        final nav = Navigator.of(context);
        nav.pop();
        open(nav.context);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LedgerChip(label),
          const SizedBox(height: Gap.x1),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              sub,
              style:
                  LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
