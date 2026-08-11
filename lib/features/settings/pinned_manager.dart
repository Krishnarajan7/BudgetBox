import 'dart:async';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// How often a pin has actually been stamped, and when it last was.
class _Usage {
  const _Usage(this.times, this.last);

  final int times;
  final DateTime? last;
}

/// A repeat the book has noticed but the page hasn't pinned yet.
class _Suggestion {
  const _Suggestion({
    required this.title,
    required this.amountPaise,
    required this.categoryId,
    required this.accountId,
    required this.times,
  });

  final String title;
  final int amountPaise;
  final int categoryId;
  final int accountId;
  final int times;
}

/// title + amount is what makes a repeat the same repeat.
String _usageKey(String title, int amountPaise) =>
    '${title.trim().toLowerCase()}|$amountPaise';

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

  /// Pins on their way off the page: struck through while the ink dries.
  final _leaving = <int>{};

  /// Read-only readings behind the page: how each pin has been used, and
  /// which repeats are still unpinned.
  Map<String, _Usage> _usage = const {};
  List<_Suggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reread());
  }

  // ————— read-only queries —————

  /// Every stamped expense grouped by title + amount: the count and the last
  /// date. Timezone-safe — counts and maxima don't care about local days.
  Future<Map<String, _Usage>> _readUsage(LedgerDb db) async {
    final times = db.txns.id.count();
    final last = db.txns.at.max();
    final rows = await (db.selectOnly(db.txns)
          ..addColumns([db.txns.title, db.txns.amountPaise, times, last])
          ..where(db.txns.type.equalsValue(TxnType.expense))
          ..groupBy([db.txns.title, db.txns.amountPaise]))
        .get();
    return {
      for (final r in rows)
        _usageKey(r.read(db.txns.title)!, r.read(db.txns.amountPaise)!):
            _Usage(r.read(times) ?? 0, r.read(last)),
    };
  }

  /// The repeats he keeps typing by hand: three or more in ninety days, not
  /// pinned yet, with the homes the last one was filed under.
  Future<List<_Suggestion>> _readSuggestions(
    LedgerDb db,
    List<Pinned> pins,
  ) async {
    final pinned = {for (final p in pins) p.title.trim().toLowerCase()};
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final times = db.txns.id.count();
    final rows = await (db.selectOnly(db.txns)
          ..addColumns([db.txns.title, times])
          ..where(db.txns.type.equalsValue(TxnType.expense) &
              db.txns.categoryId.isNotNull() &
              db.txns.at.isBiggerOrEqualValue(cutoff))
          ..groupBy([db.txns.title])
          ..orderBy([OrderingTerm.desc(times)])
          ..limit(12))
        .get();

    final out = <_Suggestion>[];
    for (final r in rows) {
      final title = r.read(db.txns.title)!;
      final count = r.read(times) ?? 0;
      if (count < 3 || pinned.contains(title.trim().toLowerCase())) continue;
      final recent = await (db.select(db.txns)
            ..where((t) => t.title.equals(title) & t.categoryId.isNotNull())
            ..orderBy([(t) => OrderingTerm.desc(t.at)])
            ..limit(1))
          .getSingleOrNull();
      if (recent == null) continue;
      out.add(_Suggestion(
        title: title,
        amountPaise: recent.amountPaise,
        categoryId: recent.categoryId!,
        accountId: recent.accountId,
        times: count,
      ));
      if (out.length == 3) break;
    }
    return out;
  }

  Future<void> _reread() async {
    final db = ref.read(dbProvider);
    final pins = await db.select(db.pinneds).get();
    final usage = await _readUsage(db);
    final suggestions = await _readSuggestions(db, pins);
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _suggestions = suggestions;
    });
  }

  // ————— writes —————

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

  /// The line is struck out and left to dry before it leaves the page.
  Future<void> _strikeOut(int id) async {
    setState(() => _leaving.add(id));
    if (!Motion.reduced(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }
    await ref.read(pinnedRepoProvider).unpin(id);
    if (mounted) setState(() => _leaving.remove(id));
    await _reread();
  }

  Future<void> _openSheet({Pinned? existing}) async {
    final verdict = await showLedgerSheet<String>(
      context,
      builder: (context) => _PinSheet(existing: existing),
    );
    if (!mounted) return;
    if (verdict == 'unpin' && existing != null) {
      await _strikeOut(existing.id);
    } else {
      await _reread();
    }
  }

  Future<void> _takeSuggestion(_Suggestion s) async {
    await ref.read(pinnedRepoProvider).pin(
          title: s.title,
          amountPaise: s.amountPaise,
          categoryId: s.categoryId,
          accountId: s.accountId,
        );
    await _reread();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(pinnedRepoProvider);

    return ModuleScaffold(
      title: 'Pinned',
      trailing: Pressable(
        scale: 0.9,
        onTap: () => _openSheet(),
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: Icon(Icons.add, size: 20, color: c.inkFaint),
        ),
      ),
      child: StreamBuilder<List<Pinned>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          final pins = _ordered(snapshot.data ?? const <Pinned>[]);
          final firstPaint = !_primed && snapshot.hasData;
          final fresh = <int>{
            if (firstPaint)
              for (final p in pins) p.id
            else if (_primed)
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
                const EmptyPage(
                  line: 'Nothing pinned yet.',
                  sub: "The Book's long-press sends an entry here, "
                      'and anything below is fair game.',
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
                    return InkIn(
                      key: ValueKey('pin-entrance-${p.id}'),
                      play: fresh.contains(p.id),
                      delay: firstPaint
                          ? Duration(milliseconds: 24 * i)
                          : Duration.zero,
                      child: Dismissible(
                        key: ValueKey('pin-${p.id}'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          color: c.paperRaised,
                          padding: const EdgeInsets.only(right: Gap.x4),
                          child: Text(
                            'unpin',
                            style: LedgerType.bodyStrong
                                .copyWith(fontSize: 13, color: c.seal),
                          ),
                        ),
                        // The row springs back struck through, then leaves —
                        // an unpin you can watch, not a row that blinks out.
                        confirmDismiss: (_) {
                          HapticFeedback.mediumImpact();
                          unawaited(_strikeOut(p.id));
                          return Future<bool>.value(false);
                        },
                        child: _PinRow(
                          pin: p,
                          index: i,
                          usage: _usage[_usageKey(p.title, p.amountPaise)],
                          leaving: _leaving.contains(p.id),
                          onTap: () => _openSheet(existing: p),
                        ),
                      ),
                    );
                  },
                ),
              if (_suggestions.isNotEmpty) ...[
                const RuleHeader('worth pinning'),
                for (final (i, s) in _suggestions.indexed)
                  InkIn(
                    key: ValueKey('suggest-${s.title}-${s.amountPaise}'),
                    delay: Duration(milliseconds: 40 * i),
                    child: _SuggestionRow(
                      suggestion: s,
                      last: i == _suggestions.length - 1,
                      onPin: () => _takeSuggestion(s),
                    ),
                  ),
              ],
              if (pins.isNotEmpty) ...[
                const SizedBox(height: Gap.x4),
                Text(
                  'Drag by the grip to reorder. Tap a line to rewrite it, '
                  'swipe it left to unpin — its past entries stay in the book.',
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

/// One ruled line: the pin, the title over how often it has been stamped,
/// the amount in mono, the grip.
class _PinRow extends StatelessWidget {
  const _PinRow({
    required this.pin,
    required this.index,
    required this.usage,
    required this.leaving,
    required this.onTap,
  });

  final Pinned pin;
  final int index;
  final _Usage? usage;
  final bool leaving;
  final VoidCallback onTap;

  String get _whisper {
    final u = usage;
    final last = u?.last;
    if (u == null || u.times == 0 || last == null) return 'not stamped yet';
    final count = u.times == 1 ? 'stamped once' : 'stamped ${u.times} times';
    return '$count · last ${LedgerDates.ddMmm(last)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final strike = leaving ? TextDecoration.lineThrough : null;
    return AnimatedOpacity(
      duration: Motion.quick,
      curve: Motion.curve,
      opacity: leaving ? 0.3 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: c.paper,
            border: Border(bottom: BorderSide(color: c.rule)),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined, size: 16, color: c.inkFaint),
              const SizedBox(width: Gap.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pin.title,
                      style: LedgerType.bodyText.copyWith(
                        color: leaving ? c.inkFaint : c.ink,
                        decoration: strike,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _whisper,
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 11, color: c.inkFaint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                Inr.format(pin.amountPaise),
                style: LedgerType.amount.copyWith(
                  color: leaving ? c.inkFaint : c.ink,
                  decoration: strike,
                ),
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
        ),
      ),
    );
  }
}

/// A repeat he keeps typing out by hand, offered quietly.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.last,
    required this.onPin,
  });

  final _Suggestion suggestion;
  final bool last;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return LedgerLine(
      mark: Icon(Icons.history, size: 15, color: c.inkFaint),
      title: suggestion.title,
      detail: '${suggestion.times} times lately',
      last: last,
      amountWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Inr.format(suggestion.amountPaise),
            style: LedgerType.amount.copyWith(color: c.inkFaint),
          ),
          const SizedBox(width: Gap.x3),
          Pressable(
            onTap: onPin,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Gap.x1, vertical: Gap.x1),
              child: Text(
                'pin it',
                style: LedgerType.bodyStrong
                    .copyWith(fontSize: 12, color: c.quill),
              ),
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
  const _PinSheet({this.existing});

  final Pinned? existing;

  @override
  ConsumerState<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends ConsumerState<_PinSheet> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.amountPaise / 100)
            .toStringAsFixed(widget.existing!.amountPaise % 100 == 0 ? 0 : 2),
  );
  late int? _categoryId = widget.existing?.categoryId;
  late int? _accountId = widget.existing?.accountId;

  List<Category> _categories = const [];
  List<Account> _accounts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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

  /// What the sheet is still waiting for, in the order it is asked.
  String get _waitingOn {
    if (_title.text.trim().isEmpty) return 'name the repeat';
    if (_paise() <= 0) return 'and how much';
    if (_categoryId == null) return 'file it somewhere';
    return 'and from which pocket';
  }

  Future<void> _keep() async {
    if (!_ready) return;
    HapticFeedback.lightImpact();
    final existing = widget.existing;
    if (existing == null) {
      await ref.read(pinnedRepoProvider).pin(
            title: _title.text.trim(),
            amountPaise: _paise(),
            categoryId: _categoryId!,
            accountId: _accountId!,
          );
    } else {
      final db = ref.read(dbProvider);
      await (db.update(db.pinneds)..where((p) => p.id.equals(existing.id)))
          .write(PinnedsCompanion(
        title: Value(_title.text.trim()),
        amountPaise: Value(_paise()),
        categoryId: Value(_categoryId!),
        accountId: Value(_accountId!),
      ));
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// The page strikes the line out before the write lands.
  void _unpin() {
    if (widget.existing == null) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop('unpin');
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
                adding
                    ? 'Pin a repeat — one tap from here on.'
                    : 'The same repeat, put differently.',
                style: LedgerType.bodyStrong.copyWith(color: c.ink),
              ),
              const SizedBox(height: Gap.x3),
              Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.rule)),
                ),
                child: TextField(
                  controller: _title,
                  autofocus: adding,
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
              const SizedBox(height: Gap.x4),
              Text(
                'how much, in rupees',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
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
              // The button fills in as the four fields land.
              AnimatedOpacity(
                duration: Motion.quick,
                curve: Motion.curve,
                opacity: _ready ? 1 : 0.5,
                child: FilledButton(
                  onPressed: _ready ? _keep : null,
                  child: AnimatedSwitcher(
                    duration: Motion.quick,
                    child: Text(
                      _ready ? (adding ? 'Pin it' : 'Keep it') : _waitingOn,
                      key: ValueKey(_ready ? 'ready' : _waitingOn),
                    ),
                  ),
                ),
              ),
              if (!adding)
                Center(
                  child: TextButton(
                    onPressed: _unpin,
                    child: const Text('Unpin it — the entries stay'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
