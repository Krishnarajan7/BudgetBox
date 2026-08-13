import 'package:drift/drift.dart';

/// Money is always integer paise. Dates that mean a calendar day (not an
/// instant) are stored as 'yyyy-MM-dd' text so timezones can never shift them.

enum AccountKind { bank, upi, cash, card, asset, liability }

enum CategoryKind { expense, income }

enum TxnType { expense, income, transfer }

enum RecurringKind { bill, subscription }

enum BudgetPeriod { month, fy, custom }

/// `all` auto-includes matching transactions (the monthly food budget);
/// `added` only counts hand-picked ones (the trip book).
enum BudgetKind { all, added }

enum GoalKind { save, clear }

enum ActivityAction { created, edited, deleted }

class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get kind => intEnum<AccountKind>()();
  IntColumn get balancePaise => integer().withDefault(const Constant(0))();

  /// When the balance was last confirmed true — drives the staleness cue.
  DateTimeColumn get asOf => dateTime().withDefault(currentDateAndTime)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  /// A key into [LedgerIcons.catalogue] — categories wear drawn marks, not
  /// typed ones.
  TextColumn get icon => text().withDefault(const Constant('circle'))();
  IntColumn get kind => intEnum<CategoryKind>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Txns extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get amountPaise => integer()();
  IntColumn get type => intEnum<TxnType>()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// Transfer destination; null for expense/income.
  IntColumn get toAccountId => integer().nullable().references(Accounts, #id)();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get note => text().nullable()();
  DateTimeColumn get at => dateTime()();
  IntColumn get goalId => integer().nullable().references(Goals, #id)();
  IntColumn get recurringId =>
      integer().nullable().references(Recurrings, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Recurrings extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  IntColumn get amountPaise => integer()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get kind => intEnum<RecurringKind>()();

  /// Every n months (1 = monthly, 12 = yearly).
  IntColumn get everyMonths => integer().withDefault(const Constant(1))();

  /// Day of month it lands (clamped to month length).
  IntColumn get dayOfMonth => integer()();
  TextColumn get nextDue => text()(); // yyyy-MM-dd
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null = an overall (all-categories) budget.
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get limitPaise => integer()();
  IntColumn get period => intEnum<BudgetPeriod>()();
  IntColumn get kind => intEnum<BudgetKind>()();
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
  IntColumn get targetPaise => integer()();
  IntColumn get kind => intEnum<GoalKind>()();
  TextColumn get targetDate => text().nullable()(); // yyyy-MM-dd
  IntColumn get monthlyPaise => integer().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// One-tap repeats: the chai, the auto, the mess lunch.
class Pinneds extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  IntColumn get amountPaise => integer()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

/// The once-daily close: one stamp per day, earned.
class DaySeals extends Table {
  TextColumn get date => text()(); // yyyy-MM-dd
  DateTimeColumn get sealedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {date};
}

/// Undo + audit: every mutation of the ledger leaves a line here.
class Activities extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get txnId => integer()();
  IntColumn get action => intEnum<ActivityAction>()();

  /// JSON snapshot of the row before/after, enough to undo.
  TextColumn get snapshot => text()();
  DateTimeColumn get at => dateTime().withDefault(currentDateAndTime)();
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ————— the other books in the box —————

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

enum FocusKind { work, rest }

class FocusSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get minutes => integer()();
  IntColumn get kind => intEnum<FocusKind>()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  TextColumn get label => text().nullable()();
}

class JournalEntries extends Table {
  /// One page per day: 'yyyy-MM-dd'.
  TextColumn get date => text()();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// 1 (rough) … 5 (great); null when unrecorded.
  IntColumn get mood => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {date};
}

enum EventRepeat { none, yearly }

class Events extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 120)();
  TextColumn get note => text().nullable()();

  /// Anchor date 'yyyy-MM-dd'; a yearly repeat recurs on this month+day.
  TextColumn get date => text()();

  /// Minutes past midnight; null = all-day.
  IntColumn get timeMinutes => integer().nullable()();
  IntColumn get repeat =>
      intEnum<EventRepeat>().withDefault(Constant(EventRepeat.none.index))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Zero-knowledge at rest: the row is a nonce + ciphertext blob. Title and
/// body only ever exist decrypted in memory, behind the vault passphrase.
/// A forgotten passphrase is permanent loss — by design.
class VaultItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get nonce => text()();
  TextColumn get cipher => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One balance reading per account per day — the memory behind Worth's
/// sparklines and the net-worth line. Written whenever a balance changes.
class BalanceSnapshots extends Table {
  IntColumn get accountId => integer().references(Accounts, #id)();
  TextColumn get date => text()(); // yyyy-MM-dd
  IntColumn get balancePaise => integer()();

  @override
  Set<Column> get primaryKey => {accountId, date};
}

/// The day's marks — the small daily truths the book keeps besides money.
/// One row per mark: a habit done ('bath', 'run', 'push', 'pull', 'squat'),
/// a meal eaten ('meal', with the food in [note]), or the one mark that
/// counts by its absence ('slip' — a clean day is a day with no slip row).
/// [kind] is a plain string so a new habit never needs a schema change.
class DayMarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get date => text()(); // yyyy-MM-dd
  TextColumn get kind => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get at => dateTime().withDefault(currentDateAndTime)();
}

// ————— the wire —————
//
// The phone keeps its own row numbers because every screen is built on them.
// The server speaks uuid7. These two tables are the whole bridge: one maps
// the ids in both directions, the other is the queue of writes still owed to
// the server. Nothing above the repos knows either exists.

/// What a queued write asks the server to do.
enum OutboxOp { put, patch, delete }

/// Which local table a synced row belongs to — 'txn', 'account', 'note'…
/// A plain string so a new module needs no schema change here.
class RemoteIds extends Table {
  TextColumn get kind => text()();

  /// The autoincrement id the UI knows this row by.
  IntColumn get localId => integer()();

  /// The server's uuid7. Minted on the phone when the row is first queued,
  /// so a write can be retried blindly and stay idempotent.
  TextColumn get remoteId => text()();

  /// The server's `updated_at` as of the last successful sync — what a pull
  /// compares against to know whether the phone's copy is stale.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {kind, localId};
}

/// Writes owed to the server, oldest first. A row lives here until the
/// server has acknowledged it, so a day spent on the Konkan railway with no
/// signal costs nothing.
class Outbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  IntColumn get localId => integer()();

  /// The uuid7 this write targets — the idempotency key.
  TextColumn get remoteId => text()();
  IntColumn get op => intEnum<OutboxOp>()();

  /// The request body as JSON. Null for a delete.
  TextColumn get payload => text().nullable()();
  DateTimeColumn get queuedAt => dateTime().withDefault(currentDateAndTime)();

  /// Attempts so far, and why the last one failed — the sync page's evidence
  /// when something is stuck, rather than a silent retry loop.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}
