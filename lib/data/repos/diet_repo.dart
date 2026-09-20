import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/foods.dart';
import '../../features/diet/diet_math.dart';
import '../db.dart';
import '../meal_voice.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import 'settings_repo.dart';

final dietRepoProvider = Provider<DietRepo>(
  (ref) => DietRepo(ref.watch(dbProvider), ref.watch(settingsRepoProvider)),
);

/// The diet book's keeper: what was eaten, measured against the catalogue
/// where it can be, and the profile the targets are drawn from.
///
/// Two sources of truth share the page for a while: the new `meals` table,
/// and the old free-text 'meal' marks the Daily page wrote before the book
/// could weigh anything. The old lines keep showing (unmeasured) until each
/// is tapped into a dish; nothing is migrated blind, because "curd rice"
/// typed in July meant a bowl of *something* and only he knows how much.
class DietRepo {
  DietRepo(this._db, this._settings);

  final LedgerDb _db;
  final SettingsRepo _settings;

  // ————— the profile —————

  Future<DietProfile?> profile() async {
    final raw = await _settings.dietProfileJson();
    if (raw == null) return null;
    return DietProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setProfile(DietProfile p) =>
      _settings.setDietProfileJson(jsonEncode(p.toJson()));

  // ————— reading the days —————

  /// Every line on [day]'s page, oldest first: measured dishes, skips, and
  /// the old free-text marks the book never weighed.
  Stream<List<MealEntry>> watchDay(DateTime day) =>
      watchSince(day, days: 1).map((byDay) => byDay[LedgerDates.dayKey(day)] ?? const []);

  /// The last [days] days ending on [day], keyed by date. Days with nothing
  /// written are absent from the map.
  Stream<Map<String, List<MealEntry>>> watchSince(DateTime day, {int days = 7}) {
    final to = DateTime(day.year, day.month, day.day);
    final from = to.subtract(Duration(days: days - 1));
    final fromKey = LedgerDates.dayKey(from);
    final toKey = LedgerDates.dayKey(to);
    final meals = (_db.select(_db.meals)
          ..where((m) => m.date.isBetweenValues(fromKey, toKey))
          ..orderBy([(m) => OrderingTerm.asc(m.at)]))
        .watch();
    final marks = (_db.select(_db.dayMarks)
          ..where(
            (m) => m.kind.equals('meal') & m.date.isBetweenValues(fromKey, toKey),
          )
          ..orderBy([(m) => OrderingTerm.asc(m.at)]))
        .watch();
    // Two streams, one page: whichever emits, the page re-reads both.
    return _combine(meals, marks).map((pair) {
      final (rows, legacy) = pair;
      final out = <String, List<MealEntry>>{};
      for (final r in rows) {
        out.putIfAbsent(r.date, () => []).add(entryOf(r));
      }
      for (final m in legacy) {
        out.putIfAbsent(m.date, () => []).add(
          MealEntry(
            markId: m.id,
            at: m.at,
            slot: slotFor(m.at),
            name: (m.note ?? '').trim().isEmpty ? 'something' : m.note!.trim(),
          ),
        );
      }
      for (final list in out.values) {
        list.sort((a, b) => a.at.compareTo(b.at));
      }
      return out;
    });
  }

  static MealEntry entryOf(Meal r) => MealEntry(
    mealId: r.id,
    at: r.at,
    slot: r.slot,
    name: r.name,
    foodKey: r.foodKey,
    servings: r.servings,
    grams: r.grams,
    facts: r.facts == null
        ? null
        : Nutrients.fromJson(jsonDecode(r.facts!) as Map<String, dynamic>),
    skipped: r.skipped,
  );

  /// Totals for each of the last [days] days ending on [day], oldest first
  /// — every day present, empty ones included, so a week reads as a week.
  Stream<List<DayTotals>> watchWeek(DateTime day, {int days = 7}) {
    final to = DateTime(day.year, day.month, day.day);
    return watchSince(day, days: days).map((byDay) => [
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = to.subtract(Duration(days: i));
          final key = LedgerDates.dayKey(d);
          return totalsFor(key, byDay[key] ?? const []);
        }(),
    ]);
  }

  /// The measured lines over the last [days] days — the pool suggestions
  /// draw dishes from.
  Future<List<MealEntry>> eatenRecently(DateTime day, {int days = 14}) async {
    final to = DateTime(day.year, day.month, day.day);
    final from = to.subtract(Duration(days: days - 1));
    final rows =
        await (_db.select(_db.meals)
              ..where(
                (m) =>
                    m.date.isBetweenValues(
                      LedgerDates.dayKey(from),
                      LedgerDates.dayKey(to),
                    ) &
                    m.facts.isNotNull(),
              )
              ..orderBy([(m) => OrderingTerm.desc(m.at)]))
            .get();
    return [for (final r in rows) entryOf(r)];
  }

  /// The dishes that come back most, newest first among ties — the quick
  /// row, so the tenth idli is one tap.
  Future<List<FoodItem>> frequent(FoodCatalogue catalogue, {int limit = 8}) async {
    final rows =
        await (_db.select(_db.meals)
              ..where((m) => m.foodKey.isNotNull() & m.skipped.equals(false))
              ..orderBy([(m) => OrderingTerm.desc(m.at)])
              ..limit(400))
            .get();
    final seen = <String, ({int count, int rank})>{};
    for (final (i, r) in rows.indexed) {
      final k = r.foodKey!;
      final prior = seen[k];
      seen[k] = (count: (prior?.count ?? 0) + 1, rank: prior?.rank ?? i);
    }
    final ranked = seen.entries.toList()
      ..sort((a, b) {
        final c = b.value.count.compareTo(a.value.count);
        return c != 0 ? c : a.value.rank.compareTo(b.value.rank);
      });
    return [
      for (final e in ranked) ?catalogue.byKey(e.key),
    ].take(limit).toList();
  }

  /// The words he typed before the catalogue existed, most used first —
  /// still offered on the quick row, still unmeasured until resolved.
  Future<List<String>> frequentWords({int limit = 6}) async {
    final rows =
        await (_db.select(_db.dayMarks)
              ..where((m) => m.kind.equals('meal'))
              ..orderBy([(m) => OrderingTerm.desc(m.at)])
              ..limit(300))
            .get();
    final seen = <String, int>{};
    final original = <String, String>{};
    for (final r in rows) {
      final t = (r.note ?? '').trim();
      if (t.isEmpty) continue;
      final k = t.toLowerCase();
      seen[k] = (seen[k] ?? 0) + 1;
      original.putIfAbsent(k, () => t);
    }
    final ranked = seen.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in ranked.take(limit)) original[e.key]!];
  }

  // ————— writing —————

  /// A measured dish: [servings] of [food] (or [grams] of it), on [day],
  /// in [slot] — or the slot the clock says when none is given.
  Future<int> add(
    FoodItem food, {
    required DateTime day,
    double servings = 1,
    double? grams,
    MealSlot? slot,
    DateTime? at,
    String? note,
  }) async {
    final when = at ?? stampFor(day);
    final facts = grams != null ? food.forGrams(grams) : food.forServings(servings);
    final id = await _db.transaction(() async {
      final id = await _db
          .into(_db.meals)
          .insert(
            MealsCompanion.insert(
              date: LedgerDates.dayKey(day),
              slot: slot ?? slotFor(when),
              foodKey: Value(food.key),
              name: food.name,
              servings: Value(servings),
              grams: Value(grams),
              facts: Value(jsonEncode(facts.toJson())),
              note: Value(note),
              at: when,
            ),
          );
      await bbxSync.upsert(SyncKinds.meal, id);
      return id;
    });
    await bbxMealVoice(_db);
    return id;
  }

  /// Words the catalogue can't weigh: kept as a line, counted as eaten,
  /// measured as nothing.
  Future<int> addUnmeasured(
    String text, {
    required DateTime day,
    MealSlot? slot,
    DateTime? at,
  }) async {
    final name = text.trim();
    if (name.isEmpty) return -1;
    final when = at ?? stampFor(day);
    final id = await _db.transaction(() async {
      final id = await _db
          .into(_db.meals)
          .insert(
            MealsCompanion.insert(
              date: LedgerDates.dayKey(day),
              slot: slot ?? slotFor(when),
              name: name,
              at: when,
            ),
          );
      await bbxSync.upsert(SyncKinds.meal, id);
      return id;
    });
    await bbxMealVoice(_db);
    return id;
  }

  /// Typed words, resolved when they name exactly one dish — 'idli',
  /// 'maggi' — and kept as words otherwise. What the Daily card's field
  /// calls, so the ten-letter habit keeps working and starts counting.
  Future<int> addByText(
    String text,
    FoodCatalogue catalogue, {
    required DateTime day,
    MealSlot? slot,
  }) async {
    final food = catalogue.resolve(text);
    if (food != null) return add(food, day: day, slot: slot);
    return addUnmeasured(text, day: day, slot: slot);
  }

  /// "No breakfast, and that was the choice." At most one skip per
  /// (day, slot); a dish written into the slot later outranks it.
  Future<void> skip(DateTime day, MealSlot slot) async {
    final key = LedgerDates.dayKey(day);
    await _db.transaction(() async {
      final existing = await (_db.select(_db.meals)..where(
            (m) =>
                m.date.equals(key) &
                m.slot.equalsValue(slot) &
                m.skipped.equals(true),
          ))
          .get();
      if (existing.isNotEmpty) return;
      final id = await _db
          .into(_db.meals)
          .insert(
            MealsCompanion.insert(
              date: key,
              slot: slot,
              name: 'skipped',
              servings: const Value(0),
              skipped: const Value(true),
              at: slotDeadline(slot, day),
            ),
          );
      await bbxSync.upsert(SyncKinds.meal, id);
    });
    await bbxMealVoice(_db);
  }

  Future<void> remove(MealEntry e) async {
    await _db.transaction(() async {
      if (e.mealId case final id?) {
        await (_db.delete(_db.meals)..where((m) => m.id.equals(id))).go();
        await bbxSync.remove(SyncKinds.meal, id);
      } else if (e.markId case final id?) {
        await (_db.delete(_db.dayMarks)..where((m) => m.id.equals(id))).go();
        await bbxSync.remove(SyncKinds.mark, id);
      }
    });
    await bbxMealVoice(_db);
  }

  /// An old words-only line becomes a measured dish: the mark goes, the
  /// meal takes its place at the same minute.
  Future<int> measure(
    MealEntry legacy,
    FoodItem food, {
    double servings = 1,
    double? grams,
  }) async {
    final markId = legacy.markId;
    final day = legacy.at;
    final id = await add(
      food,
      day: DateTime(day.year, day.month, day.day),
      servings: servings,
      grams: grams,
      slot: legacy.slot,
      at: legacy.at,
    );
    if (markId != null) {
      await _db.transaction(() async {
        await (_db.delete(_db.dayMarks)..where((m) => m.id.equals(markId))).go();
        await bbxSync.remove(SyncKinds.mark, markId);
      });
    }
    return id;
  }

  /// Re-measure a dish already on the page: a different serving count.
  Future<void> resize(MealEntry e, FoodItem food, double servings) async {
    final id = e.mealId;
    if (id == null) return;
    await _db.transaction(() async {
      await (_db.update(_db.meals)..where((m) => m.id.equals(id))).write(
        MealsCompanion(
          servings: Value(servings),
          grams: const Value(null),
          facts: Value(jsonEncode(food.forServings(servings).toJson())),
        ),
      );
      await bbxSync.upsert(SyncKinds.meal, id);
    });
    await bbxMealVoice(_db);
  }

  // ————— the ledger as evidence —————

  /// Money spent on food on [day] — the cue for "₹180 at lunch, nothing
  /// written". Food is any expense whose category is one of the eating
  /// ones by name, matched loosely because his categories are his own.
  Future<List<Txn>> foodSpend(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final cats = await _db.select(_db.categories).get();
    final foodIds = {
      for (final c in cats)
        if (RegExp(
          r'food|chai|meal|eat|snack|coffee|cafe|restaurant|zomato|swiggy|mess|tiffin|canteen|treat|bakery',
          caseSensitive: false,
        ).hasMatch(c.name))
          c.id,
    };
    if (foodIds.isEmpty) return const [];
    return (_db.select(_db.txns)
          ..where(
            (t) =>
                t.type.equalsValue(TxnType.expense) &
                t.at.isBiggerOrEqualValue(start) &
                t.at.isSmallerThanValue(start.add(const Duration(days: 1))) &
                t.categoryId.isIn(foodIds),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.at)]))
        .get();
  }

  /// To-day is stamped with the clock; a day filled in later is stamped at
  /// the sitting's usual hour rather than an invented one.
  static DateTime stampFor(DateTime day) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return isToday ? now : DateTime(day.year, day.month, day.day, 13);
  }
}

/// The latest value of two streams, as a pair, whenever either moves.
Stream<(A, B)> _combine<A, B>(Stream<A> a, Stream<B> b) async* {
  A? la;
  B? lb;
  var hasA = false;
  var hasB = false;
  final controller = StreamController<(A, B)>();
  final subA = a.listen((v) {
    la = v;
    hasA = true;
    if (hasB) controller.add((la as A, lb as B));
  }, onError: controller.addError);
  final subB = b.listen((v) {
    lb = v;
    hasB = true;
    if (hasA) controller.add((la as A, lb as B));
  }, onError: controller.addError);
  try {
    yield* controller.stream;
  } finally {
    await subA.cancel();
    await subB.cancel();
    await controller.close();
  }
}
