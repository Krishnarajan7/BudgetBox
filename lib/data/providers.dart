import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'dev_seed.dart';
import 'repos/account_repo.dart';
import 'repos/budget_repo.dart';
import 'repos/goal_repo.dart';
import 'repos/pinned_repo.dart';
import 'repos/recurring_repo.dart';
import 'repos/settings_repo.dart';
import 'repos/txn_repo.dart';

/// The single database instance. Overridden with an in-memory executor in
/// tests.
final dbProvider = Provider<LedgerDb>((ref) {
  final db = LedgerDb();
  // The setup ritual owns first launch now. A fake month is still available
  // for UI work: flutter run --dart-define=DEV_SEED=true
  const wantSeed = bool.fromEnvironment('DEV_SEED');
  if (wantSeed && kDebugMode) {
    unawaited(devSeed(db));
  }
  ref.onDispose(db.close);
  return db;
});

final txnRepoProvider =
    Provider<TxnRepo>((ref) => TxnRepo(ref.watch(dbProvider)));

final accountRepoProvider =
    Provider<AccountRepo>((ref) => AccountRepo(ref.watch(dbProvider)));

final pinnedRepoProvider = Provider<PinnedRepo>(
  (ref) => PinnedRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

final budgetRepoProvider =
    Provider<BudgetRepo>((ref) => BudgetRepo(ref.watch(dbProvider)));

final recurringRepoProvider = Provider<RecurringRepo>(
  (ref) => RecurringRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

final goalRepoProvider = Provider<GoalRepo>(
  (ref) => GoalRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

final settingsRepoProvider =
    Provider<SettingsRepo>((ref) => SettingsRepo(ref.watch(dbProvider)));
