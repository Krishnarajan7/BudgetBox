import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../icons.dart';
import '../inr.dart';
import '../tokens.dart';
import '../typography.dart';
import 'ledger_widgets.dart';
import 'motion.dart';
import 'sheets.dart';

/// The one account picker: ruled lines, kind marks, balances in mono, the
/// current choice wearing a quill tick. Returns the picked account, or null
/// if the sheet is let go.
Future<Account?> pickLedgerAccount(
  BuildContext context, {
  required List<Account> accounts,
  int? selectedId,
  String line = 'from which pocket?',
}) {
  return showLedgerSheet<Account>(
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
                padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x2),
                child: Text(
                  line,
                  style:
                      LedgerType.title.copyWith(fontSize: 18, color: c.ink),
                ),
              ),
              for (final (i, a) in accounts.indexed)
                InkIn(
                  delay: Duration(milliseconds: 24 * i),
                  child: LedgerLine(
                    mark: Icon(
                      LedgerIcons.account[a.kind.name] ??
                          LedgerIcons.fallback,
                      size: 15,
                      color: a.id == selectedId ? c.quill : c.inkFaint,
                    ),
                    title: a.name,
                    detail: a.id == selectedId ? 'in use' : null,
                    amount: Inr.format(a.balancePaise),
                    amountColor: c.inkFaint,
                    last: i == accounts.length - 1,
                    onTap: () => Navigator.of(context).pop(a),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
