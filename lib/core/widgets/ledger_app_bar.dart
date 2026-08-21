import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/settings_page.dart';
import '../../features/shelf/shelf_overlay.dart';
import '../../features/weather/weather_page.dart';
import '../holidays.dart';
import '../tokens.dart';
import '../typography.dart';
import '../weather.dart';
import 'motion.dart';
import 'pen_marks.dart';
import 'sky_marks.dart';

/// Wordmark (tap → the shelf) · the day's weather and whatever the country
/// calls to-morrow · optional trailing · gear (→ the box's settings). Every
/// root screen wears this.
///
/// The sky and the named day live up here rather than in the page because
/// neither is news: they are the kind of thing you glance at, like the time.
/// Both are marks, not sentences — tap one and it says what it means.
class LedgerAppBar extends ConsumerWidget {
  const LedgerAppBar({super.key, this.title, this.trailing});

  /// Defaults to the wordmark; a section name (Book, Plans…) elsewhere.
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        children: [
          // The wordmark yields first: chrome on the right is information,
          // and a bar that overflows is worse than a shortened name.
          Expanded(
            child: Pressable(
              scale: 0.97,
              onTap: () => showShelf(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title ?? 'Krish Space',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.wordmark.copyWith(color: c.ink),
                    ),
                  ),
                  const SizedBox(width: 3),
                  PenChevron(size: 12, color: c.inkFaint),
                ],
              ),
            ),
          ),
          const SizedBox(width: Gap.x2),
          const HolidayMark(),
          const SkyMarkChip(),
          ?trailing,
          if (trailing != null) const SizedBox(width: Gap.x3),
          Pressable(
            scale: 0.9,
            onTap: () => Navigator.of(
              context,
            ).push(LedgerRoute<void>(builder: (_) => const SettingsPage())),
            // The box's mark: adjustments drawn as dots on rules, the way a
            // ledger would show its settings — never Material's machine gear.
            child: PenSliders(size: 17, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// The sky as one small drawn mark and the temperature beside it. Tap it and
/// it says the words: "overcast · 15° now · 22° / 12° to-day". Double-tap
/// and the sky gets its whole page.
class SkyMarkChip extends ConsumerWidget {
  const SkyMarkChip({super.key});

  /// "feels 38°", when that is worth saying. Null when the reading carries
  /// no apparent temperature, or when it agrees with the real one.
  static String? _feelsLine(Weather sky) {
    final feels = sky.feelsC;
    if (feels == null || (feels - sky.nowC).abs() < 2) return null;
    return 'feels ${feels.round()}°';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final sky = ref.watch(weatherProvider).value;
    if (sky == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final stale = sky.staleness(now);
    return GestureDetector(
      // A second tap within the window wins the gesture arena, so a single
      // tap still opens the tooltip — just a beat later.
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        Navigator.of(
          context,
        ).push(LedgerRoute<void>(builder: (_) => const WeatherPage()));
      },
      child: _Says(
        message: [
          Weather.describe(sky.code),
          // Now that the reading carries the hour, the tooltip names it:
          // "rain by 6 pm" is something to act on, "rain later" is trivia.
          ?(Weather.isWet(sky.code) ? null : sky.rainLine),
          '${sky.nowC.round()}° now',
          // What it feels like, when that differs enough to matter — the
          // number that decides whether you take the bike. Within a degree
          // or two of the real one it is just noise, so it stays off.
          ?_feelsLine(sky),
          sky.bracket,
          ?sky.sunLine(now),
          ?stale,
        ].join(' · '),
        child: Padding(
          padding: const EdgeInsets.only(right: Gap.x3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkyMark(
                shape: skyShapeFor(sky.code, night: sky.isNight(now)),
                color: c.inkFaint,
                size: 20,
              ),
              const SizedBox(width: 5),
              Text(
                '${sky.nowC.round()}°',
                style: LedgerType.amount.copyWith(fontSize: 12, color: c.ink),
              ),
              const SizedBox(width: 5),
              // The word as well as the mark: a drawn cloud is a guess until
              // it is read once, and this bar is not a quiz. Capped, so a
              // long condition can never crowd the wordmark off the page.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 64),
                child: Text(
                  Weather.shortLabel(sky.code),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 11,
                    color: c.inkFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A day the country names, drawn as a torn calendar leaf carrying its own
/// date — the same leaf the agenda and the plans use for anything dated, so
/// it needs no explaining: a date, marked. Vermilion when the day is off,
/// plain ink when it is a festival that closes nothing.
///
/// It only appears when that day is to-day or the next two. A mark that is
/// always there is furniture, and furniture is not a notification.
class HolidayMark extends ConsumerWidget {
  const HolidayMark({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(holidayBookProvider).value;
    if (book == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final next = book.next(now, within: 2);
    if (next == null) return const SizedBox.shrink();
    final line = dayLine(book, now);
    if (line == null) return const SizedBox.shrink();

    return _Says(
      message: line,
      child: Padding(
        padding: const EdgeInsets.only(right: Gap.x3),
        child: DayLeaf(day: next.holiday.date, off: next.holiday.isDayOff),
      ),
    );
  }
}

/// A calendar leaf the size of a glyph: a paper block under a vermilion
/// cap, carrying its own date. The same leaf the agenda and the plans use
/// for anything dated, so it needs no explaining — a date, torn off and
/// held up. A festival keeps the shape and loses the vermilion.
class DayLeaf extends StatelessWidget {
  const DayLeaf({super.key, required this.day, this.off = true});

  final DateTime day;

  /// A day off wears the vermilion cap; a festival keeps to ink.
  final bool off;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      width: 22,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.paperRaised,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: c.rule, width: 0.8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The cap: the red band across the top of every wall calendar.
          Container(height: 5, color: off ? c.seal : c.inkFaint),
          Padding(
            padding: const EdgeInsets.only(top: 1.5, bottom: 2),
            child: Text(
              '${day.day}',
              style: LedgerType.amount.copyWith(
                fontSize: 12,
                height: 1,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A mark that answers when you tap it — the book's tooltip: paper, a
/// hairline, and the same voice as everything else. Never on hover-only,
/// because a thumb doesn't hover.
class _Says extends StatelessWidget {
  const _Says({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      preferBelow: true,
      margin: const EdgeInsets.symmetric(horizontal: Gap.page),
      padding: const EdgeInsets.symmetric(
        horizontal: Gap.x3,
        vertical: Gap.x2,
      ),
      decoration: BoxDecoration(
        color: c.paperRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.rule),
      ),
      textStyle: LedgerType.bodyText.copyWith(fontSize: 13, color: c.ink),
      child: child,
    );
  }
}
