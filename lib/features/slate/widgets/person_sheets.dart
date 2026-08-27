import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/inr.dart';
import '../../../core/tokens.dart';
import '../../../core/typography.dart';
import '../../../core/widgets/ledger_widgets.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/pickers.dart';
import '../../../core/widgets/sheets.dart';
import '../../../data/api/endpoints/endpoints.dart';
import '../../../data/db.dart';
import '../../../data/providers.dart';
import '../../../data/sync/ids.dart';
import '../slate_page.dart';
import '../slate_providers.dart';

/// Which way the money goes.
enum MoveKind {
  /// Out to them.
  lend,

  /// Back — from them if they owed you, from you if you owed them. The
  /// server works out which; the sheet only needs to know it is a return.
  back,

  /// In from them, because you needed it.
  borrow,
}

/// New name on the slate.
Future<void> addPersonSheet(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final relation = TextEditingController();
  final saved = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => _Sheet(
      title: 'who?',
      fields: [
        _Field(controller: name, hint: 'name', autofocus: true),
        const SizedBox(height: Gap.x3),
        _Field(controller: relation, hint: 'sister, college, work — optional'),
      ],
      confirm: 'put them on the slate',
      onConfirm: () async {
        if (name.text.trim().isEmpty) return false;
        await ref
            .read(slateWriterProvider)
            .addPerson(
              newUuid7(),
              PersonIn(
                name: name.text.trim(),
                relation: relation.text.trim().isEmpty
                    ? null
                    : relation.text.trim(),
              ),
            );
        return true;
      },
    ),
  );
  name.dispose();
  relation.dispose();
  if (saved ?? false) ref.invalidate(slateGateProvider);
}

/// Money moving, in either direction. The amount is pre-filled with the
/// standing balance on a return, because paying the whole thing back is the
/// commonest single act — and freely editable, because paying part of it is
/// the commonest thing overall.
Future<void> moveSheet(
  BuildContext context,
  WidgetRef ref, {
  required SlatePerson person,
  required MoveKind move,
}) async {
  final standing = person.balancePaise.abs();
  final amount = TextEditingController(
    text: move == MoveKind.back && standing > 0
        ? (standing / 100).toStringAsFixed(0)
        : '',
  );
  final note = TextEditingController();
  var account = await _defaultAccount(ref);
  var at = DateTime.now();
  if (!context.mounted) return;

  final done = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => _Sheet(
        title: switch (move) {
          MoveKind.lend => 'lent ${person.name}',
          MoveKind.back => person.owesYou
              ? '${person.name} paid back'
              : 'you paid ${person.name} back',
          MoveKind.borrow => 'borrowed from ${person.name}',
        },
        fields: [
          _Field(
            controller: amount,
            hint: '₹',
            autofocus: true,
            number: true,
          ),
          const SizedBox(height: Gap.x3),
          _Row(
            label: move == MoveKind.borrow || move == MoveKind.back
                ? 'into'
                : 'from',
            value: account?.name ?? 'pick a pocket',
            onTap: () async {
              final accounts = await ref
                  .read(accountRepoProvider)
                  .watchAll()
                  .first;
              if (!sheet.mounted) return;
              final picked = await pickLedgerAccount(
                sheet,
                accounts: accounts,
                selectedId: account?.id,
              );
              if (picked != null) setSheet(() => account = picked);
            },
          ),
          _Row(
            label: 'when',
            value: slateDateWord(at),
            onTap: () async {
              final picked = await showDatePicker(
                context: sheet,
                initialDate: at,
                firstDate: DateTime(2015),
                lastDate: DateTime.now(),
              );
              if (picked != null) setSheet(() => at = picked);
            },
          ),
          const SizedBox(height: Gap.x3),
          _Field(controller: note, hint: 'what for — optional'),
        ],
        confirm: switch (move) {
          MoveKind.lend => 'put it on the slate',
          MoveKind.back => 'take it off the slate',
          MoveKind.borrow => 'note it down',
        },
        onConfirm: () async {
          final rupees = int.tryParse(amount.text.trim());
          final pocket = account;
          if (rupees == null || rupees <= 0 || pocket == null) return false;
          // The slate speaks the server's uuids; the phone's pockets are
          // row numbers. The bridge is the same one sync uses.
          final remote = await SyncIds(
            ref.read(dbProvider),
          ).remoteFor(SyncKinds.account, pocket.id);
          if (remote == null) return false;
          final body = MoveIn(
            amountPaise: rupees * 100,
            accountId: remote,
            at: at,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
          final writer = ref.read(slateWriterProvider);
          switch (move) {
            case MoveKind.lend:
              await writer.lend(person.id, body);
            case MoveKind.back:
              await writer.repay(person.id, body);
            case MoveKind.borrow:
              await writer.borrow(person.id, body);
          }
          return true;
        },
      ),
    ),
  );
  amount.dispose();
  note.dispose();
  if (done ?? false) _refresh(ref, person.id);
}

/// The honest exit. It becomes an expense today — not on the day the money
/// left — and stays on the record as let go rather than being erased.
Future<void> letGoSheet(
  BuildContext context,
  WidgetRef ref, {
  required SlatePerson person,
}) async {
  final done = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => _Sheet(
      title: person.owesYou ? 'let it go?' : 'they let it go?',
      fields: [
        Text(
          person.owesYou
              ? '${Inr.format(person.balancePaise.abs())} stops being money '
                    'you are waiting for and becomes money you spent — '
                    'dated today, because that is when you decided. It stays '
                    'on the slate as let go; nothing is erased.'
              : '${Inr.format(person.balancePaise.abs())} you owed becomes '
                    'yours. It lands as income today and the slate closes.',
          style: LedgerType.bodyText.copyWith(
            fontSize: 14,
            height: 1.5,
            color: LedgerColors.of(sheet).inkFaint,
          ),
        ),
      ],
      confirm: person.owesYou ? 'let it go' : 'close it',
      destructive: true,
      onConfirm: () async {
        await ref.read(slateWriterProvider).close(person.id);
        return true;
      },
    ),
  );
  if (done ?? false) _refresh(ref, person.id);
}

/// The backfill door: an expense already in the book that was really a loan.
/// Picking it converts that line into a transfer instead of writing a second
/// one beside it, so nothing is counted twice.
Future<void> adoptSheet(
  BuildContext context,
  WidgetRef ref, {
  required SlatePerson person,
}) async {
  final done = await showLedgerSheet<bool>(
    context,
    builder: (sheet) => Consumer(
      builder: (sheet, ref, _) {
        final c = LedgerColors.of(sheet);
        final list = ref.watch(adoptableProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Gap.page,
              0,
              Gap.page,
              Gap.x4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.x2),
                  child: Text(
                    'which line was really a loan?',
                    style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
                  ),
                ),
                Text(
                  'It moves onto the slate instead of staying as spending — '
                  'the month gets more honest, and nothing is counted twice.',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    height: 1.45,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(height: Gap.x3),
                Flexible(
                  child: list.when(
                    loading: () => const SizedBox(height: 80),
                    error: (_, _) => Text(
                      'could not read the book',
                      style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                    ),
                    data: (rows) => rows.isEmpty
                        ? Text(
                            'no spending left to move.',
                            style: LedgerType.bodyText.copyWith(
                              color: c.inkFaint,
                            ),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final (i, a) in rows.indexed)
                                LedgerLine(
                                  leading: slateDateWord(a.at),
                                  title: a.title,
                                  amount: Inr.format(a.amountPaise),
                                  last: i == rows.length - 1,
                                  onTap: () async {
                                    await ref
                                        .read(slateWriterProvider)
                                        .adopt(person.id, a.txnId);
                                    if (sheet.mounted) {
                                      Navigator.of(sheet).pop(true);
                                    }
                                  },
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (done ?? false) {
    ref.invalidate(adoptableProvider);
    _refresh(ref, person.id);
  }
}

void _refresh(WidgetRef ref, String personId) {
  ref.invalidate(slatePersonProvider(personId));
  ref.invalidate(slateGateProvider);
}

Future<Account?> _defaultAccount(WidgetRef ref) async {
  final accounts = await ref.read(accountRepoProvider).watchAll().first;
  return accounts.isEmpty ? null : accounts.first;
}

// ————— the sheet's furniture —————

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.title,
    required this.fields,
    required this.confirm,
    required this.onConfirm,
    this.destructive = false,
  });

  final String title;
  final List<Widget> fields;
  final String confirm;

  /// Returns true when the write landed; false leaves the sheet open.
  final Future<bool> Function() onConfirm;
  final bool destructive;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _busy = false;
  String? _problem;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final ok = await widget.onConfirm();
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _problem = 'check the amount and the pocket');
    } catch (_) {
      if (mounted) setState(() => _problem = 'the server would not take it');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.page,
          0,
          Gap.page,
          Gap.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x4),
              child: Text(
                widget.title,
                style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
              ),
            ),
            ...widget.fields,
            if (_problem != null) ...[
              const SizedBox(height: Gap.x3),
              Text(
                _problem!,
                style: LedgerType.label.copyWith(color: c.seal),
              ),
            ],
            const SizedBox(height: Gap.x4),
            Pressable(
              onTap: _busy ? null : _go,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                decoration: BoxDecoration(
                  color: widget.destructive ? c.paperRaised : c.quill,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.destructive ? c.seal : c.quill,
                    width: 0.75,
                  ),
                ),
                child: Center(
                  child: Text(
                    _busy ? 'writing…' : widget.confirm,
                    style: LedgerType.bodyStrong.copyWith(
                      color: widget.destructive ? c.seal : c.paper,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.autofocus = false,
    this.number = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final bool number;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      style: number
          ? LedgerType.heroAmount.copyWith(fontSize: 32, color: c.ink)
          : LedgerType.bodyText.copyWith(color: c.ink),
      cursorColor: c.quill,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: (number
                ? LedgerType.heroAmount.copyWith(fontSize: 32)
                : LedgerType.bodyText)
            .copyWith(color: c.inkFaint),
        isDense: true,
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.rule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        child: Row(
          children: [
            Text(label, style: LedgerType.label.copyWith(color: c.inkFaint)),
            const Spacer(),
            Text(value, style: LedgerType.bodyStrong.copyWith(color: c.ink)),
          ],
        ),
      ),
    );
  }
}
