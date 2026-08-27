import '../api_client.dart';
import 'wire.dart';

/// The slate: money lent to people, and money they lend back.
///
/// Lending is not spending. Every movement here is a transfer between a real
/// pocket and one asset account the server keeps ('On the slate'), so the
/// month's spending stays honest and net worth stays flat — until a loan is
/// let go, which is the only moment it becomes an expense.
class SlateApi {
  const SlateApi(this._c);

  final BbxClient _c;

  Future<SlateOverview> overview() async =>
      SlateOverview.fromJson(wireObject(await _c.get('/v1/slate/overview')));

  Future<List<SlatePerson>> people({bool includeArchived = false}) async =>
      wireList(
        await _c.get('/v1/slate/people', {
          'include_archived': '$includeArchived',
        }),
        SlatePerson.fromJson,
      );

  Future<SlatePerson> person(String id) async =>
      SlatePerson.fromJson(wireObject(await _c.get('/v1/slate/people/$id')));

  Future<List<SlateEntry>> entries(String id) async => wireList(
    await _c.get('/v1/slate/people/$id/entries'),
    SlateEntry.fromJson,
  );

  Future<SlatePerson> upsertPerson(String id, PersonIn body) async =>
      SlatePerson.fromJson(
        wireObject(await _c.put('/v1/slate/people/$id', body.toJson())),
      );

  Future<SlatePerson> patchPerson(String id, PersonPatch body) async =>
      SlatePerson.fromJson(
        wireObject(await _c.patch('/v1/slate/people/$id', body.toJson())),
      );

  Future<void> deletePerson(String id) => _c.delete('/v1/slate/people/$id');

  /// Money out to them.
  Future<SlateEntry> lend(String id, MoveIn body) async => SlateEntry.fromJson(
    wireObject(await _c.post('/v1/slate/people/$id/lend', body.toJson())),
  );

  /// Money in from them, when you were the one who needed it.
  Future<SlateEntry> borrow(String id, MoveIn body) async => SlateEntry.fromJson(
    wireObject(await _c.post('/v1/slate/people/$id/borrow', body.toJson())),
  );

  /// Money coming back. Part of it is the normal case.
  Future<SlateEntry> repay(String id, MoveIn body) async => SlateEntry.fromJson(
    wireObject(await _c.post('/v1/slate/people/$id/repay', body.toJson())),
  );

  /// Let it go. Null amount means the whole standing balance.
  Future<SlateEntry> close(String id, {int? amountPaise, String? note}) async =>
      SlateEntry.fromJson(
        wireObject(
          await _c.post('/v1/slate/people/$id/close', {
            'amount_paise': ?amountPaise,
            'note': ?note,
          }),
        ),
      );

  /// An expense already in the book that was really a loan.
  Future<SlateEntry> adopt(String id, String txnId) async =>
      SlateEntry.fromJson(
        wireObject(
          await _c.post('/v1/slate/people/$id/adopt', {'txn_id': txnId}),
        ),
      );

  Future<List<Adoptable>> adoptable() async =>
      wireList(await _c.get('/v1/slate/adoptable'), Adoptable.fromJson);
}

/// What each entry did to the balance.
enum SlateKind { lent, repaid, borrowed, settled, forgiven, writtenOff }

final slateKindWire = WireEnum<SlateKind>('slate kind', const {
  'lent': SlateKind.lent,
  'repaid': SlateKind.repaid,
  'borrowed': SlateKind.borrowed,
  'settled': SlateKind.settled,
  'forgiven': SlateKind.forgiven,
  'written_off': SlateKind.writtenOff,
});

class SlateOverview {
  const SlateOverview({
    required this.owedToYouPaise,
    required this.youOwePaise,
    required this.netPaise,
    required this.peopleInDebt,
    required this.peopleYouOwe,
    required this.slateAccountPaise,
    required this.balanced,
  });

  final int owedToYouPaise;
  final int youOwePaise;
  final int netPaise;
  final int peopleInDebt;
  final int peopleYouOwe;

  /// What the ledger actually parked on the slate. Equal to [netPaise] unless
  /// something has gone wrong — and then the screen says so rather than
  /// quietly disagreeing with itself.
  final int slateAccountPaise;
  final bool balanced;

  factory SlateOverview.fromJson(Map<String, dynamic> json) => SlateOverview(
    owedToYouPaise: json.whole('owed_to_you_paise'),
    youOwePaise: json.whole('you_owe_paise'),
    netPaise: json.whole('net_paise'),
    peopleInDebt: json.whole('people_in_debt'),
    peopleYouOwe: json.whole('people_you_owe'),
    slateAccountPaise: json.whole('slate_account_paise'),
    balanced: json.flag('balanced'),
  );
}

class SlatePerson {
  const SlatePerson({
    required this.id,
    required this.name,
    required this.relation,
    required this.note,
    required this.archived,
    required this.balancePaise,
    required this.lentPaise,
    required this.returnedPaise,
    required this.entries,
    required this.loopsClosed,
    required this.loopsTotal,
    required this.since,
    required this.lastAt,
    required this.outstandingSince,
  });

  final String id;
  final String name;
  final String? relation;
  final String? note;
  final bool archived;

  /// Positive: they owe you. Negative: you owe them. Zero: clean.
  final int balancePaise;
  final int lentPaise;
  final int returnedPaise;
  final int entries;

  /// Loops that ended by being paid back, out of loops there have been.
  /// A fact for the next decision, not a score.
  final int loopsClosed;
  final int loopsTotal;
  final DateTime? since;
  final DateTime? lastAt;

  /// When the standing balance first went out; null on a clean slate.
  final DateTime? outstandingSince;

  bool get clean => balancePaise == 0;
  bool get owesYou => balancePaise > 0;

  factory SlatePerson.fromJson(Map<String, dynamic> json) => SlatePerson(
    id: json.text('id'),
    name: json.text('name'),
    relation: json.textOrNull('relation'),
    note: json.textOrNull('note'),
    archived: json.flag('archived'),
    balancePaise: json.whole('balance_paise'),
    lentPaise: json.whole('lent_paise'),
    returnedPaise: json.whole('returned_paise'),
    entries: json.whole('entries'),
    loopsClosed: json.whole('loops_closed'),
    loopsTotal: json.whole('loops_total'),
    since: json.instantOrNull('since'),
    lastAt: json.instantOrNull('last_at'),
    outstandingSince: json.instantOrNull('outstanding_since'),
  );
}

class SlateEntry {
  const SlateEntry({
    required this.id,
    required this.personId,
    required this.kind,
    required this.amountPaise,
    required this.at,
    required this.note,
    required this.txnId,
  });

  final String id;
  final String personId;
  final SlateKind kind;
  final int amountPaise;
  final DateTime at;
  final String? note;

  /// The ledger line that moved the money.
  final String? txnId;

  factory SlateEntry.fromJson(Map<String, dynamic> json) => SlateEntry(
    id: json.text('id'),
    personId: json.text('person_id'),
    kind: json.enumAt('kind', slateKindWire),
    amountPaise: json.whole('amount_paise'),
    at: json.instant('at'),
    note: json.textOrNull('note'),
    txnId: json.textOrNull('txn_id'),
  );
}

/// An expense that might really have been a loan.
class Adoptable {
  const Adoptable({
    required this.txnId,
    required this.title,
    required this.amountPaise,
    required this.at,
    required this.accountId,
  });

  final String txnId;
  final String title;
  final int amountPaise;
  final DateTime at;
  final String accountId;

  factory Adoptable.fromJson(Map<String, dynamic> json) => Adoptable(
    txnId: json.text('txn_id'),
    title: json.text('title'),
    amountPaise: json.whole('amount_paise'),
    at: json.instant('at'),
    accountId: json.text('account_id'),
  );
}

class PersonIn {
  const PersonIn({required this.name, this.relation, this.note});

  final String name;
  final String? relation;
  final String? note;

  Map<String, dynamic> toJson() => {
    'name': name,
    'relation': relation,
    'note': note,
  };
}

class PersonPatch {
  const PersonPatch({this.name, this.relation, this.note, this.archived});

  final String? name;
  final Opt<String?>? relation;
  final Opt<String?>? note;
  final bool? archived;

  Map<String, dynamic> toJson() => (WireBody()
        ..maybe('name', name)
        ..opt('relation', relation)
        ..opt('note', note)
        ..maybe('archived', archived))
      .build();
}

/// One movement of money: how much, out of (or into) which pocket, when.
class MoveIn {
  const MoveIn({
    required this.amountPaise,
    required this.accountId,
    this.at,
    this.note,
  });

  final int amountPaise;
  final String accountId;

  /// Null means now — backdating is how an old loan gets onto the slate.
  final DateTime? at;
  final String? note;

  Map<String, dynamic> toJson() => {
    'amount_paise': amountPaise,
    'account_id': accountId,
    if (at != null) 'at': wireInstant(at!),
    if (note != null) 'note': note,
  };
}
