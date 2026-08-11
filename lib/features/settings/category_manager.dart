import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// What a category has actually been doing — the difference between an
/// administrative list and a page worth reading.
class CategoryPulse {
  const CategoryPulse({
    required this.monthPaise,
    required this.months,
    required this.lastUsed,
  });

  /// Nothing filed here at all.
  static const none =
      CategoryPulse(monthPaise: 0, months: <double>[], lastUsed: null);

  /// This month's total, in paise.
  final int monthPaise;

  /// Six monthly totals in paise, oldest first — the sparkline's memory.
  final List<double> months;

  /// When it was last written to; null if it never has been.
  final DateTime? lastUsed;

  /// Nothing in ninety days. The line stays on the page — it just went quiet.
  bool get quiet {
    final last = lastUsed;
    return last == null || DateTime.now().difference(last).inDays >= 90;
  }

  /// The faint caption a quiet line wears.
  String? get quietLabel {
    if (!quiet) return null;
    final last = lastUsed;
    return last == null ? 'unused' : 'unused since ${LedgerDates.ddMmm(last)}';
  }

  /// A flat line of zeroes says nothing — don't draw it.
  bool get hasTrend => months.length > 1 && months.any((m) => m > 0);
}

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

  /// Read-only. Six months of entries bucketed by local month, plus the last
  /// time each category was written to. Buckets are computed in Dart so a
  /// late-evening entry never lands in the wrong month.
  Future<Map<int, CategoryPulse>> pulses({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final windowStart = DateTime(today.year, today.month - 5);
    final thisMonth = LedgerDates.monthStart(today);

    final rows = await (_db.selectOnly(_db.txns)
          ..addColumns([_db.txns.categoryId, _db.txns.at, _db.txns.amountPaise])
          ..where(_db.txns.categoryId.isNotNull() &
              _db.txns.at.isBiggerOrEqualValue(windowStart)))
        .get();

    final months = <int, List<double>>{};
    final month = <int, int>{};
    for (final r in rows) {
      final id = r.read(_db.txns.categoryId)!;
      final at = r.read(_db.txns.at)!;
      final paise = r.read(_db.txns.amountPaise)!;
      final bucket =
          (at.year - windowStart.year) * 12 + at.month - windowStart.month;
      if (bucket < 0 || bucket > 5) continue;
      (months[id] ??= List<double>.filled(6, 0))[bucket] += paise;
      if (!at.isBefore(thisMonth)) month[id] = (month[id] ?? 0) + paise;
    }

    final lastAt = _db.txns.at.max();
    final lastRows = await (_db.selectOnly(_db.txns)
          ..addColumns([_db.txns.categoryId, lastAt])
          ..where(_db.txns.categoryId.isNotNull())
          ..groupBy([_db.txns.categoryId]))
        .get();
    final last = <int, DateTime?>{
      for (final r in lastRows) r.read(_db.txns.categoryId)!: r.read(lastAt),
    };

    return {
      for (final id in {...months.keys, ...last.keys})
        id: CategoryPulse(
          monthPaise: month[id] ?? 0,
          months: months[id] ?? const <double>[],
          lastUsed: last[id],
        ),
    };
  }
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

  /// Lines on their way off the page: struck through while the ink dries.
  final _leaving = <int>{};

  /// What each category has been doing — refreshed whenever the page writes.
  Map<int, CategoryPulse> _pulse = const {};

  @override
  void initState() {
    super.initState();
    _readPulses();
  }

  Future<void> _readPulses() async {
    final pulse = await ref.read(_categoryStoreProvider).pulses();
    if (mounted) setState(() => _pulse = pulse);
  }

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

  /// The line is struck first and only then leaves — a retirement should be
  /// something you watch happen, not something that already happened.
  Future<void> _retire(Category cat) async {
    setState(() => _leaving.add(cat.id));
    if (!Motion.reduced(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }
    await ref.read(_categoryStoreProvider).retire(cat.id);
    if (mounted) setState(() => _leaving.remove(cat.id));
  }

  Future<void> _openSheet({Category? existing}) async {
    final verdict = await showLedgerSheet<String>(
      context,
      builder: (context) => _CategorySheet(existing: existing),
    );
    if (!mounted) return;
    if (verdict == 'retire' && existing != null) {
      await _retire(existing);
    }
    await _readPulses();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final store = ref.watch(_categoryStoreProvider);

    return ModuleScaffold(
      title: 'Categories',
      trailing: Pressable(
        scale: 0.9,
        onTap: () => _openSheet(),
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: PenPlus(size: 18, color: c.inkFaint),
        ),
      ),
      child: StreamBuilder<List<Category>>(
        stream: store.watchAll(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Category>[];
          final firstPaint = !_primed && snapshot.hasData;
          final fresh = <int>{
            if (firstPaint)
              for (final cat in all) cat.id
            else if (_primed)
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
              _group(spending, CategoryKind.expense, fresh, firstPaint),
              const RuleHeader('income'),
              _group(income, CategoryKind.income, fresh, firstPaint),
              const SizedBox(height: Gap.x4),
              Text(
                'The figure is this month; the line beside it is the last six. '
                'Drag by the grip to put them in your order, tap a line to '
                'rewrite it.',
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

  Widget _group(
    List<Category> group,
    CategoryKind kind,
    Set<int> fresh,
    bool firstPaint,
  ) {
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
        return InkIn(
          key: ValueKey('cat-${cat.id}'),
          play: fresh.contains(cat.id),
          delay: firstPaint ? Duration(milliseconds: 24 * i) : Duration.zero,
          child: _CategoryRow(
            category: cat,
            index: i,
            pulse: _pulse[cat.id] ?? CategoryPulse.none,
            // A book with nothing in it yet doesn't get to call lines unused.
            showQuiet: _pulse.isNotEmpty,
            leaving: _leaving.contains(cat.id),
            onTap: () => _openSheet(existing: cat),
          ),
        );
      },
    );
  }
}

/// One ruled line: the mark, the word, what it cost this month, the shape of
/// the last six, the grip.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.index,
    required this.pulse,
    required this.showQuiet,
    required this.leaving,
    required this.onTap,
  });

  final Category category;
  final int index;
  final CategoryPulse pulse;

  /// False while the book has no history at all — an empty book has no
  /// standing to call a line unused.
  final bool showQuiet;
  final bool leaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return AnimatedOpacity(
      duration: Motion.quick,
      curve: Motion.curve,
      opacity: leaving ? 0.3 : 1,
      child: LedgerLine(
        mark: CatMark(category.icon, size: 16),
        title: category.name,
        detail: showQuiet ? pulse.quietLabel : null,
        struck: leaving,
        onTap: onTap,
        amountWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 16,
              child: pulse.hasTrend ? Sparkline(pulse.months) : null,
            ),
            const SizedBox(width: Gap.x3),
            SizedBox(
              width: 72,
              child: Text(
                pulse.monthPaise == 0 ? '—' : Inr.format(pulse.monthPaise),
                textAlign: TextAlign.right,
                style: LedgerType.amount.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                  decoration: leaving ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            const SizedBox(width: Gap.x2),
            ReorderableDragStartListener(
              index: index,
              child: PenLines(
                size: 15, color: c.inkFaint.withValues(alpha: 0.55)),
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

  /// The page strikes the line out before the write lands, so the verdict
  /// travels back rather than the deletion.
  void _retire() {
    if (widget.existing == null) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop('retire');
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final adding = widget.existing == null;

    return Padding(
      padding: EdgeInsets.only(
        left: Gap.page,
        right: Gap.page,
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
              const SheetHandle(),
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
                  for (final (i, key) in LedgerIcons.keys.indexed)
                    InkIn(
                      delay: Duration(milliseconds: 12 * i),
                      child: Pressable(
                        onTap: () => setState(() => _icon = key),
                        child: AnimatedContainer(
                          duration: Motion.quick,
                          curve: Motion.curve,
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
                    ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _name,
                builder: (context, value, _) {
                  final ready = value.text.trim().isNotEmpty;
                  return AnimatedOpacity(
                    duration: Motion.quick,
                    curve: Motion.curve,
                    opacity: ready ? 1 : 0.5,
                    child: FilledButton(
                      onPressed: ready ? _keep : null,
                      child: AnimatedSwitcher(
                        duration: Motion.quick,
                        child: Text(
                          ready ? 'Keep it' : 'give it a word first',
                          key: ValueKey(ready),
                        ),
                      ),
                    ),
                  );
                },
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
