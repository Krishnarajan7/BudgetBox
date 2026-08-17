import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// How often this line has been rewritten, and when it last was — read
/// straight off the activity log. Null when it has only ever been written
/// once; a whisper with nothing to say stays quiet.
Future<({int times, DateTime last})?> txnRewriteHistory(
  LedgerDb db,
  int txnId,
) async {
  final rows =
      await (db.select(db.activities)
            ..where((a) => a.txnId.equals(txnId))
            ..where((a) => a.action.equalsValue(ActivityAction.edited))
            ..orderBy([(a) => OrderingTerm.desc(a.at)]))
          .get();
  if (rows.isEmpty) return null;
  return (times: rows.length, last: rows.first.at);
}

/// 'rewritten twice · last on 12 Jul' — the line's own margin note.
String rewriteWhisper(int times, DateTime last) {
  const words = ['once', 'twice', 'three times', 'four times', 'five times'];
  final howOften = times <= words.length ? words[times - 1] : '$times times';
  return 'rewritten $howOften · last on ${LedgerDates.ddMmm(last)}';
}

/// Rewriting a line in the book. The add sheet's sibling: same handle, same
/// hero amount, same chips — but it opens on an entry that already exists,
/// and saving stamps it again. No toast; the corrected line is the
/// confirmation.
Future<void> showTxnEditor(BuildContext context, Txn txn) {
  return showLedgerSheet<void>(context, builder: (_) => TxnEditor(txn: txn));
}

/// The long-press context sheet: pin the entry as a one-tap repeat, or
/// strike it out of the book. This is where the strike wears the seal —
/// the editor's own strike stays faint so the page keeps its budget.
Future<void> showTxnActions(BuildContext context, WidgetRef ref, Txn txn) {
  final canPin = txn.type == TxnType.expense && txn.categoryId != null;
  return showLedgerSheet<void>(
    context,
    builder: (sheetContext) {
      final c = LedgerColors.of(sheetContext);

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x2),
                child: Text(
                  '${txn.title} · ${Inr.format(txn.amountPaise)}',
                  style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canPin)
                InkIn(
                  child: LedgerLine(
                    mark: SealOutline(size: 14, color: c.inkFaint),
                    title: 'pin as a repeat',
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final nav = Navigator.of(sheetContext);
                      await ref
                          .read(pinnedRepoProvider)
                          .pin(
                            title: txn.title,
                            amountPaise: txn.amountPaise,
                            categoryId: txn.categoryId!,
                            accountId: txn.accountId,
                          );
                      nav.pop();
                    },
                  ),
                ),
              InkIn(
                delay: const Duration(milliseconds: 24),
                child: LedgerLine(
                  mark: PenCross(size: 13, color: c.seal),
                  title: 'strike it out',
                  last: true,
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    final nav = Navigator.of(sheetContext);
                    await ref.read(txnRepoProvider).deleteTxn(txn.id);
                    nav.pop();
                  },
                ),
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
  late final TextEditingController _title = TextEditingController(
    text: widget.txn.title,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.txn.note ?? '',
  );
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

  /// The stamp lands on the page before the sheet leaves.
  bool _stamping = false;

  /// What the activity log remembers about this line.
  String? _history;

  bool get _isTransfer => widget.txn.type == TxnType.transfer;

  @override
  void initState() {
    super.initState();
    if (!_isTransfer) _load();
    _loadHistory();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final kind = widget.txn.type == TxnType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    final cats =
        await (db.select(db.categories)
              ..where((x) => x.archived.equals(false))
              ..where((x) => x.kind.equalsValue(kind))
              ..orderBy([(x) => OrderingTerm.asc(x.sortOrder)]))
            .get();
    final accts =
        await (db.select(db.accounts)
              ..where((a) => a.archived.equals(false))
              ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
            .get();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _accounts = accts;
    });
  }

  Future<void> _loadHistory() async {
    final past = await txnRewriteHistory(ref.read(dbProvider), widget.txn.id);
    if (!mounted || past == null) return;
    setState(() => _history = rewriteWhisper(past.times, past.last));
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

  String get _dateLabel => LedgerDates.ddMmm(_at);

  int? _parsePaise(String s) {
    final v = double.tryParse(s.trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  void _startAmountEdit() {
    HapticFeedback.selectionClick();
    final p = _amountPaise;
    _amountCtl.text = p % 100 == 0
        ? '${p ~/ 100}'
        : (p / 100).toStringAsFixed(2);
    _amountCtl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _amountCtl.text.length,
    );
    setState(() => _editingAmount = true);
  }

  Future<void> _stamp() async {
    if (_saving || _amountPaise <= 0) return;
    setState(() {
      _saving = true;
      _stamping = true;
    });
    HapticFeedback.lightImpact();

    final title = _title.text.trim().isEmpty
        ? (_selectedCategory?.name ?? 'Entry')
        : _title.text.trim();
    final note = _note.text.trim();

    await ref
        .read(txnRepoProvider)
        .updateTxn(
          widget.txn.id,
          amountPaise: _amountPaise,
          categoryId: _categoryId,
          accountId: _accountId,
          title: title,
          at: _at,
          note: note.isEmpty ? null : note,
        );

    // The stamp has to land before the sheet leaves — it is the receipt.
    await Future<void>.delayed(const Duration(milliseconds: 340));
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
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              // The sheet writes itself in, section after section.
              InkIn(
                child: Text(
                  _isTransfer ? 'a transfer' : 'rewriting this line',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
              ),
              const SizedBox(height: Gap.x2),
              InkIn(
                delay: const Duration(milliseconds: 40),
                child: _amountHero(c),
              ),
              if (_history != null) ...[
                const SizedBox(height: 2),
                InkIn(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    _history!,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ],
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
      InkIn(delay: const Duration(milliseconds: 110), child: _categoryChips(c)),
      const SizedBox(height: Gap.x2),
      InkIn(
        delay: const Duration(milliseconds: 150),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_titleField(c), _defaultsRow(c)],
        ),
      ),
      if (_noteOpen) InkIn(child: _noteField(c)),
      const SizedBox(height: Gap.x4),
      InkIn(delay: const Duration(milliseconds: 190), child: _stampButton(c)),
      const SizedBox(height: Gap.x1),
      // One strike affordance wears the seal, and it is the long-press
      // sheet's. Here it stays faint — the stamp owns the vermilion.
      Center(
        child: TextButton(
          onPressed: _saving ? null : _strike,
          child: Text(
            'strike it out',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
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
      // Nothing else on this sheet takes ink, so the strike keeps the seal.
      TextButton(
        onPressed: _saving ? null : _strike,
        child: Text(
          'strike it out',
          style: LedgerType.bodyStrong.copyWith(fontSize: 14, color: c.seal),
        ),
      ),
    ];
  }

  /// The figure and its field are the same number in two hands — the swap
  /// cross-fades and the row resizes rather than jumping.
  Widget _amountHero(LedgerColors c) {
    final style = LedgerType.heroAmount.copyWith(fontSize: 38, color: c.ink);
    final editing = !_isTransfer && _editingAmount;
    final swap = Motion.reduced(context) ? Duration.zero : Motion.quick;

    return AnimatedSize(
      duration: swap,
      curve: Motion.curve,
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: swap,
        switchInCurve: Motion.curve,
        switchOutCurve: Motion.curve,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.06),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: editing ? _amountField(c, style) : _amountRead(c, style),
      ),
    );
  }

  Widget _amountRead(LedgerColors c, TextStyle style) {
    return GestureDetector(
      key: const ValueKey('amount-read'),
      behavior: HitTestBehavior.opaque,
      onTap: _isTransfer ? null : _startAmountEdit,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(Inr.format(_amountPaise), style: style),
          if (!_isTransfer) ...[
            const SizedBox(width: Gap.x2),
            PenLines(size: 14, color: c.inkFaint),
          ],
        ],
      ),
    );
  }

  Widget _amountField(LedgerColors c, TextStyle style) {
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

  /// Chips take the quill wash when chosen — the same wash the add sheet
  /// uses, so picking a category feels the same wherever it happens.
  Widget _categoryChips(LedgerColors c) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final cat in _categories) ...[
            _chip(c, category: cat, selected: _categoryId == cat.id),
            const SizedBox(width: Gap.x2),
          ],
        ],
      ),
    );
  }

  Widget _chip(
    LedgerColors c, {
    required Category category,
    required bool selected,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(
          () => _categoryId = _categoryId == category.id ? null : category.id,
        );
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: selected ? 1 : 0, end: selected ? 1 : 0),
        duration: Motion.quick,
        curve: Motion.curve,
        builder: (context, t, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Color.lerp(null, c.quillSoft, t),
            border: Border.all(color: Color.lerp(c.rule, c.quill, t)!),
            borderRadius: BorderRadius.circular(Corner.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LedgerIcons.resolve(category.icon),
                size: 13,
                color: Color.lerp(c.inkFaint, c.quill, t),
              ),
              const SizedBox(width: 5),
              Text(
                category.name,
                style: (selected ? LedgerType.bodyStrong : LedgerType.bodyText)
                    .copyWith(
                      fontSize: 13,
                      color: Color.lerp(c.inkFaint, c.quill, t),
                    ),
              ),
            ],
          ),
        ),
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
    final acct =
        _accounts.where((a) => a.id == _accountId).firstOrNull?.name ?? '—';
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
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(width: 2),
          PenChevron(size: 12, color: c.inkFaint),
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
          hintStyle: LedgerType.bodyText.copyWith(
            fontSize: 14,
            color: c.inkFaint,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
        ),
      ),
    );
  }

  /// Saving is a stamp: the button presses down, then gives way to the chop
  /// landing on the page. The seal is the receipt — there is no toast.
  Widget _stampButton(LedgerColors c) {
    final enabled = _amountPaise > 0 && !_saving;
    return SizedBox(
      height: 48,
      child: AnimatedSwitcher(
        duration: Motion.quick,
        switchInCurve: Motion.curve,
        switchOutCurve: Motion.curve,
        child: _stamping
            ? const Center(key: ValueKey('stamped'), child: StampIn(size: 36))
            : Listener(
                key: const ValueKey('stamp-button'),
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
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: enabled ? _stamp : null,
                    child: const Text('Stamp it again'),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _pickAccount() async {
    final picked = await pickLedgerAccount(
      context,
      accounts: _accounts,
      selectedId: _accountId,
      line: 'which pocket did it leave?',
    );
    if (picked != null) setState(() => _accountId = picked.id);
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
      setState(
        () => _at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _at.hour,
          _at.minute,
        ),
      );
    }
  }
}
