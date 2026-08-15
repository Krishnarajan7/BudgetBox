import 'package:drift/drift.dart' show BooleanExpressionOperators;

import '../data/db.dart';
import 'notifications.dart';

/// Keeps actionable notes and the operating system's pending notifications
/// in exact agreement. Called after reminder mutations, after sync pulls and
/// at launch so reboots and app upgrades cannot make a reminder disappear.
class NoteReminders {
  const NoteReminders(this._db);

  final LedgerDb _db;

  Future<void> resync() async {
    final now = DateTime.now();
    final rows =
        await (_db.select(_db.notes)..where(
              (n) =>
                  n.archived.equals(false) &
                  n.completed.equals(false) &
                  n.remindAt.isNotNull(),
            ))
            .get();
    final upcoming = <int, (String, String, DateTime)>{};
    for (final note in rows) {
      final at = note.remindAt;
      if (at == null || !at.isAfter(now)) continue;
      final title = note.title.trim().isEmpty
          ? 'A note for you'
          : note.title.trim();
      final body = note.body
          .split('\n')
          .map((line) => line.trim())
          .firstWhere(
            (line) => line.isNotEmpty,
            orElse: () => 'You asked me to keep this in sight.',
          );
      upcoming[note.id] = (title, body, at);
    }
    await LedgerReminders.scheduleNotes(upcoming);
  }
}
