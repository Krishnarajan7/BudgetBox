import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One app-wide undo offer. While it stands, the floating nav steps aside
/// and the shell shows this instead — a toast in the tab bar's place with a
/// draining ring. The owner of the struck thing keeps the timers and the
/// truth; the shell only renders the offer and forwards the tap.
class UndoBanner {
  const UndoBanner({
    required this.id,
    required this.label,
    required this.duration,
    required this.onUndo,
  });

  /// Identifies the struck thing, so a newer strike can replace the offer
  /// and a stale timeout can't clear the wrong one.
  final int id;
  final String label;
  final Duration duration;
  final void Function() onUndo;
}

class UndoBannerNotifier extends Notifier<UndoBanner?> {
  @override
  UndoBanner? build() => null;

  void offer(UndoBanner banner) => state = banner;

  /// Clears only if the standing offer is [id]'s — a stale timeout can't
  /// take down a newer strike's offer.
  void clear(int id) {
    if (state?.id == id) state = null;
  }
}

final undoBannerProvider = NotifierProvider<UndoBannerNotifier, UndoBanner?>(
  UndoBannerNotifier.new,
);
