import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/note_repo.dart';
import 'package:budgetbox/features/notes/notes_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteRepo', () {
    late LedgerDb db;
    late NoteRepo repo;

    setUp(() {
      db = LedgerDb.forTesting(NativeDatabase.memory());
      repo = NoteRepo(db);
    });

    tearDown(() => db.close());

    Future<Note> fetch(int id) =>
        (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();

    Future<void> stamp(int id, DateTime at) =>
        (db.update(db.notes)..where((n) => n.id.equals(id)))
            .write(NotesCompanion(updatedAt: Value(at)));

    test('create writes a note with defaults in place', () async {
      final id = await repo.create(title: 'chai list');
      final note = await fetch(id);
      expect(note.title, 'chai list');
      expect(note.body, '');
      expect(note.pinned, isFalse);
      expect(note.archived, isFalse);
    });

    test('update rewrites the ink and bumps updatedAt', () async {
      final id = await repo.create(title: 'chai list');
      final past = DateTime(2026, 1, 1);
      await stamp(id, past);

      await repo.update(id, body: 'jaggery, cardamom');

      final note = await fetch(id);
      expect(note.body, 'jaggery, cardamom');
      expect(note.title, 'chai list');
      expect(note.updatedAt.isAfter(past), isTrue);
    });

    test('watchAll orders pinned first, then by last touch', () async {
      final a = await repo.create(title: 'a');
      final b = await repo.create(title: 'b');
      final c = await repo.create(title: 'c');
      await stamp(a, DateTime(2026, 7, 1));
      await stamp(b, DateTime(2026, 7, 2));
      await stamp(c, DateTime(2026, 7, 3));

      // Oldest note pinned: it should still lead the page.
      await repo.setPinned(a, true);

      final rows = await repo.watchAll().first;
      expect(rows.map((n) => n.title).toList(), ['a', 'c', 'b']);

      // Unpin: recency takes over again.
      await repo.setPinned(a, false);
      final unpinned = await repo.watchAll().first;
      expect(unpinned.map((n) => n.title).toList(), ['c', 'b', 'a']);
    });

    test('archive slides the note off the page', () async {
      final keep = await repo.create(title: 'keep');
      final gone = await repo.create(title: 'gone');

      await repo.archive(gone);

      final rows = await repo.watchAll().first;
      expect(rows.map((n) => n.id), [keep]);
      // Still in the book, just off the page.
      final row = await fetch(gone);
      expect(row.archived, isTrue);
    });
  });

  group('NotesPage', () {
    testWidgets('quick capture puts the thought on top of the page',
        (tester) async {
      final db = LedgerDb.forTesting(NativeDatabase.memory());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dbProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: ledgerDayTheme(),
            home: const NotesPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Nothing here yet. First thought goes on top.'),
        findsOneWidget,
      );

      await tester.enterText(
          find.byType(TextField), 'Buy jaggery before Sunday');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The note landed in the list and the capture line cleared itself.
      expect(find.text('Buy jaggery before Sunday'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(
        find.text('Nothing here yet. First thought goes on top.'),
        findsNothing,
      );

      // Unmount and drain drift's timers so the binding ends clean.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await db.close();
    });
  });
}
