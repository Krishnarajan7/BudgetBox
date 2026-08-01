import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db.dart';
import '../providers.dart';

final noteRepoProvider =
    Provider<NoteRepo>((ref) => NoteRepo(ref.watch(dbProvider)));

/// The notes book. A note is never deleted from here — archiving slides it
/// off the page; the ink stays in the ledger.
class NoteRepo {
  NoteRepo(this._db);

  final LedgerDb _db;

  /// Writes a new note and returns its id.
  Future<int> create({String title = '', String body = ''}) {
    return _db.into(_db.notes).insert(
          NotesCompanion(
            title: Value(title),
            body: Value(body),
          ),
        );
  }

  /// Rewrites title and/or body, and bumps [Note.updatedAt] so the note
  /// climbs back to the top of its section.
  Future<void> update(int id, {String? title, String? body}) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        body: body == null ? const Value.absent() : Value(body),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Pins (or unpins) without touching [Note.updatedAt] — pinning is about
  /// place on the page, not recency.
  Future<void> setPinned(int id, bool pinned) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id)))
        .write(NotesCompanion(pinned: Value(pinned)));
  }

  /// Slides the note off the page. Nothing is destroyed.
  Future<void> archive(int id) {
    return (_db.update(_db.notes)..where((n) => n.id.equals(id)))
        .write(const NotesCompanion(archived: Value(true)));
  }

  /// Active notes: pinned first, then most recently touched.
  Stream<List<Note>> watchAll() {
    final q = _db.select(_db.notes)
      ..where((n) => n.archived.equals(false))
      ..orderBy([
        (n) => OrderingTerm.desc(n.pinned),
        (n) => OrderingTerm.desc(n.updatedAt),
      ]);
    return q.watch();
  }
}
