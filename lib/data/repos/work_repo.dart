import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/work/work_math.dart';
import '../db.dart';
import '../providers.dart';
import '../sync/ids.dart';
import '../sync/seam.dart';
import 'txn_repo.dart';

final workRepoProvider = Provider<WorkRepo>(
  (ref) => WorkRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

/// The work book's keeper: clients, projects, the quote as it moves, and
/// the ledger lines a project claims.
///
/// Money never lives here twice. A payment received is an income line in
/// the ledger, claimed by the project through a link; a cost is an expense
/// line, claimed the same way. Strike the line from the Book and the
/// project simply stops counting it.
class WorkRepo {
  WorkRepo(this._db, this._txns);

  final LedgerDb _db;
  final TxnRepo _txns;

  // ————— clients —————

  Stream<List<Client>> watchClients() =>
      (_db.select(_db.clients)
            ..where((c) => c.archived.equals(false))
            ..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .watch();

  Future<int> createClient(String name, {String? note}) {
    return _db.transaction(() async {
      final id = await _db
          .into(_db.clients)
          .insert(ClientsCompanion.insert(name: name.trim(), note: Value(note)));
      await bbxSync.upsert(SyncKinds.client, id);
      return id;
    });
  }

  // ————— projects —————

  Stream<List<Project>> watchProjects() =>
      (_db.select(_db.projects)..orderBy([
            (p) => OrderingTerm.desc(p.startedAt),
          ]))
          .watch();

  Stream<Project?> watchProject(int id) =>
      (_db.select(_db.projects)..where((p) => p.id.equals(id))).watchSingleOrNull();

  /// A new piece of work. The opening quote is also the first revision, so
  /// the history starts where the project does.
  Future<int> createProject({
    required int clientId,
    required String name,
    required ProjectKind kind,
    required int quotePaise,
    int? billingDay,
    DateTime? startedAt,
    String? note,
  }) {
    final at = startedAt ?? DateTime.now();
    return _db.transaction(() async {
      final id = await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              clientId: clientId,
              name: name.trim(),
              kind: kind,
              quotePaise: quotePaise,
              billingDay: Value(kind == ProjectKind.monthly ? billingDay : null),
              startedAt: at,
              note: Value(note),
            ),
          );
      await bbxSync.upsert(SyncKinds.project, id);
      final rev = await _db
          .into(_db.quoteRevisions)
          .insert(
            QuoteRevisionsCompanion.insert(
              projectId: id,
              paise: quotePaise,
              reason: const Value('first quote'),
              at: at,
            ),
          );
      await bbxSync.upsert(SyncKinds.quote, rev);
      return id;
    });
  }

  /// The quote moved. The project carries the new figure; the history
  /// keeps the old one and why it changed.
  Future<void> reviseQuote(int projectId, int paise, {String? reason}) {
    return _db.transaction(() async {
      await (_db.update(_db.projects)..where((p) => p.id.equals(projectId))).write(
        ProjectsCompanion(quotePaise: Value(paise)),
      );
      await bbxSync.upsert(SyncKinds.project, projectId);
      final rev = await _db
          .into(_db.quoteRevisions)
          .insert(
            QuoteRevisionsCompanion.insert(
              projectId: projectId,
              paise: paise,
              reason: Value(reason?.trim().isEmpty ?? true ? null : reason!.trim()),
              at: DateTime.now(),
            ),
          );
      await bbxSync.upsert(SyncKinds.quote, rev);
    });
  }

  Future<void> setStatus(int projectId, ProjectStatus status) {
    return _db.transaction(() async {
      await (_db.update(_db.projects)..where((p) => p.id.equals(projectId))).write(
        ProjectsCompanion(status: Value(status)),
      );
      await bbxSync.upsert(SyncKinds.project, projectId);
    });
  }

  Future<void> updateProject(
    int projectId, {
    String? name,
    int? billingDay,
    String? note,
  }) {
    return _db.transaction(() async {
      await (_db.update(_db.projects)..where((p) => p.id.equals(projectId))).write(
        ProjectsCompanion(
          name: name == null ? const Value.absent() : Value(name.trim()),
          billingDay: billingDay == null ? const Value.absent() : Value(billingDay),
          note: note == null ? const Value.absent() : Value(note),
        ),
      );
      await bbxSync.upsert(SyncKinds.project, projectId);
    });
  }

  Stream<List<QuoteRevision>> watchAllRevisions() =>
      (_db.select(_db.quoteRevisions)..orderBy([(r) => OrderingTerm.asc(r.at)]))
          .watch();

  Stream<List<QuoteRevision>> watchRevisions(int projectId) =>
      (_db.select(_db.quoteRevisions)
            ..where((r) => r.projectId.equals(projectId))
            ..orderBy([(r) => OrderingTerm.asc(r.at)]))
          .watch();

  // ————— the lines a project claims —————

  Stream<List<ProjectLine>> watchLines(int projectId) {
    final q = _db.select(_db.projectLinks).join([
      innerJoin(_db.txns, _db.txns.id.equalsExp(_db.projectLinks.txnId)),
    ])
      ..where(_db.projectLinks.projectId.equals(projectId))
      ..orderBy([OrderingTerm.desc(_db.txns.at)]);
    return q.watch().map((rows) => [
      for (final r in rows)
        ProjectLine(
          link: r.readTable(_db.projectLinks),
          txn: r.readTable(_db.txns),
        ),
    ]);
  }

  /// Every claimed line across every project — the work page reads these
  /// once and summarises each project from them.
  Stream<List<ProjectLine>> watchAllLines() {
    final q = _db.select(_db.projectLinks).join([
      innerJoin(_db.txns, _db.txns.id.equalsExp(_db.projectLinks.txnId)),
    ]);
    return q.watch().map((rows) => [
      for (final r in rows)
        ProjectLine(
          link: r.readTable(_db.projectLinks),
          txn: r.readTable(_db.txns),
        ),
    ]);
  }

  /// Claims an existing ledger line for a project.
  Future<int> attach(
    int projectId,
    int txnId, {
    required LinkRole role,
    bool billable = false,
    String? note,
  }) {
    return _db.transaction(() async {
      final id = await _db
          .into(_db.projectLinks)
          .insert(
            ProjectLinksCompanion.insert(
              projectId: projectId,
              txnId: txnId,
              role: role,
              billable: Value(billable),
              note: Value(note),
            ),
          );
      await bbxSync.upsert(SyncKinds.plink, id);
      return id;
    });
  }

  Future<void> detach(int linkId) {
    return _db.transaction(() async {
      await (_db.delete(_db.projectLinks)..where((l) => l.id.equals(linkId))).go();
      await bbxSync.remove(SyncKinds.plink, linkId);
    });
  }

  Future<void> setBillable(int linkId, bool billable) {
    return _db.transaction(() async {
      await (_db.update(_db.projectLinks)..where((l) => l.id.equals(linkId))).write(
        ProjectLinksCompanion(billable: Value(billable)),
      );
      await bbxSync.upsert(SyncKinds.plink, linkId);
    });
  }

  /// The client paid: one income line in the ledger, claimed at once.
  Future<int> receive(
    int projectId, {
    required int amountPaise,
    required int accountId,
    required String title,
    int? categoryId,
    DateTime? at,
  }) async {
    final txnId = await _txns.addIncome(
      amountPaise: amountPaise,
      accountId: accountId,
      title: title,
      categoryId: categoryId,
      at: at,
    );
    await attach(projectId, txnId, role: LinkRole.received);
    return txnId;
  }

  /// The project cost something: one expense line, claimed at once, and
  /// marked whether it sat inside the quote.
  Future<int> spend(
    int projectId, {
    required int amountPaise,
    required int accountId,
    required String title,
    int? categoryId,
    bool billable = false,
    DateTime? at,
  }) async {
    final txnId = await _txns.addExpense(
      amountPaise: amountPaise,
      accountId: accountId,
      title: title,
      categoryId: categoryId,
      at: at,
    );
    await attach(projectId, txnId, role: LinkRole.cost, billable: billable);
    return txnId;
  }

  /// Ledger lines of [type] from the last [days] not yet claimed by any
  /// project — what the attach sheet offers.
  Future<List<Txn>> unclaimed(TxnType type, {int days = 90}) async {
    final since = DateTime.now().subtract(Duration(days: days));
    final claimed = {
      for (final l in await _db.select(_db.projectLinks).get()) l.txnId,
    };
    final rows =
        await (_db.select(_db.txns)
              ..where(
                (t) => t.type.equalsValue(type) & t.at.isBiggerOrEqualValue(since),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.at)]))
            .get();
    return [
      for (final t in rows)
        if (!claimed.contains(t.id)) t,
    ];
  }
}
