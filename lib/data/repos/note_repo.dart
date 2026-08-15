import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/note_reminders.dart';
import '../db.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';

final noteRepoProvider = Provider<NoteRepo>(
  (ref) => NoteRepo(ref.watch(dbProvider)),
);

/// The notes book. A note is never deleted from here — archiving slides it
/// off the page; the ink stays in the ledger.
class NoteRepo {
  NoteRepo(this._db);

  final LedgerDb _db;

  /// Writes a new note and returns its id.
  Future<int> create({
    String title = '',
    String body = '',
    DateTime? remindAt,
  }) async {
    final id = await _db.transaction(() async {
      final id = await _db
          .into(_db.notes)
          .insert(
            NotesCompanion(
              title: Value(title),
              body: Value(body),
              remindAt: Value(remindAt),
            ),
          );
      await bbxSync.upsert(SyncKinds.note, id);
      return id;
    });
    if (remindAt != null) await NoteReminders(_db).resync();
    return id;
  }

  /// Rewrites title and/or body, and bumps [Note.updatedAt] so the note
  /// climbs back to the top of its section.
  Future<void> update(int id, {String? title, String? body}) {
    return _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          title: title == null ? const Value.absent() : Value(title),
          body: body == null ? const Value.absent() : Value(body),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await bbxSync.upsert(SyncKinds.note, id);
    });
  }

  /// Pins (or unpins) without touching [Note.updatedAt] — pinning is about
  /// place on the page, not recency.
  Future<void> setPinned(int id, bool pinned) {
    return _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(pinned: Value(pinned)),
      );
      await bbxSync.upsert(SyncKinds.note, id);
    });
  }

  /// Adds, moves or clears a note's one-shot reminder. Moving a completed
  /// reminder makes it active again: choosing another time is an explicit
  /// decision to bring the task back.
  Future<void> setReminder(int id, DateTime? at) async {
    await _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          remindAt: Value(at),
          completed: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await bbxSync.upsert(SyncKinds.note, id);
    });
    await NoteReminders(_db).resync();
  }

  Future<void> setCompleted(int id, bool completed) async {
    await _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          completed: Value(completed),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await bbxSync.upsert(SyncKinds.note, id);
    });
    await NoteReminders(_db).resync();
  }

  /// Slides the note off the page. Nothing is destroyed.
  Future<void> archive(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        const NotesCompanion(archived: Value(true)),
      );
      // NoteIn carries no `archived`; sliding a note off the page is a PATCH.
      await bbxSync.patch(SyncKinds.note, id, {'archived': true});
    });
    await NoteReminders(_db).resync();
  }

  /// Brings an archived note back onto the page, freshly touched so it
  /// surfaces where it can be seen.
  Future<void> restore(int id) async {
    await _db.transaction(() async {
      await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          archived: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await bbxSync.patch(SyncKinds.note, id, {'archived': false});
    });
    await NoteReminders(_db).resync();
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

  /// The notes slid off the page, most recently touched first.
  Stream<List<Note>> watchArchived() {
    final q = _db.select(_db.notes)
      ..where((n) => n.archived.equals(true))
      ..orderBy([(n) => OrderingTerm.desc(n.updatedAt)]);
    return q.watch();
  }
}
