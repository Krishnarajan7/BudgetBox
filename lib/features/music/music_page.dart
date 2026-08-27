import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/api/endpoints/endpoints.dart';
import '../../data/providers.dart';
import '../shelf/shelf_overlay.dart';
import 'music_providers.dart';
import 'room.dart';
import 'widgets/artist_wall.dart';
import 'widgets/month_shelf.dart';
import 'widgets/now_bar.dart';
import 'widgets/skeleton.dart';
import 'widgets/top_tracks.dart';

/// The listening room — the one book that is always dark. Spotify won't keep
/// a history (50 plays and the past is gone), so the backend records every
/// play and this page is the record: how much, what most, who most, and the
/// months.
class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({super.key});

  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage> {
  String _range = 'month';

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(musicGateProvider);
    return Scaffold(
      backgroundColor: Room.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            Expanded(
              child: gate.when(
                loading: () => const RoomSkeleton(),
                error: (_, _) => _Word(
                  title: 'The room would not open.',
                  body: 'Something went wrong reading the record. '
                      'Pull back and try again.',
                ),
                data: (g) => switch (g) {
                  MusicUnwired() => const _Word(
                    title: 'This book lives on the server.',
                    body:
                        'The music record is kept by the backend — wire the '
                        'book to the server in Settings and the room opens.',
                  ),
                  MusicAway() => _Word(
                    title: 'The server is away.',
                    body: 'The record is safe; it just can\'t be read right '
                        'now. Try again in a moment.',
                    action: 'try again',
                    onAction: () => ref.invalidate(musicGateProvider),
                  ),
                  MusicSilent() => const _ConnectPoster(),
                  MusicOpen(overview: final o) => RefreshIndicator(
                    color: Room.lime,
                    backgroundColor: Room.raised,
                    onRefresh: () async {
                      ref.invalidate(musicGateProvider);
                      ref.invalidate(musicTopProvider);
                      ref.invalidate(musicMonthsProvider);
                      ref.invalidate(musicNowProvider);
                    },
                    child: _open(context, o),
                  ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Same affordances as every book (back, name opens the shelf) — different
  /// room, so it is set by hand rather than through ModuleScaffold.
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Pressable(
            scale: 0.9,
            onTap: () => Navigator.of(context).pop(),
            child: const RotatedBox(
              quarterTurns: 1,
              child: PenChevron(size: 16, color: Room.faint),
            ),
          ),
          const SizedBox(width: 12),
          Pressable(
            scale: 0.97,
            onTap: () => showShelf(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Music',
                  style: LedgerType.wordmark.copyWith(color: Room.ivory),
                ),
                const SizedBox(width: 2),
                const PenChevron(size: 12, color: Room.faint),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _open(BuildContext context, MusicOverview o) {
    final top = ref.watch(musicTopProvider(_range));
    final months = ref.watch(musicMonthsProvider);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 14, bottom: 48),
      children: [
        const NowBar(),
        _Rise(order: 0, child: _hero(o)),
        if (!o.connected)
          _Rise(order: 0, child: const _ConnectNudge()),
        const SizedBox(height: 30),
        _Rise(order: 1, child: _rangeRow()),
        const SizedBox(height: 22),
        _Rise(
          order: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const RoomLabel('most played'),
                const SizedBox(height: 16),
                top.when(
                  // The range switched: the labels and the layout hold
                  // still, only the rows go back to bones. Nothing below
                  // the fold moves.
                  loading: () => const Breathing(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TopListSkeleton(),
                        SizedBox(height: 30),
                        Bone(width: 62, height: 11, radius: 2),
                        SizedBox(height: 16),
                        WallSkeleton(),
                      ],
                    ),
                  ),
                  error: (_, _) => Text(
                    'the lists would not load — pull to retry',
                    style: LedgerType.bodyText.copyWith(color: Room.faint),
                  ),
                  data: (t) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TopTracks(entries: t.tracks),
                      const SizedBox(height: 30),
                      const RoomLabel('the wall'),
                      const SizedBox(height: 16),
                      ArtistWall(entries: t.artists),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 34),
        _Rise(
          order: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: months.when(
              loading: () => const Breathing(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RoomLabel('the months'),
                    SizedBox(height: 6),
                    MonthsSkeleton(),
                  ],
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
              data: (m) => m.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const RoomLabel('the months'),
                        const SizedBox(height: 6),
                        MonthShelf(months: m),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        _Rise(order: 4, child: _footer(o)),
      ],
    );
  }

  Widget _hero(MusicOverview o) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const RoomLabel('on record'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              HeroCount(
                value: (o.totalMs / 3600000).round(),
                format: (v) =>
                    o.totalMs >= 360000000 ? groupCount(v) : hoursFigure(o.totalMs),
                style: const TextStyle(
                  fontFamily: LedgerType.headline,
                  fontSize: 72,
                  height: 1,
                  letterSpacing: -2,
                  color: Room.ivory,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'hours of music',
                style: TextStyle(
                  fontFamily: LedgerType.headline,
                  fontSize: 20,
                  color: Room.faint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _LimeRule(),
          const SizedBox(height: 12),
          Text(
            '${groupCount(o.totalPlays)} plays · '
            '${groupCount(o.distinctArtists)} artists · '
            '${groupCount(o.distinctTracks)} songs'
            '${o.since == null ? '' : ' · since ${_dateWord(o.since!)}'}',
            style: TextStyle(
              fontFamily: LedgerType.ledger,
              fontVariations: const [FontVariation('wght', 460)],
              fontSize: 12.5,
              color: Room.faint,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangeRow() {
    const ranges = [
      ('month', 'this month'),
      ('year', 'this year'),
      ('all', 'all time'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (final (key, word) in ranges) ...[
            Pressable(
              onTap: () => setState(() => _range = key),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: Motion.quick,
                    style: TextStyle(
                      fontFamily: LedgerType.ledger,
                      fontVariations: const [FontVariation('wght', 560)],
                      fontSize: 12,
                      letterSpacing: 1.6,
                      color: _range == key ? Room.ivory : Room.faint,
                    ),
                    child: Text(word.toUpperCase()),
                  ),
                  const SizedBox(height: 5),
                  AnimatedContainer(
                    duration: Motion.spring,
                    curve: Motion.curve,
                    height: 2,
                    width: _range == key ? 26 : 0,
                    color: Room.lime,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 26),
          ],
        ],
      ),
    );
  }

  Widget _footer(MusicOverview o) {
    final polled = o.recordingSince;
    final backfilled = o.since != null &&
        polled != null &&
        o.since!.isBefore(polled);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        polled == null
            ? 'The recorder is set — the book fills as you listen.'
            : backfilled
                ? 'Recording live since ${_dateWord(polled)}; everything '
                      'earlier recovered from Spotify\'s export.'
                : 'Recording since ${_dateWord(polled)}. The years before '
                      'can be recovered with Spotify\'s extended streaming '
                      'history export — budgetbox music import.',
        style: LedgerType.label.copyWith(color: Room.faint, height: 1.5),
      ),
    );
  }

  static String _dateWord(DateTime d) =>
      '${LedgerDates.ddMmm(d)} ${d.year}';
}

/// The lime stroke under the hero figure: draws left-to-right when the page
/// lands, instant under reduced motion.
class _LimeRule extends StatelessWidget {
  const _LimeRule();

  @override
  Widget build(BuildContext context) {
    const rule = SizedBox(
      width: 54,
      height: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Room.lime,
          borderRadius: BorderRadius.all(Radius.circular(1.5)),
        ),
      ),
    );
    if (Motion.reduced(context)) return rule;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.draw,
      curve: Curves.easeOutCubic,
      builder: (_, t, _) => Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 54 * t,
          height: 3,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Room.lime,
              borderRadius: BorderRadius.all(Radius.circular(1.5)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sections rise into place one after another, on the book's one spring.
class _Rise extends StatelessWidget {
  const _Rise({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.settle + Duration(milliseconds: 90 * order),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

/// A quiet page of words for the states with nothing to show.
class _Word extends StatelessWidget {
  const _Word({
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: LedgerType.title.copyWith(color: Room.ivory),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: LedgerType.bodyText.copyWith(
                color: Room.faint,
                height: 1.5,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              _LimeButton(word: action!, onTap: onAction ?? () {}),
            ],
          ],
        ),
      ),
    );
  }
}

/// First opening: the room exists, nothing has been heard. One action.
class _ConnectPoster extends ConsumerWidget {
  const _ConnectPoster();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const RoomLabel('the listening room'),
            const SizedBox(height: 14),
            Text(
              'Nothing on record yet.',
              style: TextStyle(
                fontFamily: LedgerType.headline,
                fontSize: 34,
                height: 1.15,
                color: Room.ivory,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Spotify only remembers your last 50 plays — connect once and '
              'the book starts keeping all of them, every half hour, '
              'forever.',
              style: LedgerType.bodyText.copyWith(
                color: Room.faint,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _ConnectAction(),
            const SizedBox(height: 14),
            Text(
              'Needs the Spotify app registered on the server and an active '
              'Premium account.',
              style: LedgerType.label.copyWith(color: Room.faint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data exists (the import came first) but the recorder isn't connected —
/// a nudge, not a wall.
class _ConnectNudge extends StatelessWidget {
  const _ConnectNudge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Room.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The recorder is off — these plays came from the export. '
            'Connect Spotify and the book keeps itself.',
            style: LedgerType.bodyText.copyWith(
              color: Room.faint,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          _ConnectAction(),
        ],
      ),
    );
  }
}

/// Fetches the consent URL and puts it on the clipboard — the handshake
/// itself belongs to a real browser, once.
class _ConnectAction extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ConnectAction> createState() => _ConnectActionState();
}

class _ConnectActionState extends ConsumerState<_ConnectAction> {
  bool _busy = false;
  String? _word;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _word = null;
    });
    try {
      final url = await musicConnectUrl(ref.read(settingsRepoProvider));
      await Clipboard.setData(ClipboardData(text: url));
      setState(() => _word = 'Link copied — open it in any browser.');
    } catch (_) {
      setState(() => _word = 'The server could not start the handshake.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LimeButton(
          word: _busy ? 'asking…' : 'copy connect link',
          onTap: _busy ? () {} : _go,
        ),
        if (_word != null) ...[
          const SizedBox(height: 8),
          Text(_word!, style: LedgerType.label.copyWith(color: Room.faint)),
        ],
      ],
    );
  }
}

class _LimeButton extends StatelessWidget {
  const _LimeButton({required this.word, required this.onTap});

  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: Room.lime,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          word.toUpperCase(),
          style: const TextStyle(
            fontFamily: LedgerType.ledger,
            fontVariations: [FontVariation('wght', 600)],
            fontSize: 12,
            letterSpacing: 1.6,
            color: Room.bg,
          ),
        ),
      ),
    );
  }
}
