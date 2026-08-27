import 'package:flutter/material.dart';

import '../../../core/widgets/motion.dart';
import '../room.dart';

/// The room while it is still listening for an answer.
///
/// Two rules hold everything here together. First, a skeleton is the *same
/// geometry* as the thing it stands in for — same heights, same gaps, same
/// column widths — so when the data lands nothing jumps; the page simply
/// gains its words. Second, the whole skeleton breathes as **one** body from
/// a single controller, rather than each block shimmering on its own clock:
/// a diagonal sweep across unrelated boxes is the stock loading animation
/// every template ships, and it reads as decoration. A room drawing breath
/// reads as waiting.

/// One placeholder block. Sized like the real ink it stands for.
class Bone extends StatelessWidget {
  const Bone({
    super.key,
    required this.width,
    required this.height,
    this.radius = 3,
    this.tone,
  });

  /// null takes the full width available.
  final double? width;
  final double height;
  final double radius;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tone ?? Room.raised,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Wraps a skeleton tree and gives it one slow breath. Under reduced motion
/// the blocks simply hold still — the shape is the information, the movement
/// only says "not yet".
class Breathing extends StatefulWidget {
  const Breathing({super.key, required this.child});

  final Widget child;

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return Opacity(opacity: 0.7, child: widget.child);
    }
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 0.9).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

/// The hero, unanswered: the big figure's block, the lime rule's ghost, and
/// the meta line beneath it.
class HeroSkeleton extends StatelessWidget {
  const HeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Bone(width: 78, height: 11, radius: 2),
          SizedBox(height: 14),
          // The 72pt figure and the words riding its baseline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Bone(width: 132, height: 58, radius: 6),
              SizedBox(width: 12),
              Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Bone(width: 116, height: 17, radius: 3),
              ),
            ],
          ),
          SizedBox(height: 14),
          Bone(width: 54, height: 3, radius: 1.5),
          SizedBox(height: 14),
          Bone(width: 232, height: 11, radius: 2),
        ],
      ),
    );
  }
}

/// The range row: three words and the underline that will sit beneath one.
class RangeSkeleton extends StatelessWidget {
  const RangeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Bone(width: 74, height: 11, radius: 2),
          SizedBox(width: 26),
          Bone(width: 66, height: 11, radius: 2),
          SizedBox(width: 26),
          Bone(width: 56, height: 11, radius: 2),
        ],
      ),
    );
  }
}

/// The ranked list, unanswered. Bars shorten down the list the way real
/// ranks do, so even the skeleton is shaped like a chart rather than a
/// stack of identical grey rows.
class TopListSkeleton extends StatelessWidget {
  const TopListSkeleton({super.key, this.rows = 5});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 30,
                      child: Bone(width: 16, height: 12, radius: 2),
                    ),
                    const Bone(width: 48, height: 48, radius: 6),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Titles are not all one length; alternating keeps
                          // the block from reading as a table.
                          Bone(
                            width: i.isEven ? 168.0 : 132.0,
                            height: 13,
                            radius: 2,
                          ),
                          const SizedBox(height: 7),
                          const Bone(width: 96, height: 10, radius: 2),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Bone(width: 30, height: 11, radius: 2),
                  ],
                ),
                const SizedBox(height: 9),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1 - (i * 0.16).clamp(0.0, 0.8),
                    child: const Bone(width: null, height: 2, radius: 1),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The poster wall, unanswered: the headliner's big print and the two
/// beside it, in the same 58/42 split the real wall uses.
class WallSkeleton extends StatelessWidget {
  const WallSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final big = (box.maxWidth - gap) * 0.58;
        final small = (big - gap) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: big, height: big, radius: 14),
                const SizedBox(width: gap),
                Expanded(
                  child: Column(
                    children: [
                      Bone(width: null, height: small, radius: 10),
                      const SizedBox(height: gap),
                      Bone(width: null, height: small, radius: 10),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 30,
                      child: Bone(width: 16, height: 12, radius: 2),
                    ),
                    const Bone(width: 40, height: 40, radius: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Bone(
                        width: i.isEven ? 124.0 : 92.0,
                        height: 13,
                        radius: 2,
                      ),
                    ),
                    const Bone(width: 28, height: 11, radius: 2),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The month shelf, unanswered — rows and their hairlines.
class MonthsSkeleton extends StatelessWidget {
  const MonthsSkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 64,
                      child: Bone(width: 46, height: 12, radius: 2),
                    ),
                    const Bone(width: 34, height: 34, radius: 6),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Bone(
                            width: i.isEven ? 142.0 : 112.0,
                            height: 12,
                            radius: 2,
                          ),
                          const SizedBox(height: 6),
                          const Bone(width: 78, height: 10, radius: 2),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Bone(width: 30, height: 11, radius: 2),
                        SizedBox(height: 5),
                        Bone(width: 42, height: 9, radius: 2),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 0.5, color: Room.line),
            ],
          ),
      ],
    );
  }
}

/// The whole room, unanswered — what stands in while the very first request
/// is in the air. Same sections, same order, same spacing as the real page.
class RoomSkeleton extends StatelessWidget {
  const RoomSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Breathing(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 14, bottom: 48),
        children: const [
          HeroSkeleton(),
          SizedBox(height: 30),
          RangeSkeleton(),
          SizedBox(height: 22),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: 92, height: 11, radius: 2),
                SizedBox(height: 16),
                TopListSkeleton(rows: 4),
                SizedBox(height: 30),
                Bone(width: 62, height: 11, radius: 2),
                SizedBox(height: 16),
                WallSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
