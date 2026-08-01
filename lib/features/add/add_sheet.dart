import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/txn_repo.dart';
import 'amount_engine.dart';

/// The sacred flow. Keypad visible on open, amount is the only required
/// field, and Save is a stamp: press, haptic, seal flash, done — the ledger
/// line is the confirmation, so there is no toast.
Future<void> showAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AddSheet(),
  );
}

class AddSheet extends ConsumerStatefulWidget {
  const AddSheet({super.key});

  @override
  ConsumerState<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<AddSheet> {
  final _engine = AmountEngine();
  final _title = TextEditingController();

  List<Category> _categories = const [];
  List<Account> _accounts = const [];
  List<int> _chipOrder = const [];
  TitleSuggestion? _suggestion;
  Timer? _debounce;

  int? _categoryId;
  int? _accountId;
  DateTime _at = DateTime.now();
  bool _stamping = false;

  @override
  void initState() {
    super.initState();
    _load();
    _title.addListener(_onTitleChanged);
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final txns = ref.read(txnRepoProvider);
    final cats = await (db.select(db.categories)
          ..where((c) => c.archived.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
    final accts = await (db.select(db.accounts)
          ..where((a) => a.archived.equals(false))
          ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
        .get();
    final top = await txns.topCategoryIds();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _accounts = accts;
      _accountId = accts.isEmpty ? null : accts.first.id;
      final expenseCats = cats
          .where((c) => c.kind == CategoryKind.expense)
          .map((c) => c.id)
          .toList();
      _chipOrder = [
        ...top.where(expenseCats.contains),
        ...expenseCats.where((id) => !top.contains(id)),
      ].take(4).toList();
    });
  }

  void _onTitleChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      final text = _title.text;
      if (text.length < 2) {
        if (mounted) setState(() => _suggestion = null);
        return;
      }
      final s = await ref.read(txnRepoProvider).suggestTitles(text, limit: 1);
      if (!mounted || _title.text != text) return;
      setState(() {
        final match = s.isEmpty ? null : s.first;
        _suggestion = (match == null ||
                match.title.toLowerCase() == text.toLowerCase())
            ? null
            : match;
        // A remembered title quietly brings its category and account along.
        if (match != null && match.title.toLowerCase() == text.toLowerCase()) {
          _categoryId = match.categoryId ?? _categoryId;
          _accountId = match.accountId ?? _accountId;
        }
      });
    });
  }

  void _acceptSuggestion() {
    final s = _suggestion;
    if (s == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _title.text = s.title;
      _title.selection = TextSelection.collapsed(offset: s.title.length);
      _categoryId = s.categoryId ?? _categoryId;
      _accountId = s.accountId ?? _accountId;
      _suggestion = null;
    });
  }

  Category? get _selectedCategory {
    if (_categoryId == null) return null;
    for (final c in _categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  Future<void> _stamp({required bool andAnother}) async {
    if (_stamping || _engine.paise <= 0 || _accountId == null) return;
    setState(() => _stamping = true);
    HapticFeedback.lightImpact();

    final title = _title.text.trim().isEmpty
        ? (_selectedCategory?.name ?? 'Entry')
        : _title.text.trim();

    await ref.read(txnRepoProvider).addExpense(
          amountPaise: _engine.paise,
          accountId: _accountId!,
          categoryId: _categoryId,
          title: title,
          at: _at,
        );

    // Let the seal flash land before the sheet leaves.
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    if (andAnother) {
      setState(() {
        _engine.clear();
        _title.clear();
        _suggestion = null;
        _stamping = false;
        // Category and account are kept — that's the whole point.
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.rule,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: Gap.x3),
            _amountRow(c),
            const SizedBox(height: Gap.x2),
            _categoryChips(c),
            _titleField(c),
            if (_suggestion != null) _suggestionRow(c),
            _defaultsRow(c),
            const SizedBox(height: Gap.x3),
            _Keypad(
              onDigit: (d) => setState(() => _engine.digit(d)),
              onOp: (o) => setState(() => _engine.op(o)),
              onPoint: () => setState(() => _engine.point()),
              onBackspace: () => setState(() => _engine.backspace()),
              onStamp: () => _stamp(andAnother: false),
              onStampAndAnother: () => _stamp(andAnother: true),
              stamping: _stamping,
              enabled: _engine.paise > 0,
            ),
            const SizedBox(height: Gap.x2),
            Center(
              child: Text(
                'hold to stamp & add another',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountRow(LedgerColors c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            _engine.isEmpty ? '₹0' : Inr.format(_engine.paise),
            style: LedgerType.heroAmount.copyWith(fontSize: 38, color: c.ink),
          ),
        ),
        if (_engine.expression.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              _engine.expression,
              style: LedgerType.amount.copyWith(color: c.inkFaint),
            ),
          ),
      ],
    );
  }

  Widget _categoryChips(LedgerColors c) {
    final chips = <Widget>[
      for (final id in _chipOrder)
        _chip(
          c,
          category: _categories.firstWhere((x) => x.id == id),
          selected: _categoryId == id,
        ),
      GestureDetector(
        onTap: _pickCategory,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: c.rule),
            borderRadius: BorderRadius.circular(Corner.chip),
          ),
          child: Icon(Icons.more_horiz, size: 16, color: c.inkFaint),
        ),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final w in chips) ...[w, const SizedBox(width: Gap.x2)],
        ],
      ),
    );
  }

  Widget _chip(LedgerColors c,
      {required Category category, required bool selected}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _categoryId = selected ? null : category.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.quillSoft : null,
          border: Border.all(color: selected ? c.quill : c.rule),
          borderRadius: BorderRadius.circular(Corner.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LedgerIcons.resolve(category.icon),
              size: 13,
              color: selected ? c.quill : c.inkFaint,
            ),
            const SizedBox(width: 5),
            Text(
              category.name,
              style: selected
                  ? LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill)
                  : LedgerType.bodyText
                      .copyWith(fontSize: 13, color: c.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory() async {
    final c = LedgerColors.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => GridView.count(
        crossAxisCount: 4,
        padding: const EdgeInsets.all(Gap.x4),
        mainAxisSpacing: Gap.x2,
        crossAxisSpacing: Gap.x2,
        shrinkWrap: true,
        children: [
          for (final cat
              in _categories.where((x) => x.kind == CategoryKind.expense))
            InkWell(
              onTap: () => Navigator.of(context).pop(cat.id),
              borderRadius: BorderRadius.circular(Corner.key),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LedgerIcons.resolve(cat.icon), size: 22, color: c.ink),
                  const SizedBox(height: 4),
                  Text(
                    cat.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 11, color: c.inkFaint),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  Widget _titleField(LedgerColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: TextField(
        controller: _title,
        style: LedgerType.bodyText.copyWith(color: c.ink),
        decoration: InputDecoration(
          hintText: 'what was it? (optional)',
          hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
        ),
      ),
    );
  }

  Widget _suggestionRow(LedgerColors c) {
    final s = _suggestion!;
    final cat = s.categoryId == null
        ? null
        : _categories.where((x) => x.id == s.categoryId).firstOrNull;
    return InkWell(
      onTap: _acceptSuggestion,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.x2),
        child: Row(
          children: [
            Icon(Icons.history, size: 14, color: c.inkFaint),
            const SizedBox(width: Gap.x2),
            if (cat != null) ...[
              Icon(LedgerIcons.resolve(cat.icon), size: 12, color: c.quill),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                cat == null ? s.title : '${s.title} · ${cat.name}',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.quill,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultsRow(LedgerColors c) {
    final acct =
        _accounts.where((a) => a.id == _accountId).firstOrNull?.name ?? '—';
    final today = DateTime.now();
    final sameDay = _at.year == today.year &&
        _at.month == today.month &&
        _at.day == today.day;
    final dateLabel = sameDay ? 'today' : '${_at.day}/${_at.month}';
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        children: [
          _defaultTap(c, acct, _pickAccount),
          const SizedBox(width: Gap.x4),
          _defaultTap(c, dateLabel, _pickDate),
          const Spacer(),
          Text('details ›',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              )),
        ],
      ),
    );
  }

  Widget _defaultTap(LedgerColors c, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style:
                LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
          ),
          const SizedBox(width: 2),
          Icon(Icons.expand_more, size: 13, color: c.inkFaint),
        ],
      ),
    );
  }

  Future<void> _pickAccount() async {
    final c = LedgerColors.of(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in _accounts)
              ListTile(
                title: Text(a.name,
                    style: LedgerType.bodyText.copyWith(color: c.ink)),
                trailing: Text(Inr.format(a.balancePaise),
                    style: LedgerType.amount.copyWith(color: c.inkFaint)),
                onTap: () => Navigator.of(context).pop(a.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _accountId = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _at = DateTime(
          picked.year, picked.month, picked.day, _at.hour, _at.minute));
    }
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onOp,
    required this.onPoint,
    required this.onBackspace,
    required this.onStamp,
    required this.onStampAndAnother,
    required this.stamping,
    required this.enabled,
  });

  final ValueChanged<String> onDigit;
  final ValueChanged<String> onOp;
  final VoidCallback onPoint;
  final VoidCallback onBackspace;
  final VoidCallback onStamp;
  final VoidCallback onStampAndAnother;
  final bool stamping;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback onTap, {bool op = false}) =>
        _Key(label: label, onTap: onTap, op: op);

    // Ops earn their keys by use: sums dominate real purchases, so + and −
    // live in the column; × and ÷ stay in the engine for later.
    return Column(
      children: [
        Row(children: [
          key('7', () => onDigit('7')),
          key('8', () => onDigit('8')),
          key('9', () => onDigit('9')),
          key('＋', () => onOp('+'), op: true),
        ]),
        Row(children: [
          key('4', () => onDigit('4')),
          key('5', () => onDigit('5')),
          key('6', () => onDigit('6')),
          key('−', () => onOp('−'), op: true),
        ]),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(children: [
                  Row(children: [
                    key('1', () => onDigit('1')),
                    key('2', () => onDigit('2')),
                    key('3', () => onDigit('3')),
                  ]),
                  Row(children: [
                    key('0', () => onDigit('0')),
                    key('.', onPoint),
                    key('⌫', onBackspace),
                  ]),
                ]),
              ),
              Expanded(
                child: _StampKey(
                  onTap: onStamp,
                  onLongPress: onStampAndAnother,
                  stamping: stamping,
                  enabled: enabled,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap, this.op = false});

  final String label;
  final VoidCallback onTap;
  final bool op;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: op ? Colors.transparent : c.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corner.key),
            side: op ? BorderSide.none : BorderSide(color: c.rule),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Corner.key),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  label,
                  style: LedgerType.amount.copyWith(
                    fontSize: 19,
                    color: op ? c.quill : c.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StampKey extends StatelessWidget {
  const _StampKey({
    required this.onTap,
    required this.onLongPress,
    required this.stamping,
    required this.enabled,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool stamping;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: AnimatedScale(
        scale: stamping ? 0.94 : 1,
        duration: const Duration(milliseconds: 120),
        child: Material(
          color: enabled ? c.seal : c.seal.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Corner.key),
          child: InkWell(
            borderRadius: BorderRadius.circular(Corner.key),
            onTap: enabled ? onTap : null,
            onLongPress: enabled ? onLongPress : null,
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: stamping
                        ? Icon(Icons.check_circle,
                            key: const ValueKey('done'),
                            color: c.paperRaised,
                            size: 26)
                        : Container(
                            key: const ValueKey('idle'),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: c.paperRaised, width: 2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(Icons.check,
                                size: 13, color: c.paperRaised),
                          ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'stamp',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 13,
                      color: c.paperRaised,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
