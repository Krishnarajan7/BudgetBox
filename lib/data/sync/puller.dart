import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../db.dart';
import 'ids.dart';
import 'outbox.dart';
import 'wire.dart';

class PullOutcome {
  const PullOutcome({
    required this.applied,
    required this.offline,
    this.at,
    this.detail,
  });

  final int applied;
  final bool offline;
  final DateTime? at;
  final String? detail;
}

/// Brings the server's side of the book down onto the phone.
///
/// `GET /v1/changes?after=` pages through durable upserts and deletion
/// tombstones; list endpoints hand over current rows. Everything is matched back to a local row
/// number through [RemoteIds] — known ids are updated in place, unknown ones
/// are inserted and mapped, so the screens keep reading the same `int` ids
/// they always did.
///
/// **The conflict rule: a local row with a pending outbox entry wins.** If
/// the phone still owes the server a write about a row, the pull leaves that
/// row alone — always, without comparing timestamps. The phone's copy is the
/// one a person typed and the server has not seen it yet; letting a stale
/// download overwrite an unsent edit would lose work that was never wrong.
/// The write goes up on the next drain and the server's answer comes back
/// after it.
class SyncPuller {
  SyncPuller(this._db, this._outbox) : _ids = SyncIds(_db);

  final LedgerDb _db;
  final SyncOutbox _outbox;
  final SyncIds _ids;

  /// The durable server sequence already applied by this phone. A new key is
  /// intentional: clients upgrading from the old timestamp watermark replay
  /// the current server snapshot once instead of risking a skipped row.
  static const cursorKey = 'sync.cursor';

  /// True only when the queue is empty. Derived figures the server owns —
  /// account balances, above all — are trusted only then, because a pending
  /// txn means the server's arithmetic is missing a term.
  bool _trustDerived = false;

  Future<int> cursor() async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(cursorKey))).getSingleOrNull();
    return int.tryParse(row?.value ?? '') ?? 0;
  }

  Future<void> _setCursor(int cursor) {
    return _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion(
            key: const Value(cursorKey),
            value: Value('$cursor'),
          ),
        );
  }

  Future<PullOutcome> pull(SyncWire wire, {required bool queueEmpty}) async {
    _trustDerived = queueEmpty;
    var settledCursor = await cursor();
    var applied = 0;
    DateTime? serverTime;
    while (true) {
      final SyncChangePage page;
      try {
        page = await wire.changes(settledCursor);
      } on BbxOffline catch (e) {
        return PullOutcome(
          applied: applied,
          offline: true,
          at: serverTime,
          detail: e.detail,
        );
      }
      serverTime = page.serverTime;

      // Several mutations of one row inside a page collapse to its final
      // state. Sequence order still decides whether that state is present or
      // deleted.
      final latest = <String, SyncChange>{};
      for (final item in page.items) {
        latest['${item.resource}/${item.resourceId}'] = item;
      }
      final changed = <String, List<String>>{};
      for (final item in latest.values.where((item) => !item.deleted)) {
        changed.putIfAbsent(item.resource, () => []).add(item.resourceId);
      }
      // Balances are derived upstream from anchors plus txn deltas, so either
      // moving means the account read model moved as well.
      if (changed.containsKey('txns') ||
          changed.containsKey('balance_anchors')) {
        changed.putIfAbsent('accounts', () => []);
      }

      try {
        for (final step in _steps) {
          final ids = changed[step.resource];
          if (ids == null) continue;
          applied += await step.apply(this, wire, ids);
        }
        for (final item in latest.values.where((item) => item.deleted)) {
          applied += await _applyDeletion(item);
        }
      } on BbxOffline catch (e) {
        // This page is replayed: its cursor is committed only after every row
        // and tombstone has been applied.
        return PullOutcome(
          applied: applied,
          offline: true,
          at: serverTime,
          detail: e.detail,
        );
      }

      settledCursor = page.nextCursor;
      await _setCursor(settledCursor);
      if (!page.hasMore) {
        return PullOutcome(applied: applied, offline: false, at: serverTime);
      }
    }
  }

  Future<int> _applyDeletion(SyncChange change) async {
    final kind = _kindForResource(change.resource);
    if (kind == null) return 0;
    final localId = await _ids.localFor(kind, change.resourceId);
    if (localId == null || await _outbox.owes(kind, localId)) return 0;

    await _db.transaction(() async {
      switch (kind) {
        case SyncKinds.txn:
          await (_db.delete(_db.txns)..where((x) => x.id.equals(localId))).go();
        case SyncKinds.pinned:
          await (_db.delete(
            _db.pinneds,
          )..where((x) => x.id.equals(localId))).go();
        case SyncKinds.seal:
          final day = SyncIds.dayForLocalId(localId);
          await (_db.delete(
            _db.daySeals,
          )..where((x) => x.date.equals(day))).go();
        case SyncKinds.journal:
          final day = SyncIds.dayForLocalId(localId);
          await (_db.delete(
            _db.journalEntries,
          )..where((x) => x.date.equals(day))).go();
        case SyncKinds.vault:
          await (_db.delete(
            _db.vaultItems,
          )..where((x) => x.id.equals(localId))).go();
        case SyncKinds.note:
          await (_db.delete(
            _db.notes,
          )..where((x) => x.id.equals(localId))).go();
        case SyncKinds.focus:
          await (_db.delete(
            _db.focusSessions,
          )..where((x) => x.id.equals(localId))).go();
        case SyncKinds.event:
          await (_db.delete(
            _db.events,
          )..where((x) => x.id.equals(localId))).go();
        default:
          // Accounts, categories, budgets, goals and recurrings use archive /
          // inactive states in the public API. Refuse to cascade an unexpected
          // server-side hard delete through local ledger relationships.
          return;
      }
      await _ids.forget(kind, localId);
    });
    return 1;
  }

  static String? _kindForResource(String resource) => switch (resource) {
    'txns' => SyncKinds.txn,
    'pinned' => SyncKinds.pinned,
    'day_seals' => SyncKinds.seal,
    'journal_entries' => SyncKinds.journal,
    'vault_items' => SyncKinds.vault,
    'notes' => SyncKinds.note,
    'focus_sessions' => SyncKinds.focus,
    'events' => SyncKinds.event,
    _ => null,
  };

  static final _steps = <_Step>[
    _Step('accounts', _applyAccounts),
    _Step('categories', _applyCategories),
    _Step('goals', _applyGoals),
    _Step('recurrings', _applyRecurrings),
    _Step('budgets', _applyBudgets),
    _Step('pinned', _applyPinned),
    _Step('txns', _applyTxns),
    _Step('day_seals', _applySeals),
    _Step('notes', _applyNotes),
    _Step('journal_entries', _applyJournal),
    _Step('focus_sessions', _applyFocus),
    _Step('events', _applyEvents),
    _Step('vault_items', _applyVault),
  ];

  // ————— the shared shape of applying one remote row —————

  /// Resolves the row's local id, refuses to touch it when the phone still
  /// owes a write about it, and records the mapping for anything new.
  Future<int> _absorb(
    String kind,
    String remoteId,
    Future<int?> Function(int? localId) write,
  ) async {
    final localId = await _ids.localFor(kind, remoteId);
    if (localId != null && await _outbox.owes(kind, localId)) return 0;
    final settled = await write(localId);
    if (settled == null) return 0;
    if (localId == null) {
      await _ids.bind(kind, settled, remoteId, syncedAt: DateTime.now());
    } else {
      await _ids.stamp(kind, settled, DateTime.now());
    }
    return 1;
  }

  // ————— per-resource appliers —————

  static Future<int> _applyAccounts(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/accounts', {'include_archived': true});
    var n = 0;
    for (final r in rows) {
      n += await p._absorb(SyncKinds.account, '${r['id']}', (localId) async {
        final name = '${r['name']}';
        final kind = _pick(AccountKind.values, r['kind'], AccountKind.bank);
        final sortOrder = _int(r['sort_order']);
        final archived = r['archived'] == true;
        final balance = _int(r['balance_paise']);
        final asOf = _time(r['as_of']);
        if (localId == null) {
          return p._db
              .into(p._db.accounts)
              .insert(
                AccountsCompanion.insert(
                  name: name,
                  kind: kind,
                  balancePaise: Value(balance),
                  sortOrder: Value(sortOrder),
                  archived: Value(archived),
                  asOf: asOf == null ? const Value.absent() : Value(asOf),
                ),
              );
        }
        await (p._db.update(
          p._db.accounts,
        )..where((a) => a.id.equals(localId))).write(
          AccountsCompanion(
            name: Value(name),
            kind: Value(kind),
            sortOrder: Value(sortOrder),
            archived: Value(archived),
            // Only when the phone owes nothing: otherwise the server's balance
            // is missing the entries still sitting in the outbox.
            balancePaise: p._trustDerived
                ? Value(balance)
                : const Value.absent(),
            asOf: p._trustDerived && asOf != null
                ? Value(asOf)
                : const Value.absent(),
          ),
        );
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyCategories(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/categories', {'include_archived': true});
    var n = 0;
    for (final r in rows) {
      n += await p._absorb(SyncKinds.category, '${r['id']}', (localId) async {
        final name = '${r['name']}';
        final icon = '${r['icon'] ?? 'circle'}';
        final kind = _pick(
          CategoryKind.values,
          r['kind'],
          CategoryKind.expense,
        );
        final sortOrder = _int(r['sort_order']);
        final archived = r['archived'] == true;
        if (localId == null) {
          return p._db
              .into(p._db.categories)
              .insert(
                CategoriesCompanion.insert(
                  name: name,
                  icon: Value(icon),
                  kind: kind,
                  sortOrder: Value(sortOrder),
                  archived: Value(archived),
                ),
              );
        }
        await (p._db.update(
          p._db.categories,
        )..where((c) => c.id.equals(localId))).write(
          CategoriesCompanion(
            name: Value(name),
            icon: Value(icon),
            kind: Value(kind),
            sortOrder: Value(sortOrder),
            archived: Value(archived),
          ),
        );
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyGoals(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final views = await wire.list('/v1/goals', {'include_archived': true});
    var n = 0;
    for (final view in views) {
      final r = (view['goal'] as Map?)?.cast<String, dynamic>() ?? view;
      n += await p._absorb(SyncKinds.goal, '${r['id']}', (localId) async {
        final name = '${r['name']}';
        final target = _int(r['target_paise']);
        final kind = _pick(GoalKind.values, r['kind'], GoalKind.save);
        final targetDate = r['target_date'] as String?;
        final monthly = r['monthly_paise'] as int?;
        if (localId == null) {
          return p._db
              .into(p._db.goals)
              .insert(
                GoalsCompanion.insert(
                  name: name,
                  targetPaise: target,
                  kind: kind,
                  targetDate: Value(targetDate),
                  monthlyPaise: Value(monthly),
                  archived: Value(r['archived'] == true),
                ),
              );
        }
        await (p._db.update(
          p._db.goals,
        )..where((g) => g.id.equals(localId))).write(
          GoalsCompanion(
            name: Value(name),
            targetPaise: Value(target),
            kind: Value(kind),
            targetDate: Value(targetDate),
            monthlyPaise: Value(monthly),
            archived: Value(r['archived'] == true),
          ),
        );
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyRecurrings(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/recurring', {'include_inactive': true});
    var n = 0;
    for (final r in rows) {
      final accountId = await p._ids.localFor(
        SyncKinds.account,
        '${r['account_id']}',
      );
      if (accountId == null) continue;
      final categoryId = r['category_id'] == null
          ? null
          : await p._ids.localFor(SyncKinds.category, '${r['category_id']}');
      n += await p._absorb(SyncKinds.recurring, '${r['id']}', (localId) async {
        final companion = RecurringsCompanion(
          title: Value('${r['title']}'),
          amountPaise: Value(_int(r['amount_paise'])),
          categoryId: Value(categoryId),
          accountId: Value(accountId),
          kind: Value(
            _pick(RecurringKind.values, r['kind'], RecurringKind.subscription),
          ),
          everyMonths: Value(_int(r['every_months'], 1)),
          dayOfMonth: Value(_int(r['day_of_month'], 1)),
          nextDue: Value('${r['next_due']}'),
          active: Value(r['active'] != false),
        );
        if (localId == null) {
          return p._db.into(p._db.recurrings).insert(companion);
        }
        await (p._db.update(
          p._db.recurrings,
        )..where((x) => x.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyBudgets(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/budgets', {'include_archived': true});
    var n = 0;
    for (final r in rows) {
      final categoryId = r['category_id'] == null
          ? null
          : await p._ids.localFor(SyncKinds.category, '${r['category_id']}');
      n += await p._absorb(SyncKinds.budget, '${r['id']}', (localId) async {
        final companion = BudgetsCompanion(
          categoryId: Value(categoryId),
          name: Value('${r['name']}'),
          limitPaise: Value(_int(r['limit_paise'])),
          period: Value(
            _pick(BudgetPeriod.values, r['period'], BudgetPeriod.month),
          ),
          kind: Value(_pick(BudgetKind.values, r['kind'], BudgetKind.all)),
          rollover: Value(r['rollover'] == true),
          archived: Value(r['archived'] == true),
        );
        if (localId == null) {
          return p._db.into(p._db.budgets).insert(companion);
        }
        await (p._db.update(
          p._db.budgets,
        )..where((b) => b.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyPinned(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/pinned');
    var n = 0;
    for (final r in rows) {
      final accountId = await p._ids.localFor(
        SyncKinds.account,
        '${r['account_id']}',
      );
      final categoryId = await p._ids.localFor(
        SyncKinds.category,
        '${r['category_id']}',
      );
      if (accountId == null || categoryId == null) continue;
      n += await p._absorb(SyncKinds.pinned, '${r['id']}', (localId) async {
        final companion = PinnedsCompanion(
          title: Value('${r['title']}'),
          amountPaise: Value(_int(r['amount_paise'])),
          categoryId: Value(categoryId),
          accountId: Value(accountId),
          sortOrder: Value(_int(r['sort_order'])),
        );
        if (localId == null) {
          return p._db.into(p._db.pinneds).insert(companion);
        }
        await (p._db.update(
          p._db.pinneds,
        )..where((x) => x.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyTxns(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    var n = 0;
    for (final remoteId in ids) {
      final Map<String, dynamic>? r;
      try {
        r = await wire.txn(remoteId);
      } on BbxProblem {
        continue; // gone, or refused — nothing to apply either way
      }
      if (r == null) continue;

      final accountId = await p._ids.localFor(
        SyncKinds.account,
        '${r['account_id']}',
      );
      if (accountId == null) continue;
      final toAccountId = r['to_account_id'] == null
          ? null
          : await p._ids.localFor(SyncKinds.account, '${r['to_account_id']}');
      final categoryId = r['category_id'] == null
          ? null
          : await p._ids.localFor(SyncKinds.category, '${r['category_id']}');
      final goalId = r['goal_id'] == null
          ? null
          : await p._ids.localFor(SyncKinds.goal, '${r['goal_id']}');
      final recurringId = r['recurring_id'] == null
          ? null
          : await p._ids.localFor(SyncKinds.recurring, '${r['recurring_id']}');

      final row = r;
      n += await p._absorb(SyncKinds.txn, '${row['id']}', (localId) async {
        final at = _time(row['at']) ?? DateTime.now();
        final companion = TxnsCompanion(
          amountPaise: Value(_int(row['amount_paise'])),
          type: Value(_pick(TxnType.values, row['type'], TxnType.expense)),
          categoryId: Value(categoryId),
          accountId: Value(accountId),
          toAccountId: Value(toAccountId),
          title: Value('${row['title']}'),
          note: Value(row['note'] as String?),
          at: Value(at),
          goalId: Value(goalId),
          recurringId: Value(recurringId),
        );
        if (localId == null) {
          return p._db.into(p._db.txns).insert(companion);
        }
        await (p._db.update(
          p._db.txns,
        )..where((t) => t.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applySeals(
    SyncPuller p,
    SyncWire wire,
    List<String> days,
  ) async {
    final span = _span(days);
    if (span == null) return 0;
    final rows = await wire.list('/v1/seals', span);
    var n = 0;
    for (final r in rows) {
      final day = '${r['date']}';
      n += await p._absorb(SyncKinds.seal, day, (_) async {
        await p._db
            .into(p._db.daySeals)
            .insertOnConflictUpdate(
              DaySealsCompanion(
                date: Value(day),
                sealedAt: Value(_time(r['sealed_at']) ?? DateTime.now()),
              ),
            );
        return SyncIds.localIdForDay(day);
      });
    }
    return n;
  }

  static Future<int> _applyJournal(
    SyncPuller p,
    SyncWire wire,
    List<String> days,
  ) async {
    final span = _span(days);
    if (span == null) return 0;
    final rows = await wire.list('/v1/journal', span);
    var n = 0;
    for (final r in rows) {
      final day = '${r['date']}';
      n += await p._absorb(SyncKinds.journal, day, (_) async {
        await p._db
            .into(p._db.journalEntries)
            .insertOnConflictUpdate(
              JournalEntriesCompanion(
                date: Value(day),
                body: Value('${r['body'] ?? ''}'),
                mood: Value(r['mood'] as int?),
                energy: Value(r['energy'] as int?),
                feelWord: Value(r['feel_word'] as String?),
                feelWhy: Value(r['feel_why'] as String?),
                feelTags: Value(r['feel_tags'] as String?),
                updatedAt: Value(_time(r['updated_at']) ?? DateTime.now()),
              ),
            );
        return SyncIds.localIdForDay(day);
      });
    }
    return n;
  }

  static Future<int> _applyNotes(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/notes', {'include_archived': true});
    var n = 0;
    for (final r in rows) {
      n += await p._absorb(SyncKinds.note, '${r['id']}', (localId) async {
        final companion = NotesCompanion(
          title: Value('${r['title'] ?? ''}'),
          body: Value('${r['body'] ?? ''}'),
          pinned: Value(r['pinned'] == true),
          remindAt: Value(_time(r['remind_at'])),
          completed: Value(r['completed'] == true),
          archived: Value(r['archived'] == true),
          updatedAt: Value(_time(r['updated_at']) ?? DateTime.now()),
          createdAt: Value(_time(r['created_at']) ?? DateTime.now()),
        );
        if (localId == null) {
          return p._db.into(p._db.notes).insert(companion);
        }
        await (p._db.update(
          p._db.notes,
        )..where((x) => x.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyFocus(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/focus/sessions');
    var n = 0;
    for (final r in rows) {
      n += await p._absorb(SyncKinds.focus, '${r['id']}', (localId) async {
        final companion = FocusSessionsCompanion(
          startedAt: Value(_time(r['started_at']) ?? DateTime.now()),
          minutes: Value(_int(r['minutes'])),
          kind: Value(_pick(FocusKind.values, r['kind'], FocusKind.work)),
          completed: Value(r['completed'] == true),
          label: Value(r['label'] as String?),
        );
        if (localId == null) {
          return p._db.into(p._db.focusSessions).insert(companion);
        }
        await (p._db.update(
          p._db.focusSessions,
        )..where((x) => x.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyEvents(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/events/all', {'include_archived': true});
    var n = 0;
    for (final r in rows) {
      n += await p._absorb(SyncKinds.event, '${r['id']}', (localId) async {
        final companion = EventsCompanion(
          title: Value('${r['title']}'),
          note: Value(r['note'] as String?),
          date: Value('${r['date']}'),
          timeMinutes: Value(r['time_minutes'] as int?),
          repeat: Value(
            _pick(EventRepeat.values, r['repeat'], EventRepeat.none),
          ),
          archived: Value(r['archived'] == true),
        );
        if (localId == null) {
          return p._db.into(p._db.events).insert(companion);
        }
        await (p._db.update(
          p._db.events,
        )..where((x) => x.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  static Future<int> _applyVault(
    SyncPuller p,
    SyncWire wire,
    List<String> ids,
  ) async {
    final rows = await wire.list('/v1/vault');
    var n = 0;
    for (final r in rows) {
      n += await p._absorb(SyncKinds.vault, '${r['id']}', (localId) async {
        final companion = VaultItemsCompanion(
          nonce: Value('${r['nonce']}'),
          cipher: Value('${r['cipher']}'),
          updatedAt: Value(_time(r['updated_at']) ?? DateTime.now()),
          createdAt: Value(_time(r['created_at']) ?? DateTime.now()),
        );
        if (localId == null) {
          return p._db.into(p._db.vaultItems).insert(companion);
        }
        await (p._db.update(
          p._db.vaultItems,
        )..where((x) => x.id.equals(localId))).write(companion);
        return localId;
      });
    }
    return n;
  }

  // ————— small readers —————

  static Map<String, dynamic>? _span(List<String> days) {
    final valid = days.where((d) => d.length >= 10).toList()..sort();
    if (valid.isEmpty) return null;
    final last = DateTime.tryParse(valid.last);
    if (last == null) return null;
    final end = last.add(const Duration(days: 1));
    final toDay =
        '${end.year.toString().padLeft(4, '0')}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}';
    return {'from_day': valid.first, 'to_day': toDay};
  }

  static int _int(Object? v, [int fallback = 0]) =>
      v is int ? v : int.tryParse('$v') ?? fallback;

  static DateTime? _time(Object? v) =>
      v == null ? null : DateTime.tryParse('$v')?.toLocal();

  static T _pick<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == '$name') return v;
    }
    return fallback;
  }
}

class _Step {
  const _Step(this.resource, this.apply);

  final String resource;
  final Future<int> Function(SyncPuller, SyncWire, List<String>) apply;
}
