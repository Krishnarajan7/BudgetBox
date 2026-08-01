import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// The one-tap repeats — kept, ordered, and let go from here.
class PinnedManagerPage extends ConsumerStatefulWidget {
  const PinnedManagerPage({super.key});

  @override
  ConsumerState<PinnedManagerPage> createState() => _PinnedManagerPageState();
}

class _PinnedManagerPageState extends ConsumerState<PinnedManagerPage> {
  /// Ids already on the page — only genuinely new lines animate in.
  final _seen = <int>{};
  bool _primed = false;

  /// The order the owner's finger just chose, kept until the write lands.
  List<int>? _localOrder;

  List<Pinned> _ordered(List<Pinned> pins) {
    final wanted = _localOrder;
    if (wanted == null) return pins;
    final byId = {for (final p in pins) p.id: p};
    if (wanted.length != pins.length ||
        !wanted.toSet().containsAll(byId.keys)) {
      return pins;
    }
    return [for (final id in wanted) byId[id]!];
  }

  Future<void> _reorder(List<Pinned> pins, int oldIndex, int newIndex) async {
    final next = [...pins];
    next.insert(newIndex, next.removeAt(oldIndex));
    HapticFeedback.lightImpact();
    setState(() => _localOrder = [for (final p in next) p.id]);
    final db = ref.read(dbProvider);
    await db.batch((b) {
      for (final (i, p) in next.indexed) {
        b.update(
          db.pinneds,
          PinnedsCompanion(sortOrder: Value(i)),
          where: ($PinnedsTable t) => t.id.equals(p.id),
        );
      }
    });
  }

  Future<void> _openSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _PinSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(pinnedRepoProvider);

    return ModuleScaffold(
      title: 'Pinned',
      trailing: InkWell(
        onTap: _openSheet,
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: Icon(Icons.add, size: 20, color: c.inkFaint),
        ),
      ),
      child: StreamBuilder<List<Pinned>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          final pins = _ordered(snapshot.data ?? const <Pinned>[]);
          final fresh = <int>{
            if (_primed)
              for (final p in pins)
                if (!_seen.contains(p.id)) p.id,
          };
          if (snapshot.hasData) {
            _primed = true;
            _seen.addAll(pins.map((p) => p.id));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const SizedBox(height: Gap.x3),
              Text(
                'The one-tap repeats behind the long-press plus.',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 12, color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x3),
              if (snapshot.hasData && pins.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x8),
                  child: Text(
                    "Nothing pinned. The Book's long-press can "
                    'send entries here.',
                    style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (from, to) => _reorder(pins, from, to),
                  proxyDecorator: (child, index, animation) => Material(
                    color: c.paperRaised,
                    elevation: 3,
                    shadowColor: c.ink.withValues(alpha: 0.25),
                    child: child,
                  ),
                  itemCount: pins.length,
                  itemBuilder: (context, i) {
                    final p = pins[i];
                    return _Entrance(
                      key: ValueKey('pin-entrance-${p.id}'),
                      animate: fresh.contains(p.id),
                      child: Dismissible(
                        key: ValueKey('pin-${p.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          color: c.seal.withValues(alpha: 0.12),
                          padding: const EdgeInsets.only(right: Gap.x4),
                          child: Icon(
                            Icons.push_pin_outlined,
                            size: 16,
                            color: c.seal,
                          ),
                        ),
                        onDismissed: (_) {
                          HapticFeedback.mediumImpact();
                          repo.unpin(p.id);
                        },
                        child: _PinRow(pin: p, index: i),
                      ),
                    );
                  },
                ),
              if (pins.isNotEmpty) ...[
                const SizedBox(height: Gap.x4),
                Text(
                  'Drag by the grip to reorder. Swipe a line left to unpin — '
                  'its past entries stay in the book.',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              ],
              const SizedBox(height: Gap.x8),
            ],
          );
        },
      ),
    );
  }
}

/// One ruled line: the pin, the title, the amount in mono, the grip.
class _PinRow extends StatelessWidget {
  const _PinRow({required this.pin, required this.index});

  final Pinned pin;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin_outlined, size: 16, color: c.inkFaint),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: Text(
              pin.title,
              style: LedgerType.bodyText.copyWith(color: c.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            Inr.format(pin.amountPaise),
            style: LedgerType.amount.copyWith(color: c.ink),
          ),
          const SizedBox(width: Gap.x3),
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
    );
  }
}

/// Title, amount, and the two homes every entry needs: a category and an
/// account. Four fields, then one tap forever.
class _PinSheet extends ConsumerStatefulWidget {
  const _PinSheet();

  @override
  ConsumerState<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends ConsumerState<_PinSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  int? _categoryId;
  int? _accountId;

  List<Category> _categories = const [];
  List<Account> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final cats = await (db.select(db.categories)
          ..where((c) =>
              c.archived.equals(false) &
              c.kind.equalsValue(CategoryKind.expense))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
    final accts = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
        .get();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _accounts = accts;
    });
  }

  int _paise() {
    final raw = _amount.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return 0;
    final rupees = double.tryParse(raw);
    if (rupees == null) return 0;
    return (rupees * 100).round();
  }

  bool get _ready =>
      _title.text.trim().isNotEmpty &&
      _paise() > 0 &&
      _categoryId != null &&
      _accountId != null;

  Future<void> _pin() async {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    await ref.read(pinnedRepoProvider).pin(
          title: _title.text.trim(),
          amountPaise: _paise(),
          categoryId: _categoryId!,
          accountId: _accountId!,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);

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
                'Pin a repeat — one tap from here on.',
                style: LedgerType.bodyStrong.copyWith(color: c.ink),
              ),
              const SizedBox(height: Gap.x3),
              Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.rule)),
                ),
                child: TextField(
                  controller: _title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  style:
                      LedgerType.bodyText.copyWith(fontSize: 16, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'the usual — chai, the bus, the mess',
                    hintStyle: LedgerType.bodyText
                        .copyWith(fontSize: 16, color: c.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x3),
              Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.rule)),
                ),
                child: TextField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: LedgerType.amountTotal
                      .copyWith(fontSize: 22, color: c.ink),
                  decoration: InputDecoration(
                    prefixText: '₹',
                    prefixStyle: LedgerType.amountTotal
                        .copyWith(fontSize: 22, color: c.inkFaint),
                    hintText: '0',
                    hintStyle: LedgerType.amountTotal
                        .copyWith(fontSize: 22, color: c.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'under',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              Wrap(
                spacing: Gap.x2,
                runSpacing: Gap.x2,
                children: [
                  for (final cat in _categories)
                    LedgerChip(
                      cat.name,
                      icon: LedgerIcons.resolve(cat.icon),
                      selected: _categoryId == cat.id,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _categoryId = cat.id);
                      },
                    ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'paid from',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              Wrap(
                spacing: Gap.x2,
                runSpacing: Gap.x2,
                children: [
                  for (final a in _accounts)
                    LedgerChip(
                      a.name,
                      icon: LedgerIcons.account[a.kind.name],
                      selected: _accountId == a.id,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _accountId = a.id);
                      },
                    ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              FilledButton(
                onPressed: _ready ? _pin : null,
                child: const Text('Pin it'),
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
