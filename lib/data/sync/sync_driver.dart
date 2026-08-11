import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final stored = await ref.read(settingsRepoProvider).serverConfig();
    if (!mounted) return;
    _engine?.reconfigure(stored);
    if (_engine?.wired ?? false) await _run();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastRun;
    if (last != null &&
        DateTime.now().difference(last) < _resumeQuietPeriod) {
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
