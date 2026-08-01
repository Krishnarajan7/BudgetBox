import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// The categories' own little repo — they never leave this page, so the
/// drift lives here instead of in lib/data/repos.
class CategoryStore {
  CategoryStore(this._db);

  final LedgerDb _db;

  /// Every category still on the page, in the owner's order.
  Stream<List<Category>> watchAll() => (_db.select(_db.categories)
        ..where((c) => c.archived.equals(false))
        ..orderBy([
          (c) => OrderingTerm.asc(c.sortOrder),
          (c) => OrderingTerm.asc(c.id),
        ]))
      .watch();

  /// A new line at the end of its group.
  Future<int> create({
    required String name,
    required String icon,
    required CategoryKind kind,
  }) async {
    final siblings = await (_db.select(_db.categories)
          ..where((c) => c.kind.equalsValue(kind)))
        .get();
    final next =
        siblings.fold(-1, (int m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;
    return _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            name: name,
            icon: Value(icon),
            kind: kind,
            sortOrder: Value(next),
          ),
        );
  }

  Future<void> edit(int id, {String? name, String? icon}) =>
      (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          name: name == null ? const Value.absent() : Value(name),
          icon: icon == null ? const Value.absent() : Value(icon),
        ),
      );

  /// Retired, not deleted — it leaves the pickers; history keeps it.
  Future<void> retire(int id) =>
      (_db.update(_db.categories)..where((c) => c.id.equals(id)))
          .write(const CategoriesCompanion(archived: Value(true)));

  /// Writes the given order back as sortOrder 0..n.
  Future<void> persistOrder(List<Category> inOrder) => _db.batch((b) {
        for (final (i, cat) in inOrder.indexed) {
          b.update(
            _db.categories,
            CategoriesCompanion(sortOrder: Value(i)),
            where: ($CategoriesTable c) => c.id.equals(cat.id),
          );
        }
      });
}

final _categoryStoreProvider =
    Provider<CategoryStore>((ref) => CategoryStore(ref.watch(dbProvider)));

/// His words, his marks, his order — the two lists behind every picker.
class CategoryManagerPage extends ConsumerStatefulWidget {
  const CategoryManagerPage({super.key});

  @override
  ConsumerState<CategoryManagerPage> createState() =>
      _CategoryManagerPageState();
}

class _CategoryManagerPageState extends ConsumerState<CategoryManagerPage> {
  /// Ids already on the page — only genuinely new lines animate in.
  final _seen = <int>{};
  bool _primed = false;

  /// The order the owner's finger just chose, kept until the write lands.
  final _localOrder = <CategoryKind, List<int>>{};

  List<Category> _ordered(List<Category> group, CategoryKind kind) {
    final wanted = _localOrder[kind];
    if (wanted == null) return group;
    final byId = {for (final c in group) c.id: c};
    if (!wanted.toSet().containsAll(byId.keys) ||
        wanted.length != group.length) {
      return group;
    }
    return [for (final id in wanted) byId[id]!];
  }

  Future<void> _reorder(
    List<Category> group,
    CategoryKind kind,
    int oldIndex,
    int newIndex,
  ) async {
    final next = [...group];
    next.insert(newIndex, next.removeAt(oldIndex));
    HapticFeedback.lightImpact();
    setState(() => _localOrder[kind] = [for (final c in next) c.id]);
    await ref.read(_categoryStoreProvider).persistOrder(next);
  }

  Future<void> _openSheet({Category? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CategorySheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final store = ref.watch(_categoryStoreProvider);

    return ModuleScaffold(
      title: 'Categories',
      trailing: InkWell(
        onTap: () => _openSheet(),
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: Icon(Icons.add, size: 20, color: c.inkFaint),
        ),
      ),
      child: StreamBuilder<List<Category>>(
        stream: store.watchAll(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Category>[];
          final fresh = <int>{
            if (_primed)
              for (final cat in all)
                if (!_seen.contains(cat.id)) cat.id,
          };
          if (snapshot.hasData) {
            _primed = true;
            _seen.addAll(all.map((cat) => cat.id));
          }

          final spending = _ordered(
            [for (final cat in all) if (cat.kind == CategoryKind.expense) cat],
            CategoryKind.expense,
          );
          final income = _ordered(
            [for (final cat in all) if (cat.kind == CategoryKind.income) cat],
            CategoryKind.income,
          );

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const RuleHeader('spending'),
              _group(spending, CategoryKind.expense, fresh),
              const RuleHeader('income'),
              _group(income, CategoryKind.income, fresh),
              const SizedBox(height: Gap.x4),
              Text(
                'Drag by the grip to put them in your order. '
                'Tap a line to rewrite it.',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 12, color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x8),
            ],
          );
        },
      ),
    );
  }

  Widget _group(List<Category> group, CategoryKind kind, Set<int> fresh) {
    final c = LedgerColors.of(context);
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) => _reorder(group, kind, from, to),
      proxyDecorator: (child, index, animation) => Material(
        color: c.paperRaised,
        elevation: 3,
        shadowColor: c.ink.withValues(alpha: 0.25),
        child: child,
      ),
      itemCount: group.length,
      itemBuilder: (context, i) {
        final cat = group[i];
        return _Entrance(
          key: ValueKey('cat-${cat.id}'),
          animate: fresh.contains(cat.id),
          child: _CategoryRow(
            category: cat,
            index: i,
            onTap: () => _openSheet(existing: cat),
          ),
        );
      },
    );
  }
}

/// One ruled line: the mark, the word, the grip.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.index,
    required this.onTap,
  });

  final Category category;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            CatMark(category.icon, size: 16),
            const SizedBox(width: Gap.x3),
            Expanded(
              child: Text(
                category.name,
                style: LedgerType.bodyText.copyWith(color: c.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_indicator,
                size: 16,
                color: c.inkFaint.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name on a ruled underline, every mark in the book to choose from.
class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.existing});

  final Category? existing;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? 'circle';
  late CategoryKind _kind = widget.existing?.kind ?? CategoryKind.expense;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _keep() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.lightImpact();
    final store = ref.read(_categoryStoreProvider);
    final existing = widget.existing;
    if (existing == null) {
      await store.create(name: name, icon: _icon, kind: _kind);
    } else {
      await store.edit(existing.id, name: name, icon: _icon);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retire() async {
    final existing = widget.existing;
    if (existing == null) return;
    HapticFeedback.mediumImpact();
    await ref.read(_categoryStoreProvider).retire(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final adding = widget.existing == null;

    return Padding(
      padding: EdgeInsets.only(
        left: Gap.page,
        right: Gap.page,
        top: Gap.x4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                adding ? 'A new line, in your words.' : 'Your word, your mark.',
                style: LedgerType.bodyStrong.copyWith(color: c.ink),
              ),
              if (adding) ...[
                const SizedBox(height: Gap.x3),
                Row(
                  children: [
                    for (final (kind, label) in const [
                      (CategoryKind.expense, 'spending'),
                      (CategoryKind.income, 'income'),
                    ]) ...[
                      LedgerChip(
                        label,
                        selected: _kind == kind,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _kind = kind);
                        },
                      ),
                      const SizedBox(width: Gap.x2),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: Gap.x3),
              Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.rule)),
                ),
                child: TextField(
                  controller: _name,
                  autofocus: adding,
                  textCapitalization: TextCapitalization.sentences,
                  style:
                      LedgerType.bodyText.copyWith(fontSize: 16, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'call it what you call it',
                    hintStyle: LedgerType.bodyText
                        .copyWith(fontSize: 16, color: c.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'its mark',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              GridView.count(
                crossAxisCount: 6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: Gap.x1,
                crossAxisSpacing: Gap.x1,
                children: [
                  for (final key in LedgerIcons.keys)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _icon = key);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _icon == key
                              ? c.quillSoft
                              : c.quillSoft.withValues(alpha: 0),
                        ),
                        child: Icon(
                          LedgerIcons.resolve(key),
                          size: 24,
                          color: _icon == key ? c.quill : c.ink,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _name,
                builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _keep,
                  child: const Text('Keep it'),
                ),
              ),
              if (!adding)
                Center(
                  child: TextButton(
                    onPressed: _retire,
                    child: const Text('Retire it — history keeps the name'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fade + small slide for a line that has just been written.
class _Entrance extends StatelessWidget {
  const _Entrance({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
