import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../story/story_page.dart';

class WorthPage extends ConsumerWidget {
  const WorthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final accounts = ref.watch(accountRepoProvider);

    return StreamBuilder<List<Account>>(
      stream: accounts.watchAll(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const [];
        final assets =
            all.where((a) => a.kind != AccountKind.liability).toList();
        final owed =
            all.where((a) => a.kind == AccountKind.liability).toList();
        final net = assets.fold<int>(0, (s, a) => s + a.balancePaise) -
            owed.fold<int>(0, (s, a) => s + a.balancePaise);

        return FutureBuilder<List<int>>(
          // Keyed on net so a balance change re-reads the history.
          key: ValueKey(net),
          future: accounts.netWorthHistory(),
          builder: (context, historySnap) {
            final fetched = historySnap.data;
            final history =
                (fetched == null || fetched.isEmpty) ? [net] : fetched;
            final delta = net - history.first;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          children: [
            LedgerAppBar(
              title: 'Worth',
              trailing: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const StoryPage()),
                ),
                child: Text('the month\'s story ›',
                    style: LedgerType.bodyStrong
                        .copyWith(fontSize: 13, color: c.quill)),
              ),
            ),
            const SizedBox(height: Gap.x4),
            HeroAmount(
              caption: 'net worth, as of to-day',
              amount: Inr.compact(net),
              size: 36,
              sub: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text:
                        '${delta >= 0 ? '▲' : '▼'} ${Inr.format(delta.abs())}',
                    style: LedgerType.bodyText.copyWith(
                        fontSize: 13,
                        color: delta >= 0 ? c.jama : c.seal),
                  ),
                  TextSpan(
                    text: ' lately',
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 13, color: c.inkFaint),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: Gap.x3),
            _NetWorthChart(history: history),
            const RuleHeader('assets'),
            for (final (i, a) in assets.indexed)
              _AccountRow(account: a, last: i == assets.length - 1),
            if (owed.isNotEmpty) ...[
              const RuleHeader('owed'),
              for (final (i, a) in owed.indexed)
                _AccountRow(
                    account: a, negative: true, last: i == owed.length - 1),
            ],
            const SizedBox(height: Gap.x6),
          ],
        );
          },
        );
      },
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow(
      {required this.account, this.negative = false, this.last = false});

  final Account account;
  final bool negative;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final ageDays = DateTime.now().difference(account.asOf).inDays;
    final stale = ageDays >= 30;
    final asOf = ageDays <= 0
        ? 'as of to-day'
        : ageDays == 1
            ? 'as of yesterday'
            : 'as of ${account.asOf.day}/${account.asOf.month}';

    return InkWell(
      onTap: () => _updateBalance(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name,
                      style: LedgerType.bodyText.copyWith(color: c.ink)),
                  Text(
                    stale ? '$asOf — update?' : asOf,
                    style: LedgerType.bodyText.copyWith(
                        fontSize: 11,
                        color: stale ? c.warn : c.inkFaint),
                  ),
                ],
              ),
            ),
            FutureBuilder<List<double>>(
              key: ValueKey('spark-${account.id}-${account.balancePaise}'),
              future: ref.read(accountRepoProvider).spark(account.id),
              builder: (context, spark) => Sparkline(
                spark.data ?? const [1, 1],
              ),
            ),
            const SizedBox(width: Gap.x3),
            Text(
              negative
                  ? '− ${Inr.format(account.balancePaise)}'
                  : Inr.format(account.balancePaise),
              style: LedgerType.amount.copyWith(color: c.ink),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateBalance(BuildContext context, WidgetRef ref) async {
    final c = LedgerColors.of(context);
    final controller = TextEditingController(
        text: (account.balancePaise ~/ 100).toString());
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: Gap.page,
          right: Gap.page,
          top: Gap.x4,
          bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${account.name} — what\'s true right now?',
                style: LedgerType.bodyStrong.copyWith(color: c.ink)),
            const SizedBox(height: Gap.x2),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: LedgerType.heroAmount
                  .copyWith(fontSize: 32, color: c.ink),
              decoration: InputDecoration(
                prefixText: '₹',
                prefixStyle: LedgerType.heroAmount
                    .copyWith(fontSize: 32, color: c.inkFaint),
                border: InputBorder.none,
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('That\'s the number'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final rupees = int.tryParse(controller.text.trim());
      if (rupees != null) {
        await ref
            .read(accountRepoProvider)
            .setBalance(account.id, rupees * 100);
      }
    }
  }
}

class _NetWorthChart extends StatelessWidget {
  const _NetWorthChart({required this.history});

  final List<int> history;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      height: 80,
      width: double.infinity,
      child: CustomPaint(
        painter: _AreaPainter(
          points: [for (final v in history) v.toDouble()],
          line: c.quill,
          rule: c.rule,
        ),
      ),
    );
  }
}

class _AreaPainter extends CustomPainter {
  _AreaPainter({required this.points, required this.line, required this.rule});

  final List<double> points;
  final Color line;
  final Color rule;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final base = size.height - 8;
    canvas.drawLine(Offset(0, base), Offset(size.width, base),
        Paint()..color = rule..strokeWidth = 1);

    final min = points.reduce(math.min);
    final max = points.reduce(math.max);
    final range = (max - min) == 0 ? 1.0 : max - min;

    Offset at(int i) => Offset(
          size.width * i / (points.length - 1),
          base - (base - 10) * ((points[i] - min) / range) * 0.9 - 4,
        );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, base)
      ..lineTo(0, base)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withValues(alpha: 0.18), line.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(points.length - 1), 3.4, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_AreaPainter old) => old.points != points;
}
