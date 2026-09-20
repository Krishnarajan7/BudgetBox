import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/plates.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/repos/work_repo.dart';
import '../today/widgets/digit_roll.dart';
import '../today/widgets/ledger_rows.dart';
import 'project_page.dart';
import 'work_math.dart';

/// The work book: every client, every project, every rupee they touch.
///
/// The page leads with what the work brought in this month, then the three
/// answers a freelancer actually checks — what clients still owe, what has
/// to be passed on, which retainers are due — and then the projects, each
/// as a plate that says how far along the money is.
class WorkPage extends ConsumerWidget {
  const WorkPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(workRepoProvider);
    final now = DateTime.now();
    return ModuleScaffold(
      title: 'Work',
      trailing: Pressable(
        key: const ValueKey('work-new'),
        onTap: () => showNewProjectSheet(context),
        child: Text(
          'new project ›',
          style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill),
        ),
      ),
      child: StreamBuilder<List<Project>>(
        stream: repo.watchProjects(),
        builder: (context, projSnap) {
          final projects = projSnap.data ?? const <Project>[];
          if (projSnap.hasData && projects.isEmpty) {
            return EmptyPage(
              line: 'No work on the books yet.',
              sub:
                  'A client, a project, what you quoted — and from then on '
                  'every payment and every cost it causes has a home.',
              action: Pressable(
                key: const ValueKey('work-first'),
                onTap: () => showNewProjectSheet(context),
                child: Text(
                  'add the first project ›',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: c.quill,
                  ),
                ),
              ),
            );
          }
          return StreamBuilder<List<Client>>(
            stream: repo.watchClients(),
            builder: (context, clientSnap) {
              final clients = {
                for (final x in clientSnap.data ?? const <Client>[]) x.id: x,
              };
              return StreamBuilder<List<ProjectLine>>(
                stream: repo.watchAllLines(),
                builder: (context, lineSnap) {
                  final lines = lineSnap.data ?? const <ProjectLine>[];
                  return StreamBuilder<List<QuoteRevision>>(
                    stream: repo.watchAllRevisions(),
                    builder: (context, revSnap) {
                      final revs = revSnap.data ?? const <QuoteRevision>[];
                      final summaries = [
                        for (final p in projects)
                          summarise(
                            p,
                            [for (final r in revs) if (r.projectId == p.id) r],
                            [for (final l in lines) if (l.link.projectId == p.id) l],
                            now,
                          ),
                      ];
                      return _body(context, c, summaries, clients, lines, now);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    LedgerColors c,
    List<ProjectSummary> summaries,
    Map<int, Client> clients,
    List<ProjectLine> lines,
    DateTime now,
  ) {
    final thisMonth = lines
        .where(
          (l) =>
              l.received &&
              l.txn.at.year == now.year &&
              l.txn.at.month == now.month,
        )
        .fold(0, (s, l) => s + l.txn.amountPaise);
    final live = [
      for (final s in summaries)
        if (s.project.status == ProjectStatus.active ||
            s.project.status == ProjectStatus.quoted)
          s,
    ];
    final finished = [
      for (final s in summaries)
        if (s.project.status == ProjectStatus.done ||
            s.project.status == ProjectStatus.dropped)
          s,
    ];
    final owed = live.fold(0, (s, p) => s + p.owedPaise);
    final passOn = live.fold(0, (s, p) => s + p.billableCostPaise);
    final due = retainersDue(live, now);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        Gap.x3,
        Gap.page,
        MediaQuery.paddingOf(context).bottom + Gap.x8,
      ),
      children: [
        Text(
          'brought in, ${LedgerDates.monthsFull[now.month - 1].toLowerCase()}',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        DigitRoll(
          paise: thisMonth,
          style: LedgerType.heroAmount.copyWith(
            fontSize: 44,
            color: c.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        StatTiles(
          tiles: [
            StatTile(
              label: 'clients owe',
              value: Inr.compact(owed),
              tone: owed > 0 ? c.ink : c.inkFaint,
              sub: live.isEmpty
                  ? 'nothing open'
                  : '${live.length} ${live.length == 1 ? 'project' : 'projects'} open',
            ),
            StatTile(
              label: 'to pass on',
              value: Inr.compact(passOn),
              tone: passOn > 0 ? c.warn : c.inkFaint,
              sub: passOn > 0 ? 'costs outside quotes' : 'nothing outside a quote',
            ),
            StatTile(
              label: 'retainers due',
              value: due.isEmpty ? 'none' : '${due.length}',
              tone: due.isEmpty ? c.inkFaint : c.ink,
              sub: due.isEmpty
                  ? 'all paid this month'
                  : Inr.compact(
                      due.fold(0, (s, p) => s + (p.quotePaise - p.months.last.paidPaise)),
                    ),
            ),
          ],
        ),
        if (live.isNotEmpty) ...[
          const SectionHead('on the books'),
          for (final s in live)
            _ProjectPlate(
              key: ValueKey('project-${s.project.id}'),
              summary: s,
              client: clients[s.project.clientId]?.name ?? '—',
              now: now,
            ),
        ],
        if (finished.isNotEmpty) ...[
          const SectionHead('finished'),
          for (final s in finished)
            PlateRow(
              key: ValueKey('project-done-${s.project.id}'),
              leading: Medallion(
                icon: s.project.status == ProjectStatus.done
                    ? Icons.check_rounded
                    : Icons.close_rounded,
                ink: c.inkFaint,
                size: 32,
                iconSize: 15,
              ),
              title: s.project.name,
              sub: clients[s.project.clientId]?.name ?? '—',
              amount: Inr.format(s.receivedPaise),
              amountSub: Text(
                s.marginPaise >= 0
                    ? 'kept ${Inr.compact(s.marginPaise)}'
                    : 'lost ${Inr.compact(-s.marginPaise)}',
                style: LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint),
              ),
              dense: true,
              onTap: () => Navigator.of(context).push(
                LedgerRoute<void>(
                  builder: (_) => ProjectPage(projectId: s.project.id),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// One project as a plate: name and client, how it is paid, how far the
/// money has come, and the one line about costs.
class _ProjectPlate extends StatelessWidget {
  const _ProjectPlate({
    super.key,
    required this.summary,
    required this.client,
    required this.now,
  });

  final ProjectSummary summary;
  final String client;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final s = summary;
    final p = s.project;
    final kind = s.isRetainer
        ? '${Inr.compact(s.quotePaise)} a month · the ${_ordinal(p.billingDay ?? 1)}'
        : 'quoted ${Inr.compact(s.quotePaise)}';
    final unpaid = s.unpaidMonths.where((m) => !m.due.isAfter(now)).length;
    final money = s.isRetainer
        ? (unpaid == 0
              ? '${s.months.length} ${s.months.length == 1 ? 'month' : 'months'} · all paid'
              : '$unpaid ${unpaid == 1 ? 'month' : 'months'} unpaid')
        : '${Inr.format(s.receivedPaise)} of ${Inr.format(s.quotePaise)} received';
    final costs = s.costPaise == 0
        ? null
        : s.billableCostPaise > 0
        ? 'costs ${Inr.format(s.costPaise)} · ${Inr.format(s.billableCostPaise)} to pass on'
        : 'costs ${Inr.format(s.costPaise)}, all inside the quote';
    return Plate(
      onTap: () => Navigator.of(context).push(
        LedgerRoute<void>(builder: (_) => ProjectPage(projectId: p.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 15,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '$client · $kind',
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
              const SizedBox(width: Gap.x3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    s.owedPaise > 0 ? Inr.format(s.owedPaise) : 'settled',
                    style: LedgerType.amountTotal.copyWith(
                      fontSize: 15,
                      color: s.owedPaise > 0 ? c.ink : c.jama,
                    ),
                  ),
                  Text(
                    s.owedPaise > 0 ? 'owed' : '',
                    style: LedgerType.label.copyWith(fontSize: 10, color: c.inkFaint),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Gap.x2),
          RoundedBar(
            fraction: s.fraction,
            ink: s.fraction >= 1 ? c.jama : c.quill,
            height: 6,
          ),
          const SizedBox(height: 6),
          Text(
            money,
            style: LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
          ),
          if (costs != null)
            Text(
              costs,
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: s.billableCostPaise > 0 ? c.warn : c.inkFaint,
              ),
            ),
        ],
      ),
    );
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

/// A new piece of work: who for, what, how it is paid, what was quoted.
Future<int?> showNewProjectSheet(BuildContext context) {
  return showLedgerSheet<int>(
    context,
    builder: (_) => const _NewProjectSheet(),
  );
}

class _NewProjectSheet extends ConsumerStatefulWidget {
  const _NewProjectSheet();

  @override
  ConsumerState<_NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends ConsumerState<_NewProjectSheet> {
  final _client = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _day = TextEditingController(text: '1');
  final _note = TextEditingController();
  int? _clientId;
  ProjectKind _kind = ProjectKind.oneTime;

  @override
  void dispose() {
    _client.dispose();
    _name.dispose();
    _amount.dispose();
    _day.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _paise {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    return v == null || v <= 0 ? null : (v * 100).round();
  }

  bool get _ready =>
      (_clientId != null || _client.text.trim().isNotEmpty) &&
      _name.text.trim().isNotEmpty &&
      _paise != null;

  Future<void> _save() async {
    if (!_ready) return;
    HapticFeedback.mediumImpact();
    final repo = ref.read(workRepoProvider);
    final clientId =
        _clientId ?? await repo.createClient(_client.text.trim());
    final id = await repo.createProject(
      clientId: clientId,
      name: _name.text.trim(),
      kind: _kind,
      quotePaise: _paise!,
      billingDay: int.tryParse(_day.text.trim())?.clamp(1, 31),
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<Client>>(
      stream: ref.watch(workRepoProvider).watchClients(),
      builder: (context, snap) {
        final clients = snap.data ?? const <Client>[];
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
                  'A new project',
                  style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
                ),
                const SizedBox(height: Gap.x4),
                Text('for', style: LedgerType.label.copyWith(color: c.inkFaint)),
                const SizedBox(height: 4),
                if (clients.isNotEmpty)
                  Wrap(
                    spacing: Gap.x4,
                    runSpacing: Gap.x2,
                    children: [
                      for (final cl in clients)
                        QuillTab(
                          cl.name,
                          selected: _clientId == cl.id,
                          onTap: () => setState(() {
                            _clientId = _clientId == cl.id ? null : cl.id;
                          }),
                        ),
                    ],
                  ),
                if (_clientId == null)
                  _field(
                    c,
                    _client,
                    key: 'work-client',
                    hint: clients.isEmpty ? 'the client\'s name' : 'or a new client',
                  ),
                const SizedBox(height: Gap.x4),
                Text('the work', style: LedgerType.label.copyWith(color: c.inkFaint)),
                _field(c, _name, key: 'work-name', hint: 'website, app, the retainer'),
                const SizedBox(height: Gap.x4),
                Text('paid', style: LedgerType.label.copyWith(color: c.inkFaint)),
                const SizedBox(height: 6),
                PillSegments(
                  labels: const ['once, against a quote', 'every month'],
                  index: _kind.index,
                  onSelect: (i) => setState(() => _kind = ProjectKind.values[i]),
                ),
                const SizedBox(height: Gap.x4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _kind == ProjectKind.monthly ? 'a month' : 'quoted',
                            style: LedgerType.label.copyWith(color: c.inkFaint),
                          ),
                          _field(
                            c,
                            _amount,
                            key: 'work-amount',
                            hint: '50000',
                            number: true,
                            prefix: '₹',
                          ),
                        ],
                      ),
                    ),
                    if (_kind == ProjectKind.monthly) ...[
                      const SizedBox(width: Gap.x4),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'due on the',
                              style: LedgerType.label.copyWith(color: c.inkFaint),
                            ),
                            _field(
                              c,
                              _day,
                              key: 'work-day',
                              hint: '5',
                              number: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Gap.x4),
                _field(c, _note, key: 'work-note', hint: 'scope, in a line — optional'),
                const SizedBox(height: Gap.x6),
                Pressable(
                  key: const ValueKey('work-save'),
                  onTap: _ready ? _save : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _ready ? c.quill : c.rule,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'open the project',
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
      },
    );
  }

  Widget _field(
    LedgerColors c,
    TextEditingController ctl, {
    required String key,
    required String hint,
    bool number = false,
    String? prefix,
  }) {
    return TextField(
      key: ValueKey(key),
      controller: ctl,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
      style: (number ? LedgerType.amount : LedgerType.bodyText).copyWith(
        fontSize: number ? 20 : 16,
        color: c.ink,
      ),
      cursorColor: c.quill,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
        prefixText: prefix,
        prefixStyle: LedgerType.amount.copyWith(fontSize: 20, color: c.inkFaint),
        isDense: true,
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule)),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill, width: 2),
        ),
      ),
    );
  }
}
