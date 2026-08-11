import '../../tables.dart';
import '../api_client.dart';
import 'wire.dart';

/// The buckets, and which of them the add sheet should offer first.
class CategoriesApi {
  const CategoriesApi(this._c);

  final BbxClient _c;

  Future<List<CategoryOut>> list({bool includeArchived = false}) async =>
      wireList(
        await _c.get('/v1/categories', {'include_archived': includeArchived}),
        CategoryOut.fromJson,
      );

  Future<CategoryOut> upsert(String id, CategoryIn body) async =>
      CategoryOut.fromJson(
        wireObject(await _c.put('/v1/categories/$id', body.toJson())),
      );

  Future<CategoryOut> patch(String id, CategoryPatch body) async =>
      CategoryOut.fromJson(
        wireObject(await _c.patch('/v1/categories/$id', body.toJson())),
      );

  /// The five-second path's memory: what actually gets written most, so the
  /// sheet can open on the right chip instead of an alphabetical list.
  Future<List<CategoryUse>> top({int days = 90, int limit = 5}) async =>
      wireList(
        await _c.get('/v1/categories/top', {'days': days, 'limit': limit}),
        CategoryUse.fromJson,
      );
}

class CategoryOut {
  const CategoryOut({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    required this.sortOrder,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// A key into the app's drawn-mark catalogue, not an emoji.
  final String icon;
  final CategoryKind kind;
  final int sortOrder;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory CategoryOut.fromJson(Map<String, dynamic> json) => CategoryOut(
        id: json.text('id'),
        name: json.text('name'),
        icon: json.text('icon'),
        kind: json.enumAt('kind', categoryKindWire),
        sortOrder: json.whole('sort_order'),
        archived: json.flag('archived'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class CategoryIn {
  const CategoryIn({
    required this.name,
    required this.kind,
    this.icon = 'circle',
    this.sortOrder = 0,
  });

  final String name;
  final CategoryKind kind;
  final String icon;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'name': name,
        'kind': categoryKindWire.toWire(kind),
        'icon': icon,
        'sort_order': sortOrder,
      };
}

/// `kind` is deliberately absent: a category that has been spent against
/// cannot change sides. Null means "leave it alone".
class CategoryPatch {
  const CategoryPatch({this.name, this.icon, this.sortOrder, this.archived});

  final String? name;
  final String? icon;
  final int? sortOrder;
  final bool? archived;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('name', name)
        ..maybe('icon', icon)
        ..maybe('sort_order', sortOrder)
        ..maybe('archived', archived))
      .build();
}

/// How often a category has been reached for lately.
class CategoryUse {
  const CategoryUse({required this.categoryId, required this.count});

  final String categoryId;
  final int count;

  factory CategoryUse.fromJson(Map<String, dynamic> json) => CategoryUse(
        categoryId: json.text('category_id'),
        count: json.whole('count'),
      );
}
