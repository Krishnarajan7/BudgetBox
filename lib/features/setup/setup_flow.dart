import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/seal.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../lock/lock_page.dart';
import 'restore_page.dart';

/// One account as it's being written into the book during setup. The id keeps
/// a line's identity stable so an added row inks itself in without the rows
/// above it re-writing.
typedef _Acct = ({int id, String name, String kind});

/// The setup ritual. One question per page, spoken progress, the app authors
/// and Krish edits. In [real] mode (first launch) every answer persists —
/// the intent, accounts, budgets, the goal, the PIN — and the book opens
/// through the lock. From Settings it stays a harmless preview.
class SetupFlow extends ConsumerStatefulWidget {
  const SetupFlow({super.key, this.real = false});

  final bool real;

  @override
  ConsumerState<SetupFlow> createState() => _SetupFlowState();
}

class _SetupFlowState extends ConsumerState<SetupFlow> {
  final _controller = PageController();
  int _page = 0;
  bool _saving = false;

  String _name = 'Krish';
  int _intent = 0;
  int _salaryDay = 1;

  final _income = TextEditingController(text: '92000');
  bool _editingIncome = false;

  final List<_Acct> _accounts = [(id: 0, name: 'HDFC salary', kind: 'bank')];
  int _nextAcct = 1;
  String? _pendingKind;
  final _acctName = TextEditingController();

  /// What the book has actually seen, per category, when it has seen
  /// anything. Empty on a first launch — then the shape below does the work.
  Map<String, int> _fromHistory = const {};

  /// Numbers Krish argued with, per category. His always win.
  final Map<String, int> _edited = {};
  int? _editingLimit;
  final _limit = TextEditingController();

  bool _wantGoal = true;
  final _goalName = TextEditingController(text: 'Ladakh');
  final _goalTarget = TextEditingController(text: '60000');

  final _pin = TextEditingController();

  static const _progress = [
    'a new book',
    'one question',
    'money in',
    'the accounts',
    'the proposed book',
    'one goal',
    'lock it down',
    'the first page',
  ];

  /// What the answer to page two is stored as. Today reads this and reorders
  /// itself around it.
  static const _intents = ['leaks', 'goal', 'truth'];

  /// A month's shape, as fractions of what comes in — proportions, never
  /// fixed rupee guesses. Seventy per cent spoken for, thirty kept.
  static const _shape = <(String, String, double)>[
    ('Rent', 'home', 0.28),
    ('Food & chai', 'cup', 0.12),
    ('Kirana & home', 'basket', 0.11),
    ('Fun & extras', 'film', 0.08),
    ('Getting around', 'bus', 0.06),
    ('Bills & recharge', 'bill', 0.05),
  ];

  static const _kindHints = {
    'bank': 'HDFC',
    'UPI': 'GPay',
    'cash': 'wallet',
    'card': 'HDFC credit',
  };

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  /// If this book already has months behind it, its own spending proposes the
  /// budget; the income shape only fills the gaps.
  Future<void> _loadHistory() async {
    try {
      final suggested =
          await ref.read(budgetRepoProvider).suggestFromHistory();
      if (suggested.isEmpty || !mounted) return;
      final db = ref.read(dbProvider);
      final cats = await db.select(db.categories).get();
      final byId = {for (final cat in cats) cat.id: cat.name};
      final seen = <String, int>{};
      for (final entry in suggested.entries) {
        final name = byId[entry.key];
        if (name != null && entry.value > 0) seen[name] = entry.value;
      }
      if (mounted && seen.isNotEmpty) setState(() => _fromHistory = seen);
    } catch (_) {
      // A book with nothing behind it has nothing to say. The shape covers it.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _income.dispose();
    _acctName.dispose();
    _limit.dispose();
    _goalName.dispose();
    _goalTarget.dispose();
    _pin.dispose();
    super.dispose();
  }

  // ————— the arithmetic —————

  int get _incomePaise => (int.tryParse(_income.text.trim()) ?? 0) * 100;

  static int _round100(int paise) => (paise / 10000).round() * 10000;

  /// The proposed book: his edits first, then what he actually spends, then
  /// the shape of what comes in.
  List<(String, String, int)> get _proposal => [
        for (final (name, icon, fraction) in _shape)
          (
            name,
            icon,
            _edited[name] ??
                _fromHistory[name] ??
                _round100((_incomePaise * fraction).round()),
          ),
      ];

  int get _spokenFor => _proposal.fold(0, (sum, row) => sum + row.$3);

  int get _keptPaise => _incomePaise - _spokenFor;

  int get _goalTargetPaise => (int.tryParse(_goalTarget.text.trim()) ?? 0) * 100;

  /// Half of what's left over — the other half stays a buffer, which is the
  /// only honest way to promise a date.
  int get _goalMonthlyPaise {
    final half = _keptPaise ~/ 2;
    return half <= 0 ? 0 : _round100(half);
  }

  DateTime? get _goalLanding {
    final monthly = _goalMonthlyPaise;
    final target = _goalTargetPaise;
    if (monthly <= 0 || target <= 0) return null;
    final months = (target / monthly).ceil();
    if (months > 360) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month + months);
  }

  String get _goalTitle {
    final typed = _goalName.text.trim();
    return typed.isEmpty ? 'Something to save for' : typed;
  }

  static String _monthYear(DateTime d) =>
      '${LedgerDates.monthsFull[d.month - 1]} ${d.year}';

  static String _spell(int n) => switch (n) {
        1 => 'One',
        2 => 'Two',
        3 => 'Three',
        4 => 'Four',
        5 => 'Five',
        6 => 'Six',
        _ => '$n',
      };

  void _next() {
    _controller.nextPage(duration: Motion.spring, curve: Motion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.x3, Gap.page, 0),
              child: Row(
                children: [
                  Text(_progress[_page],
                      style: LedgerType.amount
                          .copyWith(fontSize: 12, color: c.inkFaint)),
                  const Spacer(),
                  // The way out for someone who would rather look around
                  // first: every default is already sensible, so the closing
                  // page is always one tap away.
                  if (_page < _progress.length - 1)
                    Pressable(
                      onTap: _skipAll,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.x2,
                          vertical: Gap.x1,
                        ),
                        child: Text(
                          'skip all',
                          style: LedgerType.amount
                              .copyWith(fontSize: 12, color: c.quill),
                        ),
                      ),
                    ),
                  // First launch has nothing to close into; the preview does.
                  if (!widget.real)
                    Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.all(Gap.x1),
                        child:
                            PenCross(size: 15, color: c.inkFaint),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _coldOpen(c),
                  _question(c),
                  _moneyIn(c),
                  _accountsPage(c),
                  _proposedBook(c),
                  _goal(c),
                  _lockDown(c),
                  _receipt(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Jump past the questions entirely and land on the closing page, where
  /// every default is already filled in and one tap opens the book.
  void _skipAll() {
    _controller.animateToPage(
      _progress.length - 1,
      duration: Motion.settle,
      curve: Motion.curve,
    );
  }

  Widget _frame(
    LedgerColors c, {
    required List<Widget> children,
    String cta = 'Next',
    VoidCallback? onCta,
    // Nothing asked here is load-bearing: every answer has a sensible default
    // and lives in Settings afterwards. Being made to answer a question you
    // do not yet have an opinion about is its own kind of friction.
    bool skippable = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.x8),
                  // The page writes itself: question first, the rest a beat
                  // later.
                  for (final (i, child) in children.indexed)
                    InkIn(
                      delay: Duration(milliseconds: 60 + i * 70),
                      child: child,
                    ),
                  const SizedBox(height: Gap.x6),
                ],
              ),
            ),
          ),
          InkIn(
            delay: const Duration(milliseconds: 320),
            child: _Cta(label: cta, onTap: onCta ?? _next),
          ),
          if (skippable)
            InkIn(
              delay: const Duration(milliseconds: 380),
              child: Center(
                child: Pressable(
                  onTap: _next,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: Gap.x3,
                      horizontal: Gap.x4,
                    ),
                    child: Text(
                      'skip — you can change this later in Settings',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 12, color: c.inkFaint),
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(height: skippable ? Gap.x3 : Gap.x6),
        ],
      ),
    );
  }

  Widget _q(LedgerColors c, String text) => Text(
        text,
        style: LedgerType.title.copyWith(fontSize: 28, color: c.ink),
      );

  Widget _hint(LedgerColors c, String text) => Padding(
        padding: const EdgeInsets.only(top: Gap.x2),
        child: Text(text,
            style:
                LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint)),
      );

  Widget _caption(LedgerColors c, String text) =>
      Text(text, style: LedgerType.label.copyWith(color: c.inkFaint));

  // ————— 1. the cold open —————

  Widget _coldOpen(LedgerColors c) {
    return _frame(c, cta: 'Write it in', children: [
      _q(c, 'This book belongs to…'),
      TextFormField(
        initialValue: _name,
        onChanged: (v) => setState(() => _name = v),
        textCapitalization: TextCapitalization.words,
        style: LedgerType.title.copyWith(fontSize: 24, color: c.ink),
        cursorColor: c.quill,
        decoration: InputDecoration(
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.quill, width: 2)),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.quill, width: 2)),
        ),
      ),
      _hint(c,
          "Just a name. There's no account — this book lives on this phone, and it's yours."),
      // The other door: someone reinstalling should not have to re-enact the
      // ritual and hope the adopter marries their accounts by name.
      if (widget.real)
        Padding(
          padding: const EdgeInsets.only(top: Gap.x6),
          child: Pressable(
            onTap: () => Navigator.of(context).push(
              LedgerRoute<void>(builder: (_) => const RestorePage()),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'I already have a book',
                  style: LedgerType.bodyStrong
                      .copyWith(fontSize: 13, color: c.quill),
                ),
                const SizedBox(width: Gap.x1),
                PenArrow(size: 13, color: c.quill),
              ],
            ),
          ),
        ),
    ]);
  }

  // ————— 2. the one question —————

  Widget _question(LedgerColors c) {
    const options = [
      'stop the leaks',
      'save for something',
      'just see the truth',
    ];
    final greeting =
        _name.trim().isEmpty ? 'Alright.' : 'Alright, ${_name.trim()}.';
    return _frame(c, children: [
      _q(c, '$greeting What should this book watch for?'),
      const SizedBox(height: Gap.x4),
      for (final (i, o) in options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.x2),
          child: LedgerChip(o,
              selected: _intent == i,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _intent = i);
              }),
        ),
      _hint(c, 'This reorders the Today page. Change it any time.'),
    ]);
  }

  // ————— 3. money in —————

  Widget _moneyIn(LedgerColors c) {
    final heroStyle = LedgerType.heroAmount.copyWith(fontSize: 38, color: c.ink);
    return _frame(c, children: [
      _q(c, 'What comes in each month?'),
      const SizedBox(height: Gap.x4),
      _caption(c, _editingIncome ? 'rupees each month' : 'each month'),
      const SizedBox(height: Gap.x1),
      if (_editingIncome)
        TextField(
          controller: _income,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: heroStyle,
          cursorColor: c.quill,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: Gap.x1),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.quill, width: 2)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.quill, width: 2)),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => setState(() => _editingIncome = false),
          onTapOutside: (_) {
            if (_editingIncome) setState(() => _editingIncome = false);
          },
        )
      else
        Pressable(
          onTap: () => setState(() => _editingIncome = true),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _Rise(
              value: _incomePaise,
              format: Inr.format,
              style: heroStyle,
            ),
          ),
        ),
      _hint(c,
          'Rough is fine — everything here can be corrected. Tap the figure to change it.'),
      const SizedBox(height: Gap.x6),
      _caption(c, 'and it lands on the'),
      const SizedBox(height: Gap.x2),
      Wrap(spacing: Gap.x2, runSpacing: Gap.x2, children: [
        for (final (day, label) in const [
          (1, '1st'),
          (5, '5th'),
          (7, '7th'),
          (10, '10th'),
        ])
          LedgerChip(label,
              selected: _salaryDay == day,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _salaryDay = day);
              }),
      ]),
      const SizedBox(height: Gap.x6),
      LedgerLine(
        title: 'A year of this',
        detail: 'if it holds',
        amountWidget: _Rise(
          value: _incomePaise * 12,
          format: Inr.format,
          style: LedgerType.amount.copyWith(color: c.ink),
        ),
        last: true,
      ),
    ]);
  }

  // ————— 4. the accounts —————

  Widget _accountsPage(LedgerColors c) {
    return _frame(c, children: [
      _q(c, 'Where does your money live?'),
      RuleHeader(
        'in the box',
        trailing: CountUp(
          value: _accounts.length,
          format: (n) => '$n',
          style: LedgerType.amount.copyWith(fontSize: 13, color: c.inkFaint),
        ),
      ),
      Column(
        children: [
          for (final (i, a) in _accounts.indexed)
            InkIn(
              key: ValueKey(a.id),
              child: LedgerLine(
                mark: Icon(
                  LedgerIcons.account[a.kind.toLowerCase()] ??
                      LedgerIcons.fallback,
                  size: 15,
                  color: c.inkFaint,
                ),
                title: a.name,
                detail: a.kind,
                last: i == _accounts.length - 1,
                onLongPress: _accounts.length > 1
                    ? () {
                        HapticFeedback.mediumImpact();
                        setState(() => _accounts.removeAt(i));
                      }
                    : null,
              ),
            ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Gap.x3),
          if (_pendingKind != null)
            InkIn(
              key: ValueKey('name-${_pendingKind!}'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: Gap.x3),
                child: Row(
                  children: [
                    Icon(
                      LedgerIcons.account[_pendingKind!.toLowerCase()] ??
                          LedgerIcons.fallback,
                      size: 15,
                      color: c.inkFaint,
                    ),
                    const SizedBox(width: Gap.x2),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border:
                              Border(bottom: BorderSide(color: c.quill)),
                        ),
                        child: TextField(
                          controller: _acctName,
                          autofocus: true,
                          textCapitalization: TextCapitalization.words,
                          style: LedgerType.bodyText.copyWith(color: c.ink),
                          cursorColor: c.quill,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: _kindHints[_pendingKind!] ?? 'a name',
                            hintStyle: LedgerType.bodyText
                                .copyWith(color: c.inkFaint),
                            contentPadding:
                                const EdgeInsets.only(bottom: Gap.x1),
                          ),
                          onSubmitted: (_) => _addAccount(),
                        ),
                      ),
                    ),
                    const SizedBox(width: Gap.x3),
                    Pressable(
                      onTap: _addAccount,
                      child: Text('write it in',
                          style: LedgerType.bodyStrong
                              .copyWith(fontSize: 13, color: c.quill)),
                    ),
                  ],
                ),
              ),
            ),
          Wrap(spacing: Gap.x2, runSpacing: Gap.x2, children: [
            for (final k in const ['bank', 'UPI', 'cash', 'card'])
              LedgerChip(
                k,
                selected: _pendingKind == k,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _acctName.clear();
                    _pendingKind = _pendingKind == k ? null : k;
                  });
                },
              ),
          ]),
        ],
      ),
      _hint(
          c,
          _pendingKind != null
              ? 'Name it — or leave it blank and it stays a plain $_pendingKind.'
              : '${_spell(_accounts.length)} in. Add another, or move on. '
                  'Long-press a line to strike it.'),
    ]);
  }

  void _addAccount() {
    final kind = _pendingKind;
    if (kind == null) return;
    final typed = _acctName.text.trim();
    HapticFeedback.selectionClick();
    setState(() {
      _accounts.add((
        id: _nextAcct++,
        name: typed.isEmpty ? kind : typed,
        kind: kind,
      ));
      _acctName.clear();
      _pendingKind = null;
    });
  }

  // ————— 5. the proposed book —————

  Widget _proposedBook(LedgerColors c) {
    final rows = _proposal;
    final kept = _keptPaise;
    return _frame(c, cta: 'Looks about right', children: [
      _q(c, "Here's a starting budget, ${_name.trim().isEmpty ? 'then' : _name.trim()}."),
      _hint(
          c,
          _fromHistory.isEmpty
              ? 'Drawn from ${Inr.format(_incomePaise)} a month. Nothing here is permanent — tap any number to argue with it.'
              : 'Drawn from what you actually spend. Nothing here is permanent — tap any number to argue with it.'),
      const SizedBox(height: Gap.x3),
      Column(
        children: [
          for (final (i, (name, icon, limit)) in rows.indexed)
            InkIn(
              key: ValueKey(name),
              delay: Duration(milliseconds: 140 + i * 90),
              child: LedgerLine(
                mark: CatMark(icon),
                title: name,
                detail: _editingLimit == i ? 'rupees a month' : null,
                amountWidget: _editingLimit == i
                    ? SizedBox(
                        width: 104,
                        child: TextField(
                          controller: _limit,
                          autofocus: true,
                          textAlign: TextAlign.right,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style: LedgerType.amount.copyWith(color: c.quill),
                          cursorColor: c.quill,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: c.quill)),
                            focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(color: c.quill)),
                          ),
                          onSubmitted: (_) => _commitLimit(name),
                          onTapOutside: (_) => _commitLimit(name),
                        ),
                      )
                    : _Rise(
                        value: limit,
                        format: Inr.format,
                        delay: Duration(milliseconds: 200 + i * 90),
                        style: LedgerType.amount.copyWith(color: c.quill),
                      ),
                onTap: () => _editLimit(i, limit),
              ),
            ),
          LedgerLine(
            title: 'Spoken for',
            detail: '${rows.length} budgets',
            amountWidget: _Rise(
              value: _spokenFor,
              format: Inr.format,
              delay: const Duration(milliseconds: 700),
              style: LedgerType.amountTotal.copyWith(color: c.ink),
            ),
          ),
          LedgerLine(
            title: 'Kept aside',
            detail: kept < 0 ? 'more than comes in' : 'yours, every month',
            amountWidget: _Rise(
              value: kept,
              format: Inr.format,
              delay: const Duration(milliseconds: 780),
              style: LedgerType.amountTotal
                  .copyWith(color: kept < 0 ? c.seal : c.jama),
            ),
            last: true,
          ),
        ],
      ),
    ]);
  }

  void _editLimit(int index, int current) {
    setState(() {
      _editingLimit = index;
      _limit.text = '${current ~/ 100}';
      _limit.selection =
          TextSelection(baseOffset: 0, extentOffset: _limit.text.length);
    });
  }

  void _commitLimit(String name) {
    if (_editingLimit == null) return;
    final typed = int.tryParse(_limit.text.trim());
    setState(() {
      if (typed != null) _edited[name] = typed * 100;
      _editingLimit = null;
    });
  }

  // ————— 6. one goal —————

  Widget _goal(LedgerColors c) {
    final landing = _goalLanding;
    final monthly = _goalMonthlyPaise;
    final answer = !_wantGoal
        ? 'Fine. The book will ask again when there\'s something to ask about.'
        : _goalName.text.trim().isEmpty || _goalTargetPaise <= 0
            ? "Name it and put a number on it, and I'll do the arithmetic."
            : landing == null
                ? 'At these budgets nothing is left over, so I can\'t promise a date yet.'
                : 'Half of what you keep is ${Inr.format(monthly)} a month. '
                    'That puts $_goalTitle in ${_monthYear(landing)}.';
    return _frame(c,
        cta: _wantGoal ? 'Keep this goal' : 'Move on',
        children: [
          _q(c, 'Saving for something?'),
          _hint(c, 'One is plenty. Skippable — goals can wait.'),
          const SizedBox(height: Gap.x4),
          _GoalField(
            label: 'what for',
            controller: _goalName,
            hint: 'Ladakh, next June',
            onChanged: () => setState(() {}),
          ),
          _GoalField(
            label: 'how much',
            controller: _goalTarget,
            hint: '60000',
            digits: true,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: Gap.x4),
          Text(answer,
              style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink)),
          const SizedBox(height: Gap.x4),
          Row(children: [
            LedgerChip('keep it',
                selected: _wantGoal,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _wantGoal = true);
                }),
            const SizedBox(width: Gap.x2),
            LedgerChip('not yet',
                selected: !_wantGoal,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _wantGoal = false);
                }),
          ]),
        ]);
  }

  // ————— 7. lock it down —————

  Widget _lockDown(LedgerColors c) {
    return _frame(c, cta: 'Lock it down', children: [
      _q(c, 'This book locks.'),
      // This used to promise nothing ever left the phone. That was true
      // before the book had a server; saying it now would be a lie about
      // exactly the thing a person is trusting you with.
      _hint(c,
          'Four digits below, Face ID in front of them. The PIN stays on this '
          'phone — it guards this device and is never sent to your server. '
          'Leave it blank to skip for now.'),
      const SizedBox(height: Gap.x6),
      Center(
        child: SizedBox(
          width: 160,
          child: TextField(
            controller: _pin,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: LedgerType.heroAmount
                .copyWith(fontSize: 30, color: c.ink, letterSpacing: 14),
            decoration: InputDecoration(
              counterText: '',
              hintText: '····',
              hintStyle: LedgerType.heroAmount.copyWith(
                  fontSize: 30, color: c.inkFaint, letterSpacing: 14),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: c.rule)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: c.quill, width: 1.6)),
            ),
          ),
        ),
      ),
      const SizedBox(height: Gap.x6),
      Center(child: SealOutline(size: 36, color: c.inkFaint)),
    ]);
  }

  // ————— 8. the receipt —————

  Widget _receipt(LedgerColors c) {
    final rows = _proposal;
    final kept = _keptPaise;
    final landing = _goalLanding;
    final closing = _wantGoal
        ? landing == null
            ? '$_goalTitle has no date on it yet — feed it when a month runs light.'
            : 'Hold this shape and $_goalTitle lands in ${_monthYear(landing)}.'
        : kept > 0
            ? 'At this shape you keep ${Inr.format(kept)} a month — ${Inr.format(kept * 12)} by this time next year.'
            : 'Every rupee is spoken for. The book will say so when that changes.';

    return _frame(c,
        cta: _saving
            ? 'opening…'
            : widget.real
                ? 'Open the book'
                : 'Close the preview',
        onCta: _finish,
        // The closing page is the destination; there is nothing past it.
        skippable: false,
        children: [
          _q(c,
              'Your box is set up${_name.trim().isEmpty ? '' : ', ${_name.trim()}'}.'),
          Column(
            children: [
              const RuleHeader('what you built'),
              LedgerLine(
                title: 'Money in',
                detail:
                    'across ${_accounts.length} ${_accounts.length == 1 ? 'account' : 'accounts'}',
                amountWidget: _Rise(
                  value: _incomePaise,
                  format: Inr.format,
                  delay: const Duration(milliseconds: 240),
                  style: LedgerType.amount.copyWith(color: c.ink),
                ),
              ),
              LedgerLine(
                title: 'Spoken for',
                detail: '${rows.length} budgets',
                amountWidget: _Rise(
                  value: _spokenFor,
                  format: Inr.format,
                  delay: const Duration(milliseconds: 330),
                  style: LedgerType.amount.copyWith(color: c.ink),
                ),
              ),
              LedgerLine(
                title: 'Kept aside',
                detail: 'every month',
                amountWidget: _Rise(
                  value: kept,
                  format: Inr.format,
                  delay: const Duration(milliseconds: 420),
                  style: LedgerType.amountTotal
                      .copyWith(color: kept < 0 ? c.seal : c.jama),
                ),
                last: !_wantGoal,
              ),
              if (_wantGoal)
                LedgerLine(
                  title: _goalTitle,
                  detail:
                      landing == null ? 'no date yet' : 'by ${_monthYear(landing)}',
                  amountWidget: _Rise(
                    value: _goalTargetPaise,
                    format: Inr.format,
                    delay: const Duration(milliseconds: 510),
                    style: LedgerType.amount.copyWith(color: c.ink),
                  ),
                  last: true,
                ),
            ],
          ),
          _hint(c, closing),
          const SizedBox(height: Gap.x8),
          const Center(
            child: StampIn(size: 64, delay: Duration(milliseconds: 900)),
          ),
          const SizedBox(height: Gap.x2),
          Center(
            child: Text('first entry, to-day',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 12, color: c.inkFaint)),
          ),
        ]);
  }

  // ————— closing the ritual —————

  Future<void> _finish() async {
    if (!widget.real) {
      Navigator.of(context).pop();
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final settings = ref.read(settingsRepoProvider);
    final accountRepo = ref.read(accountRepoProvider);
    final budgetRepo = ref.read(budgetRepoProvider);
    final goalRepo = ref.read(goalRepoProvider);
    final db = ref.read(dbProvider);

    await settings.setName(_name.trim().isEmpty ? 'Krish' : _name.trim());
    await settings.setSalaryDay(_salaryDay);
    await settings.setIntent(_intents[_intent]);

    for (final a in _accounts) {
      await accountRepo.create(
        name: a.name,
        kind: switch (a.kind.toLowerCase()) {
          'upi' => AccountKind.upi,
          'cash' => AccountKind.cash,
          'card' => AccountKind.card,
          _ => AccountKind.bank,
        },
      );
    }

    final cats = await db.select(db.categories).get();
    for (final (name, _, limit) in _proposal) {
      final cat = cats.where((x) => x.name == name).firstOrNull;
      await budgetRepo.create(
        name: name,
        limitPaise: limit,
        categoryId: cat?.id,
      );
    }

    if (_wantGoal && _goalTargetPaise > 0) {
      final monthly = _goalMonthlyPaise;
      await goalRepo.create(
        name: _goalTitle,
        targetPaise: _goalTargetPaise,
        monthlyPaise: monthly > 0 ? monthly : null,
        targetDate: _goalLanding,
      );
    }

    final pin = _pin.text.trim();
    if (pin.length == 4 && int.tryParse(pin) != null) {
      await settings.setPin(pin);
    }

    await settings.markSetupDone();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const LockPage(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

/// The page's one forward affordance: it presses, it speaks, it turns.
class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.quill,
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

/// A figure that arrives by counting: it starts at nothing and settles onto
/// its value a beat after it lands on the page — and settles again whenever
/// the value is argued with.
class _Rise extends StatefulWidget {
  const _Rise({
    required this.value,
    required this.format,
    required this.style,
    this.delay = const Duration(milliseconds: 160),
  });

  final int value;
  final String Function(int) format;
  final TextStyle style;
  final Duration delay;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> {
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (mounted && _shown != widget.value) {
        setState(() => _shown = widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(_Rise old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _shown = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) {
      return Text(widget.format(widget.value), style: widget.style);
    }
    return CountUp(
      value: _shown,
      format: widget.format,
      style: widget.style,
    );
  }
}

/// One ruled line of the goal card: a quiet label, then his answer on the
/// rule. No boxes — the page is paper.
class _GoalField extends StatelessWidget {
  const _GoalField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.digits = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final VoidCallback onChanged;
  final bool digits;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final style = digits
        ? LedgerType.amount.copyWith(color: c.ink)
        : LedgerType.bodyText.copyWith(color: c.ink);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: LedgerType.bodyText
                    .copyWith(fontSize: 13, color: c.inkFaint)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: digits ? TextInputType.number : TextInputType.text,
              textCapitalization: digits
                  ? TextCapitalization.none
                  : TextCapitalization.sentences,
              inputFormatters:
                  digits ? [FilteringTextInputFormatter.digitsOnly] : null,
              textAlign: digits ? TextAlign.right : TextAlign.left,
              style: style,
              cursorColor: c.quill,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: style.copyWith(color: c.inkFaint),
                contentPadding: const EdgeInsets.only(bottom: Gap.x2),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }
}
