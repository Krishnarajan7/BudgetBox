import 'dart:math';

import 'package:drift/drift.dart';

import '../db.dart';

/// Which local table a synced row belongs to. Plain strings, because the
/// bridge tables key on them and a new module should need no schema change.
abstract final class SyncKinds {
  static const txn = 'txn';
  static const account = 'account';
  static const category = 'category';
  static const budget = 'budget';
  static const recurring = 'recurring';
  static const goal = 'goal';
  static const pinned = 'pinned';
  static const seal = 'seal';
  static const note = 'note';
  static const journal = 'journal';
  static const focus = 'focus';
  static const event = 'event';
  static const vault = 'vault';

  /// Not a row of its own: a confirmed balance reading posted against an
  /// account. It rides the outbox so a balance edited on a train still lands.
  static const anchor = 'anchor';

  /// Kinds the server keys by the day itself, not by a uuid7 — the journal
  /// page and the day seal are one-per-date by construction.
  static const dayKeyed = {seal, journal};

  /// Dependency order: an account must exist upstream before a txn can name
  /// it. The backfill sweep walks this list in order.
  static const inDependencyOrder = [
    account,
    category,
    goal,
    recurring,
    budget,
    pinned,
    txn,
    seal,
    note,
    journal,
    focus,
    event,
    vault,
  ];
}

final Random _entropy = Random.secure();
int _lastMs = 0;
int _seq = 0;

/// A uuid7: 48 bits of millisecond time, then version/variant tags, then
/// randomness. Time-ordered, so the server's primary keys stay clustered and
/// a queue drained out of order still sorts sanely.
///
/// The 12-bit `rand_a` field doubles as a counter within a millisecond, which
/// keeps ids strictly increasing even when the add sheet fires twice in a
/// tick — RFC 9562's "replace leftmost random bits with increased clock
/// precision" method, using a counter instead of sub-ms precision Dart
/// doesn't reliably have.
String newUuid7({DateTime? at, Random? random}) {
  final rnd = random ?? _entropy;
  final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
  if (ms == _lastMs) {
    _seq = (_seq + 1) & 0xfff;
  } else {
    _lastMs = ms;
    _seq = rnd.nextInt(1 << 12);
  }

  final b = List<int>.filled(16, 0);
  b[0] = (ms >> 40) & 0xff;
  b[1] = (ms >> 32) & 0xff;
  b[2] = (ms >> 24) & 0xff;
  b[3] = (ms >> 16) & 0xff;
  b[4] = (ms >> 8) & 0xff;
  b[5] = ms & 0xff;
  b[6] = 0x70 | ((_seq >> 8) & 0x0f); // version 7 in the high nibble
  b[7] = _seq & 0xff;
  for (var i = 8; i < 16; i++) {
    b[i] = rnd.nextInt(256);
  }
  b[8] = 0x80 | (b[8] & 0x3f); // RFC 4122 variant

  final hex = StringBuffer();
  for (var i = 0; i < 16; i++) {
    if (i == 4 || i == 6 || i == 8 || i == 10) hex.write('-');
    hex.write(b[i].toRadixString(16).padLeft(2, '0'));
  }
  return hex.toString();
}

/// True for a well-formed uuid7 — used by the tests and by the puller when it
/// decides whether a string off the wire is an id it can trust.
bool isUuid7(String s) {
  final m = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  return m.hasMatch(s);
}

/// The id bridge: the phone's autoincrement row numbers on one side, the
/// server's uuid7s on the other. Nothing above the repos ever sees the far
/// side of it.
class SyncIds {
  SyncIds(this._db);

  final LedgerDb _db;

  Future<String?> remoteFor(String kind, int localId) async {
    final row = await (_db.select(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.localId.equals(localId)))
        .getSingleOrNull();
    return row?.remoteId;
  }

  Future<int?> localFor(String kind, String remoteId) async {
    final row = await (_db.select(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.remoteId.equals(remoteId)))
        .getSingleOrNull();
    return row?.localId;
  }

  Future<RemoteId?> entry(String kind, int localId) {
    return (_db.select(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.localId.equals(localId)))
        .getSingleOrNull();
  }

  /// Returns the remote id for this row, minting one if it has none.
  ///
  /// Atomic on purpose: the insert is `INSERT OR IGNORE` and the id is read
  /// back afterwards, so two callers racing for the same row agree on one
  /// uuid7 rather than each minting their own and splitting the row in two.
  Future<String> claim(String kind, int localId) async {
    final minted = SyncKinds.dayKeyed.contains(kind)
        ? dayForLocalId(localId)
        : newUuid7();
    await _db.into(_db.remoteIds).insert(
          RemoteIdsCompanion.insert(
            kind: kind,
            localId: localId,
            remoteId: minted,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final settled = await remoteFor(kind, localId);
    // insertOrIgnore also swallows a clash on the (kind, remote_id) unique
    // index; if that somehow happened there is no mapping to return.
    return settled ?? minted;
  }

  /// Records a mapping the server told us about (a row pulled down, not one
  /// the phone minted).
  Future<void> bind(
    String kind,
    int localId,
    String remoteId, {
    DateTime? syncedAt,
  }) {
    return _db.into(_db.remoteIds).insertOnConflictUpdate(
          RemoteIdsCompanion.insert(
            kind: kind,
            localId: localId,
            remoteId: remoteId,
            syncedAt: Value(syncedAt),
          ),
        );
  }

  /// Marks a row as agreed with the server as of [at].
  Future<void> stamp(String kind, int localId, DateTime at) {
    return (_db.update(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.localId.equals(localId)))
        .write(RemoteIdsCompanion(syncedAt: Value(at)));
  }

  Future<void> forget(String kind, int localId) {
    return (_db.delete(_db.remoteIds)
          ..where((r) => r.kind.equals(kind) & r.localId.equals(localId)))
        .go();
  }

  /// Day-keyed kinds have no autoincrement id to bridge, so the day itself is
  /// packed into the int column: '2026-08-01' ⇄ 20260801.
  static int localIdForDay(String day) =>
      int.parse(day.replaceAll('-', '').substring(0, 8));

  static String dayForLocalId(int id) {
    final s = id.toString().padLeft(8, '0');
    return '${s.substring(0, 4)}-${s.substring(4, 6)}-${s.substring(6, 8)}';
  }
}
