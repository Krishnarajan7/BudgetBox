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
List<DateTime> quietDays(List<Txn> monthTxns, DateTime now,
    {int lookback = 7}) {
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

final _sheetMotion = AnimationStyle(
  duration: const Duration(milliseconds: 280),
  curve: Curves.easeOutCubic,
);

Future<void> _show(BuildContext context, Widget sheet) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: _sheetMotion,
    builder: (_) => sheet,
  );
}

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

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 'Wed 30 Jul'
String _dayLabel(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

final _amountFilter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'));

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: c.rule,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Press state for anything tappable: a quiet 0.95 dip under the finger.
class _Springy extends StatefulWidget {
  const _Springy({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Springy> createState() => _SpringyState();
}

class _SpringyState extends State<_Springy> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
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

/// The full-width save. Disabled = same button at reduced opacity.
class _SheetButton extends StatelessWidget {
  const _SheetButton(this.label, {required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return FilledButton(
      style: FilledButton.styleFrom(
        disabledBackgroundColor: c.quill.withValues(alpha: 0.35),
        disabledForegroundColor: c.paper,
      ),
      onPressed: onPressed,
      child: Text(label),
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
            _Springy(
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

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final cats = await (db.select(db.categories)
          ..where((c) =>
              c.archived.equals(false) &
              c.kind.equalsValue(CategoryKind.income))
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
    await ref.read(txnRepoProvider).addIncome(
          amountPaise: paise,
          accountId: _accountId!,
          categoryId: _categoryId,
          title: title,
          at: _at,
        );
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
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            const SizedBox(height: Gap.x3),
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
                    _Springy(
                      onTap: () => setState(() => _categoryId =
                          _categoryId == cat.id ? null : cat.id),
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
              child: TextField(
                controller: _title,
                style: LedgerType.bodyText.copyWith(color: c.ink),
                decoration: InputDecoration(
                  hintText: 'what came in?',
                  hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: Gap.x2),
                ),
              ),
            ),
            _defaultsRow(c),
            const SizedBox(height: Gap.x4),
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
    final sameDay = _at.year == today.year &&
        _at.month == today.month &&
        _at.day == today.day;
    final dateLabel =
        sameDay ? 'today' : '${_at.day} ${_months[_at.month - 1]}';
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
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return SafeArea(
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
        );
      },
    );
    if (picked != null && mounted) setState(() => _accountId = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _at = DateTime(
          picked.year, picked.month, picked.day, _at.hour, _at.minute));
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

  Account? _byId(int? id) =>
      _accounts.where((a) => a.id == id).firstOrNull;

  bool get _sidesOk => _fromId != null && _toId != null && _fromId != _toId;

  Future<void> _save() async {
    final paise = _paiseFrom(_amount.text);
    if (_busy || paise == null || paise <= 0 || !_sidesOk) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    await ref.read(txnRepoProvider).addTransfer(
          amountPaise: paise,
          fromAccountId: _fromId!,
          toAccountId: _toId!,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final paise = _paiseFrom(_amount.text);
    final ready = !_busy && paise != null && paise > 0 && _sidesOk;

    final effect = (paise != null && paise > 0 && _sidesOk)
        ? '${_byId(_fromId)!.name} − ${Inr.format(paise)}'
            ' · ${_byId(_toId)!.name} + ${Inr.format(paise)}'
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            const SizedBox(height: Gap.x3),
            Text('from one pocket to another',
                style: LedgerType.label.copyWith(color: c.inkFaint)),
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
                duration: const Duration(milliseconds: 200),
                child: effect == null
                    ? const SizedBox.shrink(key: ValueKey('quiet'))
                    : Text(
                        effect,
                        key: ValueKey(effect),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LedgerType.amount
                            .copyWith(fontSize: 12, color: c.inkFaint),
                      ),
              ),
            ),
            const SizedBox(height: Gap.x3),
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
      _amount.selection =
          TextSelection(baseOffset: 0, extentOffset: _amount.text.length);
    });
    _focus.requestFocus();
  }

  Future<void> _save() async {
    final paise = _paiseFrom(_amount.text);
    if (_busy || paise == null || _accountId == null) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    await ref.read(accountRepoProvider).setBalance(_accountId!, paise);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final acct = _selected;
    final ready =
        !_busy && acct != null && _paiseFrom(_amount.text) != null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            const SizedBox(height: Gap.x3),
            Text('make the book match the world',
                style: LedgerType.label.copyWith(color: c.inkFaint)),
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
                        style: LedgerType.bodyText
                            .copyWith(fontSize: 13, color: c.inkFaint),
                      ),
                    )
                  : Column(
                      key: ValueKey('picked-${acct.id}'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'the book says ${Inr.format(acct.balancePaise)}',
                          style: LedgerType.amount
                              .copyWith(fontSize: 13, color: c.inkFaint),
                        ),
                        const SizedBox(height: Gap.x3),
                        Text("what's true right now?",
                            style: LedgerType.label
                                .copyWith(color: c.inkFaint)),
                        _AmountField(
                          controller: _amount,
                          fieldKey: const Key('fix-amount'),
                          size: 32,
                          focusNode: _focus,
                          autofocus: false,
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: Gap.x3),
            _SheetButton("That's the number",
                onPressed: ready ? _save : null),
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
    final txns = await (db.select(db.txns)
          ..where((t) => t.at.isBiggerOrEqualValue(from)))
        .get();

    final cats = await (db.select(db.categories)
          ..where((c) =>
              c.archived.equals(false) &
              c.kind.equalsValue(CategoryKind.expense))
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .get();
    final top = await ref.read(txnRepoProvider).topCategoryIds();
    final ids = cats.map((c) => c.id).toList();
    final order = [
      ...top.where(ids.contains),
      ...ids.where((id) => !top.contains(id)),
    ].take(4).toList();

    final accts = await _activeAccounts(ref.read(dbProvider));
    if (!mounted) return;
    setState(() {
      _days = quietDays(txns, now);
      _chipCats = [
        for (final id in order) cats.firstWhere((c) => c.id == id),
      ];
      _accountId = accts.isEmpty ? null : accts.first.id;
    });
  }

  Future<void> _save(DateTime day, int paise, Category? cat) async {
    final accountId = _accountId;
    if (accountId == null) return;
    await ref.read(txnRepoProvider).addExpense(
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
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            const SizedBox(height: Gap.x3),
            Text(
              'Catching up, no hurry.',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: Gap.x1),
            Text(
              'Fill what you remember. A blank day just stays blank.',
              style:
                  LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
            ),
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
                      for (final d in days)
                        _QuietDayRow(
                          key: Key('quiet-${LedgerDates.dayKey(d)}'),
                          day: d,
                          categories: _chipCats,
                          enabled: _accountId != null,
                          onSave: (paise, cat) => _save(d, paise, cat),
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
  bool _saved = false;
  int _savedPaise = 0;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Category? get _cat =>
      widget.categories.where((c) => c.id == _catId).firstOrNull;

  Future<void> _stamp() async {
    final paise = _paiseFrom(_amount.text);
    if (_saving || _saved || paise == null || paise <= 0) return;
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    await widget.onSave(paise, _cat);
    if (!mounted) return;
    setState(() {
      _saved = true;
      _savedPaise = paise;
    });
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
        child: _saved ? _writtenLine(c) : _entryLine(c),
      ),
    );
  }

  /// The row after its stamp: a settled ledger line with a small jama check.
  Widget _writtenLine(LedgerColors c) {
    return Row(
      key: const ValueKey('written'),
      children: [
        SizedBox(
          width: 84,
          child: Text(
            _dayLabel(widget.day),
            style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
          ),
        ),
        Expanded(
          child: Text(
            _cat?.name ?? 'Entry',
            style: LedgerType.bodyText.copyWith(color: c.ink),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          Inr.format(_savedPaise),
          style: LedgerType.amount.copyWith(color: c.ink),
        ),
        const SizedBox(width: Gap.x2),
        Icon(Icons.check, size: 15, color: c.jama),
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
              child: Text(
                _dayLabel(widget.day),
                style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.ink),
              ),
            ),
            Expanded(
              child: TextField(
                key: Key('quiet-amount-${LedgerDates.dayKey(widget.day)}'),
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_amountFilter],
                style: LedgerType.amount.copyWith(fontSize: 16, color: c.ink),
                cursorColor: c.quill,
                decoration: InputDecoration(
                  prefixText: '₹',
                  prefixStyle: LedgerType.amount
                      .copyWith(fontSize: 16, color: c.inkFaint),
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
            _Springy(
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
                    borderRadius: BorderRadius.circular(Corner.stamp + 2),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: ready ? c.quill : c.inkFaint,
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
                  _Springy(
                    onTap: () => setState(
                        () => _catId = _catId == cat.id ? null : cat.id),
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
