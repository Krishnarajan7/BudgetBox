import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../db.dart';
import '../providers.dart';
import 'adopt.dart';
import 'outbox.dart';
import 'puller.dart';
import 'reconcile.dart';
import 'seam.dart';
import 'settings_sync.dart';
import 'wire.dart';

/// Reading this once at startup is the whole wiring: it installs the repo
/// seam and hands back the thing that can be told to sync. It lives here
/// rather than in `providers.dart` for the same reason the other repos'
/// providers do — the module owns its own door.
///
/// Nothing calls it yet. Until the app decides when to sync (launch, resume,
/// pull-to-refresh), an unwatched provider is never built and this layer
/// stays asleep.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(db: ref.watch(dbProvider))..install();
  ref.onDispose(engine.dispose);
  return engine;
});

enum SyncPhase {
  /// Nothing in flight. Also what an unwired app is, forever.
  idle,

  syncing,

  /// The last attempt could not reach the server. Everything owed is still
  /// owed, and nothing was lost.
  offline,

  /// The token is missing or wrong. Retrying will not fix it; a person must.
  blocked,
}

@immutable
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSyncedAt,
    this.pending = 0,
    this.parked = 0,
    this.lastError,
  });

  final SyncPhase phase;

  /// When the phone and the server last agreed.
  final DateTime? lastSyncedAt;

  /// Writes still owed and still worth trying.
  final int pending;

  /// Writes the server refused often enough to be set aside. These need
  /// looking at; they are not retried, and they block nothing.
  final int parked;

  final String? lastError;

  bool get busy => phase == SyncPhase.syncing;

  SyncStatus _with({
    SyncPhase? phase,
    DateTime? lastSyncedAt,
    int? pending,
    int? parked,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncStatus(
      phase: phase ?? this.phase,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      pending: pending ?? this.pending,
      parked: parked ?? this.parked,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  @override
  String toString() =>
      'SyncStatus(${phase.name}, pending: $pending, parked: $parked)';
}

/// The conductor.
///
/// One order, always: **push, then pull.** The phone's own writes go up
/// first, so what comes down is already an answer to them rather than a
/// stale contradiction of them. A second [syncNow] while one is running is
/// dropped rather than queued — two drains racing over the same rows is the
/// one way this design could double-send.
///
/// When [BbxConfig.wired] is false the engine does *nothing at all*: it never
/// installs the repo seam, so no outbox row is ever written and the app
/// behaves exactly as it did before there was a server to talk to.
class SyncEngine {
  factory SyncEngine({
    required LedgerDb db,
    BbxConfig? config,
    http.Client? httpClient,
  }) {
    return SyncEngine._(
      db,
      SyncOutbox(db),
      config ?? BbxConfig.fromEnvironment(),
      httpClient,
    );
  }

  SyncEngine._(
    LedgerDb db,
    SyncOutbox outbox,
    this._config,
    http.Client? httpClient,
  ) : _outbox = outbox,
      _httpOverride = httpClient,
      _adopter = SyncAdopter(db),
      _reconciler = SyncReconciler(db, outbox),
      _puller = SyncPuller(db, outbox),
      _settings = SettingsSync(db) {
    _client = BbxClient(_config, inner: httpClient);
    _wire = SyncWire(_client);
  }

  BbxConfig _config;
  final SyncOutbox _outbox;
  final http.Client? _httpOverride;
  final SyncAdopter _adopter;
  final SyncReconciler _reconciler;
  final SyncPuller _puller;
  final SettingsSync _settings;
  late BbxClient _client;
  late SyncWire _wire;

  final ValueNotifier<SyncStatus> status = ValueNotifier<SyncStatus>(
    const SyncStatus(),
  );

  bool _running = false;

  BbxConfig get config => _config;

  bool get wired => _config.wired;

  /// Points every repo's writes at this engine's outbox. Called once at
  /// startup; a no-op when nothing is configured.
  void install() {
    if (!wired) return;
    installSyncSeam(OutboxSeam(_outbox));
  }

  /// Point the book at a different server, or at none at all.
  ///
  /// Wiring a book that has been keeping accounts locally loses nothing: the
  /// reconciler's catch-up sweep queues everything the server has never been
  /// told about on the next round, so months of history walk upstream by
  /// themselves. Unwiring stops the queue being written to; it never touches
  /// what is already on the page.
  void reconfigure(BbxConfig next) {
    if (next == _config) return;
    _client.close();
    _config = next;
    _client = BbxClient(next, inner: _httpOverride);
    _wire = SyncWire(_client);
    if (next.wired) {
      installSyncSeam(OutboxSeam(_outbox));
    } else {
      uninstallSyncSeam();
    }
    // The old server's verdict says nothing about the new one.
    status.value = const SyncStatus();
  }

  /// One round-trip that proves an address and a token before they are
  /// saved. Returns null when the server answered; a sentence when it did
  /// not.
  static Future<String?> probe(BbxConfig config, {http.Client? inner}) async {
    if (!config.wired) return 'an address and a token are both needed';
    final client = BbxClient(config, inner: inner);
    try {
      await client.get('/v1/ping');
      return null;
    } on BbxOffline catch (e) {
      return 'could not reach it — ${e.detail}';
    } on BbxProblem catch (e) {
      return e.status == 401 || e.status == 403
          ? 'the server is there, but it refused that token'
          : 'the server answered ${e.status} — ${e.detail}';
    } finally {
      client.close();
    }
  }

  /// Push what is owed, then take what is new. Safe to call as often as the
  /// app likes; overlapping calls are dropped, not stacked.
  Future<void> syncNow() async {
    if (!wired || _running) return;
    _running = true;
    status.value = status.value._with(
      phase: SyncPhase.syncing,
      clearError: true,
    );
    try {
      // Before anything is pushed as new, let rows that already exist on both
      // sides recognise each other — otherwise the very first sweep doubles
      // the seeded categories.
      //
      // If that conversation fails there is no safe way to continue: pushing
      // without it is precisely what creates the duplicates. So a failure
      // here ends the round with nothing sent, the adoption flag unset, and
      // the queue exactly as it was — the next attempt starts over.
      try {
        await _adopter.adopt(_wire);
      } on BbxOffline catch (e) {
        await _settle(SyncPhase.offline, e.detail);
        return;
      } on BbxProblem catch (e) {
        await _settle(SyncPhase.blocked, e.detail);
        return;
      }

      await _reconciler.sweep();

      final drained = await _outbox.drain(_wire);
      if (drained.stop != DrainStop.done) {
        await _settle(
          drained.stop == DrainStop.offline
              ? SyncPhase.offline
              : SyncPhase.blocked,
          drained.detail,
        );
        return;
      }

      final queueEmpty = await _outbox.totalCount() == 0;
      final pulled = await _puller.pull(_wire, queueEmpty: queueEmpty);
      if (pulled.offline) {
        await _settle(SyncPhase.offline, pulled.detail);
        return;
      }

      // Preferences last, and never fatal: a theme that did not make it up
      // is not a reason to call a round that moved the ledger a failure.
      try {
        await _settings.run(_client);
      } on BbxOffline {
        // The round already succeeded; the next one carries these.
      } on BbxProblem {
        // Same. A refused preference must not park the ledger.
      }

      await _settle(SyncPhase.idle, null, at: pulled.at ?? DateTime.now());
    } on Object catch (e) {
      // The catch-all that keeps the status honest. Anything unexpected —
      // a server speaking an older dialect, a parse error, a bug — must
      // still settle the phase, or "talking to the server…" hangs on the
      // settings row forever while nothing is talking at all.
      await _settle(
        SyncPhase.blocked,
        'the answer made no sense — the server and the app may be '
        'out of step ($e)',
      );
    } finally {
      _running = false;
    }
  }

  /// The counts a sync page would show, without running a sync.
  Future<void> refresh() async {
    if (!wired) return;
    await _settle(status.value.phase, status.value.lastError);
  }

  Future<void> _settle(SyncPhase phase, String? error, {DateTime? at}) async {
    status.value = status.value._with(
      phase: phase,
      lastSyncedAt: at,
      pending: await _outbox.pendingCount(),
      parked: await _outbox.parkedCount(),
      lastError: error,
      clearError: error == null,
    );
  }

  void dispose() {
    uninstallSyncSeam();
    _client.close();
    status.dispose();
  }
}
