/// The arithmetic of freelance work — pure, no widgets, testable.
///
/// Two shapes of money the ledger alone loses: a quote that moves (50k,
/// then 40k when the scope shrank, then 55k when they added a page) and
/// costs a project causes that must not be forgotten when the invoice goes
/// out. This file turns a project, its quote history and its claimed
/// ledger lines into the few figures that matter, and into the sentences
/// worth putting in front of a client.
library;

import '../../data/db.dart';

/// A claimed ledger line with the entry it points at.
class ProjectLine {
  const ProjectLine({required this.link, required this.txn});

  final ProjectLink link;
  final Txn txn;

  bool get received => link.role == LinkRole.received;
  bool get cost => link.role == LinkRole.cost;
}

/// One retainer month: which month, and whether it was paid.
class RetainerMonth {
  const RetainerMonth({
    required this.month,
    required this.due,
    required this.paidPaise,
  });

  /// The first of the month.
  final DateTime month;

  /// When the retainer fell due that month.
  final DateTime due;
  final int paidPaise;
}

/// Everything the page and the notifications need to know about a
/// project, worked out once from its rows.
class ProjectSummary {
  const ProjectSummary({
    required this.project,
    required this.quotePaise,
    required this.firstQuotePaise,
    required this.receivedPaise,
    required this.costPaise,
    required this.billableCostPaise,
    required this.months,
    required this.owedPaise,
  });

  final Project project;

  /// The quote as it stands (for a retainer: the monthly figure).
  final int quotePaise;
  final int firstQuotePaise;
  final int receivedPaise;

  /// Every cost the project caused, in and out of the quote.
  final int costPaise;

  /// The costs that sat outside the quote — the ones to pass on.
  final int billableCostPaise;

  /// A retainer's months since it started, oldest first; empty for
  /// one-time work.
  final List<RetainerMonth> months;

  /// What the client still owes: the balance of the quote for one-time
  /// work, the unpaid months for a retainer — plus any cost to pass on.
  final int owedPaise;

  /// What is left after the project's own costs.
  int get marginPaise => receivedPaise - costPaise;

  bool get isRetainer => project.kind == ProjectKind.monthly;

  /// 0..1 of the quote received (one-time), or of the months paid.
  double get fraction {
    if (isRetainer) {
      if (months.isEmpty) return 0;
      final paid = months.where((m) => m.paidPaise >= quotePaise).length;
      return paid / months.length;
    }
    if (quotePaise <= 0) return receivedPaise > 0 ? 1 : 0;
    return (receivedPaise / quotePaise).clamp(0.0, 1.0);
  }

  /// Retainer months still unpaid, oldest first.
  List<RetainerMonth> get unpaidMonths => [
    for (final m in months)
      if (m.paidPaise < quotePaise) m,
  ];
}

/// The day a retainer falls due in [month] — the billing day, clamped to
/// the month's length; the 1st when none was chosen.
DateTime retainerDue(Project p, DateTime month) {
  final day = p.billingDay ?? 1;
  final last = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, day > last ? last : day);
}

/// The months a retainer has run: from the month it started through the
/// current month, each with what was received against it. A payment is
/// counted for the month it was received in.
List<RetainerMonth> retainerMonths(
  Project p,
  Iterable<ProjectLine> lines,
  DateTime now,
) {
  if (p.kind != ProjectKind.monthly) return const [];
  final start = DateTime(p.startedAt.year, p.startedAt.month, 1);
  final end = p.status == ProjectStatus.done || p.status == ProjectStatus.dropped
      ? start
      : DateTime(now.year, now.month, 1);
  final out = <RetainerMonth>[];
  for (var m = start; !m.isAfter(end); m = DateTime(m.year, m.month + 1, 1)) {
    var paid = 0;
    for (final l in lines) {
      if (!l.received) continue;
      if (l.txn.at.year == m.year && l.txn.at.month == m.month) {
        paid += l.txn.amountPaise;
      }
    }
    out.add(RetainerMonth(month: m, due: retainerDue(p, m), paidPaise: paid));
  }
  return out;
}

ProjectSummary summarise(
  Project p,
  List<QuoteRevision> revisions,
  List<ProjectLine> lines,
  DateTime now,
) {
  final sorted = [...revisions]..sort((a, b) => a.at.compareTo(b.at));
  final first = sorted.isEmpty ? p.quotePaise : sorted.first.paise;
  var received = 0;
  var costs = 0;
  var billable = 0;
  for (final l in lines) {
    if (l.received) {
      received += l.txn.amountPaise;
    } else {
      costs += l.txn.amountPaise;
      if (l.link.billable) billable += l.txn.amountPaise;
    }
  }
  final months = retainerMonths(p, lines, now);
  final int owed;
  if (p.kind == ProjectKind.monthly) {
    var unpaid = 0;
    for (final m in months) {
      // Only months whose due day has passed are owed; this month before
      // its day is upcoming, not late.
      if (m.due.isAfter(now)) continue;
      final short = p.quotePaise - m.paidPaise;
      if (short > 0) unpaid += short;
    }
    owed = unpaid + billable;
  } else {
    final balance = p.quotePaise - received;
    owed = (balance > 0 ? balance : 0) + billable;
  }
  return ProjectSummary(
    project: p,
    quotePaise: p.quotePaise,
    firstQuotePaise: first,
    receivedPaise: received,
    costPaise: costs,
    billableCostPaise: billable,
    months: months,
    owedPaise: owed,
  );
}

/// The lines to put in front of the client, in plain words: the balance
/// of the quote, the months unpaid, and every cost that sat outside the
/// quote. Nothing here is a guess; every rupee traces to a ledger line.
List<String> clientLines(ProjectSummary s, DateTime now) {
  final out = <String>[];
  String rs(int paise) => _rupees(paise);
  final p = s.project;
  if (s.isRetainer) {
    final late = [
      for (final m in s.unpaidMonths)
        if (!m.due.isAfter(now)) m,
    ];
    if (late.isNotEmpty) {
      final names = late.map((m) => _monthName(m.month)).join(', ');
      final total = late.fold(0, (t, m) => t + (s.quotePaise - m.paidPaise));
      out.add(
        late.length == 1
            ? '$names\'s retainer of ${rs(s.quotePaise)} is unpaid'
            : '${late.length} months unpaid ($names) — ${rs(total)} in all',
      );
    }
  } else {
    final balance = s.quotePaise - s.receivedPaise;
    if (balance > 0) {
      out.add(
        s.receivedPaise == 0
            ? 'nothing received yet against the ${rs(s.quotePaise)} quote'
            : '${rs(balance)} of the ${rs(s.quotePaise)} quote still to come',
      );
    } else if (balance < 0) {
      out.add('${rs(-balance)} received over the quote');
    }
    if (s.firstQuotePaise != s.quotePaise) {
      out.add(
        'quote moved from ${rs(s.firstQuotePaise)} to ${rs(s.quotePaise)}',
      );
    }
  }
  if (s.billableCostPaise > 0) {
    out.add(
      '${rs(s.billableCostPaise)} of costs outside the quote to pass on',
    );
  }
  if (out.isEmpty) {
    out.add(
      p.kind == ProjectKind.monthly
          ? 'every month paid, nothing to pass on'
          : 'settled in full, nothing to pass on',
    );
  }
  return out;
}

/// Retainers falling due on or before [on] in the current month that have
/// not been paid — what the morning notification names.
List<ProjectSummary> retainersDue(List<ProjectSummary> all, DateTime on) => [
  for (final s in all)
    if (s.isRetainer && s.project.status == ProjectStatus.active)
      if (s.months.isNotEmpty)
        if (s.months.last.paidPaise < s.quotePaise &&
            !s.months.last.due.isAfter(on))
          s,
];

String _rupees(int paise) {
  final r = paise ~/ 100;
  final s = r.toString();
  if (s.length <= 3) return '₹$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  parts.insert(0, rest);
  return '₹${parts.join(',')},$last3';
}

String _monthName(DateTime m) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][m.month - 1];
