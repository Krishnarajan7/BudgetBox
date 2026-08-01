import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/db.dart';
import '../../data/providers.dart';

/// An account may retire only once it holds nothing — an archived account
/// with money in it would make the net worth lie.
bool canRetireAccount(int balancePaise) => balancePaise == 0;

String _kindLabel(AccountKind kind) =>
    kind == AccountKind.upi ? 'UPI' : kind.name;

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

  Future<void> _openSheet({Account? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AccountSheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(accountRepoProvider);

    return ModuleScaffold(
      title: 'Accounts',
      trailing: InkWell(
        onTap: () => _openSheet(),
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: Icon(Icons.add, size: 20, color: c.inkFaint),
        ),
      ),
      child: StreamBuilder<List<Account>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          final accounts = snapshot.data ?? const <Account>[];
          final fresh = <int>{
            if (_primed)
              for (final a in accounts)
                if (!_seen.contains(a.id)) a.id,
          };
          if (snapshot.hasData) {
            _primed = true;
            _seen.addAll(accounts.map((a) => a.id));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const SizedBox(height: Gap.x3),
              if (snapshot.hasData && accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x8),
                  child: Text(
                    'No accounts yet. The book needs somewhere '
                    'for the money to sit.',
                    style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  ),
                )
              else
                for (final a in accounts)
                  _Entrance(
                    key: ValueKey('acct-${a.id}'),
                    animate: fresh.contains(a.id),
                    child: _AccountRow(
                      account: a,
                      onTap: () => _openSheet(existing: a),
                    ),
                  ),
              const SizedBox(height: Gap.x4),
              if (accounts.isNotEmpty)
                Text(
                  'Balances move with the book. Tap a line to rename it '
                  'or change what kind of thing it is.',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 12, color: c.inkFaint),
                ),
              const SizedBox(height: Gap.x8),
            ],
          );
        },
      ),
    );
  }
}

/// One ruled line: the kind's mark, the name over a faint kind label,
/// the balance in mono holding the right edge.
class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.account, required this.onTap});

  final Account account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Icon(
              LedgerIcons.account[account.kind.name] ?? LedgerIcons.fallback,
              size: 16,
              color: c.inkFaint,
            ),
            const SizedBox(width: Gap.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: LedgerType.bodyText.copyWith(color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _kindLabel(account.kind),
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 11, color: c.inkFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.x2),
            Text(
              Inr.format(account.balancePaise),
              style: LedgerType.amount.copyWith(color: c.ink),
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

  Future<void> _retire() async {
    final existing = widget.existing;
    if (existing == null || !canRetireAccount(existing.balancePaise)) return;
    HapticFeedback.mediumImpact();
    final db = ref.read(dbProvider);
    await (db.update(db.accounts)..where((a) => a.id.equals(existing.id)))
        .write(const AccountsCompanion(archived: Value(true)));
    if (mounted) Navigator.of(context).pop();
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
        top: Gap.x4,
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
                  'opening balance',
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
                      prefixText: '₹',
                      prefixStyle: LedgerType.amountTotal
                          .copyWith(fontSize: 22, color: c.inkFaint),
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
                builder: (context, value, _) => FilledButton(
                  onPressed: value.text.trim().isEmpty ? null : _keep,
                  child: const Text('Keep it'),
                ),
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

/// Fade + small slide for a line that has just been written.
class _Entrance extends StatelessWidget {
  const _Entrance({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
