import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../typography.dart';
import 'cat_mark.dart';
import 'motion.dart';
import 'pen_marks.dart';

/// "this month ————————" — a ruled section header.
class RuleHeader extends StatelessWidget {
  const RuleHeader(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x6, bottom: Gap.x1),
      child: Row(
        children: [
          Text(label, style: LedgerType.label.copyWith(color: c.inkFaint)),
          const SizedBox(width: Gap.x3),
          Expanded(child: Container(height: 1, color: c.rule)),
          if (trailing != null) ...[
            const SizedBox(width: Gap.x3),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// A lifted surface: the midnight identity's unit of content. The hero and
/// the ledger lines live on the page itself; everything that *reads* the book
/// back to Krish — pace, upcoming, the month grid — sits a layer up.
class LedgerCard extends StatelessWidget {
  const LedgerCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    // Hard corners, no outline: a plate of lacquer, not the borderless-soft
    // card every dark app ships. The edge is the tone change itself.
    return Container(
      margin: const EdgeInsets.only(top: Gap.x3),
      padding: padding ??
          const EdgeInsets.fromLTRB(Gap.x4, Gap.x1, Gap.x4, Gap.x4),
      decoration: BoxDecoration(
        color: c.paperRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: child,
    );
  }
}

/// Caption over a Fraunces hero number — numbers in the spotlight.
class HeroAmount extends StatelessWidget {
  const HeroAmount({
    super.key,
    required this.caption,
    required this.amount,
    this.sub,
    this.size = 42,
  });

  final String caption;
  final String amount;
  final Widget? sub;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: LedgerType.label.copyWith(color: c.inkFaint)),
        const SizedBox(height: 2),
        Text(
          amount,
          style: LedgerType.heroAmount.copyWith(fontSize: size, color: c.ink),
        ),
        if (sub != null) ...[const SizedBox(height: 2), sub!],
      ],
    );
  }
}

/// One ruled ledger line: time · mark · title · account — amount.
class LedgerLine extends StatelessWidget {
  const LedgerLine({
    super.key,
    this.leading,
    this.mark,
    required this.title,
    this.detail,
    this.amount = '',
    this.amountWidget,
    this.amountColor,
    this.struck = false,
    this.last = false,
    this.onTap,
    this.onLongPress,
  });

  final String? leading;

  /// A small glyph before the title — a [CatMark], a kind icon.
  final Widget? mark;
  final String title;
  final String? detail;
  final String amount;

  /// Replaces the amount text when the figure needs to move (a [CountUp])
  /// or carry more than mono ink.
  final Widget? amountWidget;
  final Color? amountColor;

  /// Renders the line struck through and faint — an entry on its way out,
  /// still tappable to bring it back.
  final bool struck;
  final bool last;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final inkColor = struck ? c.inkFaint : c.ink;
    final strike = struck ? TextDecoration.lineThrough : null;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (leading != null)
              SizedBox(
                width: 44,
                child: Text(
                  leading!,
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              ),
            if (mark != null) ...[
              Baseline(
                baseline: 11,
                baselineType: TextBaseline.alphabetic,
                child: mark!,
              ),
              const SizedBox(width: Gap.x2),
            ],
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: title,
                  children: [
                    if (detail != null)
                      TextSpan(
                        text: '  $detail',
                        style: LedgerType.bodyText
                            .copyWith(fontSize: 12, color: c.inkFaint),
                      ),
                  ],
                ),
                style: LedgerType.bodyText
                    .copyWith(color: inkColor, decoration: strike),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            amountWidget ??
                Text(
                  amount,
                  style: LedgerType.amount.copyWith(
                    color: struck ? c.inkFaint : (amountColor ?? c.ink),
                    decoration: strike,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// The shared counting hero: caption over a Fraunces figure that settles
/// whenever [paise] changes. The one number the screen exists for.
class CountHero extends StatelessWidget {
  const CountHero({
    super.key,
    required this.caption,
    required this.paise,
    required this.format,
    this.sub,
    this.size = 42,
  });

  final String caption;
  final int paise;
  final String Function(int) format;
  final Widget? sub;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: LedgerType.label.copyWith(color: c.inkFaint)),
        const SizedBox(height: 2),
        CountUp(
          value: paise,
          format: format,
          style: LedgerType.heroAmount.copyWith(fontSize: size, color: c.ink),
        ),
        if (sub != null) ...[const SizedBox(height: 2), sub!],
      ],
    );
  }
}

/// A day's header: "Today · Thu 31 ——— ₹340", underlined in ink.
class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.label, required this.total, this.sealed = false});

  final String label;
  final String total;
  final bool sealed;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: Gap.x4),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.ink, width: 1)),
      ),
      child: Row(
        children: [
          Text(label,
              style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.ink)),
          if (sealed) ...[
            const SizedBox(width: Gap.x2),
            // The chop that closed it, in miniature — not a checkmark badge.
            SealOutline(size: 13, color: c.seal),
          ],
          const Spacer(),
          Text(total,
              style: LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint)),
        ],
      ),
    );
  }
}

/// A blank page speaking for itself: a Fraunces line in the author's voice,
/// a faint second thought beneath. No illustrations, no icons — the copy is
/// the empty state.
class EmptyPage extends StatelessWidget {
  const EmptyPage({
    super.key,
    required this.line,
    this.sub,
    this.action,
  });

  /// The page's one sentence — wry, first person, no exclamation marks.
  final String line;
  final String? sub;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Center(
      child: InkIn(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Gap.x8, vertical: Gap.x12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                line,
                textAlign: TextAlign.center,
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              if (sub != null) ...[
                const SizedBox(height: Gap.x2),
                Text(
                  sub!,
                  textAlign: TextAlign.center,
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 13, color: c.inkFaint),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: Gap.x4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipe a ledger line right to correct it, left to strike it out.
/// The reveal is flat paper and a word — no tinted floods; the strike side
/// uses seal ink only for its label, kept within the seal budget.
class SwipeRow extends StatelessWidget {
  const SwipeRow({
    super.key,
    required this.rowKey,
    required this.child,
    this.onEdit,
    this.onDelete,
    this.deleteLabel = 'strike',
    this.editLabel = 'correct',
  });

  final Key rowKey;
  final Widget child;
  final VoidCallback? onEdit;

  /// Called after the row is dismissed; the deletion itself is the caller's.
  final VoidCallback? onDelete;
  final String deleteLabel;
  final String editLabel;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Dismissible(
      key: rowKey,
      direction: onEdit == null
          ? (onDelete == null
              ? DismissDirection.none
              : DismissDirection.endToStart)
          : (onDelete == null
              ? DismissDirection.startToEnd
              : DismissDirection.horizontal),
      background: Container(
        color: c.paperRaised,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: Gap.x4),
        child: Text(editLabel,
            style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill)),
      ),
      secondaryBackground: Container(
        color: c.paperRaised,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Gap.x4),
        child: Text(deleteLabel,
            style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.seal)),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.selectionClick();
          onEdit?.call();
          return false; // The row stays; the editor opens over it.
        }
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) => onDelete?.call(),
      child: child,
    );
  }
}

/// A pill chip; selected state wears the quill. [icon] draws a small line
/// icon before the label — the only ornament chips are allowed.
class LedgerChip extends StatelessWidget {
  const LedgerChip(this.label,
      {super.key, this.icon, this.selected = false, this.onTap});

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final color = selected ? c.quill : c.inkFaint;
    return GestureDetector(
      onTap: onTap,
      // A stamp block, not a pill: lifted lacquer, hard corners, and the
      // selected one takes a wash of the binding's vermilion.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.quill.withValues(alpha: 0.16) : c.paperRaised,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: selected
                  ? LedgerType.bodyStrong.copyWith(fontSize: 13, color: color)
                  : LedgerType.bodyText.copyWith(fontSize: 13, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// One category's weight in the month: a name, a mono amount, and behind
/// them a wash of the lightning drawn to the category's share of the
/// heaviest line. Shared by Book's heat view, Today's compact door, and
/// the Insights page.
class WhereRow extends StatelessWidget {
  const WhereRow({
    super.key,
    required this.label,
    required this.iconKey,
    required this.amount,
    required this.frac,
    required this.stagger,
    required this.last,
    this.onTap,
  });

  final String label;
  final String? iconKey;
  final String amount;

  /// Bar length as a fraction of the heaviest category's.
  final double frac;
  final int stagger;
  final bool last;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final total = 450 + 60 * stagger;
    final row = Container(
      decoration: last
          ? null
          : BoxDecoration(border: Border(bottom: BorderSide(color: c.rule))),
      child: Stack(
        children: [
          Positioned.fill(
            child: DrawIn(
              duration: Duration(milliseconds: total),
              builder: (context, t) {
                final p = ((t * total - 60 * stagger) / 450).clamp(0.0, 1.0);
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (frac.clamp(0.0, 1.0)) * p,
                  child: ColoredBox(color: c.quill.withValues(alpha: 0.10)),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                CatMark(iconKey, size: 14),
                const SizedBox(width: Gap.x2),
                Expanded(
                  child: Text(
                    label,
                    style: LedgerType.bodyText.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(amount, style: LedgerType.amount.copyWith(color: c.ink)),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}
