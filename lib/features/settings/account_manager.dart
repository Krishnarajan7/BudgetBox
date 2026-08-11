import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// An account may retire only once it holds nothing — an archived account
/// with money in it would make the net worth lie.
bool canRetireAccount(int balancePaise) => balancePaise == 0;

String _kindLabel(AccountKind kind) =>
    kind == AccountKind.upi ? 'UPI' : kind.name;

/// What an account is worth to the footing: a liability counts against it.
int _signed(Account a) =>
    a.kind == AccountKind.liability ? -a.balancePaise : a.balancePaise;

/// Banks, cash, cards — where the money sits, in the owner's words.
class AccountManagerPage extends ConsumerStatefulWidget {
  const AccountManagerPage({super.key});

  @override
  ConsumerState<AccountManagerPage> createState() =>
      _AccountManagerPageState();
}

class _AccountManagerPageState extends ConsumerState<AccountManagerPage> {
  /// Ids already on the page — only genuinely new lines animate in.
  final _seen = <int>{};
  bool _primed = false;

  /// The order the owner's finger just chose, kept until the write lands.
  List<int>? _localOrder;

  /// Lines on their way off the page: struck through while the ink dries.
  final _leaving = <int>{};

  List<Account> _ordered(List<Account> accounts) {
    final wanted = _localOrder;
    if (wanted == null) return accounts;
    final byId = {for (final a in accounts) a.id: a};
    if (wanted.length != accounts.length ||
        !wanted.toSet().containsAll(byId.keys)) {
      return accounts;
    }
    return [for (final id in wanted) byId[id]!];
  }

  Future<void> _reorder(List<Account> accounts, int oldIndex, int newIndex) async {
    final next = [...accounts];
    next.insert(newIndex, next.removeAt(oldIndex));
    HapticFeedback.lightImpact();
    setState(() => _localOrder = [for (final a in next) a.id]);
    final db = ref.read(dbProvider);
    await db.batch((b) {
      for (final (i, a) in next.indexed) {
        b.update(
          db.accounts,
          AccountsCompanion(sortOrder: Value(i)),
          where: ($AccountsTable t) => t.id.equals(a.id),
        );
      }
    });
  }

  /// The line is struck first and only then leaves — a retirement is
  /// something you watch happen.
  Future<void> _retire(Account account) async {
    setState(() => _leaving.add(account.id));
    if (!Motion.reduced(context)) {
      await Future<void>.delayed(const Duration(milliseconds: 320));
    }
    final db = ref.read(dbProvider);
    await (db.update(db.accounts)..where((a) => a.id.equals(account.id)))
        .write(const AccountsCompanion(archived: Value(true)));
    if (mounted) setState(() => _leaving.remove(account.id));
  }

  Future<void> _openSheet({Account? existing}) async {
    final verdict = await showLedgerSheet<String>(
      context,
      builder: (context) => _AccountSheet(existing: existing),
    );
    if (!mounted) return;
    if (verdict == 'retire' && existing != null) await _retire(existing);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(accountRepoProvider);

    return ModuleScaffold(
      title: 'Accounts',
      trailing: Pressable(
        scale: 0.9,
        onTap: () => _openSheet(),
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: PenPlus(size: 18, color: c.inkFaint),
        ),
      ),
      child: StreamBuilder<List<Account>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          final accounts = _ordered(snapshot.data ?? const <Account>[]);
          final firstPaint = !_primed && snapshot.hasData;
          final fresh = <int>{
            if (firstPaint)
              for (final a in accounts) a.id
            else if (_primed)
              for (final a in accounts)
                if (!_seen.contains(a.id)) a.id,
          };
          if (snapshot.hasData) {
            _primed = true;
            _seen.addAll(accounts.map((a) => a.id));
          }

          if (snapshot.hasData && accounts.isEmpty) {
            return const EmptyPage(
              line: 'Nowhere for the money to sit yet.',
              sub: 'The plus above opens the first one — '
                  'rough is fine, all of it can be corrected.',
            );
          }

          final footing =
              accounts.fold(0, (int sum, a) => sum + _signed(a));

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const SizedBox(height: Gap.x3),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) => _reorder(accounts, from, to),
                proxyDecorator: (child, index, animation) => Material(
                  color: c.paperRaised,
                  elevation: 3,
                  shadowColor: c.ink.withValues(alpha: 0.25),
                  child: child,
                ),
                itemCount: accounts.length,
                itemBuilder: (context, i) {
                  final a = accounts[i];
                  return InkIn(
                    key: ValueKey('acct-${a.id}'),
                    play: fresh.contains(a.id),
                    delay: firstPaint
                        ? Duration(milliseconds: 24 * i)
                        : Duration.zero,
                    child: _AccountRow(
                      account: a,
                      index: i,
                      leaving: _leaving.contains(a.id),
                      onTap: () => _openSheet(existing: a),
                    ),
                  );
                },
              ),
              if (accounts.isNotEmpty) ...[
                _Footing(paise: footing),
                const SizedBox(height: Gap.x4),
                Text(
                  'Balances move with the book. Drag by the grip to put them '
                  'in your order, tap a line to rename it or change what kind '
                  'of thing it is.',
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

/// The column's total, ruled off in ink like a page that has been added up.
class _Footing extends StatelessWidget {
  const _Footing({required this.paise});

  final int paise;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      margin: const EdgeInsets.only(top: Gap.x3),
      padding: const EdgeInsets.only(top: Gap.x2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.ink)),
      ),
      child: Row(
        children: [
          Text(
            'the footing',
            style: LedgerType.label.copyWith(color: c.inkFaint),
          ),
          const Spacer(),
          CountUp(
            value: paise,
            format: (p) => Inr.format(p),
            style: LedgerType.amountTotal.copyWith(color: c.ink),
          ),
        ],
      ),
    );
  }
}

/// One ruled line: the kind's mark, the name over its nature, the last few
/// readings as a whisper, the balance in mono holding the right edge.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({
    required this.account,
    required this.index,
    required this.leaving,
    required this.onTap,
  });

  final Account account;
  final int index;
  final bool leaving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final owed = account.kind == AccountKind.liability;
    return AnimatedOpacity(
      duration: Motion.quick,
      curve: Motion.curve,
      opacity: leaving ? 0.3 : 1,
      child: LedgerLine(
        mark: Icon(
          LedgerIcons.account[account.kind.name] ?? LedgerIcons.fallback,
          size: 15,
          color: c.inkFaint,
        ),
        title: account.name,
        detail: _kindLabel(account.kind),
        struck: leaving,
        onTap: onTap,
        amountWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 44,
              height: 16,
              child: FutureBuilder<List<double>>(
                key: ValueKey('spark-${account.id}-${account.balancePaise}'),
                future: ref.read(accountRepoProvider).spark(account.id),
                builder: (context, spark) =>
                    Sparkline(spark.data ?? const <double>[]),
              ),
            ),
            const SizedBox(width: Gap.x3),
            // Settles to the new figure after an entry lands, never snaps.
            CountUp(
              value: owed ? -account.balancePaise : account.balancePaise,
              format: (p) => Inr.format(p),
              style: LedgerType.amount.copyWith(
                color: leaving ? c.inkFaint : c.ink,
                decoration: leaving ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(width: Gap.x2),
            ReorderableDragStartListener(
              index: index,
              child: PenLines(
                size: 15, color: c.inkFaint.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name, kind, and — only at birth — an opening balance. After that the
/// balance belongs to the book.
class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet({this.existing});

  final Account? existing;

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  final _opening = TextEditingController();
  late AccountKind _kind = widget.existing?.kind ?? AccountKind.bank;

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  int _openingPaise() {
    final raw = _opening.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return 0;
    final rupees = double.tryParse(raw);
    if (rupees == null) return 0;
    return (rupees * 100).round();
  }

  Future<void> _keep() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    HapticFeedback.lightImpact();
    final existing = widget.existing;
    if (existing == null) {
      await ref.read(accountRepoProvider).create(
            name: name,
            kind: _kind,
            openingBalancePaise: _openingPaise(),
          );
    } else {
      final db = ref.read(dbProvider);
      await (db.update(db.accounts)..where((a) => a.id.equals(existing.id)))
          .write(AccountsCompanion(name: Value(name), kind: Value(_kind)));
    }
    if (mounted) Navigator.of(context).pop();
  }

  /// The page strikes the line out before the write lands.
  void _retire() {
    final existing = widget.existing;
    if (existing == null || !canRetireAccount(existing.balancePaise)) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop('retire');
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final existing = widget.existing;
    final adding = existing == null;

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
                    ? 'Somewhere new for the money to sit.'
                    : 'Its name and its nature.',
                style: LedgerType.bodyStrong.copyWith(color: c.ink),
              ),
              const SizedBox(height: Gap.x3),
              Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.rule)),
                ),
                child: TextField(
                  controller: _name,
                  autofocus: adding,
                  textCapitalization: TextCapitalization.words,
                  style:
                      LedgerType.bodyText.copyWith(fontSize: 16, color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'what you call it',
                    hintStyle: LedgerType.bodyText
                        .copyWith(fontSize: 16, color: c.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'what kind of thing',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              Wrap(
                spacing: Gap.x2,
                runSpacing: Gap.x2,
                children: [
                  for (final kind in AccountKind.values)
                    LedgerChip(
                      _kindLabel(kind),
                      icon: LedgerIcons.account[kind.name],
                      selected: _kind == kind,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _kind = kind);
                      },
                    ),
                ],
              ),
              const SizedBox(height: Gap.x4),
              if (adding) ...[
                Text(
                  'opening balance, in rupees',
                  style: LedgerType.label.copyWith(color: c.inkFaint),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.rule)),
                  ),
                  child: TextField(
                    controller: _opening,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
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
              ] else
                Text(
                  'Balance moves with the book — correct it from Worth.',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              const SizedBox(height: Gap.x4),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _name,
                builder: (context, value, _) {
                  final ready = value.text.trim().isNotEmpty;
                  return AnimatedOpacity(
                    duration: Motion.quick,
                    curve: Motion.curve,
                    opacity: ready ? 1 : 0.5,
                    child: FilledButton(
                      onPressed: ready ? _keep : null,
                      child: AnimatedSwitcher(
                        duration: Motion.quick,
                        child: Text(
                          ready ? 'Keep it' : 'give it a name first',
                          key: ValueKey(ready),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (!adding)
                Center(
                  child: canRetireAccount(existing.balancePaise)
                      ? TextButton(
                          onPressed: _retire,
                          child: const Text('Retire it — history keeps it'),
                        )
                      : TextButton(
                          onPressed: null,
                          child: Text(
                            'It still holds '
                            '${Inr.format(existing.balancePaise)} — '
                            'empty it first',
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
