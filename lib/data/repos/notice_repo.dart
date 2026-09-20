import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../db.dart';
import '../providers.dart';

final noticeRepoProvider = Provider<NoticeRepo>(
  (ref) => NoticeRepo(ref.watch(dbProvider)),
);

/// The notification ledger's keeper. Every book's reminders land here
/// through [LedgerReminders.log], so the Notifications page can read
/// them back as one list — what was said, what is coming, what he opened.
class NoticeRepo implements ReminderLog {
  NoticeRepo(this._db);

  final LedgerDb _db;

  /// A reminder laid down: any earlier row for the same id that has not
  /// yet had its hour is replaced — re-saying tonight's line after every
  /// entry must not leave nine copies of it.
  @override
  Future<void> scheduled({
    required int id,
    required String module,
    required String title,
    required String body,
    required DateTime at,
    String? repeat,
    String? payload,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      await (_db.delete(
        _db.notices,
      )..where((n) => n.notifId.equals(id) & n.at.isBiggerThanValue(now))).go();
      await _db
          .into(_db.notices)
          .insert(
            NoticesCompanion.insert(
              notifId: id,
              module: module,
              title: title,
              body: body,
              at: at,
              repeat: Value(repeat),
              payload: Value(payload),
            ),
          );
    });
  }

  @override
  Future<void> cancelled(int id) async {
    final now = DateTime.now();
    await (_db.delete(
      _db.notices,
    )..where((n) => n.notifId.equals(id) & n.at.isBiggerThanValue(now))).go();
  }

  @override
  Future<void> opened(int id) async {
    final now = DateTime.now();
    await (_db.update(_db.notices)..where(
          (n) =>
              n.notifId.equals(id) &
              n.openedAt.isNull() &
              n.at.isSmallerOrEqualValue(now.add(const Duration(minutes: 1))),
        ))
        .write(NoticesCompanion(openedAt: Value(now)));
  }

  /// Settles the fate of every line whose hour has passed. In the tray
  /// means shown — and stays shown once seen, dismissed or not. Still
  /// pending with no later copy laid means the phone is holding it back.
  /// Otherwise it is gone from the phone's list, which is what said
  /// looks like from here.
  @override
  Future<void> reconcile({
    required Set<int> pending,
    required Set<int> active,
  }) {
    return _db.transaction(() async {
      final now = DateTime.now();
      final rows = await (_db.select(
        _db.notices,
      )..where((n) => n.at.isSmallerOrEqualValue(now))).get();
      final relaid = {
        for (final n in await (_db.select(
          _db.notices,
        )..where((n) => n.at.isBiggerThanValue(now))).get())
          n.notifId,
      };
      for (final n in rows) {
        if (n.fate == 'shown') continue;
        final fate = active.contains(n.notifId)
            ? 'shown'
            : pending.contains(n.notifId) && !relaid.contains(n.notifId)
            ? 'stuck'
            : 'said';
        if (fate == n.fate) continue;
        await (_db.update(_db.notices)..where((x) => x.id.equals(n.id))).write(
          NoticesCompanion(fate: Value(fate)),
        );
      }
    });
  }

  /// The last [days] of what was said and everything still to come,
  /// newest first.
  Stream<List<Notice>> watch({int days = 30}) {
    final since = DateTime.now().subtract(Duration(days: days));
    return (_db.select(_db.notices)
          ..where((n) => n.at.isBiggerOrEqualValue(since))
          ..orderBy([(n) => OrderingTerm.desc(n.at)]))
        .watch();
  }

  /// Rows older than [days] go; the ledger is a record, not an archive.
  Future<int> prune({int days = 60}) {
    final before = DateTime.now().subtract(Duration(days: days));
    return (_db.delete(
      _db.notices,
    )..where((n) => n.at.isSmallerThanValue(before))).go();
  }
}
