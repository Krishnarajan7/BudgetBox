import 'package:flutter/material.dart';

import '../../../core/typography.dart';
import '../../../data/api/endpoints/endpoints.dart';
import '../room.dart';

/// The poster wall: rank one gets the big print, the rest hang beside it.
/// Portraits fill in over a few polls (the GDPR import knows only names) —
/// until then the initial-letter tiles carry the wall.
class ArtistWall extends StatelessWidget {
  const ArtistWall({super.key, required this.entries});

  final List<MusicEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final headliner = entries.first;
    final rest = entries.skip(1).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final gap = 10.0;
        final big = (box.maxWidth - gap) * 0.58;
        final smallW = box.maxWidth - gap - big;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Poster(entry: headliner, size: big, big: true),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    children: [
                      for (final e in rest.take(2)) ...[
                        _Poster(
                          entry: e,
                          size: smallW,
                          height: (big - gap) / 2,
                        ),
                        if (e != rest.take(2).last) SizedBox(height: gap),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (rest.length > 2) ...[
              SizedBox(height: gap + 4),
              for (final e in rest.skip(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          e.rank.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontFamily: LedgerType.ledger,
                            fontVariations: const [FontVariation('wght', 500)],
                            fontSize: 15,
                            color: Room.faint,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      ArtTile(
                        url: e.imageUrl,
                        fallbackText: e.name,
                        size: 40,
                        radius: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LedgerType.bodyStrong.copyWith(
                            color: Room.ivory,
                          ),
                        ),
                      ),
                      PlayCount(e.plays),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// One print on the wall: portrait under a dark scrim, name and count
/// pressed into the lower corner.
class _Poster extends StatelessWidget {
  const _Poster({
    required this.entry,
    required this.size,
    this.height,
    this.big = false,
  });

  final MusicEntry entry;
  final double size;
  final double? height;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: height ?? size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(big ? 14 : 10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ArtTile(
              url: entry.imageUrl,
              fallbackText: entry.name,
              size: size,
              radius: 0,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.45, 1.0],
                  colors: [Colors.transparent, Color(0xCC0C0A09)],
                ),
              ),
            ),
            Positioned(
              left: big ? 14 : 10,
              right: big ? 14 : 10,
              bottom: big ? 12 : 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: big ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: LedgerType.headline,
                      fontSize: big ? 22 : 13,
                      height: 1.1,
                      color: Room.ivory,
                    ),
                  ),
                  const SizedBox(height: 2),
                  PlayCount(
                    entry.plays,
                    size: big ? 13 : 11,
                    color: big ? Room.lime : Room.faint,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
