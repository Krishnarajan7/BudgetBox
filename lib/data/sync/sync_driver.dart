import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../core/occasions.dart';
import '../providers.dart';
import 'sync_engine.dart';

/// Decides *when* the book talks to the server. It draws nothing: it wraps
/// the app, hands its child straight back, and syncs on the two moments that
/// matter — the app opening, and the app coming back to the front.
///
/// There is no sync button and no spinner anywhere, by design. The screens
/// were finished before the server existed and they are not going to start
/// apologising for the network now; a write is saved the moment the ledger
/// line appears, and the queue settles it whenever there is signal.
///
/// With no `BBX_URL`/`BBX_TOKEN` supplied at launch the engine is inert and
/// this widget costs one lifecycle listener and nothing else.
class SyncDriver extends ConsumerStatefulWidget {
  const SyncDriver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncDriver> createState() => _SyncDriverState();
}

class _SyncDriverState extends ConsumerState<SyncDriver>
    with WidgetsBindingObserver {
  SyncEngine? _engine;

  /// Coming back to the app half a minute after leaving it is not news.
  static const _resumeQuietPeriod = Duration(seconds: 30);
  DateTime? _lastRun;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Reading the provider is what installs the repo seam, so it must happen
    // before any screen can write.
    final engine = ref.read(syncEngineProvider);
    _engine = engine;
    unawaited(_bootstrap());
  }

  /// The address may have been typed into Settings rather than compiled in,
  /// which means one read of the settings table before the engine knows where
  /// it is pointed.
  ///
  /// Nothing is lost by that read landing a few milliseconds late: a book
  /// that writes before it is wired is exactly a book that predates its
  /// server, and the reconciler's catch-up sweep carries that upstream on the
  /// first round.
  Future<void> _bootstrap() async {
    final settings = ref.read(settingsRepoProvider);
    // The nudge is on by default now, and the phone still has to allow it —
    // asked once, at a launch, never buried behind a toggle.
    if (await settings.nudgeTime() != null &&
        !await settings.nudgePermissionAsked()) {
      await settings.markNudgePermissionAsked();
      await LedgerReminders.requestPermission();
    }
    // Re-assert the book's voice every launch: schedules survive reboots
    // via the boot receiver, but not an app update — and re-scheduling the
    // same ids is free.
    unawaited(ref.read(nudgesProvider).resync());
    // Every calendar day's notification stands again after reboots and
    // app updates.
    unawaited(Occasions(ref.read(dbProvider)).resyncNotifications());
    final stored = await settings.serverConfig();
    if (!mounted) return;
    _engine?.reconfigure(stored);
    if (_engine?.wired ?? false) await _run();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving is the moment tonight's nudge is re-voiced: whatever was
    // written this session is what the evening line should carry.
    if (state == AppLifecycleState.paused) {
      unawaited(ref.read(nudgesProvider).resync());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    // Coming back is when the book catches up with the clock: days that
    // ended while it was away seal themselves, and tonight's nudge
    // re-reads the page it now stands on.
    unawaited(ref.read(nudgesProvider).resync());
    final last = _lastRun;
    if (last != null && DateTime.now().difference(last) < _resumeQuietPeriod) {
      return;
    }
    unawaited(_run());
  }

  Future<void> _run() async {
    final engine = _engine;
    if (engine == null || !engine.wired) return;
    _lastRun = DateTime.now();
    // A failed sync is not the user's problem to solve mid-gesture: the queue
    // keeps what is owed and the next resume tries again.
    try {
      await engine.syncNow();
    } on Object {
      // Deliberately swallowed — engine.status carries the detail.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
