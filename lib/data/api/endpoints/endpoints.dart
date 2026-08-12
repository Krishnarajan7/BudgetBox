/// The typed face of the backend: one file per module, one method per
/// operation, and a DTO for every shape that crosses the wire.
///
/// Everything here is a thin, honest translation of `backend/openapi.json` —
/// no caching, no retrying, no deciding what a failure means. A call either
/// returns its DTO or throws `BbxOffline` / `BbxProblem` straight through to
/// the sync engine, which is the only layer that knows whether a write is
/// still owed.
///
/// Three conventions hold everywhere, and [wire] is where they are enforced:
/// money is integer paise, a calendar day is a 'yyyy-MM-dd' `String`, and an
/// instant is a local-time `DateTime`.
library;

export 'accounts_api.dart';
export 'activities_api.dart';
export 'budgets_api.dart';
export 'categories_api.dart';
export 'changes_api.dart';
export 'coaching_api.dart';
export 'events_api.dart';
export 'export_api.dart';
export 'focus_api.dart';
export 'goals_api.dart';
export 'insights_api.dart';
export 'journal_api.dart';
export 'networth_api.dart';
export 'notes_api.dart';
export 'pinned_api.dart';
export 'recurring_api.dart';
export 'seals_api.dart';
export 'settings_api.dart';
export 'summary_api.dart';
export 'system_api.dart';
export 'txns_api.dart';
export 'vault_api.dart';
export 'wire.dart';
