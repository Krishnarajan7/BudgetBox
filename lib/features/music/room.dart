import 'package:flutter/material.dart';

import '../../core/typography.dart';
import '../../core/widgets/motion.dart';

/// The listening room. The one book that is always dark, whichever theme the
/// rest of the app wears — music happens with the lights off. Warm charcoal,
/// not the ledger's indigo night: a different room, not a different hour.
/// One acid accent that exists nowhere else in the app; the artwork brings
/// every other color the page needs.
abstract final class Room {
  /// The dark itself — warm, near-black, no blue in it.
  static const bg = Color(0xFF0C0A09);

  /// Panels and tiles a step out of the dark.
  static const raised = Color(0xFF171312);

  /// Hairlines and resting bars.
  static const line = Color(0xFF2B2522);

  /// Type. Warm ivory, same family as the ledger's night text.
  static const ivory = Color(0xFFF0EAE0);

  /// Secondary type.
  static const faint = Color(0xFF978C83);

  /// The acid accent — flyer lime. Rank one, the live dot, the drawn bars.
  /// Used nowhere else in the app, which is the point.
  static const lime = Color(0xFFC9F04F);

  /// Lime at rest, for fills that shouldn't shout.
  static const limeDim = Color(0x59C9F04F);
}

/// Counts in this room: 8140 -> '8,140' (Indian 2-2-3 grouping, same as the
/// ledger's rupees — one habit of mind across books).
String groupCount(int n) {
  final s = n.toString();
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var head = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (head.length > 2) {
    parts.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  parts.insert(0, head);
  return '${parts.join(',')},$last3';
}

/// Milliseconds listened -> the hours figure the hero shows.
/// Whole hours once past a hundred; one decimal before that.
String hoursFigure(int ms) {
  final hours = ms / 3600000;
  if (hours >= 100) return groupCount(hours.round());
  final r = (hours * 10).round() / 10;
  return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
}

/// 'x143' in the room's mono — every play count on the page goes through
/// this so they all speak alike.
class PlayCount extends StatelessWidget {
  const PlayCount(this.plays, {super.key, this.size = 13, this.color});

  final int plays;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '×${groupCount(plays)}',
      style: TextStyle(
        fontFamily: LedgerType.ledger,
        fontVariations: const [FontVariation('wght', 460)],
        fontSize: size,
        color: color ?? Room.faint,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Small spaced-out mono label — the room's section voice.
class RoomLabel extends StatelessWidget {
  const RoomLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: LedgerType.ledger,
        fontVariations: const [FontVariation('wght', 500)],
        fontSize: 11,
        letterSpacing: 2.4,
        color: color ?? Room.faint,
      ),
    );
  }
}

/// Album art or an artist portrait; when the record has no image (the GDPR
/// import knows names, not pictures), the initial letter set big in the dark
/// stands in — deliberate, not broken.
class ArtTile extends StatelessWidget {
  const ArtTile({
    super.key,
    required this.url,
    required this.fallbackText,
    this.size = 48,
    this.radius = 6,
  });

  final String? url;
  final String fallbackText;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final letter = fallbackText.isEmpty ? '?' : fallbackText[0].toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      color: Room.raised,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          fontFamily: LedgerType.headline,
          fontSize: size * 0.42,
          color: Room.faint,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url == null
          ? fallback
          : Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              frameBuilder: (context, child, frame, wasSync) {
                if (wasSync || Motion.reduced(context)) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: Motion.spring,
                  curve: Motion.curve,
                  child: child,
                );
              },
            ),
    );
  }
}

/// A figure that counts itself up from nothing when it first lands — unlike
/// the motion kit's [CountUp], which settles *changes*, this is an entrance.
/// Renders instantly under reduced motion.
class HeroCount extends StatelessWidget {
  const HeroCount({
    super.key,
    required this.value,
    required this.style,
    this.format = _plain,
  });

  final int value;
  final TextStyle style;
  final String Function(int) format;

  static String _plain(int v) => groupCount(v);

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return Text(format(value), style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: Motion.draw,
      curve: Curves.easeOutQuart,
      builder: (_, v, _) => Text(format(v.round()), style: style),
    );
  }
}

/// The hairline bar under a top row: how this one stands against rank one.
/// Draws itself in on arrival, staggered by rank.
class RankBar extends StatelessWidget {
  const RankBar({super.key, required this.fraction, required this.delayIndex});

  final double fraction;
  final int delayIndex;

  @override
  Widget build(BuildContext context) {
    final bar = LayoutBuilder(
      builder: (context, box) => Container(
        height: 2,
        width: box.maxWidth * fraction.clamp(0.02, 1.0),
        decoration: BoxDecoration(
          color: Room.limeDim,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
    if (Motion.reduced(context)) return bar;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.draw + Duration(milliseconds: 60 * delayIndex),
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => Opacity(
        opacity: t,
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          child: FractionallySizedBox(widthFactor: t, child: bar),
        ),
      ),
    );
  }
}
