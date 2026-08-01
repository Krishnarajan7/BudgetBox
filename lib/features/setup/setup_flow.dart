import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/seal.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../lock/lock_page.dart';

/// The setup ritual. One question per page, spoken progress, the app authors
/// and Krish edits. In [real] mode (first launch) every answer persists —
/// accounts, budgets, the goal, the PIN — and the book opens through the
/// lock. From Settings it stays a harmless preview.
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
  bool _wantGoal = true;
  final _income = TextEditingController(text: '92000');
  final _pin = TextEditingController();
  final List<(String, String)> _accounts = [('HDFC salary', 'bank')];

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

  void _next() {
    HapticFeedback.selectionClick();
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _income.dispose();
    _pin.dispose();
    super.dispose();
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
                  // First launch has nothing to close into; the preview does.
                  if (!widget.real)
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(Icons.close, size: 18, color: c.inkFaint),
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

  Widget _frame(LedgerColors c,
      {required List<Widget> children, String cta = 'Next', VoidCallback? onCta}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.page),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Gap.x8),
          ...children,
          const Spacer(),
          FilledButton(onPressed: onCta ?? _next, child: Text(cta)),
          const SizedBox(height: Gap.x6),
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

  Widget _coldOpen(LedgerColors c) {
    return _frame(c, cta: 'Write it in', children: [
      _q(c, 'This book belongs to…'),
      TextFormField(
        initialValue: _name,
        onChanged: (v) => _name = v,
        style: LedgerType.title.copyWith(fontSize: 24, color: c.ink),
        decoration: InputDecoration(
          enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.quill, width: 2)),
          focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: c.quill, width: 2)),
        ),
      ),
      _hint(c,
          "Just a name. There's no account — this book lives on this phone, and it's yours."),
    ]);
  }

  Widget _question(LedgerColors c) {
    const options = [
      'stop the leaks',
      'save for something',
      'just see the truth',
    ];
    return _frame(c, children: [
      _q(c, 'Alright, $_name. What should this book watch for?'),
      const SizedBox(height: Gap.x4),
      for (final (i, o) in options.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.x2),
          child: LedgerChip(o,
              selected: _intent == i,
              onTap: () => setState(() => _intent = i)),
        ),
      _hint(c, 'This reorders the Today page. Change it any time.'),
    ]);
  }

  Widget _moneyIn(LedgerColors c) {
    return _frame(c, children: [
      _q(c, 'What comes in each month?'),
      TextField(
        controller: _income,
        keyboardType: TextInputType.number,
        style: LedgerType.heroAmount.copyWith(fontSize: 36, color: c.ink),
        decoration: InputDecoration(
          prefixText: '₹',
          prefixStyle:
              LedgerType.heroAmount.copyWith(fontSize: 36, color: c.inkFaint),
          border: InputBorder.none,
        ),
      ),
      _hint(c, 'Rough is fine — everything here can be corrected.'),
      const SizedBox(height: Gap.x4),
      Row(children: [
        Text('salary lands on the ',
            style: LedgerType.bodyText.copyWith(color: c.inkFaint)),
        Text('1st',
            style: LedgerType.bodyStrong.copyWith(color: c.quill)),
      ]),
    ]);
  }

  Widget _accountsPage(LedgerColors c) {
    return _frame(c, children: [
      _q(c, 'Where does your money live?'),
      const SizedBox(height: Gap.x3),
      for (final (i, (name, kind)) in _accounts.indexed)
        LedgerLine(
            title: name, detail: kind, amount: '', last: i == _accounts.length - 1),
      const SizedBox(height: Gap.x3),
      Wrap(spacing: Gap.x2, runSpacing: Gap.x2, children: [
        for (final k in const ['bank', 'UPI', 'cash', 'card'])
          LedgerChip(k, icon: Icons.add, onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _accounts.add((k, k)));
          }),
      ]),
      _hint(
          c,
          _accounts.length == 1
              ? 'One in. Add another, or move on.'
              : '${_accounts.length} in. Add another, or move on.'),
    ]);
  }

  /// The preview's proposed book. When this flow persists for real, these
  /// come from BudgetRepo.suggestFromHistory instead.
  static const _proposal = <(String, int)>[
    ('Food & chai', 900000),
    ('Getting around', 350000),
    ('Kirana & home', 1000000),
    ('Rent', 1500000),
    ('Bills & recharge', 240000),
    ('Fun & extras', 400000),
  ];

  Widget _proposedBook(LedgerColors c) {
    final income = (int.tryParse(_income.text) ?? 92000) * 100;
    final total = _proposal.fold(0, (s, e) => s + e.$2);
    return _frame(c, cta: 'Looks about right', children: [
      _q(c, "Here's a starting budget, $_name."),
      _hint(c,
          'Drawn from ${Inr.format(income)} a month. Nothing here is permanent — tap any number to argue with it.'),
      const SizedBox(height: Gap.x3),
      for (final (name, limit) in _proposal)
        LedgerLine(
          title: name,
          amount: Inr.format(limit),
          amountColor: c.quill,
        ),
      LedgerLine(
        title: 'Kept aside',
        amount: '${Inr.format(income - total)} stays with you',
        amountColor: c.jama,
        last: true,
      ),
    ]);
  }

  Widget _goal(LedgerColors c) {
    return _frame(c,
        cta: _wantGoal ? 'Keep this goal' : 'Move on',
        children: [
          _q(c, 'Saving for something?'),
          const SizedBox(height: Gap.x3),
          LedgerLine(title: 'Ladakh, next June', amount: Inr.format(6000000)),
          _hint(c,
              '₹4,000 a month gets you there by March 2028. Skippable — goals can wait.'),
          const SizedBox(height: Gap.x3),
          Row(children: [
            LedgerChip('keep it',
                selected: _wantGoal,
                onTap: () => setState(() => _wantGoal = true)),
            const SizedBox(width: Gap.x2),
            LedgerChip('not yet',
                selected: !_wantGoal,
                onTap: () => setState(() => _wantGoal = false)),
          ]),
        ]);
  }

  Widget _lockDown(LedgerColors c) {
    return _frame(c, cta: 'Lock it down', children: [
      _q(c, 'This book locks.'),
      _hint(c,
          'Four digits below, Face ID in front of them. Nothing leaves this '
          'phone — there is no cloud to leak from. Leave it blank to skip '
          'for now.'),
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
      Center(child: Icon(Icons.face_outlined, size: 36, color: c.inkFaint)),
    ]);
  }

  Widget _receipt(LedgerColors c) {
    return _frame(c,
        cta: _saving
            ? 'opening…'
            : widget.real
                ? 'Open the book'
                : 'Close the preview',
        onCta: _finish,
        children: [
          _q(c, 'Your box is set up, $_name.'),
          const SizedBox(height: Gap.x4),
          LedgerLine(
              title: 'In the book', amount: '${_accounts.length} accounts'),
          LedgerLine(
              title: 'Watching', amount: '${_proposal.length} budgets'),
          LedgerLine(
              title: 'Saving for',
              amount: _wantGoal ? 'Ladakh, next June' : 'nothing yet',
              last: true),
          const SizedBox(height: Gap.x8),
          const Center(child: Seal(size: 64)),
          const SizedBox(height: Gap.x2),
          Center(
            child: Text('first entry, to-day',
                style: LedgerType.bodyText
                    .copyWith(fontSize: 12, color: c.inkFaint)),
          ),
        ]);
  }

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
    await settings.setSalaryDay(1);

    for (final (name, kind) in _accounts) {
      await accountRepo.create(
        name: name,
        kind: switch (kind.toLowerCase()) {
          'upi' => AccountKind.upi,
          'cash' => AccountKind.cash,
          'card' => AccountKind.card,
          _ => AccountKind.bank,
        },
      );
    }

    final cats = await db.select(db.categories).get();
    for (final (name, limit) in _proposal) {
      final cat = cats.where((x) => x.name == name).firstOrNull;
      await budgetRepo.create(
        name: name,
        limitPaise: limit,
        categoryId: cat?.id,
      );
    }

    if (_wantGoal) {
      await goalRepo.create(
        name: 'Ladakh, next June',
        targetPaise: 6000000,
        monthlyPaise: 400000,
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
