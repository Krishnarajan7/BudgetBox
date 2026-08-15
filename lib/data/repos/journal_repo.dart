import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../db.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';

final journalRepoProvider = Provider<JournalRepo>(
  (ref) => JournalRepo(ref.watch(dbProvider)),
);

/// The journal's page-keeper. One row per day ('yyyy-MM-dd'); words and mood
/// autosave independently, and [dayFacts] reads the rest of the box so each
/// page arrives half-written.
class JournalRepo {
  JournalRepo(this._db);

  final LedgerDb _db;

  /// Writes only what was passed: `upsert(d, mood: 4)` never touches the
  /// body, and `upsert(d, body: '…')` never touches the mood. A mood write
  /// is a *felt* write — it carries energy and the chosen word with it
  /// (nulls included), because the field always commits the three together.
  /// Creates the page if it doesn't exist yet; always bumps
  /// [JournalEntry.updatedAt].
  Future<void> upsert(
    String date, {
    String? body,
    int? mood,
    int? energy,
    String? feelWord,
    String? feelWhy,
    String? feelTags,
  }) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      await _db
          .into(_db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              date: date,
              body: Value(body ?? ''),
              mood: Value(mood),
              energy: Value(energy),
              feelWord: Value(feelWord),
              feelWhy: Value(feelWhy),
              feelTags: Value(feelTags),
              updatedAt: Value(now),
            ),
            onConflict: DoUpdate(
              (old) => JournalEntriesCompanion(
                body: body == null ? const Value.absent() : Value(body),
                mood: mood == null ? const Value.absent() : Value(mood),
                energy: mood == null ? const Value.absent() : Value(energy),
                feelWord: mood == null
                    ? const Value.absent()
                    : Value(feelWord),
                // The second breath writes on its own: passed → written,
                // empty string → cleared, null → left alone.
                feelWhy: feelWhy == null
                    ? const Value.absent()
                    : Value(feelWhy),
                feelTags: feelTags == null
                    ? const Value.absent()
                    : Value(feelTags),
                updatedAt: Value(now),
              ),
            ),
          );
      // The journal is keyed by day both here and upstream, so the day is
      // the id — no uuid7 involved.
      await bbxSync.upsertDay(SyncKinds.journal, date);
    });
  }

  /// One day's page, or null while it's still blank.
  Stream<JournalEntry?> watch(String date) {
    return (_db.select(
      _db.journalEntries,
    )..where((e) => e.date.equals(date))).watchSingleOrNull();
  }

  /// Every written page, newest first.
  Stream<List<JournalEntry>> watchAll() {
    return (_db.select(
      _db.journalEntries,
    )..orderBy([(e) => OrderingTerm.desc(e.date)])).watch();
  }

  /// Every past year's page for this same month-and-day, newest year first —
  /// the "on this day" shelf. To-day itself and wordless pages stay out.
  Future<List<JournalEntry>> onThisDay(DateTime today) async {
    final suffix =
        '-${today.month.toString().padLeft(2, '0')}'
        '-${today.day.toString().padLeft(2, '0')}';
    final todayKey = '${today.year.toString().padLeft(4, '0')}$suffix';
    final rows =
        await (_db.select(_db.journalEntries)
              ..where((e) => e.date.like('%$suffix'))
              ..orderBy([(e) => OrderingTerm.desc(e.date)]))
            .get();
    return [
      for (final r in rows)
        if (r.date != todayKey && r.body.trim().isNotEmpty) r,
    ];
  }

  /// Pages whose words hold [query], newest first. LIKE is enough for one
  /// person's journal; nobody indexes their own diary.
  Future<List<JournalEntry>> search(String query) {
    final q = '%${query.trim()}%';
    return (_db.select(_db.journalEntries)
          ..where((e) => e.body.like(q))
          ..orderBy([(e) => OrderingTerm.desc(e.date)]))
        .get();
  }

  /// What the rest of the box already knows about [day]: money out (expenses
  /// only), completed work-focus minutes, and notes written that day.
  Future<({int spentPaise, int txnCount, int focusMinutes, int notesCount})>
  dayFacts(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);

    final spentSum = _db.txns.amountPaise.sum();
    final txnCount = _db.txns.id.count();
    final spentRow =
        await (_db.selectOnly(_db.txns)
              ..addColumns([spentSum, txnCount])
              ..where(
                _db.txns.type.equalsValue(TxnType.expense) &
                    _db.txns.at.isBiggerOrEqualValue(start) &
                    _db.txns.at.isSmallerThanValue(end),
              ))
            .getSingle();

    final focusSum = _db.focusSessions.minutes.sum();
    final focusRow =
        await (_db.selectOnly(_db.focusSessions)
              ..addColumns([focusSum])
              ..where(
                _db.focusSessions.kind.equalsValue(FocusKind.work) &
                    _db.focusSessions.completed.equals(true) &
                    _db.focusSessions.startedAt.isBiggerOrEqualValue(start) &
                    _db.focusSessions.startedAt.isSmallerThanValue(end),
              ))
            .getSingle();

    final notesCount = _db.notes.id.count();
    final notesRow =
        await (_db.selectOnly(_db.notes)
              ..addColumns([notesCount])
              ..where(
                _db.notes.archived.equals(false) &
                    _db.notes.createdAt.isBiggerOrEqualValue(start) &
                    _db.notes.createdAt.isSmallerThanValue(end),
              ))
            .getSingle();

    return (
      spentPaise: spentRow.read(spentSum) ?? 0,
      txnCount: spentRow.read(txnCount) ?? 0,
      focusMinutes: focusRow.read(focusSum) ?? 0,
      notesCount: notesRow.read(notesCount) ?? 0,
    );
  }
}
