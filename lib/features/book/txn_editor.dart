import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// Rewriting a line in the book. The add sheet's sibling: same handle, same
/// hero amount, same chips — but it opens on an entry that already exists,
/// and saving stamps it again. No toast; the corrected line is the
/// confirmation.
Future<void> showTxnEditor(BuildContext context, Txn txn) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => TxnEditor(txn: txn),
  );
}

/// The long-press context sheet: pin the entry as a one-tap repeat, or
/// strike it out of the book.
Future<void> showTxnActions(BuildContext context, WidgetRef ref, Txn txn) {
  final canPin = txn.type == TxnType.expense && txn.categoryId != null;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final c = LedgerColors.of(sheetContext);

      Widget row({
        required IconData icon,
        required String label,
        required Color color,
        required VoidCallback onTap,
        bool last = false,
      }) {
        return InkWell(
          onTap: onTap,
          child: Container(
            decoration: last
                ? null
                : BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.rule)),
                  ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: Gap.x3),
                Text(label, style: LedgerType.bodyText.copyWith(color: color)),
              ],
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x3),
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
              Text(
                '${txn.title} · ${Inr.format(txn.amountPaise)}',
                style: LedgerType.label.copyWith(color: c.inkFaint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Gap.x1),
              if (canPin)
                row(
                  icon: Icons.push_pin_outlined,
                  label: 'pin as a repeat',
                  color: c.ink,
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final nav = Navigator.of(sheetContext);
                    await ref.read(pinnedRepoProvider).pin(
                          title: txn.title,
                          amountPaise: txn.amountPaise,
                          categoryId: txn.categoryId!,
                          accountId: txn.accountId,
                        );
                    nav.pop();
                  },
                ),
              row(
                icon: Icons.close,
                label: 'strike it out',
                color: c.seal,
                last: true,
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  final nav = Navigator.of(sheetContext);
                  await ref.read(txnRepoProvider).deleteTxn(txn.id);
                  nav.pop();
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class TxnEditor extends ConsumerStatefulWidget {
  const TxnEditor({super.key, required this.txn});

  final Txn txn;

  @override
  ConsumerState<TxnEditor> createState() => _TxnEditorState();
}

class _TxnEditorState extends ConsumerState<TxnEditor> {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  late final TextEditingController _title =
      TextEditingController(text: widget.txn.title);
  late final TextEditingController _note =
      TextEditingController(text: widget.txn.note ?? '');
  final _amountCtl = TextEditingController();

  List<Category> _categories = const [];
  List<Account> _accounts = const [];

  late int _amountPaise = widget.txn.amountPaise;
  late int? _categoryId = widget.txn.categoryId;
  late int _accountId = widget.txn.accountId;
  late DateTime _at = widget.txn.at;
  late bool _noteOpen = (widget.txn.note ?? '').trim().isNotEmpty;
  bool _editingAmount = false;
  bool _pressed = false;
  bool _saving = false;

  bool get _isTransfer => widget.txn.type == TxnType.transfer;

  @override
  void initState() {
    super.initState();
    if (!_isTransfer) _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final kind = widget.txn.type == TxnType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    final cats = await (db.select(db.categories)
          ..where((x) => x.archived.equals(false))
          ..where((x) => x.kind.equalsValue(kind))
          ..orderBy([(x) => OrderingTerm.asc(x.sortOrder)]))
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

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _amountCtl.dispose();
    super.dispose();
  }

  Category? get _selectedCategory {
    for (final c in _categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  String get _dateLabel => '${_at.day} ${_months[_at.month - 1]}';

  int? _parsePaise(String s) {
    final v = double.tryParse(s.trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  void _startAmountEdit() {
    HapticFeedback.selectionClick();
    final p = _amountPaise;
    _amountCtl.text =
        p % 100 == 0 ? '${p ~/ 100}' : (p / 100).toStringAsFixed(2);
    _amountCtl.selection =
        TextSelection(baseOffset: 0, extentOffset: _amountCtl.text.length);
    setState(() => _editingAmount = true);
  }

  Future<void> _stamp() async {
    if (_saving || _amountPaise <= 0) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();

    final title = _title.text.trim().isEmpty
        ? (_selectedCategory?.name ?? 'Entry')
        : _title.text.trim();
    final note = _note.text.trim();

    await ref.read(txnRepoProvider).updateTxn(
          widget.txn.id,
          amountPaise: _amountPaise,
          categoryId: _categoryId,
          accountId: _accountId,
          title: title,
          at: _at,
          note: note.isEmpty ? null : note,
        );

    // Let the press scale settle before the sheet leaves.
    await Future<void>.delayed(const Duration(milliseconds: 160));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _strike() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    await ref.read(txnRepoProvider).deleteTxn(widget.txn.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SingleChildScrollView(
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
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
              Text(
                _isTransfer ? 'a transfer' : 'rewriting this line',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              _amountHero(c),
              if (_isTransfer) ..._transferBody(c) else ..._editBody(c),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _editBody(LedgerColors c) {
    return [
      const SizedBox(height: Gap.x2),
      _categoryChips(c),
      const SizedBox(height: Gap.x2),
      _titleField(c),
      _defaultsRow(c),
      if (_noteOpen) _noteField(c),
      const SizedBox(height: Gap.x4),
      _stampButton(c),
      const SizedBox(height: Gap.x1),
      Center(
        child: TextButton(
          onPressed: _saving ? null : _strike,
          child: Text(
            'strike it out',
            style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.seal),
          ),
        ),
      ),
    ];
  }

  List<Widget> _transferBody(LedgerColors c) {
    return [
      const SizedBox(height: Gap.x1),
      Text(
        '${widget.txn.title} · $_dateLabel',
        style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
      ),
      const SizedBox(height: Gap.x3),
      Text(
        'Transfers are rewritten, not edited — strike it out and write it fresh.',
        style: LedgerType.bodyText.copyWith(color: c.inkFaint),
      ),
      const SizedBox(height: Gap.x4),
      TextButton(
        onPressed: _saving ? null : _strike,
        child: Text(
          'strike it out',
          style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.seal),
        ),
      ),
    ];
  }

  Widget _amountHero(LedgerColors c) {
    final style = LedgerType.heroAmount.copyWith(fontSize: 38, color: c.ink);

    if (_isTransfer || !_editingAmount) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isTransfer ? null : _startAmountEdit,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(Inr.format(_amountPaise), style: style),
            if (!_isTransfer) ...[
              const SizedBox(width: Gap.x2),
              Icon(Icons.edit_outlined, size: 15, color: c.inkFaint),
            ],
          ],
        ),
      );
    }

    return TextField(
      key: const ValueKey('amount-field'),
      controller: _amountCtl,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: style,
      decoration: InputDecoration(
        prefixText: '₹',
        prefixStyle: style,
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (v) => setState(() => _amountPaise = _parsePaise(v) ?? 0),
      onSubmitted: (_) => setState(() {
        if (_amountPaise <= 0) _amountPaise = widget.txn.amountPaise;
        _editingAmount = false;
      }),
    );
  }

  Widget _categoryChips(LedgerColors c) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final cat in _categories) ...[
            LedgerChip(
              cat.name,
              icon: LedgerIcons.resolve(cat.icon),
              selected: _categoryId == cat.id,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() =>
                    _categoryId = _categoryId == cat.id ? null : cat.id);
              },
            ),
            const SizedBox(width: Gap.x2),
          ],
        ],
      ),
    );
  }

  Widget _titleField(LedgerColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: TextField(
        key: const ValueKey('title-field'),
        controller: _title,
        style: LedgerType.bodyText.copyWith(color: c.ink),
        decoration: InputDecoration(
          hintText: 'what was it?',
          hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
        ),
      ),
    );
  }

  Widget _defaultsRow(LedgerColors c) {
    final acct = _accounts.where((a) => a.id == _accountId).firstOrNull?.name ??
        '—';
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x3),
      child: Row(
        children: [
          _defaultTap(c, acct, _pickAccount),
          const SizedBox(width: Gap.x4),
          _defaultTap(c, _dateLabel, _pickDate),
          const Spacer(),
          LedgerChip(
            'note',
            icon: Icons.notes_outlined,
            selected: _noteOpen,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                if (_noteOpen && _note.text.trim().isEmpty) {
                  _noteOpen = false;
                } else {
                  _noteOpen = true;
                }
              });
            },
          ),
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

  Widget _noteField(LedgerColors c) {
    return Container(
      margin: const EdgeInsets.only(top: Gap.x2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: TextField(
        key: const ValueKey('note-field'),
        controller: _note,
        style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: 'a line for later',
          hintStyle:
              LedgerType.bodyText.copyWith(fontSize: 14, color: c.inkFaint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
        ),
      ),
    );
  }

  Widget _stampButton(LedgerColors c) {
    final enabled = _amountPaise > 0 && !_saving;
    return Listener(
      onPointerDown: (_) {
        if (enabled) setState(() => _pressed = true);
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed || _saving ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.seal,
            foregroundColor: c.paperRaised,
            disabledBackgroundColor: c.seal.withValues(alpha: 0.35),
            disabledForegroundColor: c.paperRaised,
          ),
          onPressed: enabled ? _stamp : null,
          child: const Text('Stamp it again'),
        ),
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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _at.isAfter(now) ? now : _at,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _at = DateTime(
          picked.year, picked.month, picked.day, _at.hour, _at.minute));
    }
  }
}
