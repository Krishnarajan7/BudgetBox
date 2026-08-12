import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/sheets.dart';
import '../../data/api/api_client.dart';
import '../../data/api/endpoints/coaching_api.dart';
import '../../data/providers.dart';
import '../../data/sync/ids.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The small bit of human judgment the coach needs. It never guesses whether
/// a merchant is essential: the owner teaches it once, then the arithmetic
/// can stay deterministic and explainable.
class CoachingManagerPage extends ConsumerStatefulWidget {
  const CoachingManagerPage({super.key});

  @override
  ConsumerState<CoachingManagerPage> createState() =>
      _CoachingManagerPageState();
}

class _CoachingManagerPageState extends ConsumerState<CoachingManagerPage> {
  List<MerchantRule>? _rules;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T> _withApi<T>(Future<T> Function(CoachingApi api) action) async {
    final config = await ref.read(settingsRepoProvider).serverConfig();
    if (!config.wired) throw const BbxOffline('wire a server first');
    final client = BbxClient(config);
    try {
      return await action(CoachingApi(client));
    } finally {
      client.close();
    }
  }

  Future<void> _load() async {
    try {
      final rules = await _withApi(
        (api) => api.merchantRules(includeInactive: true),
      );
      if (mounted) {
        setState(() {
          _rules = rules;
          _error = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _rules = const [];
          _error = '$error';
        });
      }
    }
  }

  Future<void> _edit([MerchantRule? existing]) async {
    final draft = await showLedgerSheet<_RuleDraft>(
      context,
      builder: (_) => _RuleSheet(existing: existing),
    );
    if (draft == null || !mounted) return;
    try {
      await _withApi(
        (api) => api.putMerchantRule(
          id: existing?.id ?? newUuid7(),
          matchText: existing?.matchText ?? draft.matchText,
          merchantName: draft.merchantName,
          classification: draft.classification,
        ),
      );
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _toggle(MerchantRule rule) async {
    try {
      await _withApi(
        (api) => api.patchMerchantRule(rule.id, active: !rule.active),
      );
      await _load();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final rules = _rules;
    return ModuleScaffold(
      title: 'spending guide',
      trailing: TextButton(
        onPressed: () => _edit(),
        child: const Text('teach it'),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x8),
        children: [
          Text(
            'Name a merchant exactly as it appears in your entries. The book '
            'uses only your labels when it speaks about repeated spending.',
            style: LedgerType.bodyText.copyWith(color: c.inkFaint),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.x3),
            Text(
              _error!.contains('wire a server first')
                  ? 'Connect this book to its server before teaching it.'
                  : 'The spending guide could not be reached. Try again.',
              style: LedgerType.bodyStrong.copyWith(color: c.quill),
            ),
          ],
          const SizedBox(height: Gap.x4),
          if (rules == null)
            const Center(child: CircularProgressIndicator())
          else if (rules.isEmpty)
            Text(
              'No merchants taught yet.',
              style: LedgerType.bodyStrong.copyWith(color: c.ink),
            )
          else
            for (final rule in rules)
              LedgerLine(
                title: rule.merchantName,
                detail:
                    '${_classLabel(rule.classification)} · matches “${rule.matchText}”',
                struck: !rule.active,
                onTap: () => _edit(rule),
                amountWidget: TextButton(
                  onPressed: () => _toggle(rule),
                  child: Text(rule.active ? 'pause' : 'use'),
                ),
              ),
        ],
      ),
    );
  }
}

String _classLabel(SpendingClass value) => switch (value) {
  SpendingClass.essential => 'essential',
  SpendingClass.discretionary => 'optional',
  SpendingClass.avoid => 'want less',
};

class _RuleDraft {
  const _RuleDraft(this.matchText, this.merchantName, this.classification);
  final String matchText;
  final String merchantName;
  final SpendingClass classification;
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({this.existing});
  final MerchantRule? existing;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final _match = TextEditingController(text: widget.existing?.matchText);
  late final _name = TextEditingController(text: widget.existing?.merchantName);
  late SpendingClass _classification =
      widget.existing?.classification ?? SpendingClass.discretionary;

  @override
  void dispose() {
    _match.dispose();
    _name.dispose();
    super.dispose();
  }

  void _keep() {
    final match = _match.text.trim();
    final name = _name.text.trim();
    if (match.isEmpty || name.isEmpty) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(_RuleDraft(match, name, _classification));
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        MediaQuery.of(context).viewInsets.bottom + Gap.x4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Text(
              'Teach the book one merchant.',
              style: LedgerType.bodyStrong.copyWith(color: c.ink),
            ),
            const SizedBox(height: Gap.x3),
            TextField(
              controller: _match,
              enabled: widget.existing == null,
              autofocus: widget.existing == null,
              decoration: const InputDecoration(
                labelText: 'entry title to match exactly',
              ),
            ),
            const SizedBox(height: Gap.x2),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'name to show'),
            ),
            const SizedBox(height: Gap.x3),
            Wrap(
              spacing: Gap.x2,
              runSpacing: Gap.x2,
              children: [
                for (final value in SpendingClass.values)
                  LedgerChip(
                    _classLabel(value),
                    selected: _classification == value,
                    onTap: () => setState(() => _classification = value),
                  ),
              ],
            ),
            const SizedBox(height: Gap.x4),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _keep, child: const Text('keep')),
            ),
          ],
        ),
      ),
    );
  }
}
