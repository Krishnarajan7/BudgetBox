import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The spine's four pages, by slot.
abstract final class LedgerTab {
  static const today = 0;
  static const book = 1;
  static const plans = 2;
  static const worth = 3;
}

/// Which page of the spine is open. Pages listen for their own slot coming
/// active and replay their pen flourishes — the chart re-drawing, the
/// underline re-crossing — without remounting: the data stays settled, only
/// the ink performs. (The old per-visit "entrance" was a remount bug; this
/// is the deliberate version of what it accidentally provided.)
class ActiveTabNotifier extends Notifier<int> {
  @override
  int build() => LedgerTab.today;

  void set(int index) => state = index;
}

final activeTabProvider = NotifierProvider<ActiveTabNotifier, int>(
  ActiveTabNotifier.new,
);
