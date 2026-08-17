import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';
import 'api/api_client.dart';
import 'api/endpoints/coaching_api.dart';
import 'dev_seed.dart';
import 'nudges.dart';
import 'repos/marks_repo.dart';
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

final txnRepoProvider = Provider<TxnRepo>(
  (ref) => TxnRepo(ref.watch(dbProvider)),
);

final accountRepoProvider = Provider<AccountRepo>(
  (ref) => AccountRepo(ref.watch(dbProvider)),
);

final pinnedRepoProvider = Provider<PinnedRepo>(
  (ref) => PinnedRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

final budgetRepoProvider = Provider<BudgetRepo>(
  (ref) => BudgetRepo(ref.watch(dbProvider)),
);

final recurringRepoProvider = Provider<RecurringRepo>(
  (ref) => RecurringRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

final goalRepoProvider = Provider<GoalRepo>(
  (ref) => GoalRepo(ref.watch(dbProvider), ref.watch(txnRepoProvider)),
);

final settingsRepoProvider = Provider<SettingsRepo>(
  (ref) => SettingsRepo(ref.watch(dbProvider)),
);

final marksRepoProvider = Provider<MarksRepo>(
  (ref) => MarksRepo(ref.watch(dbProvider)),
);

/// What the book was asked to watch for — 'leaks', 'goal', or 'truth'.
/// Loaded once from settings, then kept live, so the Today page reorders
/// itself the moment the answer changes rather than on the next launch.
final intentProvider = NotifierProvider<IntentNotifier, String?>(
  IntentNotifier.new,
);

class IntentNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.read(settingsRepoProvider).intent().then((saved) {
      if (saved != null && saved != state) state = saved;
    });
    return null;
  }

  void set(String value) {
    state = value;
    ref.read(settingsRepoProvider).setIntent(value);
  }
}

final nudgesProvider = Provider<Nudges>(
  (ref) => Nudges(
    ref.watch(dbProvider),
    ref.watch(settingsRepoProvider),
    ref.watch(txnRepoProvider),
    ref.watch(recurringRepoProvider),
  ),
);

/// Evidence-backed server coaching. An unwired book stays silent; network
/// failure also stays out of Today's way and remains visible through sync
/// status rather than replacing the ledger with an error panel.
final coachingFeedProvider = FutureProvider.autoDispose<List<CoachingInsight>>((
  ref,
) async {
  final config = await ref.watch(settingsRepoProvider).serverConfig();
  if (!config.wired) return const [];
  final client = BbxClient(config);
  try {
    return await CoachingApi(client).feed();
  } on BbxOffline {
    return const [];
  } on BbxProblem {
    return const [];
  } finally {
    client.close();
  }
});
