import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

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

/// One ruled ledger line: time · title · account — amount.
class LedgerLine extends StatelessWidget {
  const LedgerLine({
    super.key,
    this.leading,
    required this.title,
    this.detail,
    required this.amount,
    this.amountColor,
    this.last = false,
    this.onTap,
    this.onLongPress,
  });

  final String? leading;
  final String title;
  final String? detail;
  final String amount;
  final Color? amountColor;
  final bool last;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
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
                style: LedgerType.bodyText.copyWith(color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              amount,
              style: LedgerType.amount.copyWith(color: amountColor ?? c.ink),
            ),
          ],
        ),
      ),
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
            Icon(Icons.verified_outlined, size: 13, color: c.seal),
          ],
          const Spacer(),
          Text(total,
              style: LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint)),
        ],
      ),
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.quillSoft : null,
          border: Border.all(color: selected ? c.quill : c.rule),
          borderRadius: BorderRadius.circular(Corner.chip),
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
