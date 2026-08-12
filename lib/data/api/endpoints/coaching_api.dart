import '../api_client.dart';
import 'wire.dart';

enum SpendingClass { essential, discretionary, avoid }

enum CoachingKind { merchantSurge, repeatedDiscretionary, budgetRisk }

class MerchantRule {
  const MerchantRule({
    required this.id,
    required this.matchText,
    required this.merchantName,
    required this.classification,
    required this.active,
  });

  final String id;
  final String matchText;
  final String merchantName;
  final SpendingClass classification;
  final bool active;

  factory MerchantRule.fromJson(Map<String, dynamic> json) => MerchantRule(
    id: json.text('id'),
    matchText: json.text('match_text'),
    merchantName: json.text('merchant_name'),
    classification: switch (json.text('classification')) {
      'essential' => SpendingClass.essential,
      'discretionary' => SpendingClass.discretionary,
      'avoid' => SpendingClass.avoid,
      final value => throw WireFormatException(
        'classification: unknown spending class "$value"',
      ),
    },
    active: json.flag('active'),
  );
}

class CoachingEvidence {
  const CoachingEvidence({
    required this.reason,
    required this.transactionIds,
    required this.comparisonMonths,
    this.merchantName,
    this.classification,
    this.count,
    this.budgetName,
  });

  final String reason;
  final List<String> transactionIds;
  final List<String> comparisonMonths;
  final String? merchantName;
  final SpendingClass? classification;
  final int? count;
  final String? budgetName;

  factory CoachingEvidence.fromJson(Map<String, dynamic> json) =>
      CoachingEvidence(
        reason: json.text('reason'),
        transactionIds: json.texts('transaction_ids'),
        comparisonMonths: json.texts('comparison_months'),
        merchantName: json.textOrNull('merchant_name'),
        classification: switch (json.textOrNull('classification')) {
          null => null,
          'essential' => SpendingClass.essential,
          'discretionary' => SpendingClass.discretionary,
          'avoid' => SpendingClass.avoid,
          final value => throw WireFormatException(
            'classification: unknown spending class "$value"',
          ),
        },
        count: json.wholeOrNull('count'),
        budgetName: json.textOrNull('budget_name'),
      );
}

class CoachingInsight {
  const CoachingInsight({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.evidence,
    required this.priority,
    required this.periodStart,
    required this.periodEnd,
    this.currentPaise,
    this.baselinePaise,
    this.differencePaise,
  });

  final String id;
  final CoachingKind kind;
  final String title;
  final String message;
  final CoachingEvidence evidence;
  final int priority;
  final String periodStart;
  final String periodEnd;
  final int? currentPaise;
  final int? baselinePaise;
  final int? differencePaise;

  factory CoachingInsight.fromJson(Map<String, dynamic> json) =>
      CoachingInsight(
        id: json.text('id'),
        kind: switch (json.text('kind')) {
          'merchant_surge' => CoachingKind.merchantSurge,
          'repeated_discretionary' => CoachingKind.repeatedDiscretionary,
          'budget_risk' => CoachingKind.budgetRisk,
          final value => throw WireFormatException(
            'kind: unknown coaching kind "$value"',
          ),
        },
        title: json.text('title'),
        message: json.text('message'),
        evidence: json.object('evidence', CoachingEvidence.fromJson),
        priority: json.whole('priority'),
        periodStart: json.day('period_start'),
        periodEnd: json.day('period_end'),
        currentPaise: json.wholeOrNull('current_paise'),
        baselinePaise: json.wholeOrNull('baseline_paise'),
        differencePaise: json.wholeOrNull('difference_paise'),
      );
}

class CoachingApi {
  const CoachingApi(this._c);

  final BbxClient _c;

  Future<List<CoachingInsight>> feed() async =>
      wireList(await _c.get('/v1/coaching/feed'), CoachingInsight.fromJson);

  Future<List<MerchantRule>> merchantRules({
    bool includeInactive = false,
  }) async => wireList(
    await _c.get('/v1/coaching/merchant-rules', {
      'include_inactive': includeInactive,
    }),
    MerchantRule.fromJson,
  );

  Future<MerchantRule> putMerchantRule({
    required String id,
    required String matchText,
    required String merchantName,
    required SpendingClass classification,
    bool active = true,
  }) async => MerchantRule.fromJson(
    wireObject(
      await _c.put('/v1/coaching/merchant-rules/$id', {
        'match_text': matchText,
        'merchant_name': merchantName,
        'classification': classification.name,
        'active': active,
      }),
    ),
  );

  Future<MerchantRule> patchMerchantRule(
    String id, {
    String? merchantName,
    SpendingClass? classification,
    bool? active,
  }) async {
    final body = <String, dynamic>{};
    if (merchantName != null) {
      body['merchant_name'] = merchantName;
    }
    if (classification != null) {
      body['classification'] = classification.name;
    }
    if (active != null) {
      body['active'] = active;
    }
    return MerchantRule.fromJson(
      wireObject(await _c.patch('/v1/coaching/merchant-rules/$id', body)),
    );
  }

  Future<void> dismiss(String insightId) async {
    await _c.post('/v1/coaching/insights/$insightId/feedback', {
      'action': 'dismiss',
    });
  }

  Future<void> acted(String insightId) async {
    await _c.post('/v1/coaching/insights/$insightId/feedback', {
      'action': 'acted',
    });
  }

  Future<void> snooze(String insightId, String until) async {
    await _c.post('/v1/coaching/insights/$insightId/feedback', {
      'action': 'snooze',
      'snoozed_until': until,
    });
  }
}
