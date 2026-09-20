import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/plates.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/repos/work_repo.dart';
import '../book/txn_editor.dart';
import '../today/widgets/digit_roll.dart';
import '../today/widgets/ledger_rows.dart';
import 'work_math.dart';

/// One project, read in full: the quote and how it moved, what the client
/// has paid, what the work cost and which of that to pass on, and the
/// plain lines to put in front of the client so nothing is argued later.
class ProjectPage extends ConsumerStatefulWidget {
  const ProjectPage({super.key, required this.projectId});

  final int projectId;

  @override
  ConsumerState<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends ConsumerState<ProjectPage> {
  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(workRepoProvider);
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: StreamBuilder<Project?>(
          stream: repo.watchProject(widget.projectId),
          builder: (context, projSnap) {
            final p = projSnap.data;
            if (p == null) return const SizedBox.shrink();
            return StreamBuilder<List<QuoteRevision>>(
              stream: repo.watchRevisions(p.id),
              builder: (context, revSnap) {
                final revs = revSnap.data ?? const <QuoteRevision>[];
                return StreamBuilder<List<ProjectLine>>(
                  stream: repo.watchLines(p.id),
                  builder: (context, lineSnap) {
                    final lines = lineSnap.data ?? const <ProjectLine>[];
                    return StreamBuilder<List<Client>>(
                      stream: repo.watchClients(),
                      builder: (context, clientSnap) {
                        final client = (clientSnap.data ?? const <Client>[])
                            .where((x) => x.id == p.clientId)
                            .firstOrNull;
                        final s = summarise(p, revs, lines, now);
                        return _page(c, p, client, s, revs, lines, now);
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _page(
    LedgerColors c,
    Project p,
    Client? client,
    ProjectSummary s,
    List<QuoteRevision> revs,
    List<ProjectLine> lines,
    DateTime now,
  ) {
    final received = [for (final l in lines) if (l.received) l];
    final costs = [for (final l in lines) if (l.cost) l];
    final faint = LedgerType.bodyText.copyWith(fontSize: 12.5, color: c.inkFaint, height: 1.4);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        MediaQuery.paddingOf(context).bottom + Gap.x8,
      ),
      children: [
        // ————— the bar —————
        Padding(
          padding: const EdgeInsets.only(top: Gap.x2),
          child: Row(
            children: [
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, Gap.x2, Gap.x3, Gap.x2),
                  child: RotatedBox(
                    quarterTurns: 2,
                    child: PenChevron(size: 16, color: c.ink),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
                    ),
                    Text(
                      '${client?.name ?? '—'} · '
                      '${s.isRetainer ? 'every month, the ${_ordinal(p.billingDay ?? 1)}' : 'one-time'}'
                      ' · since ${LedgerDates.ddMmm(p.startedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Gap.x3),
        PillSegments(
          labels: const ['quoted', 'active', 'done', 'dropped'],
          index: p.status.index,
          onSelect: (i) => ref
              .read(workRepoProvider)
              .setStatus(p.id, ProjectStatus.values[i]),
          height: 30,
        ),
        const SizedBox(height: Gap.x6),
        // ————— the quote —————
        Text(
          s.isRetainer ? 'a month' : 'the quote',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DigitRoll(
              paise: s.quotePaise,
              style: LedgerType.heroAmount.copyWith(
                fontSize: 40,
                color: c.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            Pressable(
              key: const ValueKey('project-revise'),
              onTap: () => _revise(p),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'revise ›',
                  style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill),
                ),
              ),
            ),
          ],
        ),
        if (s.firstQuotePaise != s.quotePaise)
          Text(
            'first quoted ${Inr.format(s.firstQuotePaise)} · '
            '${revs.length - 1} ${revs.length - 1 == 1 ? 'change' : 'changes'} since',
            style: faint,
          ),
        StatTiles(
          tiles: [
            StatTile(
              label: 'received',
              value: Inr.compact(s.receivedPaise),
              tone: c.jama,
              sub: received.isEmpty
                  ? 'nothing yet'
                  : '${received.length} ${received.length == 1 ? 'payment' : 'payments'}',
            ),
            StatTile(
              label: 'owed',
              value: s.owedPaise > 0 ? Inr.compact(s.owedPaise) : 'settled',
              tone: s.owedPaise > 0 ? c.ink : c.inkFaint,
              sub: s.billableCostPaise > 0
                  ? 'incl. ${Inr.compact(s.billableCostPaise)} to pass on'
                  : (s.isRetainer ? 'unpaid months' : 'of the quote'),
            ),
            StatTile(
              label: 'costs',
              value: Inr.compact(s.costPaise),
              tone: s.costPaise > 0 ? c.ink : c.inkFaint,
              sub: s.costPaise == 0
                  ? 'none yet'
                  : 'kept ${Inr.compact(s.marginPaise)}',
            ),
          ],
        ),
        // ————— for the client —————
        const SectionHead('for the client'),
        Plate(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in clientLines(s, now))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    line,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13.5,
                      color: c.ink,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ————— retainer months —————
        if (s.isRetainer && s.months.isNotEmpty) ...[
          const SectionHead('month by month'),
          for (final m in s.months.reversed)
            PlateRow(
              leading: Medallion(
                icon: m.paidPaise >= s.quotePaise
                    ? Icons.check_rounded
                    : m.due.isAfter(now)
                    ? Icons.schedule_rounded
                    : Icons.priority_high_rounded,
                ink: m.paidPaise >= s.quotePaise
                    ? c.jama
                    : m.due.isAfter(now)
                    ? c.inkFaint
                    : c.warn,
                size: 32,
                iconSize: 15,
              ),
              title: LedgerDates.monthsFull[m.month.month - 1],
              sub: m.paidPaise >= s.quotePaise
                  ? 'paid'
                  : m.due.isAfter(now)
                  ? 'due ${LedgerDates.ddMmm(m.due)}'
                  : 'was due ${LedgerDates.ddMmm(m.due)}',
              amount: Inr.format(m.paidPaise),
              amountColor: m.paidPaise >= s.quotePaise ? c.jama : c.inkFaint,
              dense: true,
            ),
        ],
        // ————— received —————
        SectionHead(
          'received',
          trailing: Text(
            Inr.format(s.receivedPaise),
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
          ),
        ),
        for (final l in received)
          PlateRow(
            key: ValueKey('line-${l.link.id}'),
            leading: Medallion(icon: Icons.south_west_rounded, ink: c.jama, size: 32, iconSize: 15),
            title: l.txn.title,
            sub: LedgerDates.ddMmm(l.txn.at),
            amount: Inr.format(l.txn.amountPaise, signed: true),
            amountColor: c.jama,
            dense: true,
            onTap: () => showTxnEditor(context, l.txn),
            onLongPress: () => _detach(l),
          ),
        _doors(c, [
          ('write a payment', 'project-receive', () => _write(p, LinkRole.received)),
          ('attach a line', 'project-attach-received', () => _attach(p, LinkRole.received)),
        ]),
        // ————— costs —————
        SectionHead(
          'costs',
          trailing: Text(
            Inr.format(s.costPaise),
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
          ),
        ),
        for (final l in costs)
          PlateRow(
            key: ValueKey('line-${l.link.id}'),
            leading: Medallion(
              icon: Icons.north_east_rounded,
              ink: l.link.billable ? c.warn : c.inkFaint,
              size: 32,
              iconSize: 15,
            ),
            title: l.txn.title,
            sub: LedgerDates.ddMmm(l.txn.at),
            amount: Inr.format(l.txn.amountPaise),
            trailing: Pressable(
              key: ValueKey('billable-${l.link.id}'),
              haptic: false,
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(workRepoProvider).setBillable(l.link.id, !l.link.billable);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (l.link.billable ? c.warn : c.inkFaint).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l.link.billable ? 'pass on' : 'in quote',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 11,
                    color: l.link.billable ? c.warn : c.inkFaint,
                  ),
                ),
              ),
            ),
            dense: true,
            onTap: () => showTxnEditor(context, l.txn),
            onLongPress: () => _detach(l),
          ),
        _doors(c, [
          ('write a cost', 'project-spend', () => _write(p, LinkRole.cost)),
          ('attach a line', 'project-attach-cost', () => _attach(p, LinkRole.cost)),
        ]),
        // ————— the quote's history —————
        if (revs.length > 1) ...[
          const SectionHead('how the quote moved'),
          for (final r in revs.reversed)
            PlateRow(
              title: Inr.format(r.paise),
              sub: '${LedgerDates.ddMmm(r.at)}${r.reason == null ? '' : ' · ${r.reason}'}',
              dense: true,
            ),
        ],
        if (p.note != null && p.note!.trim().isNotEmpty) ...[
          const SectionHead('scope'),
          Text(p.note!, style: LedgerType.bodyText.copyWith(fontSize: 13.5, color: c.ink, height: 1.45)),
        ],
      ],
    );
  }

  Widget _doors(LedgerColors c, List<(String, String, VoidCallback)> doors) {
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        children: [
          for (final (i, (label, key, go)) in doors.indexed) ...[
            if (i > 0) const SizedBox(width: Gap.x4),
            Pressable(
              key: ValueKey(key),
              onTap: go,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill),
                  ),
                  const SizedBox(width: 3),
                  PenChevron(size: 11, color: c.quill),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _revise(Project p) async {
    final result = await showLedgerSheet<(int, String?)>(
      context,
      builder: (_) => _ReviseSheet(current: p.quotePaise, retainer: p.kind == ProjectKind.monthly),
    );
    if (result == null || !mounted) return;
    await ref.read(workRepoProvider).reviseQuote(p.id, result.$1, reason: result.$2);
  }

  Future<void> _write(Project p, LinkRole role) async {
    final db = ref.read(dbProvider);
    final accounts =
        await (db.select(db.accounts)
              ..where((a) => a.archived.equals(false))
              ..orderBy([(a) => OrderingTerm.asc(a.sortOrder)]))
            .get();
    final cats =
        await (db.select(db.categories)..where(
              (x) => x.kind.equalsValue(
                role == LinkRole.received ? CategoryKind.income : CategoryKind.expense,
              ),
            ))
            .get();
    if (!mounted || accounts.isEmpty) return;
    final made = await showLedgerSheet<_Written>(
      context,
      builder: (_) => _WriteSheet(role: role, accounts: accounts, categories: cats),
    );
    if (made == null || !mounted) return;
    final repo = ref.read(workRepoProvider);
    if (role == LinkRole.received) {
      await repo.receive(
        p.id,
        amountPaise: made.paise,
        accountId: made.accountId,
        title: made.title,
        categoryId: made.categoryId,
      );
    } else {
      await repo.spend(
        p.id,
        amountPaise: made.paise,
        accountId: made.accountId,
        title: made.title,
        categoryId: made.categoryId,
        billable: made.billable,
      );
    }
  }

  Future<void> _attach(Project p, LinkRole role) async {
    final repo = ref.read(workRepoProvider);
    final candidates = await repo.unclaimed(
      role == LinkRole.received ? TxnType.income : TxnType.expense,
    );
    if (!mounted) return;
    final picked = await showLedgerSheet<Txn>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
                child: Text(
                  role == LinkRole.received ? 'which payment?' : 'which cost?',
                  style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
                ),
              ),
              Flexible(
                child: candidates.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Gap.page),
                        child: Text(
                          'every line of the last three months is already claimed',
                          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, Gap.x6),
                        children: [
                          for (final t in candidates)
                            PlateRow(
                              key: ValueKey('attach-${t.id}'),
                              title: t.title,
                              sub: LedgerDates.ddMmm(t.at),
                              amount: Inr.format(t.amountPaise),
                              dense: true,
                              onTap: () => Navigator.of(context).pop(t),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    HapticFeedback.mediumImpact();
    await repo.attach(p.id, picked.id, role: role);
  }

  Future<void> _detach(ProjectLine l) async {
    HapticFeedback.mediumImpact();
    await ref.read(workRepoProvider).detach(l.link.id);
  }
}

String _ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

/// The quote moved: the new figure and, in a line, why.
class _ReviseSheet extends StatefulWidget {
  const _ReviseSheet({required this.current, required this.retainer});

  final int current;
  final bool retainer;

  @override
  State<_ReviseSheet> createState() => _ReviseSheetState();
}

class _ReviseSheetState extends State<_ReviseSheet> {
  late final _amount = TextEditingController(text: '${widget.current ~/ 100}');
  final _reason = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  int? get _paise {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return v == null || v < 0 ? null : (v * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final paise = _paise;
    final delta = paise == null ? null : paise - widget.current;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        MediaQuery.viewInsetsOf(context).bottom + Gap.x6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: Gap.x2),
          Text(
            widget.retainer ? 'The retainer moved' : 'The quote moved',
            style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'the old figure stays in the history, with the reason',
            style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
          ),
          const SizedBox(height: Gap.x4),
          TextField(
            key: const ValueKey('revise-amount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            style: LedgerType.heroAmount.copyWith(fontSize: 34, color: c.ink),
            cursorColor: c.quill,
            decoration: InputDecoration(
              prefixText: '₹',
              prefixStyle: LedgerType.heroAmount.copyWith(fontSize: 34, color: c.inkFaint),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          if (delta != null && delta != 0)
            Text(
              '${delta > 0 ? 'up' : 'down'} ${Inr.format(delta.abs())} from ${Inr.format(widget.current)}',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: delta > 0 ? c.jama : c.inkFaint,
              ),
            ),
          const SizedBox(height: Gap.x3),
          TextField(
            key: const ValueKey('revise-reason'),
            controller: _reason,
            textCapitalization: TextCapitalization.sentences,
            style: LedgerType.bodyText.copyWith(fontSize: 15, color: c.ink),
            cursorColor: c.quill,
            decoration: InputDecoration(
              hintText: 'why — scope cut, an extra page, a discount',
              hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
              isDense: true,
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.quill, width: 2),
              ),
            ),
          ),
          const SizedBox(height: Gap.x6),
          Pressable(
            key: const ValueKey('revise-save'),
            onTap: paise == null || paise == widget.current
                ? null
                : () => Navigator.of(context).pop((paise, _reason.text)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: paise == null || paise == widget.current ? c.rule : c.quill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'write it down',
                textAlign: TextAlign.center,
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 15,
                  color: paise == null || paise == widget.current ? c.inkFaint : c.paper,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Written {
  const _Written({
    required this.paise,
    required this.title,
    required this.accountId,
    this.categoryId,
    this.billable = false,
  });

  final int paise;
  final String title;
  final int accountId;
  final int? categoryId;
  final bool billable;
}

/// A payment received or a cost caused, written straight into the ledger
/// and claimed by the project in the same breath.
class _WriteSheet extends StatefulWidget {
  const _WriteSheet({
    required this.role,
    required this.accounts,
    required this.categories,
  });

  final LinkRole role;
  final List<Account> accounts;
  final List<Category> categories;

  @override
  State<_WriteSheet> createState() => _WriteSheetState();
}

class _WriteSheetState extends State<_WriteSheet> {
  final _amount = TextEditingController();
  final _title = TextEditingController();
  late int _accountId = widget.accounts.first.id;
  int? _categoryId;
  bool _billable = false;

  @override
  void initState() {
    super.initState();
    // A sensible default category: the one whose name says what this is.
    final want = widget.role == LinkRole.received ? 'extra' : 'bills';
    for (final c in widget.categories) {
      if (c.name.toLowerCase().contains(want)) _categoryId = c.id;
    }
    _categoryId ??= widget.categories.firstOrNull?.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    super.dispose();
  }

  int? get _paise {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return v == null || v <= 0 ? null : (v * 100).round();
  }

  bool get _ready => _paise != null && _title.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final cost = widget.role == LinkRole.cost;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        MediaQuery.viewInsetsOf(context).bottom + Gap.x6,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              cost ? 'A cost the project caused' : 'The client paid',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: Gap.x3),
            TextField(
              key: const ValueKey('write-amount'),
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: LedgerType.heroAmount.copyWith(fontSize: 34, color: c.ink),
              cursorColor: c.quill,
              decoration: InputDecoration(
                prefixText: '₹',
                prefixStyle: LedgerType.heroAmount.copyWith(fontSize: 34, color: c.inkFaint),
                hintText: '0',
                hintStyle: LedgerType.heroAmount.copyWith(
                  fontSize: 34,
                  color: c.inkFaint.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            TextField(
              key: const ValueKey('write-title'),
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: LedgerType.bodyText.copyWith(fontSize: 15, color: c.ink),
              cursorColor: c.quill,
              decoration: InputDecoration(
                hintText: cost ? 'server, domain, the mail plan' : 'advance, second half, September',
                hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                isDense: true,
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: c.quill, width: 2),
                ),
              ),
            ),
            const SizedBox(height: Gap.x4),
            Text(
              cost ? 'paid from' : 'landed in',
              style: LedgerType.label.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: Gap.x4,
              runSpacing: Gap.x2,
              children: [
                for (final a in widget.accounts)
                  QuillTab(
                    a.name,
                    icon: LedgerIcons.account[a.kind.name],
                    selected: _accountId == a.id,
                    onTap: () => setState(() => _accountId = a.id),
                  ),
              ],
            ),
            if (widget.categories.length > 1) ...[
              const SizedBox(height: Gap.x3),
              Text('filed under', style: LedgerType.label.copyWith(color: c.inkFaint)),
              const SizedBox(height: 4),
              Wrap(
                spacing: Gap.x4,
                runSpacing: Gap.x2,
                children: [
                  for (final x in widget.categories)
                    QuillTab(
                      x.name.split(' ').first.toLowerCase(),
                      icon: LedgerIcons.resolve(x.icon),
                      selected: _categoryId == x.id,
                      onTap: () => setState(() => _categoryId = x.id),
                    ),
                ],
              ),
            ],
            if (cost) ...[
              const SizedBox(height: Gap.x4),
              PillSegments(
                labels: const ['inside the quote', 'pass on to the client'],
                index: _billable ? 1 : 0,
                onSelect: (i) => setState(() => _billable = i == 1),
                height: 32,
              ),
            ],
            const SizedBox(height: Gap.x6),
            Pressable(
              key: const ValueKey('write-save'),
              onTap: _ready
                  ? () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(context).pop(
                        _Written(
                          paise: _paise!,
                          title: _title.text.trim(),
                          accountId: _accountId,
                          categoryId: _categoryId,
                          billable: _billable,
                        ),
                      );
                    }
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _ready ? c.quill : c.rule,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'write it',
                  textAlign: TextAlign.center,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 15,
                    color: _ready ? c.paper : c.inkFaint,
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
