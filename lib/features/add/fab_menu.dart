import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../data/providers.dart';
import 'money_moves.dart';

/// Long-press the ＋: the power menu. Pinned repeats stamp instantly —
/// the true sub-second path — with transfer/income/catch-up behind it.
Future<void> showFabMenu(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _FabMenu(),
  );
}

class _FabMenu extends ConsumerWidget {
  const _FabMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final pins = ref.watch(pinnedRepoProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
        child: StreamBuilder(
          stream: pins.watchAll(),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const [];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                for (final p in items)
                  InkWell(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await pins.stamp(p);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.rule)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                      child: Row(
                        children: [
                          Icon(Icons.push_pin_outlined,
                              size: 13, color: c.inkFaint),
                          const SizedBox(width: Gap.x2),
                          Expanded(
                            child: Text(
                              p.title,
                              style:
                                  LedgerType.bodyText.copyWith(color: c.ink),
                            ),
                          ),
                          Text(
                            Inr.format(p.amountPaise),
                            style:
                                LedgerType.amount.copyWith(color: c.ink),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Gap.x3),
                Text(
                  'more',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                const SizedBox(height: Gap.x2),
                Wrap(
                  spacing: Gap.x2,
                  runSpacing: Gap.x2,
                  children: const [
                    _MoveChip(Icons.swap_horiz, 'transfer', showTransferSheet),
                    _MoveChip(Icons.rule, 'fix a balance', showFixBalanceSheet),
                    _MoveChip(Icons.south_west, 'income', showIncomeSheet),
                    _MoveChip(
                        Icons.history_edu_outlined, 'quiet days',
                        showCatchUpSheet),
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

/// One of the four money moves. Closes the menu first, then opens its sheet
/// from the navigator's own context — the menu never stacks under it.
class _MoveChip extends StatefulWidget {
  const _MoveChip(this.icon, this.label, this.open);

  final IconData icon;
  final String label;
  final Future<void> Function(BuildContext) open;

  @override
  State<_MoveChip> createState() => _MoveChipState();
}

class _MoveChipState extends State<_MoveChip> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        HapticFeedback.selectionClick();
        final nav = Navigator.of(context);
        nav.pop();
        widget.open(nav.context);
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: c.rule),
            borderRadius: BorderRadius.circular(Corner.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 13, color: c.inkFaint),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: LedgerType.bodyText
                    .copyWith(fontSize: 13, color: c.inkFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
