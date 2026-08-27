import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/typography.dart';
import '../../../core/widgets/motion.dart';
import '../music_providers.dart';
import '../room.dart';

/// The live strip: what the speakers are doing right now. Absent entirely
/// when the room is quiet — silence needs no tile.
class NowBar extends ConsumerWidget {
  const NowBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(musicNowProvider).value;
    if (now == null || !now.playing || now.track == null) {
      return const SizedBox.shrink();
    }
    final progress =
        (now.progressMs != null &&
            now.durationMs != null &&
            now.durationMs! > 0)
        ? (now.progressMs! / now.durationMs!).clamp(0.0, 1.0)
        : null;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Room.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _LiveDot(),
              const SizedBox(width: 10),
              ArtTile(url: now.imageUrl, fallbackText: now.track!, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      now.track!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.bodyStrong.copyWith(color: Room.ivory),
                    ),
                    if (now.artist != null)
                      Text(
                        now.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.label.copyWith(color: Room.faint),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Room.line,
                valueColor: const AlwaysStoppedAnimation(Room.lime),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The lime pulse that says "live". Breathes on a slow loop; holds steady
/// under reduced motion.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dot = DecoratedBox(
      decoration: BoxDecoration(color: Room.lime, shape: BoxShape.circle),
      child: SizedBox(width: 7, height: 7),
    );
    if (Motion.reduced(context)) return dot;
    if (!_breath.isAnimating) _breath.repeat(reverse: true);
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _breath, curve: Curves.easeInOut),
      ),
      child: dot,
    );
  }
}
