import 'package:flutter/material.dart';

import '../../../core/typography.dart';
import '../../../data/api/endpoints/endpoints.dart';
import '../room.dart';

/// The ranked list. Real play counts from the book's own record — not
/// Spotify's opaque affinity — with a drawn bar setting each row against
/// rank one.
class TopTracks extends StatelessWidget {
  const TopTracks({super.key, required this.entries});

  final List<MusicEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const _QuietLine('nothing on record in this stretch');
    }
    final most = entries.first.plays;
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TrackRow(entry: e, fraction: e.plays / most),
          ),
      ],
    );
  }
}

class TrackRow extends StatelessWidget {
  const TrackRow({super.key, required this.entry, required this.fraction});

  final MusicEntry entry;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final first = entry.rank == 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                entry.rank.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontFamily: LedgerType.ledger,
                  fontVariations: const [FontVariation('wght', 500)],
                  fontSize: 15,
                  color: first ? Room.lime : Room.faint,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            ArtTile(url: entry.imageUrl, fallbackText: entry.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LedgerType.bodyStrong.copyWith(color: Room.ivory),
                  ),
                  if (entry.artist != null)
                    Text(
                      entry.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.label.copyWith(color: Room.faint),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            PlayCount(entry.plays, color: first ? Room.lime : Room.faint),
          ],
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.only(left: 30),
          child: RankBar(fraction: fraction, delayIndex: entry.rank),
        ),
      ],
    );
  }
}

class _QuietLine extends StatelessWidget {
  const _QuietLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(text, style: LedgerType.bodyText.copyWith(color: Room.faint)),
    );
  }
}
