import '../../tables.dart';
import '../api_client.dart';
import 'txns_api.dart';
import 'wire.dart';

/// What the money is for. Progress is never stored — it is the sum of the
/// transactions tagged to the goal, so undoing a contribution needs no
/// correction anywhere.
class GoalsApi {
  const GoalsApi(this._c);

  final BbxClient _c;

  Future<List<GoalView>> list({bool includeArchived = false}) async => wireList(
        await _c.get('/v1/goals', {'include_archived': includeArchived}),
        GoalView.fromJson,
      );

  Future<GoalView> get(String id) async =>
      GoalView.fromJson(wireObject(await _c.get('/v1/goals/$id')));

  Future<GoalView> upsert(String id, GoalIn body) async => GoalView.fromJson(
        wireObject(await _c.put('/v1/goals/$id', body.toJson())),
      );

  Future<GoalView> patch(String id, GoalPatch body) async => GoalView.fromJson(
        wireObject(await _c.patch('/v1/goals/$id', body.toJson())),
      );

  /// Put money towards it — which is just a transaction wearing the goal's tag.
  Future<TxnOut> contribute(String id, ContributeIn body) async =>
      TxnOut.fromJson(
        wireObject(await _c.post('/v1/goals/$id/contribute', body.toJson())),
      );
}

class GoalOut {
  const GoalOut({
    required this.id,
    required this.name,
    required this.targetPaise,
    required this.kind,
    required this.targetDate,
    required this.monthlyPaise,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int targetPaise;

  /// `save` climbs towards the target; `clear` pays a debt down to it.
  final GoalKind kind;

  /// 'yyyy-MM-dd'; null when the goal has no deadline.
  final String? targetDate;

  /// The rhythm the setup ritual promised — null when none was set.
  final int? monthlyPaise;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory GoalOut.fromJson(Map<String, dynamic> json) => GoalOut(
        id: json.text('id'),
        name: json.text('name'),
        targetPaise: json.whole('target_paise'),
        kind: json.enumAt('kind', goalKindWire),
        targetDate: json.dayOrNull('target_date'),
        monthlyPaise: json.wholeOrNull('monthly_paise'),
        archived: json.flag('archived'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class GoalIn {
  const GoalIn({
    required this.name,
    required this.targetPaise,
    required this.kind,
    this.targetDate,
    this.monthlyPaise,
  });

  final String name;
  final int targetPaise;
  final GoalKind kind;

  /// 'yyyy-MM-dd'.
  final String? targetDate;
  final int? monthlyPaise;

  Map<String, dynamic> toJson() => {
        'name': name,
        'target_paise': targetPaise,
        'kind': goalKindWire.toWire(kind),
        'target_date': targetDate,
        'monthly_paise': monthlyPaise,
      };
}

/// `kind` is fixed once set. A deadline and a monthly rhythm can both be
/// dropped, so they take an [Opt]; the rest read null as "leave it alone".
class GoalPatch {
  const GoalPatch({
    this.name,
    this.targetPaise,
    this.targetDate,
    this.monthlyPaise,
    this.archived,
  });

  final String? name;
  final int? targetPaise;

  /// 'yyyy-MM-dd'; `Opt(null)` drops the deadline.
  final Opt<String?>? targetDate;
  final Opt<int?>? monthlyPaise;
  final bool? archived;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('name', name)
        ..maybe('target_paise', targetPaise)
        ..opt('target_date', targetDate)
        ..opt('monthly_paise', monthlyPaise)
        ..maybe('archived', archived))
      .build();
}

/// A goal with its arithmetic done: how far along, how much is left, and when
/// it lands if the current rhythm holds.
class GoalView {
  const GoalView({
    required this.goal,
    required this.donePaise,
    required this.remainingPaise,
    required this.fraction,
    required this.reached,
    required this.entryCount,
    required this.eta,
    required this.rhythm,
  });

  final GoalOut goal;
  final int donePaise;
  final int remainingPaise;

  /// 0…1 — a ratio, not money.
  final double fraction;
  final bool reached;

  /// How many contributions it took.
  final int entryCount;

  /// 'yyyy-MM-dd' the goal lands on at the current rate; null when there is
  /// no rhythm to project from — silence rather than a guess.
  final String? eta;

  /// Recent months, one flag each: was anything put in?
  final List<bool> rhythm;

  factory GoalView.fromJson(Map<String, dynamic> json) => GoalView(
        goal: json.object('goal', GoalOut.fromJson),
        donePaise: json.whole('done_paise'),
        remainingPaise: json.whole('remaining_paise'),
        fraction: json.real('fraction'),
        reached: json.flag('reached'),
        entryCount: json.whole('entry_count'),
        eta: json.dayOrNull('eta'),
        rhythm: json.flags('rhythm'),
      );
}

class ContributeIn {
  const ContributeIn({
    required this.amountPaise,
    required this.accountId,
    this.at,
    this.note,
  });

  final int amountPaise;

  /// Where the money comes from.
  final String accountId;
  final DateTime? at;
  final String? note;

  Map<String, dynamic> toJson() => (WireBody()
        ..set('amount_paise', amountPaise)
        ..set('account_id', accountId)
        ..maybe('at', wireInstantOrNull(at))
        ..maybe('note', note))
      .build();
}
