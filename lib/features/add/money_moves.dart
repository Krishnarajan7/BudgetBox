import 'dart:async';

import 'package:drift/drift.dart'
    show BooleanExpressionOperators, ComparableExpr, OrderingTerm;
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

/// Money moves — the four doors behind the long-press ＋: income, transfer,
/// fix-a-balance, and the quiet-days catch-up. Each is a sibling of the add
/// sheet: same paper, same handle, same chips, same write-and-go rhythm.

Future<void> showIncomeSheet(BuildContext context) =>
    _show(context, const _IncomeSheet());

Future<void> showTransferSheet(BuildContext context) =>
    _show(context, const _TransferSheet());

Future<void> showFixBalanceSheet(BuildContext context) =>
    _show(context, const _FixBalanceSheet());

Future<void> showCatchUpSheet(BuildContext context) =>
    _show(context, const _CatchUpSheet());

/// The last [lookback] local dates before [now] with no expense entry —
/// the quiet days the catch-up sheet offers back, most recent first.
/// Today is skipped (the day is still being written), and only expenses
/// mark a day as written; income and transfers keep a day quiet.
List<DateTime> quietDays(
  List<Txn> monthTxns,
  DateTime now, {
  int lookback = 7,
}) {
  final written = <String>{
    for (final t in monthTxns)
      if (t.type == TxnType.expense) LedgerDates.dayKey(t.at),
  };
  final out = <DateTime>[];
  for (var i = 1; i <= lookback; i++) {
    final d = DateTime(now.year, now.month, now.day - i);
    if (!written.contains(LedgerDates.dayKey(d))) out.add(d);
  }
  return out;
}

// ————— shared anatomy —————

/// Active accounts, one-shot, in shelf order.
Future<List<Account>> _activeAccounts(LedgerDb db) {
  return (db.select(db.accounts)
        ..where((a) => a.archived.equals(false))
        ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
      .get();
}

Future<void> _show(BuildContext context, Widget sheet) =>
    showLedgerSheet<void>(context, builder: (_) => sheet);

/// Rupee text → paise, or null when it isn't a number yet.
int? _paiseFrom(String text) {
  final t = text.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v.isNegative) return null;
  return (v * 100).round();
}

/// Paise → plain rupee text for prefilling a field. Paise only when non-zero.
String _rupeesText(int paise) => paise % 100 == 0
    ? (paise ~/ 100).toString()
    : (paise / 100).toStringAsFixed(2);

final _amountFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

/// The beat that replaces the save button the moment a move is written: the
/// chop lands, then the sheet leaves. Same height as the button it stands
/// in for, so nothing jumps on the way out.
class _StampBeat extends StatelessWidget {
  const _StampBeat();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 52,
      child: Center(child: StampIn(size: 36, haptic: false)),
    );
  }
}

/// The hero amount as an inline field: ₹ prefix, Fraunces, ink.
class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.fieldKey,
    this.size = 38,
    this.focusNode,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final Key fieldKey;
  final double size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final style = LedgerType.heroAmount.copyWith(fontSize: size, color: c.ink);
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_amountFilter],
      style: style,
      cursorColor: c.quill,
      decoration: InputDecoration(
        prefixText: '₹',
        prefixStyle: style.copyWith(color: c.inkFaint),
        hintText: '0',
        hintStyle: style.copyWith(color: c.inkFaint.withValues(alpha: 0.45)),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: Gap.x2),
      ),
    );
  }
}

/// The full-width save: quill ink, ledger-key corners, and the kit's press
/// under the finger. Disabled is the same block at reduced strength — the
/// button never disappears, it just waits.
class _SheetButton extends StatelessWidget {
  const _SheetButton(this.label, {required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final live = onPressed != null;
    return Pressable(
      onTap: onPressed,
      haptic: false,
      scale: 0.97,
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.curve,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: live ? c.quill : c.quill.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(Corner.key),
        ),
        child: Text(
          label,
          style: LedgerType.bodyStrong.copyWith(color: c.paper),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of account chips.
class _AccountChips extends StatelessWidget {
  const _AccountChips({
    required this.accounts,
    required this.selectedId,
    required this.onPick,
    required this.keyPrefix,
  });

  final List<Account> accounts;
  final int? selectedId;
  final ValueChanged<int> onPick;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final a in accounts) ...[
            Pressable(
              key: Key('$keyPrefix-${a.id}'),
              onTap: () => onPick(a.id),
              child: LedgerChip(
                a.name,
                icon: LedgerIcons.account[a.kind.name],
                selected: selectedId == a.id,
              ),
            ),
            const SizedBox(width: Gap.x2),
          ],
        ],
      ),
    );
  }
}

// ————— income —————

class _IncomeSheet extends ConsumerStatefulWidget {
  const _IncomeSheet();

  @override
  ConsumerState<_IncomeSheet> createState() => _IncomeSheetState();
}

class _IncomeSheetState extends ConsumerState<_IncomeSheet> {
  final _amount = TextEditingController();
  final _title = TextEditingController();

  List<Category> _categories = const [];
  List<Account> _accounts = const [];
  int? _categoryId;
  int? _accountId;
  DateTime _at = DateTime.now();
  bool _busy = false;
  bool _stamped = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _title.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final cats =
        await (db.select(db.categories)
              ..where(
                (c) =>
                    c.archived.equals(false) &
                    c.kind.equalsValue(CategoryKind.income),
              )
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    final accts = await _activeAccounts(ref.read(dbProvider));
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _accounts = accts;
      _accountId ??= accts.isEmpty ? null : accts.first.id;
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    super.dispose();
  }

  Category? get _selected {
    for (final c in _categories) {
      if (c.id == _categoryId) return c;
    }
    return null;
  }

  Future<void> _save() async {
    final paise = _paiseFrom(_amount.text);
    if (_busy || paise == null || paise <= 0 || _accountId == null) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final title = _title.text.trim().isEmpty
        ? (_selected?.name ?? 'Money in')
        : _title.text.trim();
    await ref
        .read(txnRepoProvider)
        .addIncome(
          amountPaise: paise,
          accountId: _accountId!,
          categoryId: _categoryId,
          title: title,
          at: _at,
        );
    if (!mounted) return;
    // The chop lands where the button was; then the sheet goes.
    setState(() => _stamped = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final paise = _paiseFrom(_amount.text);
    final ready = !_busy && paise != null && paise > 0 && _accountId != null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text('money in', style: LedgerType.label.copyWith(color: c.jama)),
            _AmountField(
              controller: _amount,
              fieldKey: const Key('income-amount'),
            ),
            const SizedBox(height: Gap.x2),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final cat in _categories) ...[
                    Pressable(
                      onTap: () => setState(
                        () =>
                            _categoryId = _categoryId == cat.id ? null : cat.id,
                      ),
                      child: LedgerChip(
                        cat.name,
                        icon: LedgerIcons.resolve(cat.icon),
                        selected: _categoryId == cat.id,
                      ),
                    ),
                    const SizedBox(width: Gap.x2),
                  ],
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.rule)),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // The hint ghosts to the picked category's name — a blank
                  // title will fall back to it, so the field says so.
                  if (_title.text.isEmpty)
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: Text(
                            _selected?.name ?? 'what came in?',
                            key: ValueKey(
                              'income-hint-${_selected?.id ?? 'none'}',
                            ),
                            style: LedgerType.bodyText.copyWith(
                              color: c.inkFaint,
                            ),
                          ),
                        ),
                      ),
                    ),
                  TextField(
                    controller: _title,
                    style: LedgerType.bodyText.copyWith(color: c.ink),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: Gap.x2),
                    ),
                  ),
                ],
              ),
            ),
            _defaultsRow(c),
            const SizedBox(height: Gap.x4),
            if (_stamped)
              const _StampBeat()
            else
              _SheetButton('Write it in', onPressed: ready ? _save : null),
          ],
        ),
      ),
    );
  }

  Widget _defaultsRow(LedgerColors c) {
    final acct =
        _accounts.where((a) => a.id == _accountId).firstOrNull?.name ?? '—';
    final today = DateTime.now();
    final sameDay =
        _at.year == today.year &&
        _at.month == today.month &&
        _at.day == today.day;
    final dateLabel = sameDay ? 'today' : LedgerDates.ddMmm(_at);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        children: [
          _defaultTap(c, acct, _pickAccount),
          const SizedBox(width: Gap.x4),
          _defaultTap(c, dateLabel, _pickDate),
        ],
      ),
    );
  }

  Widget _defaultTap(LedgerColors c, String label, VoidCallback onTap) {
    return Pressable(
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

  Future<void> _pickAccount() async {
    final picked = await pickLedgerAccount(
      context,
      accounts: _accounts,
      selectedId: _accountId,
      line: 'which pocket did it land in?',
    );
    if (picked != null && mounted) setState(() => _accountId = picked.id);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
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

// ————— transfer —————

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _amount = TextEditingController();

  List<Account> _accounts = const [];
  int? _fromId;
  int? _toId;
  bool _busy = false;
  bool _stamped = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final accts = await _activeAccounts(ref.read(dbProvider));
    if (!mounted) return;
    setState(() => _accounts = accts);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Account? _byId(int? id) => _accounts.where((a) => a.id == id).firstOrNull;

  bool get _sidesOk => _fromId != null && _toId != null && _fromId != _toId;

  Future<void> _save() async {
    final paise = _paiseFrom(_amount.text);
    if (_busy || paise == null || paise <= 0 || !_sidesOk) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    await ref
        .read(txnRepoProvider)
        .addTransfer(
          amountPaise: paise,
          fromAccountId: _fromId!,
          toAccountId: _toId!,
        );
    if (!mounted) return;
    setState(() => _stamped = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final paise = _paiseFrom(_amount.text);
    final ready = !_busy && paise != null && paise > 0 && _sidesOk;

    final showEffect = paise != null && paise > 0 && _sidesOk;
    final fromAcct = _byId(_fromId);
    final toAcct = _byId(_toId);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'from one pocket to another',
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
            _AmountField(
              controller: _amount,
              fieldKey: const Key('transfer-amount'),
            ),
            const SizedBox(height: Gap.x2),
            Text('from', style: LedgerType.label.copyWith(color: c.inkFaint)),
            const SizedBox(height: Gap.x1),
            _AccountChips(
              accounts: _accounts,
              selectedId: _fromId,
              onPick: (id) => setState(() => _fromId = id),
              keyPrefix: 'from',
            ),
            const SizedBox(height: Gap.x3),
            Text('to', style: LedgerType.label.copyWith(color: c.inkFaint)),
            const SizedBox(height: Gap.x1),
            _AccountChips(
              accounts: _accounts,
              selectedId: _toId,
              onPick: (id) => setState(() => _toId = id),
              keyPrefix: 'to',
            ),
            const SizedBox(height: Gap.x3),
            SizedBox(
              height: 18,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: !showEffect
                    ? const SizedBox.shrink(key: ValueKey('quiet'))
                    // Keyed by the pair, not the amount, so a changed
                    // amount counts up in place; a changed side cross-fades.
                    : Align(
                        key: ValueKey('effect-$_fromId-$_toId'),
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: CountUp(
                            value: paise,
                            format: (p) =>
                                '${fromAcct!.name} − ${Inr.format(p)}'
                                ' · ${toAcct!.name} + ${Inr.format(p)}',
                            style: LedgerType.amount.copyWith(
                              fontSize: 12,
                              color: c.inkFaint,
                            ),
                            duration: const Duration(milliseconds: 300),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: Gap.x3),
            if (_stamped)
              const _StampBeat()
            else
              _SheetButton('Move it', onPressed: ready ? _save : null),
          ],
        ),
      ),
    );
  }
}

// ————— fix a balance —————

class _FixBalanceSheet extends ConsumerStatefulWidget {
  const _FixBalanceSheet();

  @override
  ConsumerState<_FixBalanceSheet> createState() => _FixBalanceSheetState();
}

class _FixBalanceSheetState extends ConsumerState<_FixBalanceSheet> {
  final _amount = TextEditingController();
  final _focus = FocusNode();

  List<Account> _accounts = const [];
  int? _accountId;
  bool _busy = false;
  bool _stamped = false;

  /// Off by default: the correction stays quiet and costs no extra tap.
  /// On, the drift is written into the book as its own line.
  bool _asEntry = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final accts = await _activeAccounts(ref.read(dbProvider));
    if (!mounted) return;
    setState(() => _accounts = accts);
  }

  /// Truth minus book, in paise. Positive = the book was short.
  int? get _difference {
    final acct = _selected;
    final paise = _paiseFrom(_amount.text);
    if (acct == null || paise == null) return null;
    return paise - acct.balancePaise;
  }

  @override
  void dispose() {
    _amount.dispose();
    _focus.dispose();
    super.dispose();
  }

  Account? get _selected =>
      _accounts.where((a) => a.id == _accountId).firstOrNull;

  void _pick(int id) {
    final acct = _accounts.firstWhere((a) => a.id == id);
    setState(() {
      _accountId = id;
      _amount.text = _rupeesText(acct.balancePaise);
      _amount.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _amount.text.length,
      );
    });
    _focus.requestFocus();
  }

  Future<void> _save() async {
    final paise = _paiseFrom(_amount.text);
    if (_busy || paise == null || _accountId == null) return;
    final diff = _difference ?? 0;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();

    // Asked for it: the drift becomes a line of its own, so the book can
    // explain itself later. Either way the account lands on the truth, and
    // the reading is dated now.
    if (_asEntry && diff != 0) {
      final txns = ref.read(txnRepoProvider);
      if (diff < 0) {
        await txns.addExpense(
          amountPaise: -diff,
          accountId: _accountId!,
          title: 'Adjustment',
          note: 'the book had drifted',
        );
      } else {
        await txns.addIncome(
          amountPaise: diff,
          accountId: _accountId!,
          title: 'Adjustment',
          note: 'the book had drifted',
        );
      }
    }
    await ref.read(accountRepoProvider).setBalance(_accountId!, paise);
    if (!mounted) return;
    setState(() => _stamped = true);
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final acct = _selected;
    final ready = !_busy && acct != null && _paiseFrom(_amount.text) != null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'make the book match the world',
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: Gap.x3),
            _AccountChips(
              accounts: _accounts,
              selectedId: _accountId,
              onPick: _pick,
              keyPrefix: 'fix',
            ),
            const SizedBox(height: Gap.x3),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: acct == null
                  ? Padding(
                      key: const ValueKey('unpicked'),
                      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                      child: Text(
                        'Pick the account that drifted.',
                        style: LedgerType.bodyText.copyWith(
                          fontSize: 13,
                          color: c.inkFaint,
                        ),
                      ),
                    )
                  : Column(
                      key: ValueKey('picked-${acct.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The book's side of the story inks in first.
                        InkIn(
                          key: ValueKey('book-says-${acct.id}'),
                          child: Text(
                            'the book says ${Inr.format(acct.balancePaise)}',
                            style: LedgerType.amount.copyWith(
                              fontSize: 13,
                              color: c.inkFaint,
                            ),
                          ),
                        ),
                        const SizedBox(height: Gap.x3),
                        Text(
                          "what's true right now?",
                          style: LedgerType.label.copyWith(color: c.inkFaint),
                        ),
                        _AmountField(
                          controller: _amount,
                          fieldKey: const Key('fix-amount'),
                          size: 32,
                          focusNode: _focus,
                          autofocus: false,
                        ),
                        _differenceChoice(c),
                      ],
                    ),
            ),
            const SizedBox(height: Gap.x3),
            if (_stamped)
              const _StampBeat()
            else
              _SheetButton(
                "That's the number",
                onPressed: ready ? _save : null,
              ),
          ],
        ),
      ),
    );
  }

  /// The drift, and the offer to record it rather than swallow it. Appears
  /// only once there is a difference to have an opinion about; leaving it
  /// alone keeps the quiet correction, which is what most days want.
  Widget _differenceChoice(LedgerColors c) {
    final diff = _difference;
    if (diff == null || diff == 0) return const SizedBox(height: Gap.x3);
    final short = diff > 0;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x3),
      child: Pressable(
        onTap: () => setState(() => _asEntry = !_asEntry),
        child: Row(
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: _asEntry ? c.quill : null,
                border: Border.all(color: _asEntry ? c.quill : c.rule),
                borderRadius: BorderRadius.circular(Corner.stamp),
              ),
              child: _asEntry ? PenTick(size: 11, color: c.paper) : null,
            ),
            const SizedBox(width: Gap.x2),
            Expanded(
              child: Text(
                'write the difference as an entry',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: _asEntry ? c.quill : c.inkFaint,
                ),
              ),
            ),
            Text(
              short ? '+ ${Inr.format(diff)}' : '− ${Inr.format(diff.abs())}',
              style: LedgerType.amount.copyWith(
                fontSize: 13,
                color: short ? c.jama : c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ————— the quiet days —————

class _CatchUpSheet extends ConsumerStatefulWidget {
  const _CatchUpSheet();

  @override
  ConsumerState<_CatchUpSheet> createState() => _CatchUpSheetState();
}

class _CatchUpSheetState extends ConsumerState<_CatchUpSheet> {
  List<DateTime>? _days;
  List<Category> _chipCats = const [];
  List<Account> _pockets = const [];
  int? _accountId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day - 7);
    final txns = await (db.select(
      db.txns,
    )..where((t) => t.at.isBiggerOrEqualValue(from))).get();

    final cats =
        await (db.select(db.categories)
              ..where(
                (c) =>
                    c.archived.equals(false) &
                    c.kind.equalsValue(CategoryKind.expense),
              )
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    final top = await ref.read(txnRepoProvider).topCategoryIds();
    final ids = cats.map((c) => c.id).toList();
    // Every active category, the most-used first. Four was a guess about
    // what a quiet day held; the rest of a life happens outside four chips.
    final order = [
      ...top.where(ids.contains),
      ...ids.where((id) => !top.contains(id)),
    ];

    final accts = await _activeAccounts(ref.read(dbProvider));
    // Catch-up writes daily spending, and daily spending never drains a
    // holding — the quiet days pay from a pocket like every other day.
    final pockets = accts.where((a) => !a.keptAside).toList();
    if (!mounted) return;
    setState(() {
      _days = quietDays(txns, now);
      _chipCats = [for (final id in order) cats.firstWhere((c) => c.id == id)];
      _pockets = pockets.isEmpty ? accts : pockets;
      _accountId = _pockets.isEmpty ? null : _pockets.first.id;
    });
  }

  Future<void> _save(DateTime day, int paise, Category? cat) async {
    final accountId = _accountId;
    if (accountId == null) return;
    await ref
        .read(txnRepoProvider)
        .addExpense(
          amountPaise: paise,
          accountId: accountId,
          categoryId: cat?.id,
          title: cat?.name ?? 'Entry',
          at: DateTime(day.year, day.month, day.day, 12),
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final days = _days;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'Catching up, no hurry.',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: Gap.x1),
            Text(
              'Fill what you remember. A blank day just stays blank.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
            // How the money went: the pocket every stamp below draws from.
            // Days before a balance reading won't re-drain it — the anchor
            // rule keeps the past out of the present.
            if (_pockets.length > 1) ...[
              const SizedBox(height: Gap.x3),
              Text(
                'paid from',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              _AccountChips(
                accounts: _pockets,
                selectedId: _accountId,
                keyPrefix: 'catchup-acct',
                onPick: (id) => setState(() => _accountId = id),
              ),
            ],
            const SizedBox(height: Gap.x3),
            if (days == null)
              const SizedBox(height: Gap.x8)
            else if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.x6),
                child: Text(
                  'No quiet days. The book is current.',
                  style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The quiet days write themselves onto the sheet,
                      // one line at a time.
                      for (final (i, d) in days.indexed)
                        InkIn(
                          key: ValueKey('quiet-ink-${LedgerDates.dayKey(d)}'),
                          delay: Duration(milliseconds: 40 * i),
                          child: _QuietDayRow(
                            key: Key('quiet-${LedgerDates.dayKey(d)}'),
                            day: d,
                            categories: _chipCats,
                            enabled: _accountId != null,
                            onSave: (paise, cat) => _save(d, paise, cat),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Gap.x3),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietDayRow extends StatefulWidget {
  const _QuietDayRow({
    super.key,
    required this.day,
    required this.categories,
    required this.enabled,
    required this.onSave,
  });

  final DateTime day;
  final List<Category> categories;
  final bool enabled;
  final Future<void> Function(int paise, Category? category) onSave;

  @override
  State<_QuietDayRow> createState() => _QuietDayRowState();
}

class _QuietDayRowState extends State<_QuietDayRow> {
  final _amount = TextEditingController();
  int? _catId;
  bool _saving = false;

  /// What this day has taken so far, in stamp order. A day is rarely one
  /// spend — dress AND the bus home — so a stamp settles the row without
  /// closing it: "one more" reopens the field for the next entry.
  final _written = <(int paise, String label)>[];

  /// True while the entry field is open (always, until the first stamp).
  bool _adding = true;

  /// The seal is on this row only for a beat; then it settles back to the
  /// small jama check, so a long catch-up never turns into a wall of red.
  bool _flash = false;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _amount.dispose();
    super.dispose();
  }

  Category? get _cat =>
      widget.categories.where((c) => c.id == _catId).firstOrNull;

  Future<void> _stamp() async {
    final paise = _paiseFrom(_amount.text);
    if (_saving || paise == null || paise <= 0) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    await widget.onSave(paise, _cat);
    if (!mounted) return;
    setState(() {
      _written.add((paise, _cat?.name ?? 'Entry'));
      _adding = false;
      _saving = false;
      _flash = true;
      _amount.clear();
      _catId = null;
    });
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _oneMore() {
    HapticFeedback.selectionClick();
    setState(() => _adding = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SizeTransition(
            sizeFactor: anim,
            alignment: Alignment.topCenter,
            child: child,
          ),
        ),
        child: (!_adding && _written.isNotEmpty)
            ? _writtenLine(c)
            : _entryLine(c),
      ),
    );
  }

  /// The row between stamps: what the day holds so far, the jama check, and
  /// the way back in — because closing a day after one entry is the sheet
  /// deciding how much a Tuesday cost.
  Widget _writtenLine(LedgerColors c) {
    final total = _written.fold(0, (s, e) => s + e.$1);
    final label = _written.length == 1
        ? _written.first.$2
        : '${_written.length} entries';
    return Row(
      key: const ValueKey('written'),
      children: [
        SizedBox(
          width: 84,
          child: Text(
            LedgerDates.dayLabel(widget.day),
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
        ),
        Expanded(
          child: Pressable(
            onTap: _oneMore,
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  TextSpan(
                    text: '  + one more?',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 12,
                      color: c.quill,
                    ),
                  ),
                ],
              ),
              style: LedgerType.bodyText.copyWith(color: c.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Text(
          Inr.format(total),
          style: LedgerType.amount.copyWith(color: c.ink),
        ),
        const SizedBox(width: Gap.x2),
        SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: _flash
                ? const StampIn(size: 22, haptic: false)
                : PenTick(size: 15, color: c.jama),
          ),
        ),
      ],
    );
  }

  Widget _entryLine(LedgerColors c) {
    final paise = _paiseFrom(_amount.text);
    final ready = widget.enabled && !_saving && paise != null && paise > 0;
    return Column(
      key: const ValueKey('entry'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    LedgerDates.dayLabel(widget.day),
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.ink,
                    ),
                  ),
                  // Back for a second entry: what the day already holds.
                  if (_written.isNotEmpty)
                    Text(
                      'has ${Inr.format(_written.fold(0, (s, e) => s + e.$1))}',
                      style: LedgerType.amount.copyWith(
                        fontSize: 10,
                        color: c.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: TextField(
                key: Key('quiet-amount-${LedgerDates.dayKey(widget.day)}'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_amountFilter],
                style: LedgerType.amount.copyWith(fontSize: 16, color: c.ink),
                cursorColor: c.quill,
                decoration: InputDecoration(
                  prefixText: '₹',
                  prefixStyle: LedgerType.amount.copyWith(
                    fontSize: 16,
                    color: c.inkFaint,
                  ),
                  hintText: '0',
                  hintStyle: LedgerType.amount.copyWith(
                    fontSize: 16,
                    color: c.inkFaint.withValues(alpha: 0.45),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
            const SizedBox(width: Gap.x2),
            Pressable(
              onTap: ready ? _stamp : null,
              child: AnimatedOpacity(
                opacity: ready ? 1 : 0.45,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: ready ? c.quill : c.rule,
                      width: 1.4,
                    ),
                    borderRadius: BorderRadius.circular(Corner.stamp),
                  ),
                  child: Center(
                    child: PenTick(
                      size: 16,
                      color: ready ? c.quill : c.inkFaint,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.x2),
        Padding(
          padding: const EdgeInsets.only(left: 84),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final cat in widget.categories) ...[
                  Pressable(
                    onTap: () => setState(
                      () => _catId = _catId == cat.id ? null : cat.id,
                    ),
                    child: LedgerChip(
                      cat.name,
                      icon: LedgerIcons.resolve(cat.icon),
                      selected: _catId == cat.id,
                    ),
                  ),
                  const SizedBox(width: Gap.x2),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
