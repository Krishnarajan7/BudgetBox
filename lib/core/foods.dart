import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The nutrients the book keeps count of, in the order the food table stores
/// them. Each carries its JSON key, the name the page prints, and its unit.
enum Nutrient {
  kcal('kcal', 'energy', 'kcal'),
  protein('pro', 'protein', 'g'),
  carbs('carb', 'carbs', 'g'),
  fat('fat', 'fat', 'g'),
  fibre('fib', 'fibre', 'g'),
  sugar('sug', 'free sugar', 'g'),
  satFat('sfa', 'saturated fat', 'g'),
  sodium('na', 'sodium', 'mg'),
  potassium('k', 'potassium', 'mg'),
  calcium('ca', 'calcium', 'mg'),
  iron('fe', 'iron', 'mg'),
  zinc('zn', 'zinc', 'mg'),
  magnesium('mg', 'magnesium', 'mg'),
  vitA('va', 'vitamin A', 'µg'),
  vitC('vc', 'vitamin C', 'mg'),
  folate('fol', 'folate', 'µg'),
  b1('b1', 'thiamine', 'mg'),
  b2('b2', 'riboflavin', 'mg'),
  b3('b3', 'niacin', 'mg');

  const Nutrient(this.key, this.label, this.unit);

  final String key;
  final String label;
  final String unit;
}

/// A fixed-width vector of nutrient amounts. Immutable; arithmetic returns
/// new values. Every figure is in the unit its [Nutrient] names.
@immutable
class Nutrients {
  const Nutrients._(this._v);

  factory Nutrients.zero() =>
      Nutrients._(List<double>.filled(Nutrient.values.length, 0));

  factory Nutrients.of(Map<Nutrient, double> m) => Nutrients._([
    for (final n in Nutrient.values) m[n] ?? 0,
  ]);

  factory Nutrients.fromJson(Map<String, dynamic> json) => Nutrients._([
    for (final n in Nutrient.values) (json[n.key] as num?)?.toDouble() ?? 0,
  ]);

  final List<double> _v;

  double operator [](Nutrient n) => _v[n.index];

  double get kcal => this[Nutrient.kcal];
  double get protein => this[Nutrient.protein];

  Nutrients scaled(double f) => Nutrients._([for (final x in _v) x * f]);

  Nutrients operator +(Nutrients o) =>
      Nutrients._([for (var i = 0; i < _v.length; i++) _v[i] + o._v[i]]);

  Map<String, double> toJson() => {
    for (final n in Nutrient.values)
      if (_v[n.index] != 0) n.key: double.parse(_v[n.index].toStringAsFixed(3)),
  };

  bool get isEmpty => _v.every((x) => x == 0);

  @override
  bool operator ==(Object other) =>
      other is Nutrients && listEquals(other._v, _v);

  @override
  int get hashCode => Object.hashAll(_v);
}

/// What a food is made of: veg, egg, or non-veg. The one filter the
/// catalogue applies to suggestions.
enum FoodKind { veg, egg, nonveg }

/// One dish in the catalogue, with its nutrients per 100 g and the size of
/// one ordinary serving.
@immutable
class FoodItem {
  const FoodItem({
    required this.key,
    required this.name,
    required this.aliases,
    required this.unit,
    required this.servingGrams,
    required this.kind,
    required this.per100g,
    this.curated = false,
  });

  factory FoodItem.fromJson(Map<String, dynamic> j) => FoodItem(
    key: '${j['k']}',
    name: '${j['n']}',
    aliases: [for (final a in (j['a'] as List? ?? const [])) '$a'],
    unit: '${j['u']}',
    servingGrams: (j['g'] as num).toDouble(),
    kind: switch (j['t']) {
      'nonveg' => FoodKind.nonveg,
      'egg' => FoodKind.egg,
      _ => FoodKind.veg,
    },
    per100g: Nutrients.fromJson(j['p'] as Map<String, dynamic>),
    curated: j['r'] == 1,
  );

  final String key;
  final String name;
  final List<String> aliases;

  /// 'bowl', 'plate', 'piece' — how one serving is spoken of.
  final String unit;
  final double servingGrams;
  final FoodKind kind;
  final Nutrients per100g;

  /// Hand-checked entries rank ahead of the survey table on a tie.
  final bool curated;

  /// The nutrients in [servings] ordinary servings.
  Nutrients forServings(double servings) =>
      per100g.scaled(servingGrams * servings / 100);

  /// The nutrients in [grams] of it.
  Nutrients forGrams(double grams) => per100g.scaled(grams / 100);

  /// 'a bowl', 'two pieces', '1½ plates' — the serving as the book says it.
  String spokenServing(double servings) {
    final u = unit.isEmpty ? 'serving' : unit;
    if (servings == 1) return '${_article(u)} $u';
    final plural = _plural(u);
    if (servings == 0.5) return 'half a $u';
    if (servings == 1.5) return '1½ $plural';
    if (servings == 2) return 'two $plural';
    if (servings == 3) return 'three $plural';
    if (servings == servings.roundToDouble()) {
      return '${servings.round()} $plural';
    }
    return '${servings.toStringAsFixed(1)} $plural';
  }

  static String _article(String u) =>
      'aeiou'.contains(u[0].toLowerCase()) ? 'an' : 'a';

  static String _plural(String u) {
    if (u.endsWith('s')) return u;
    if (u == 'idli' || u == 'dosa' || u == 'vada' || u == 'chapati') {
      return '${u}s';
    }
    if (u.endsWith('y')) return '${u.substring(0, u.length - 1)}ies';
    return '${u}s';
  }
}

/// The bundled food table, read once and searched in memory.
///
/// Sourced from the Indian Nutrient Databank (per-100 g values on an
/// ICMR-NIN IFCT 2017 basis) plus a hand-checked supplement of the dishes
/// a Pune office day actually meets — vada pav, misal, maggi, momos,
/// a chicken biryani. Nothing here needs the network.
class FoodCatalogue {
  FoodCatalogue._(this.items) {
    for (final f in items) {
      _byKey[f.key] = f;
    }
  }

  /// For tests and previews: a catalogue from a handful of items.
  FoodCatalogue.of(this.items) {
    for (final f in items) {
      _byKey[f.key] = f;
    }
  }

  final List<FoodItem> items;
  final _byKey = <String, FoodItem>{};

  static FoodCatalogue? _loaded;
  static Future<FoodCatalogue>? _loading;

  /// The catalogue, loaded on first use. Cheap after that.
  static Future<FoodCatalogue> load() {
    final done = _loaded;
    if (done != null) return Future.value(done);
    return _loading ??= rootBundle
        .loadString('assets/diet/foods.json')
        .then((text) {
          final doc = jsonDecode(text) as Map<String, dynamic>;
          final list = [
            for (final j in doc['foods'] as List)
              FoodItem.fromJson(j as Map<String, dynamic>),
          ];
          return _loaded = FoodCatalogue._(list);
        });
  }

  /// What's already in memory, if anything — for synchronous readers that
  /// would rather show a name than wait.
  static FoodCatalogue? get loaded => _loaded;

  FoodItem? byKey(String key) => _byKey[key];

  /// The dishes matching what was typed, best first. A word-start match
  /// beats a match in the middle; an exact alias beats everything; a
  /// curated line wins ties. [prefer] keeps the list to what he eats.
  List<FoodItem> search(String query, {int limit = 12, FoodKind? prefer}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final scored = <(int, FoodItem)>[];
    for (final f in items) {
      if (prefer == FoodKind.veg && f.kind != FoodKind.veg) continue;
      if (prefer == FoodKind.egg && f.kind == FoodKind.nonveg) continue;
      final s = _score(f, q);
      if (s > 0) scored.add((s, f));
    }
    scored.sort((a, b) {
      final d = b.$1.compareTo(a.$1);
      if (d != 0) return d;
      return a.$2.name.length.compareTo(b.$2.name.length);
    });
    return [for (final s in scored.take(limit)) s.$2];
  }

  /// The one dish a plain word means, when it means exactly one: 'idli',
  /// 'chai', 'maggi'. Null when the word is ambiguous or unknown — the
  /// caller keeps the words and measures nothing.
  FoodItem? resolve(String text) {
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final f in items) {
      if (f.name.toLowerCase() == q || f.aliases.contains(q)) return f;
    }
    final hits = search(q, limit: 2);
    if (hits.length == 1) return hits.first;
    if (hits.length == 2 && _score(hits[0], q) >= 90 && _score(hits[1], q) < 90) {
      return hits.first;
    }
    return null;
  }

  static int _score(FoodItem f, String q) {
    final name = f.name.toLowerCase();
    var best = 0;
    if (name == q) best = 100;
    for (final a in f.aliases) {
      if (a == q) best = best < 95 ? 95 : best;
    }
    if (best == 0 && name.startsWith(q)) best = 80;
    if (best == 0) {
      for (final a in f.aliases) {
        if (a.startsWith(q)) best = 75;
      }
    }
    if (best == 0) {
      for (final w in name.split(RegExp(r'[\s/(),-]+'))) {
        if (w.startsWith(q)) best = 60;
      }
    }
    if (best == 0 && name.contains(q)) best = 40;
    if (best == 0) {
      for (final a in f.aliases) {
        if (a.contains(q)) best = 30;
      }
    }
    if (best > 0 && f.curated) best += 3;
    return best;
  }
}
