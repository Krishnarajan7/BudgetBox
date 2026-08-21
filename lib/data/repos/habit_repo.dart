import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;

import '../db.dart';
import '../providers.dart';
import 'settings_repo.dart';

final habitRepoProvider = Provider<HabitRepo>(
  (ref) => HabitRepo(ref.watch(dbProvider)),
);

/// One tracked habit's definition.
///
/// [kind] is the stable key written into `day_marks`; the name can change
/// tomorrow without the history forgetting what it meant. [target] of 1 is a
/// plain tick — did it or didn't. Above 1 the habit is *counted*: every tap
/// writes another mark, and the day is kept when the marks reach the target.
class Habit {
  const Habit({
    required this.kind,
    required this.name,
    this.target = 1,
    this.unit,
    this.archived = false,
  });

  final String kind;
  final String name;
  final int target;

  /// What one mark is called — 'glasses', 'sets'. Null on ticks.
  final String? unit;

  /// Archived habits keep their history but leave the checklist.
  final bool archived;

  bool get counted => target > 1;

  /// [clearUnit] is the only way to take a unit off — a habit turned back
  /// into a tick has nothing left to count in glasses.
  Habit copyWith({
    String? name,
    int? target,
    String? unit,
    bool clearUnit = false,
    bool? archived,
  }) => Habit(
    kind: kind,
    name: name ?? this.name,
    target: target ?? this.target,
    unit: clearUnit ? null : (unit ?? this.unit),
    archived: archived ?? this.archived,
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'name': name,
    if (target != 1) 'target': target,
    if (unit != null) 'unit': unit,
    if (archived) 'archived': true,
  };

  static Habit? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    final name = raw['name'];
    if (kind is! String || name is! String) return null;
    if (kind.trim().isEmpty || name.trim().isEmpty) return null;
    final target = raw['target'];
    return Habit(
      kind: kind,
      name: name,
      target: target is int && target > 0 ? target : 1,
      unit: raw['unit'] is String ? raw['unit'] as String : null,
      archived: raw['archived'] == true,
    );
  }
}

/// What the book starts with — the five it always tracked, plus water,
/// which is the one that shows what a counted habit is for.
const startingHabits = <Habit>[
  Habit(kind: 'bath', name: 'Bath'),
  Habit(kind: 'run', name: 'Running'),
  Habit(kind: 'push', name: 'Push-ups'),
  Habit(kind: 'pull', name: 'Pull-ups'),
  Habit(kind: 'squat', name: 'Squats'),
  Habit(kind: 'water', name: 'Water', target: 8, unit: 'glasses'),
];

/// The kinds `day_marks` uses for something other than a habit — the page
/// filters these out wherever it counts what was kept.
const nonHabitKinds = {'slip', 'meal', 'pledge'};

/// The checklist's shape, kept as one settings row.
///
/// Habits are a handful of lines of configuration, not a ledger: they're
/// stored as JSON under a single key rather than earning a table of their
/// own. The *marks* — the actual history — stay rows in `day_marks`, which
/// is what any of this is worth keeping.
class HabitRepo {
  HabitRepo(this._db);

  static const _key = SettingsRepo.habitsKey;

  final LedgerDb _db;

  /// The live checklist, archived habits included — callers filter. A book
  /// that has never been edited reads back [startingHabits] without writing
  /// anything, so the default can still improve later.
  Stream<List<Habit>> watch() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(_key))).watchSingleOrNull().map(_decode);
  }

  Future<List<Habit>> load() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(_key))).getSingleOrNull();
    return _decode(row);
  }

  List<Habit> _decode(Setting? row) {
    if (row == null) return startingHabits;
    try {
      final raw = jsonDecode(row.value);
      if (raw is! List) return startingHabits;
      final habits = [for (final item in raw) ?Habit.fromJson(item)];
      return habits.isEmpty ? const [] : habits;
    } on FormatException {
      // A corrupted row is not worth losing the checklist over.
      return startingHabits;
    }
  }

  Future<void> save(List<Habit> habits) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion(
            key: const Value(_key),
            value: Value(jsonEncode([for (final h in habits) h.toJson()])),
          ),
        );
  }

  /// Adds a habit, giving it a mark key derived from its name so a future
  /// export reads like words rather than row numbers. Existing keys — live
  /// or archived — are never reused, or a new habit would inherit the old
  /// one's history.
  Future<Habit> add({
    required String name,
    int target = 1,
    String? unit,
  }) async {
    final habits = await load();
    final taken = {for (final h in habits) h.kind};
    final base = _slug(name);
    var kind = base;
    var n = 2;
    while (taken.contains(kind)) {
      kind = '$base$n';
      n++;
    }
    final habit = Habit(
      kind: kind,
      name: name.trim(),
      target: target < 1 ? 1 : target,
      unit: target > 1 ? unit?.trim() : null,
    );
    await save([...habits, habit]);
    return habit;
  }

  Future<void> update(
    String kind, {
    String? name,
    int? target,
    String? unit,
    bool? archived,
  }) async {
    final habits = await load();
    await save([
      for (final h in habits)
        if (h.kind == kind)
          h.copyWith(
            name: name?.trim(),
            target: target,
            unit: unit,
            clearUnit: (target ?? h.target) <= 1,
            archived: archived,
          )
        else
          h,
    ]);
  }

  /// Reorders the live habits, leaving archived ones where they sit.
  Future<void> reorder(List<Habit> ordered) => save(ordered);

  static String _slug(String name) {
    final cleaned = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp('^_+|_+\$'), '');
    return cleaned.isEmpty ? 'habit' : cleaned;
  }
}
