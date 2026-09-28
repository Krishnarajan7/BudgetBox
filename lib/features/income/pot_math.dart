/// The pots: where the money came from, and what each has left.
///
/// An account says where the money *sits*; a pot says where it *came
/// from*. Salary and extra work land in the same GPay, but "don't touch
/// the salary" is a rule about pots, not pockets — so every expense names
/// the pot it drew on, and this file adds each pot up: in, out, kept.
library;

import '../../data/db.dart';

class PotLedger {
  const PotLedger({
    required this.categoryId,
    required this.name,
    required this.inPaise,
    required this.outPaise,
    required this.allInPaise,
    required this.allOutPaise,
  });

  final int categoryId;
  final String name;

  /// In the window being read.
  final int inPaise;
  final int outPaise;

  /// Since the book began.
  final int allInPaise;
  final int allOutPaise;

  int get keptPaise => inPaise - outPaise;
  int get allKeptPaise => allInPaise - allOutPaise;

  /// 0..1 of the window's income still unspent; 0 when nothing came in.
  double get keptShare =>
      inPaise <= 0 ? 0 : (keptPaise / inPaise).clamp(0.0, 1.0);
}

/// Expenses that never named a pot: count and total, in the window.
class Unassigned {
  const Unassigned(this.count, this.paise, this.ids);
  final int count;
  final int paise;
  final List<int> ids;
}

/// [window] and [all] are ledger lines, any type; [pots] are the income
/// categories, in shelf order. A pot with nothing in and nothing drawn,
/// ever, is left out — a category nobody has used is not a pot yet.
List<PotLedger> potLedgers(
  Iterable<Txn> window,
  Iterable<Txn> all,
  Iterable<Category> pots,
) {
  final out = <PotLedger>[];
  final w = window.toList();
  final a = all.toList();
  for (final p in pots) {
    if (p.kind != CategoryKind.income) continue;
    int sum(Iterable<Txn> rows, bool Function(Txn) test) =>
        rows.where(test).fold(0, (s, t) => s + t.amountPaise);
    bool income(Txn t) => t.type == TxnType.income && t.categoryId == p.id;
    bool drew(Txn t) => t.type == TxnType.expense && t.sourceId == p.id;
    final ledger = PotLedger(
      categoryId: p.id,
      name: p.name,
      inPaise: sum(w, income),
      outPaise: sum(w, drew),
      allInPaise: sum(a, income),
      allOutPaise: sum(a, drew),
    );
    if (ledger.allInPaise == 0 && ledger.allOutPaise == 0) continue;
    out.add(ledger);
  }
  return out;
}

Unassigned unassigned(Iterable<Txn> window) {
  final rows = [
    for (final t in window)
      if (t.type == TxnType.expense && t.sourceId == null) t,
  ];
  return Unassigned(rows.length, rows.fold(0, (s, t) => s + t.amountPaise), [
    for (final t in rows) t.id,
  ]);
}

/// The sentence under a pot: plain, and honest about an overdraw.
String potLine(PotLedger p) {
  if (p.inPaise == 0 && p.outPaise == 0) return 'nothing moved this window';
  if (p.inPaise == 0) return 'drawn on with nothing new in';
  if (p.keptPaise < 0) return 'spent past what came in';
  final pct = (p.keptShare * 100).round();
  return '$pct% of it still unspent';
}
