import 'package:flutter/material.dart';

import '../../../core/tokens.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/pen_marks.dart';

/// A section's tracked small-caps header over the page's hand-ruled line:
/// `LATELY ————————`. Quieter than a title, louder than a caption — the
/// page's table of contents.
class SectionHead extends StatelessWidget {
  const SectionHead(this.label, {super.key, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final seed = label.codeUnits.fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x6, bottom: Gap.x2),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: LedgerType.label.copyWith(
              fontSize: 10.5,
              letterSpacing: 1.6,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: InkRule(color: c.rule.withValues(alpha: 0.8), seed: seed),
          ),
          if (trailing != null) ...[const SizedBox(width: Gap.x3), trailing!],
        ],
      ),
    );
  }
}

/// The pen's underline stroke: draws itself left→right once, on mount.
/// Keyed by the caller when a re-draw should be felt (a selection landing,
/// the title's memory picking a chip).
class PenUnderline extends StatelessWidget {
  const PenUnderline({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final line = Container(height: 2, color: color);
    if (Motion.reduced(context)) return line;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: t == 0 ? 0.001 : t,
          child: child,
        ),
      ),
      child: line,
    );
  }
}

/// A choice as a written word, not a box: plain text, and the pen
/// underlines the chosen one — the stroke draws in when the choice lands.
/// Nothing is bordered, nothing is a chip.
class QuillTab extends StatelessWidget {
  const QuillTab(
    this.label, {
    super.key,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final color = selected ? c.quill : c.inkFaint;
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: selected
                        ? LedgerType.bodyStrong.copyWith(
                            fontSize: 13,
                            color: color,
                          )
                        : LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            color: color,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 2,
                child: selected ? PenUnderline(color: c.quill) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `label ········· amount` — one line of the page's shared amount column.
/// Every figure on Today right-aligns through rows like this one, so the
/// whole screen reads as one ruled column instead of a stack of plates.
class LeaderRow extends StatelessWidget {
  const LeaderRow({
    super.key,
    required this.label,
    required this.amount,
    this.detail,
    this.amountColor,
    this.emphasized = false,
    this.onTap,
  });

  final String label;
  final String amount;
  final String? detail;
  final Color? amountColor;

  /// True sets the amount in the heavier total mono — for the one line a
  /// section actually answers with.
  final bool emphasized;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: Gap.x2),
            Text(
              detail!,
              style: LedgerType.bodyText.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
          ],
          const SizedBox(width: Gap.x2),
          Expanded(
            child: Baseline(
              baseline: 2,
              baselineType: TextBaseline.alphabetic,
              child: SizedBox(
                height: 2,
                child: CustomPaint(
                  painter: _DottedLeaderPainter(c.rule),
                  size: const Size(double.infinity, 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: Gap.x2),
          Text(
            amount,
            style: (emphasized ? LedgerType.amountTotal : LedgerType.amount)
                .copyWith(color: amountColor ?? c.ink),
          ),
        ],
      ),
    );
    return onTap == null ? row : Pressable(onTap: onTap, child: row);
  }
}

class _DottedLeaderPainter extends CustomPainter {
  const _DottedLeaderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final dot = Paint()..color = color;
    final y = size.height / 2;
    for (var x = 0.0; x <= size.width; x += 6) {
      canvas.drawCircle(Offset(x, y), 0.9, dot);
    }
  }

  @override
  bool shouldRepaint(_DottedLeaderPainter old) => old.color != color;
}

/// An empty section as a ledger leaves it: ruled and waiting. The fact sits
/// on the first line in a plain hand; an optional action takes the last.
/// No box, no paragraph, no apology.
class EmptyRuledLines extends StatelessWidget {
  const EmptyRuledLines({
    super.key,
    required this.line,
    this.actionLabel,
    this.onAction,
    this.rules = 2,
  });

  final String line;
  final String? actionLabel;
  final VoidCallback? onAction;
  final int rules;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final ruleSide = BorderSide(color: c.rule.withValues(alpha: 0.7));
    Widget ruled(Widget? child) => Container(
      height: 30,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(border: Border(bottom: ruleSide)),
      child: child,
    );
    final action = actionLabel == null
        ? null
        : Pressable(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: LedgerType.bodyStrong.copyWith(
                fontSize: 13,
                color: c.quill,
              ),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rules; i++)
          ruled(
            i == 0
                ? Text(
                    line,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  )
                : (i == rules - 1 ? action : null),
          ),
      ],
    );
  }
}
