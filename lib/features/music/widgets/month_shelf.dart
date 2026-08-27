import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/dates.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/motion.dart';
import '../../../data/api/endpoints/endpoints.dart';
import '../music_providers.dart';
import '../room.dart';
import 'skeleton.dart';

/// The months, newest first: each one a line — how much, and who owned it.
/// A tap opens the month in place (its top ten and its artists); no
/// sub-screen, the wall just unfolds.
class MonthShelf extends ConsumerStatefulWidget {
  const MonthShelf({super.key, required this.months});

  final List<MusicMonth> months;

  @override
  ConsumerState<MonthShelf> createState() => _MonthShelfState();
}

class _MonthShelfState extends ConsumerState<MonthShelf> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final m in widget.months)
          _MonthRow(
            month: m,
            open: _open == m.month,
            onTap: () =>
                setState(() => _open = _open == m.month ? null : m.month),
          ),
      ],
    );
  }
}

class _MonthRow extends ConsumerWidget {
  const _MonthRow({
    required this.month,
    required this.open,
    required this.onTap,
  });

  final MusicMonth month;
  final bool open;
  final VoidCallback onTap;

  /// '2026-08' -> ('AUG', ''26').
  (String, String) get _label {
    final m = int.parse(month.month.substring(5, 7));
    return (
      LedgerDates.months[m - 1].toUpperCase(),
      "'${month.month.substring(2, 4)}",
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (mon, yr) = _label;
    final top = month.topTrack;
    return Column(
      children: [
        Pressable(
          scale: 0.985,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 64,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        mon,
                        style: TextStyle(
                          fontFamily: LedgerType.ledger,
                          fontVariations: const [FontVariation('wght', 560)],
                          fontSize: 14,
                          color: open ? Room.lime : Room.ivory,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        yr,
                        style: TextStyle(
                          fontFamily: LedgerType.ledger,
                          fontVariations: const [FontVariation('wght', 460)],
                          fontSize: 11,
                          color: Room.faint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (top != null) ...[
                  ArtTile(url: top.imageUrl, fallbackText: top.name, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LedgerType.bodyStrong.copyWith(
                            color: Room.ivory,
                          ),
                        ),
                        Text(
                          top.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LedgerType.label.copyWith(color: Room.faint),
                        ),
                      ],
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    PlayCount(month.plays),
                    Text(
                      '${hoursFigure(month.ms)} hrs',
                      style: LedgerType.label.copyWith(color: Room.faint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: Motion.reduced(context) ? Duration.zero : Motion.spring,
          curve: Motion.curve,
          alignment: Alignment.topCenter,
          child: open
              ? _MonthDetail(month: month.month)
              : const SizedBox(width: double.infinity),
        ),
        const Divider(height: 1, thickness: 0.5, color: Room.line),
      ],
    );
  }
}

class _MonthDetail extends ConsumerWidget {
  const _MonthDetail({required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(musicMonthDetailProvider(month));
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 16),
      child: detail.when(
        // An opened month fills with the same rows it is about to hold,
        // so the shelf below never jumps as the answer arrives.
        loading: () => const Breathing(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OpenedMonthSkeleton(),
            ],
          ),
        ),
        error: (_, _) => Text(
          'the month would not open — try again',
          style: LedgerType.label.copyWith(color: Room.faint),
        ),
        data: (d) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in d.tracks.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${e.rank}'.padLeft(2, '0'),
                        style: TextStyle(
                          fontFamily: LedgerType.ledger,
                          fontVariations: const [FontVariation('wght', 460)],
                          fontSize: 12,
                          color: e.rank == 1 ? Room.lime : Room.faint,
                        ),
                      ),
                    ),
                    ArtTile(url: e.imageUrl, fallbackText: e.name, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        e.artist == null ? e.name : '${e.name} — ${e.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.bodyText.copyWith(color: Room.ivory),
                      ),
                    ),
                    PlayCount(e.plays, size: 12),
                  ],
                ),
              ),
            if (d.artists.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in d.artists)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Room.raised,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        '${a.name} ×${groupCount(a.plays)}',
                        style: LedgerType.label.copyWith(color: Room.faint),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The five track lines and the artist chips an opened month unfolds into.
class _OpenedMonthSkeleton extends StatelessWidget {
  const _OpenedMonthSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 26,
                  child: Bone(width: 14, height: 10, radius: 2),
                ),
                const Bone(width: 28, height: 28, radius: 6),
                const SizedBox(width: 10),
                Expanded(
                  child: Bone(
                    width: i.isEven ? 186.0 : 148.0,
                    height: 12,
                    radius: 2,
                  ),
                ),
                const Bone(width: 26, height: 10, radius: 2),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in const [86.0, 104.0, 74.0, 96.0])
              Bone(width: w, height: 26, radius: 15),
          ],
        ),
      ],
    );
  }
}
