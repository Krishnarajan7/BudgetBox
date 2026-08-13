import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/pickers.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/txn_repo.dart';
import 'amount_engine.dart';

/// The sacred flow. Keypad visible on open, amount is the only required
/// field, and Save is a stamp: press, haptic, seal flash, done — the ledger
/// line is the confirmation, so there is no toast.
Future<void> showAddSheet(BuildContext context) {
  return showLedgerSheet<void>(context, builder: (_) => const AddSheet());
}

class AddSheet extends ConsumerStatefulWidget {
  const AddSheet({super.key});

  @override
  ConsumerState<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<AddSheet> {
  /// False writes an expense (the five-second default); true, money in.
  /// It lives on the sheet because money arriving is a normal Tuesday fact,
  /// not a hidden move — a +₹600 recorded as spending is how a book lies.
  bool _moneyIn = false;

  final _engine = AmountEngine();
  final _title = TextEditingController();
  final _note = TextEditingController();

  List<Category> _categories = const [];
  List<Account> _accounts = const [];
  List<int> _chipOrder = const [];
  TitleSuggestion? _suggestion;
  Timer? _debounce;

  int? _categoryId;
  int? _accountId;
  DateTime _at = DateTime.now();
  bool _stamping = false;

  /// The optional line behind "details" — closed until asked for, so the
  /// core path never pays a tap for it.
  bool _noteOpen = false;

  /// The three amounts this category is usually written for — a whisper,
  /// never a step. [_recentsFor] keeps it honest while the query is in air.
  List<int> _recentAmounts = const [];
  int? _recentsFor;

  /// Bumped when save-and-add-another clears the sheet, so the fresh ₹0
  /// inks in as a new line rather than glitching in place.
  int _generation = 0;

  /// The chip the title's memory just picked — it gets one soft quill wash
  /// so the "it remembered" moment is visible. The seq restarts the wash.
  int? _flashCategoryId;
  int _flashSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _title.addListener(_onTitleChanged);
  }

  Future<void> _load() async {
    final db = ref.read(dbProvider);
    final txns = ref.read(txnRepoProvider);
    final cats =
        await (db.select(db.categories)
              ..where((c) => c.archived.equals(false))
              ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
            .get();
    final accts =
        await (db.select(db.accounts)
              ..where((a) => a.archived.equals(false))
              ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
            .get();
    // Daily spending is offered pockets, never holdings — the emergency
    // fund does not sit next to the chai money. (If holdings are ALL there
    // is, they stay offered rather than leaving the sheet unusable.)
    final pockets = accts.where((a) => !a.keptAside).toList();
    final offered = pockets.isEmpty ? accts : pockets;
    final top = await txns.topCategoryIds();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _accounts = offered;
      _accountId = offered.isEmpty ? null : offered.first.id;
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

  /// The category's habitual figures, most-written first — read-only history
  /// the whisper row offers back. Ties break by recency.
  Future<void> _loadRecents(int? categoryId) async {
    if (categoryId == null) {
      if (mounted) {
        setState(() {
          _recentsFor = null;
          _recentAmounts = const [];
        });
      }
      return;
    }
    final db = ref.read(dbProvider);
    final rows =
        await (db.select(db.txns)
              ..where(
                (t) =>
                    t.categoryId.equals(categoryId) &
                    t.type.equalsValue(TxnType.expense),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.at)])
              ..limit(60))
            .get();
    final tally = <int, int>{};
    final firstSeen = <int, int>{};
    for (final (i, r) in rows.indexed) {
      tally[r.amountPaise] = (tally[r.amountPaise] ?? 0) + 1;
      firstSeen.putIfAbsent(r.amountPaise, () => i);
    }
    final ranked = tally.keys.toList()
      ..sort((a, b) {
        final byCount = tally[b]!.compareTo(tally[a]!);
        return byCount != 0 ? byCount : firstSeen[a]!.compareTo(firstSeen[b]!);
      });
    if (!mounted) return;
    setState(() {
      _recentsFor = categoryId;
      _recentAmounts = ranked.take(3).toList();
    });
  }

  /// One door for every category change, so the whisper always matches the
  /// chip that is lit.
  void _setCategory(int? id) {
    setState(() => _categoryId = id);
    unawaited(_loadRecents(id));
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
        _suggestion =
            (match == null || match.title.toLowerCase() == text.toLowerCase())
            ? null
            : match;
        // A remembered title quietly brings its category and account along.
        if (match != null && match.title.toLowerCase() == text.toLowerCase()) {
          if (match.categoryId != null && match.categoryId != _categoryId) {
            _flashCategoryId = match.categoryId;
            _flashSeq++;
          }
          _categoryId = match.categoryId ?? _categoryId;
          _accountId = match.accountId ?? _accountId;
        }
      });
      unawaited(_loadRecents(_categoryId));
    });
  }

  void _acceptSuggestion() {
    final s = _suggestion;
    if (s == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _title.text = s.title;
      _title.selection = TextSelection.collapsed(offset: s.title.length);
      if (s.categoryId != null && s.categoryId != _categoryId) {
        _flashCategoryId = s.categoryId;
        _flashSeq++;
      }
      _categoryId = s.categoryId ?? _categoryId;
      _accountId = s.accountId ?? _accountId;
      _suggestion = null;
    });
    unawaited(_loadRecents(_categoryId));
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
    final note = _note.text.trim();

    final repo = ref.read(txnRepoProvider);
    if (_moneyIn) {
      await repo.addIncome(
        amountPaise: _engine.paise,
        accountId: _accountId!,
        categoryId: _categoryId,
        title: title,
        note: note.isEmpty ? null : note,
        at: _at,
      );
    } else {
      await repo.addExpense(
        amountPaise: _engine.paise,
        accountId: _accountId!,
        categoryId: _categoryId,
        title: title,
        note: note.isEmpty ? null : note,
        at: _at,
      );
    }

    // Let the seal land on the key before the sheet leaves — the stamp is
    // the whole confirmation, so it is allowed to finish.
    await Future<void>.delayed(const Duration(milliseconds: 340));
    if (!mounted) return;
    if (andAnother) {
      setState(() {
        _engine.clear();
        _title.clear();
        _note.clear();
        _noteOpen = false;
        _suggestion = null;
        _stamping = false;
        // A new generation: the fresh ₹0 inks in like a new ledger line.
        _generation++;
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
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

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
            _amountRow(c),
            _leavesThePen(child: _recentsWhisper(c)),
            const SizedBox(height: Gap.x1),
            _leavesThePen(child: _categoryChips(c)),
            _titleField(c),
            if (_suggestion != null)
              InkIn(
                key: ValueKey('suggestion-${_suggestion!.title}'),
                child: _suggestionRow(c),
              ),
            _defaultsRow(c),
            if (_noteOpen) _leavesThePen(child: _noteField(c)),
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

  /// On stamp, the written parts dip to 0.92 and fade — the entry leaves
  /// the pen for the page, inside the existing 280ms window before the pop.
  Widget _leavesThePen({required Widget child}) {
    return AnimatedOpacity(
      opacity: _stamping ? 0 : 1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: _stamping ? 0.92 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _amountRow(LedgerColors c) {
    final expression = _engine.expression;
    return InkIn(
      // A new generation (save-and-add-another) re-inks the fresh ₹0.
      key: ValueKey('hero-$_generation'),
      play: _generation > 0,
      child: _leavesThePen(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: _PulseOnChange(
                trigger: _engine.paise,
                child: CountUp(
                  value: _engine.paise,
                  format: (p) => _moneyIn ? '+${Inr.format(p)}' : Inr.format(p),
                  style: LedgerType.heroAmount.copyWith(
                    fontSize: 38,
                    color: _moneyIn ? c.jama : c.ink,
                  ),
                  // Typing must feel instant, just soft.
                  duration: const Duration(milliseconds: 160),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: Gap.x2),
              child: Pressable(
                onTap: () => setState(() => _moneyIn = !_moneyIn),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.x2,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _moneyIn
                        ? c.jama.withValues(alpha: 0.16)
                        : c.paperRaised,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _moneyIn ? 'money in' : 'spent',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 11,
                      color: _moneyIn ? c.jama : c.inkFaint,
                    ),
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              child: expression.isEmpty
                  ? const SizedBox.shrink(key: ValueKey('no-expression'))
                  : Padding(
                      key: ValueKey('expression-$expression'),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        expression,
                        style: LedgerType.amount.copyWith(color: c.inkFaint),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// What this category usually costs, in faint mono. A tap writes the
  /// figure in whole — it can only ever save keystrokes. The row holds its
  /// height whether or not it speaks, so the keypad never moves.
  Widget _recentsWhisper(LedgerColors c) {
    final speaks = _recentsFor == _categoryId && _recentAmounts.isNotEmpty;
    return SizedBox(
      height: 22,
      child: IgnorePointer(
        ignoring: !speaks,
        child: AnimatedOpacity(
          opacity: speaks ? 1 : 0,
          duration: Motion.quick,
          curve: Motion.curve,
          child: Row(
            children: [
              Text(
                'usually',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 11,
                  color: c.inkFaint,
                ),
              ),
              for (final paise in _recentAmounts)
                Pressable(
                  onTap: () => setState(() => _engine.setPaise(paise)),
                  child: Padding(
                    padding: const EdgeInsets.only(left: Gap.x3),
                    child: Text(
                      Inr.format(paise),
                      style: LedgerType.amount.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
      Pressable(
        onTap: _pickCategory,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: c.rule),
            borderRadius: BorderRadius.circular(Corner.chip),
          ),
          child: PenDots(size: 16, color: c.inkFaint),
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

  Widget _chip(
    LedgerColors c, {
    required Category category,
    required bool selected,
  }) {
    Widget body(Color? wash) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: wash,
        border: Border.all(color: selected ? c.quill : c.rule),
        borderRadius: BorderRadius.circular(Corner.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CatMark(
            category.icon,
            size: 13,
            color: selected ? c.quill : c.inkFaint,
          ),
          const SizedBox(width: 5),
          Text(
            category.name,
            style: selected
                ? LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill)
                : LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
          ),
        ],
      ),
    );

    // When the title's memory picked this chip, it takes one soft quill
    // wash — out and back in 250ms, self-settling.
    final remembered = selected && category.id == _flashCategoryId;
    return Pressable(
      onTap: () => _setCategory(selected ? null : category.id),
      child: remembered
          ? TweenAnimationBuilder<double>(
              key: ValueKey('chip-wash-$_flashSeq'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => body(
                Color.lerp(
                  c.quillSoft,
                  c.quill.withValues(alpha: 0.3),
                  math.sin(math.pi * t),
                ),
              ),
            )
          : body(selected ? c.quillSoft : null),
    );
  }

  Future<void> _pickCategory() async {
    final cats = _categories
        .where((x) => x.kind == CategoryKind.expense)
        .toList();
    final picked = await showLedgerSheet<int>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                Padding(
                  padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x3),
                  child: Text(
                    'which shelf does this go on?',
                    style: LedgerType.title.copyWith(
                      fontSize: 18,
                      color: c.ink,
                    ),
                  ),
                ),
                Flexible(
                  child: GridView.count(
                    crossAxisCount: 4,
                    padding: EdgeInsets.zero,
                    mainAxisSpacing: Gap.x2,
                    crossAxisSpacing: Gap.x2,
                    shrinkWrap: true,
                    children: [
                      for (final (i, cat) in cats.indexed)
                        InkIn(
                          delay: Duration(milliseconds: 18 * i),
                          child: Pressable(
                            onTap: () => Navigator.of(context).pop(cat.id),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CatMark(
                                  cat.icon,
                                  size: 22,
                                  color: cat.id == _categoryId
                                      ? c.quill
                                      : c.ink,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cat.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: LedgerType.bodyText.copyWith(
                                    fontSize: 11,
                                    color: cat.id == _categoryId
                                        ? c.quill
                                        : c.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) _setCategory(picked);
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
            PenLines(size: 14, color: c.inkFaint),
            const SizedBox(width: Gap.x2),
            if (cat != null) ...[
              CatMark(cat.icon, size: 12, color: c.quill),
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
    final sameDay =
        _at.year == today.year &&
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
          // Optional by construction: the note only exists once asked for,
          // and asking is off the core path.
          Pressable(
            onTap: _toggleNote,
            child: Text(
              _noteOpen ? 'details ˅' : 'details ›',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: _noteOpen ? c.quill : c.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the note line; closes it again only while it is still blank, so
  /// a written line can never be hidden away and saved unseen.
  void _toggleNote() {
    setState(() {
      _noteOpen = !(_noteOpen && _note.text.trim().isEmpty);
    });
  }

  Widget _noteField(LedgerColors c) {
    return InkIn(
      key: const ValueKey('note-row'),
      child: Container(
        margin: const EdgeInsets.only(top: Gap.x2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: TextField(
          key: const ValueKey('add-note-field'),
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

/// A tiny 1.02 out-and-back pulse each time [trigger] changes — the paper
/// takes the digit. One pulse per keypress, driven off the value itself;
/// self-settling, nothing to cancel.
class _PulseOnChange extends StatefulWidget {
  const _PulseOnChange({required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<_PulseOnChange> createState() => _PulseOnChangeState();
}

class _PulseOnChangeState extends State<_PulseOnChange> {
  int _beat = 0;

  @override
  void didUpdateWidget(_PulseOnChange old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) _beat++;
  }

  @override
  Widget build(BuildContext context) {
    if (_beat == 0) return widget.child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(_beat),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (context, t, child) => Transform.scale(
        scale: 1 + 0.02 * math.sin(math.pi * t),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
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
    // live in the column; × and ÷ stay in the engine for later. Their glyphs
    // sit at the same width as . and ⌫ — one key grid, one rhythm.
    return Column(
      children: [
        Row(
          children: [
            key('7', () => onDigit('7')),
            key('8', () => onDigit('8')),
            key('9', () => onDigit('9')),
            key('+', () => onOp('+'), op: true),
          ],
        ),
        Row(
          children: [
            key('4', () => onDigit('4')),
            key('5', () => onDigit('5')),
            key('6', () => onDigit('6')),
            key('−', () => onOp('−'), op: true),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Row(
                      children: [
                        key('1', () => onDigit('1')),
                        key('2', () => onDigit('2')),
                        key('3', () => onDigit('3')),
                      ],
                    ),
                    Row(
                      children: [
                        key('0', () => onDigit('0')),
                        key('.', onPoint),
                        key('⌫', onBackspace),
                      ],
                    ),
                  ],
                ),
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
          // Op keys wear the sheet's own paper: a mark, not a block.
          color: op ? c.paperRaised : c.paper,
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
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Material(
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
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          border: Border.all(color: c.paperRaised, width: 2),
                          borderRadius: BorderRadius.circular(Corner.stamp),
                        ),
                        child: PenTick(size: 13, color: c.paperRaised),
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
            // The moment of saving: the key turns back into paper and the
            // chop lands on it. The haptic is already spent on the press.
            if (stamping)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: c.paperRaised,
                    borderRadius: BorderRadius.circular(Corner.key),
                  ),
                  alignment: Alignment.center,
                  child: const StampIn(size: 34, haptic: false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
