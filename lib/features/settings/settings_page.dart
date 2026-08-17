import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/notifications.dart';
import '../../core/occasions.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/api/api_client.dart';
import '../../data/api/api_config.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_engine.dart';
import '../setup/setup_flow.dart';
import 'account_manager.dart';
import 'activity_log.dart';
import 'category_manager.dart';
import 'coaching_manager.dart';
import 'pinned_manager.dart';

/// Day / night / follow-the-sun — persisted in the settings table, loaded on
/// first read so the book keeps its light across launches.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.read(settingsRepoProvider).themeMode().then((saved) {
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null && mode != state) state = mode;
    });
    return ThemeMode.system;
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(settingsRepoProvider).setThemeMode(mode.name);
  }
}

// ————— pure helpers (the bits worth testing on their own) —————

/// '1st', '2nd', '23rd' — the salary day said the way a person says it.
String ordinalDay(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

/// How the stored year frame reads on the page: the frame itself, then the
/// months it spans.
String yearFrameCaption(String frame, {DateTime? now}) {
  final d = now ?? DateTime.now();
  return frame == 'fy'
      ? '${LedgerDates.fyLabel(d)} · April to March'
      : '${d.year} · January to December';
}

/// 1–31 laid out seven to a line — the salary-day grid.
List<List<int>> salaryDayGrid() {
  final out = <List<int>>[];
  for (var start = 1; start <= 31; start += 7) {
    out.add([for (var d = start; d < start + 7 && d <= 31; d++) d]);
  }
  return out;
}

/// A CSV cell, quoted only when it has to be.
String csvCell(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  final body = value.replaceAll('"', '""');
  return needsQuotes ? '"$body"' : body;
}

String csvRow(List<String> cells) => cells.map(csvCell).join(',');

/// Paise as plain rupees for a spreadsheet — no symbol, no grouping, two
/// decimals. The ₹ formatting belongs on the page, not in the file.
String csvAmount(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

String _hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// The whole book as one CSV sheet, oldest first.
String buildLedgerCsv(
  List<Txn> txns, {
  required Map<int, String> categories,
  required Map<int, String> accounts,
}) {
  final lines = <String>[
    csvRow(const [
      'date',
      'time',
      'title',
      'type',
      'amount',
      'category',
      'account',
      'note',
    ]),
  ];
  for (final t in txns) {
    lines.add(
      csvRow([
        LedgerDates.dayKey(t.at),
        _hhmm(t.at),
        t.title,
        t.type.name,
        csvAmount(t.amountPaise),
        t.categoryId == null ? '' : categories[t.categoryId] ?? '',
        accounts[t.accountId] ?? '',
        t.note ?? '',
      ]),
    );
  }
  return '${lines.join('\n')}\n';
}

/// The box — settings by intent, never an A–Z toggle dump.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  int? _salaryDay;
  (int, int)? _birthday;
  (int, int)? _nudge;
  String? _yearFrame;
  bool? _hasPin;
  int _entries = 0;
  int _daysClosed = 0;

  _Note? _exportNote;
  _Note? _backupNote;
  Timer? _exportTimer;
  Timer? _backupTimer;

  /// Where this book syncs. Null while the settings table is still being read.
  BbxConfig? _server;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _exportTimer?.cancel();
    _backupTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsRepoProvider);
    final day = await settings.salaryDay();
    final frame = await settings.yearFrame();
    final birthday = await settings.birthday();
    final nudge = await settings.nudgeTime();
    final hasPin = await settings.hasPin();
    final server = await settings.serverConfig();
    final facts = await _countFacts();
    if (!mounted) return;
    setState(() {
      _salaryDay = day;
      _birthday = birthday;
      _nudge = nudge;
      _yearFrame = frame;
      _hasPin = hasPin;
      _server = server;
      _entries = facts.$1;
      _daysClosed = facts.$2;
    });
  }

  /// Two cheap counts: how much is written, and how many days were closed.
  Future<(int, int)> _countFacts() async {
    final db = ref.read(dbProvider);
    final entries = db.txns.id.count();
    final entriesRow = await (db.selectOnly(
      db.txns,
    )..addColumns([entries])).getSingle();
    final sealed = db.daySeals.date.count();
    final sealedRow = await (db.selectOnly(
      db.daySeals,
    )..addColumns([sealed])).getSingle();
    return (entriesRow.read(entries) ?? 0, sealedRow.read(sealed) ?? 0);
  }

  Future<void> _refreshPin() async {
    final has = await ref.read(settingsRepoProvider).hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  // ————— rhythm —————

  Future<void> _pickSalaryDay() async {
    final picked = await showSalaryDaySheet(context, current: _salaryDay ?? 1);
    if (picked == null || !mounted) return;
    setState(() => _salaryDay = picked);
    await ref.read(settingsRepoProvider).setSalaryDay(picked);
  }

  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// The same question the ritual asked, answerable again: what the book
  /// watches for. It reorders the Today page, nothing more.
  Future<void> _pickIntent() async {
    final picked = await showLedgerSheet<String>(
      context,
      builder: (context) => _IntentSheet(current: ref.read(intentProvider)),
    );
    if (picked == null || !mounted) return;
    ref.read(intentProvider.notifier).set(picked);
  }

  Future<void> _pickBirthday() async {
    final picked = await showLedgerSheet<(int, int)>(
      context,
      builder: (context) => _BirthdaySheet(current: _birthday),
    );
    if (picked == null || !mounted) return;
    setState(() => _birthday = picked);
    await ref.read(settingsRepoProvider).setBirthday(picked.$1, picked.$2);
    // And onto the calendar, as one yearly "my birthday" — the two entries
    // are the same fact, so they move together.
    await Occasions(
      ref.read(dbProvider),
    ).birthdaySetInSettings(picked.$1, picked.$2);
  }

  Future<void> _pickNudge() async {
    final picked = await showLedgerSheet<((int, int)?, bool)>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                const SizedBox(height: Gap.x2),
                Text(
                  'a nudge to close the day?',
                  style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  'One notification, in the evening, asking nothing more '
                  'than whether the page is done.',
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(height: Gap.x3),
                Wrap(
                  spacing: Gap.x2,
                  runSpacing: Gap.x2,
                  children: [
                    for (final (h, m) in const [
                      (20, 30),
                      (21, 0),
                      (21, 30),
                      (22, 0),
                      (22, 30),
                    ])
                      LedgerChip(
                        '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}',
                        selected: _nudge == (h, m),
                        onTap: () => Navigator.of(context).pop(((h, m), false)),
                      ),
                    LedgerChip(
                      'off',
                      selected: _nudge == null,
                      onTap: () => Navigator.of(context).pop((null, true)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    final settings = ref.read(settingsRepoProvider);
    final (time, turnOff) = picked;
    if (turnOff || time == null) {
      await settings.clearNudge();
      // The hour is the voice's one switch: clearing it quiets everything —
      // tonight, salary morning, the dues.
      await ref.read(nudgesProvider).resync();
      if (mounted) setState(() => _nudge = null);
      return;
    }
    // Permission first; a refused nudge is not stored as a promise.
    final ok = await LedgerReminders.requestPermission();
    if (!ok) {
      if (mounted) {
        _say(
          false,
          _Note('the phone said no — allow notifications first', ok: false),
        );
      }
      return;
    }
    await settings.setNudgeTime(time.$1, time.$2);
    await ref.read(nudgesProvider).resync();
    if (mounted) setState(() => _nudge = time);
  }

  Future<void> _swapYearFrame() async {
    final next = _yearFrame == 'fy' ? 'calendar' : 'fy';
    setState(() => _yearFrame = next);
    await ref.read(settingsRepoProvider).setYearFrame(next);
  }

  // ————— the data —————

  void _say(bool export, _Note note) {
    setState(() {
      if (export) {
        _exportNote = note;
      } else {
        _backupNote = note;
      }
    });
    final timer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      setState(() {
        if (export) {
          _exportNote = null;
        } else {
          _backupNote = null;
        }
      });
    });
    if (export) {
      _exportTimer?.cancel();
      _exportTimer = timer;
    } else {
      _backupTimer?.cancel();
      _backupTimer = timer;
    }
  }

  Future<void> _export() async {
    try {
      final db = ref.read(dbProvider);
      final txns = await (db.select(
        db.txns,
      )..orderBy([(t) => OrderingTerm.asc(t.at)])).get();
      final categories = {
        for (final c in await db.select(db.categories).get()) c.id: c.name,
      };
      final accounts = {
        for (final a in await db.select(db.accounts).get()) a.id: a.name,
      };
      final csv = buildLedgerCsv(
        txns,
        categories: categories,
        accounts: accounts,
      );
      final dir = await getApplicationDocumentsDirectory();
      final name = 'budgetbox-${LedgerDates.dayKey(DateTime.now())}.csv';
      final path = '${dir.path}/$name';
      await File(path).writeAsString(csv);
      if (!mounted) return;
      // The share sheet is the download: save to Files, send to Drive,
      // mail it — the phone's choice, not the sandbox's.
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path, mimeType: 'text/csv')]),
      );
      if (!mounted) return;
      _say(true, _Note('${txns.length} entries shared · $name', ok: true));
    } catch (_) {
      if (!mounted) return;
      _say(true, _Note('nothing written — the folder refused', ok: false));
    }
  }

  /// A whole copy of the book, taken the way SQLite prefers — the live file
  /// is never touched.
  Future<void> _backup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'budgetbox-${LedgerDates.dayKey(DateTime.now())}.sqlite';
      final file = File('${dir.path}/$name');
      if (file.existsSync()) await file.delete();
      await ref.read(dbProvider).customStatement('VACUUM INTO ?', [file.path]);
      final kb = (await file.length()) ~/ 1024;
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      if (!mounted) return;
      _say(false, _Note('$kb KB ready to save · $name', ok: true));
    } catch (_) {
      if (!mounted) return;
      _say(false, _Note('nothing copied — the folder refused', ok: false));
    }
  }

  void _push(Widget page) {
    Navigator.of(context).push(LedgerRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final mode = ref.watch(themeModeProvider);
    var section = 0;
    Duration next() => Duration(milliseconds: 50 * section++);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Row(
                children: [
                  Pressable(
                    scale: 0.9,
                    onTap: () => Navigator.of(context).pop(),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: PenChevron(size: 16, color: c.inkFaint),
                    ),
                  ),
                  const SizedBox(width: Gap.x3),
                  Text(
                    'the box',
                    style: LedgerType.wordmark.copyWith(color: c.ink),
                  ),
                ],
              ),
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('appearance'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                  child: Wrap(
                    spacing: Gap.x2,
                    runSpacing: Gap.x2,
                    children: [
                      // Words carry the choice — the book has no weather
                      // icons, and 'night' says night better than a moon.
                      for (final (m, label) in const [
                        (ThemeMode.light, 'day'),
                        (ThemeMode.dark, 'night'),
                        (ThemeMode.system, 'follow the sun'),
                      ])
                        _ThemeChip(
                          label: label,
                          selected: mode == m,
                          onTap: () =>
                              ref.read(themeModeProvider.notifier).set(m),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('my book'),
                _Row(
                  'Categories',
                  'your words, your marks',
                  onTap: () => _push(const CategoryManagerPage()),
                ),
                _Row(
                  'Accounts',
                  'banks, cash, cards',
                  onTap: () => _push(const AccountManagerPage()),
                ),
                _Row(
                  'Pinned entries',
                  'the one-tap repeats',
                  onTap: () => _push(const PinnedManagerPage()),
                ),
                _Row(
                  'Spending guide',
                  'teach the book what is worth it',
                  onTap: () => _push(const CoachingManagerPage()),
                ),
                // The ritual's one question, finally changeable — the hint
                // there always promised it could be.
                _Row(
                  'Watching for',
                  switch (ref.watch(intentProvider)) {
                    'leaks' => 'the leaks — the month leads Today',
                    'goal' => 'the saving — the goal leads Today',
                    'truth' => 'the plain truth — no favourites',
                    _ => 'never asked — the plain order',
                  },
                  onTap: _pickIntent,
                ),
              ],
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('rhythm'),
                _Row(
                  'Salary day',
                  _salaryDay == null
                      ? 'reading the book…'
                      : 'the ${ordinalDay(_salaryDay!)}, every month',
                  onTap: _pickSalaryDay,
                ),
                _Row('Birthday', switch (_birthday) {
                  null => 'unset — the book never celebrates',
                  (final d, final m) =>
                    '$d ${_monthsShort[m - 1]} — one shower of seals a year',
                }, onTap: _pickBirthday),
                _Row('Evening nudge', switch (_nudge) {
                  null => 'off — the book waits to be opened',
                  (final h, final m) =>
                    'at ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} — close the day',
                }, onTap: _pickNudge),
                _Row(
                  'Year',
                  _yearFrame == null
                      ? 'reading the book…'
                      : yearFrameCaption(_yearFrame!),
                  onTap: _yearFrame == null ? null : _swapYearFrame,
                  goesSomewhere: false,
                  trailing: Text(
                    'swap',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 11,
                      color: c.quill,
                    ),
                  ),
                ),
              ],
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('lock'),
                _Row('PIN', switch (_hasPin) {
                  null => 'reading the book…',
                  true => 'set — tap to change it',
                  false => 'not set — tap to add one',
                }, onTap: () => _setPin()),
                // No toggle exists for the face: the cover asks for it
                // whenever a PIN is set. A fact, not a dead switch.
                _Row('Face ID', switch (_hasPin) {
                  null => 'reading the book…',
                  true => 'already on — it asks first, the PIN waits behind',
                  false => 'waits on a PIN — set one and the face takes over',
                }),
              ],
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('the data'),
                _Row(
                  'Export',
                  _exportNote?.text ?? 'CSV, any time',
                  captionColor: _exportNote?.color(c),
                  onTap: _export,
                  goesSomewhere: false,
                ),
                _Row(
                  'Backup',
                  _backupNote?.text ?? 'one file, the whole book',
                  captionColor: _backupNote?.color(c),
                  onTap: _backup,
                  goesSomewhere: false,
                ),
                _Row(
                  'Activity log',
                  'every stroke, undoable',
                  onTap: () => _push(const ActivityLogPage()),
                ),
              ],
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('the other half'),
                // The row listens to the engine: "syncing with host" told
                // nobody whether anything ever actually happened. Now it
                // answers — settled and when, still talking, offline with a
                // count owed, or a refused token that needs a hand.
                ValueListenableBuilder<SyncStatus>(
                  valueListenable: ref.read(syncEngineProvider).status,
                  builder: (context, s, _) => _Row(
                    'Server',
                    _serverCaption(s),
                    captionColor: _serverTone(c, s),
                    // The row opens the server's own page now: live status,
                    // what it holds row by row, and the erase.
                    onTap: _server == null
                        ? null
                        : () => _push(const ServerPage()),
                  ),
                ),
              ],
            ),
            _Section(
              delay: next(),
              children: [
                const RuleHeader('the ritual'),
                _Row(
                  'Run the setup ritual',
                  'preview the first-launch flow',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SetupFlow()),
                  ),
                ),
                _Row(
                  'Erase this book',
                  'this phone only — the server copy stays',
                  onTap: _eraseBook,
                  goesSomewhere: false,
                ),
              ],
            ),
            const SizedBox(height: Gap.x8),
            _Facts(entries: _entries, daysClosed: _daysClosed),
            const SizedBox(height: Gap.x6),
          ],
        ),
      ),
    );
  }

  /// What the server row says, from the engine's own mouth.
  String _serverCaption(SyncStatus s) {
    final server = _server;
    if (server == null) return 'reading the book…';
    if (!server.wired) return 'not set — this book syncs with nothing';
    final host = server.host;
    final owed = s.pending == 0
        ? ''
        : ' · ${s.pending} ${s.pending == 1 ? 'entry' : 'entries'} owed';
    return switch (s.phase) {
      SyncPhase.syncing => 'talking to $host…',
      SyncPhase.offline => 'can\'t reach $host$owed — will retry',
      SyncPhase.blocked =>
        (s.lastError?.contains('token') ?? false)
            ? '$host refused the token — tap to fix'
            : '$host answered wrongly — tap to check',
      SyncPhase.idle when s.lastSyncedAt != null =>
        'settled with $host · ${_hhmm(s.lastSyncedAt!)}$owed',
      SyncPhase.idle => 'wired to $host — first sync pending',
    };
  }

  Color? _serverTone(LedgerColors c, SyncStatus s) {
    if (_server?.wired != true) return null;
    return switch (s.phase) {
      SyncPhase.blocked => c.seal,
      SyncPhase.offline => c.warn,
      SyncPhase.idle when s.lastSyncedAt != null => c.jama,
      _ => null,
    };
  }

  /// Burn it down and begin again — the reinstall, without the reinstall.
  /// Local only: whatever the server holds is a separate decision.
  Future<void> _eraseBook() async {
    final sure = await showLedgerSheet<bool>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                'Erase this book?',
                style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'Every entry, account, budget, goal, note and setting on this '
                'phone — gone, and the setup ritual begins again. If the book '
                'syncs to a server, that copy is untouched and can be brought '
                'back through "I already have a book".',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x4),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.seal),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Erase it all'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep the book'),
              ),
            ],
          ),
        );
      },
    );
    if (sure != true || !mounted) return;

    // Stop the engine before the floor goes: nothing may sync mid-erase.
    ref.read(syncEngineProvider).reconfigure(BbxConfig.none);
    await ref.read(dbProvider).eraseBook();
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const SetupFlow(real: true),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
      (route) => false,
    );
  }

  /// Set, change, or remove the four digits that close the book.
  ///
  /// The digits come back as a value rather than through a controller this
  /// page holds: a sheet's future completes the moment the route is popped,
  /// with the reverse transition still drawing the field for another beat.
  /// Anything freed on that boundary is freed while it is still in use.
  Future<void> _setPin() async {
    final outcome = await showLedgerSheet<_PinOutcome>(
      context,
      builder: (_) => _PinSheet(canRemove: _hasPin == true),
    );
    if (!mounted) return;
    final settings = ref.read(settingsRepoProvider);
    switch (outcome) {
      case _PinChosen(:final pin)
          when pin.length == 6 && int.tryParse(pin) != null:
        await settings.setPin(pin);
      case _PinRemoved() when _hasPin == true:
        await settings.clearPin();
      // Dismissed, or six digits that weren't six digits: the book keeps
      // whatever it had.
      case _:
        break;
    }
    if (!mounted) return;
    await _refreshPin();
  }
}

/// What an erase of the server copy leaves behind.
enum _EraseChoice {
  /// The phone's book is uploaded fresh — the server ends as this phone.
  reupload,

  /// The address is forgotten too — the server ends empty and stays empty.
  disconnect,
}

/// Whose book survives when a phone that holds one is wired to a server
/// that also holds one.
enum _FirstSyncChoice { keepPhone, takeServer, merge }

/// The question the first sync used to skip: two books, one address —
/// whose is it? Shown only when both sides actually hold something.
class _FirstSyncSheet extends StatelessWidget {
  const _FirstSyncSheet();

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: Gap.x2),
          Text(
            'Two books, one address.',
            style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            'This phone holds a book, and so does that server. Decide whose '
            'it is before they speak — syncing blind would pour one into the '
            'other and double what both hold.',
            style: LedgerType.bodyText.copyWith(
              fontSize: 13,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(height: Gap.x3),
          _option(
            context,
            title: 'Keep this phone\'s book',
            caption:
                'the server copy is erased, and this book uploads itself in '
                'its place',
            choice: _FirstSyncChoice.keepPhone,
          ),
          _option(
            context,
            title: 'Take the server\'s book',
            caption:
                'entries and accounts on this phone are cleared, and the '
                'server copy comes down whole — your name, PIN and settings '
                'stay',
            choice: _FirstSyncChoice.takeServer,
          ),
          _option(
            context,
            title: 'Keep both, merged',
            caption:
                'everything from both sides lands in one book — balances and '
                'totals may double where the two overlap',
            choice: _FirstSyncChoice.merge,
          ),
          const SizedBox(height: Gap.x2),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required String title,
    required String caption,
    required _FirstSyncChoice choice,
  }) {
    final c = LedgerColors.of(context);
    return Pressable(
      scale: 0.98,
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(context).pop(choice);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: Gap.x2),
        padding: const EdgeInsets.all(Gap.x3),
        decoration: BoxDecoration(
          color: c.paperRaised,
          borderRadius: BorderRadius.circular(Corner.key),
          border: Border.all(color: c.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: LedgerType.bodyStrong.copyWith(color: c.ink)),
            const SizedBox(height: 2),
            Text(
              caption,
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

sealed class _ServerOutcome {
  const _ServerOutcome();
}

class _ServerChosen extends _ServerOutcome {
  const _ServerChosen(this.config);
  final BbxConfig config;
}

class _ServerCleared extends _ServerOutcome {
  const _ServerCleared();
}

/// Owns its two fields and both controllers, so they are freed when the route
/// leaves rather than when its future resolves — see [_PinSheet].
class _ServerSheet extends StatefulWidget {
  const _ServerSheet({required this.current});

  final BbxConfig current;

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final _url = TextEditingController(text: widget.current.baseUrl);
  late final _token = TextEditingController(text: widget.current.token);

  /// The verdict of the last test: null before one is run.
  String? _verdict;
  bool _ok = false;
  bool _testing = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  BbxConfig get _typed => BbxConfig(
    baseUrl: _url.text.trim().replaceAll(RegExp(r'/+$'), ''),
    token: _token.text.trim(),
  );

  /// Better to find out here than to leave the book quietly out of touch.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _verdict = null;
    });
    final problem = await SyncEngine.probe(_typed);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _ok = problem == null;
      _verdict = problem ?? 'answered — this book has somewhere to live';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final verdict = _verdict;
    // The sheet hands its content unbounded width, and a button asked to be
    // infinitely wide takes the whole frame down with it. Pin the body to the
    // screen so every child below lays out against a real number.
    return SizedBox(
      width: MediaQuery.sizeOf(context).width,
      child: Padding(
        padding: EdgeInsets.only(
          left: Gap.page,
          right: Gap.page,
          top: Gap.x4,
          bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            Text(
              'The other half of the book.',
              style: LedgerType.bodyStrong.copyWith(color: c.ink),
            ),
            const SizedBox(height: Gap.x1),
            Text(
              'Its address, and the one token that opens it.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x3),
            _field(c, _url, 'https://bbx.example.in', autofocus: true),
            const SizedBox(height: Gap.x2),
            _field(c, _token, 'bbx_…', obscure: true),
            if (verdict != null) ...[
              const SizedBox(height: Gap.x2),
              Text(
                verdict,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: _ok ? c.jama : c.seal,
                ),
              ),
            ],
            const SizedBox(height: Gap.x3),
            // Stacked, never side by side. The book's theme gives every
            // FilledButton `Size.fromHeight(52)` — an *infinite* minimum
            // width — which is right in a column that hands down the sheet's
            // width, and fatal in a Row, where non-flex children are measured
            // against unbounded space.
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_ServerChosen(_typed)),
              child: const Text('Save'),
            ),
            TextButton(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'asking…' : 'Test it'),
            ),
            if (widget.current.wired)
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _ServerCleared()),
                child: const Text('Stop syncing'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    LedgerColors c,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    bool autofocus = false,
  }) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.url,
      style: LedgerType.bodyText.copyWith(color: c.ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: LedgerType.bodyText.copyWith(
          color: c.inkFaint.withValues(alpha: 0.6),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.rule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill),
        ),
      ),
    );
  }
}

/// What the PIN sheet came back with.
sealed class _PinOutcome {
  const _PinOutcome();
}

class _PinChosen extends _PinOutcome {
  const _PinChosen(this.pin);
  final String pin;
}

class _PinRemoved extends _PinOutcome {
  const _PinRemoved();
}

/// The PIN sheet owns its field and the controller behind it, so the two are
/// disposed together when the route finally leaves — never a frame apart.
class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.canRemove});

  final bool canRemove;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: Gap.page,
        right: Gap.page,
        top: Gap.x4,
        bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          Text(
            'Six digits. Only your book, only you.',
            style: LedgerType.bodyStrong.copyWith(color: c.ink),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            style: LedgerType.heroAmount.copyWith(
              fontSize: 32,
              color: c.ink,
              letterSpacing: 12,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              counterText: '',
            ),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_PinChosen(_controller.text.trim())),
            child: const Text('Lock it down'),
          ),
          if (widget.canRemove)
            TextButton(
              onPressed: () => Navigator.of(context).pop(const _PinRemoved()),
              child: const Text('Remove the PIN instead'),
            ),
        ],
      ),
    );
  }
}

/// A short-lived line the row says about itself — the confirmation lives in
/// place, never in a toast.
class _Note {
  const _Note(this.text, {required this.ok});

  final String text;
  final bool ok;

  Color color(LedgerColors c) => ok ? c.jama : c.warn;
}

/// A block of the box: its ruled header and rows, inked in as one.
class _Section extends StatelessWidget {
  const _Section({required this.children, required this.delay});

  final List<Widget> children;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return InkIn(
      delay: delay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// One line of the box: the thing on the left in ink, what it currently says
/// beneath it as a caption. Never two columns of equal weight.
class _Row extends StatelessWidget {
  const _Row(
    this.title,
    this.caption, {
    this.onTap,
    this.trailing,
    this.captionColor,
    this.goesSomewhere = true,
  });

  final String title;
  final String caption;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? captionColor;

  /// Chevrons are a promise of another page — rows that act in place, or do
  /// nothing at all, don't wear one.
  final bool goesSomewhere;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: LedgerType.bodyText.copyWith(color: c.ink)),
                const SizedBox(height: 1),
                AnimatedSwitcher(
                  duration: Motion.reduced(context)
                      ? Duration.zero
                      : Motion.quick,
                  switchInCurve: Motion.curve,
                  child: Text(
                    caption,
                    key: ValueKey(caption),
                    // Subjectivity is static — no light axis to pull; the
                    // faint colour alone keeps the caption quiet.
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11.5,
                      height: 1.25,
                      color: captionColor ?? c.inkFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Gap.x2), trailing!],
          if (onTap != null && goesSomewhere) ...[
            const SizedBox(width: Gap.x2),
            RotatedBox(
              quarterTurns: 3,
              child: PenChevron(size: 13, color: c.inkFaint),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Pressable(scale: 0.985, onTap: onTap, child: row);
  }
}

/// The footer, and every word of it true: counted straight out of the book.
class _Facts extends StatelessWidget {
  const _Facts({required this.entries, required this.daysClosed});

  final int entries;
  final int daysClosed;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final words = LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint);
    final figures = LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint);
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('home-cooked, for one · ', style: words),
          CountUp(value: entries, format: (v) => '$v', style: figures),
          Text(entries == 1 ? ' entry · ' : ' entries · ', style: words),
          CountUp(value: daysClosed, format: (v) => '$v', style: figures),
          Text(daysClosed == 1 ? ' day closed' : ' days closed', style: words),
        ],
      ),
    );
  }
}

/// A theme chip that presses, and whose selection washes in rather than
/// snapping — two [LedgerChip]s crossfading in place.
class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = Motion.reduced(context) ? Duration.zero : Motion.spring;
    return Pressable(
      scale: 0.94,
      onTap: onTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            duration: d,
            curve: Motion.curve,
            opacity: selected ? 1 : 0,
            child: LedgerChip(label, selected: true),
          ),
          AnimatedOpacity(
            duration: d,
            curve: Motion.curve,
            opacity: selected ? 0 : 1,
            child: LedgerChip(label),
          ),
        ],
      ),
    );
  }
}

/// 1–31 on ruled paper: the day the salary lands, picked in one tap.
Future<int?> showSalaryDaySheet(BuildContext context, {required int current}) {
  return showLedgerSheet<int>(
    context,
    builder: (context) {
      final c = LedgerColors.of(context);
      final grid = salaryDayGrid();
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              Padding(
                padding: const EdgeInsets.only(top: Gap.x2),
                child: Text(
                  'when does the money land?',
                  style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'the book counts its months from this day',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x3),
              for (final (r, days) in grid.indexed)
                InkIn(
                  delay: Duration(milliseconds: 28 * r),
                  child: Row(
                    children: [
                      for (final d in days)
                        Expanded(
                          child: _DayCell(day: d, selected: d == current),
                        ),
                      for (var pad = days.length; pad < 7; pad++)
                        const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected});

  final int day;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      scale: 0.9,
      onTap: () => Navigator.of(context).pop(day),
      child: Container(
        height: 42,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.quillSoft : null,
          borderRadius: BorderRadius.circular(Corner.key),
          border: selected ? Border.all(color: c.quill) : null,
        ),
        child: Text(
          '$day',
          style: LedgerType.amount.copyWith(color: selected ? c.quill : c.ink),
        ),
      ),
    );
  }
}

/// The ritual's question, asked again in the same words. Pops 'leaks',
/// 'goal' or 'truth'.
class _IntentSheet extends StatelessWidget {
  const _IntentSheet({required this.current});

  final String? current;

  static const _options = [
    ('leaks', 'stop the leaks', 'the month and its charges lead Today'),
    ('goal', 'save for something', 'the goal leads, the rest follows'),
    ('truth', 'just see the truth', 'the plain order, no favourites'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'What should this book watch for?',
              style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
            ),
            const SizedBox(height: 2),
            Text(
              'it reorders the Today page, nothing more',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x3),
            for (final (i, (value, label, caption)) in _options.indexed)
              InkIn(
                delay: Duration(milliseconds: 40 * i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gap.x2),
                  child: Row(
                    children: [
                      LedgerChip(
                        label,
                        selected: value == current,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.of(context).pop(value);
                        },
                      ),
                      const SizedBox(width: Gap.x2),
                      Expanded(
                        child: Text(
                          caption,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 12,
                            color: c.inkFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Day and month, nothing else — the book does not need your year to buy
/// the chai. Pops `(day, month)`.
class _BirthdaySheet extends StatefulWidget {
  const _BirthdaySheet({required this.current});

  final (int, int)? current;

  @override
  State<_BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends State<_BirthdaySheet> {
  late int _month = widget.current?.$2 ?? DateTime.now().month;
  late int? _day = widget.current?.$1;

  static int _daysIn(int month) =>
      DateTime(2024, month + 1, 0).day; // leap-friendly Februarys keep 29

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'when were you written in?',
              style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
            ),
            const SizedBox(height: Gap.x3),
            Wrap(
              spacing: Gap.x1,
              runSpacing: Gap.x1,
              children: [
                for (final (i, m) in _SettingsPageState._monthsShort.indexed)
                  LedgerChip(
                    m.toLowerCase(),
                    selected: _month == i + 1,
                    onTap: () => setState(() {
                      _month = i + 1;
                      final d = _day;
                      if (d != null && d > _daysIn(_month)) _day = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: Gap.x3),
            Wrap(
              spacing: Gap.x1,
              runSpacing: Gap.x1,
              children: [
                for (var d = 1; d <= _daysIn(_month); d++)
                  Pressable(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop((d, _month));
                    },
                    child: Container(
                      width: 40,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _day == d
                            ? c.quill.withValues(alpha: 0.16)
                            : c.paperRaised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$d',
                        style: LedgerType.amount.copyWith(
                          fontSize: 14,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The server, as a place: what it holds, row by row, and the one match
/// that burns it. Built because a book under test stamps junk upstream —
/// the owner gets to see the copies and sweep them, permanently.
class ServerPage extends ConsumerStatefulWidget {
  const ServerPage({super.key});

  @override
  ConsumerState<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends ConsumerState<ServerPage> {
  BbxConfig? _server;
  Map<String, int>? _counts;
  String? _countsError;
  bool _fetching = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final server = await ref.read(settingsRepoProvider).serverConfig();
    if (!mounted) return;
    setState(() => _server = server);
    if (server.wired) unawaited(_fetchCounts());
  }

  Future<void> _fetchCounts() async {
    final server = _server;
    if (server == null || !server.wired || _fetching) return;
    setState(() {
      _fetching = true;
      _countsError = null;
    });
    final client = BbxClient(server);
    try {
      final body = await client.get('/v1/book/stats');
      final map = (body as Map).cast<String, dynamic>();
      final counts = (map['counts'] as Map).cast<String, int>();
      if (mounted) setState(() => _counts = counts);
    } on BbxOffline catch (e) {
      if (mounted) {
        setState(() => _countsError = 'could not reach it — ${e.detail}');
      }
    } on BbxProblem catch (e) {
      if (mounted) {
        setState(() => _countsError = 'the server refused — ${e.detail}');
      }
    } finally {
      client.close();
      if (mounted) setState(() => _fetching = false);
    }
  }

  /// Server table names, said the way the app says them.
  static String _plain(String table) => switch (table) {
    'txns' => 'entries',
    'day_seals' => 'closed days',
    'focus_sessions' => 'focus sessions',
    'journal_entries' => 'journal pages',
    'events' => 'calendar plans',
    'vault_items' => 'vault items',
    'balance_anchors' => 'balance readings',
    'change_events' => 'change log',
    'recurrings' => 'recurring charges',
    'pinneds' => 'pinned repeats',
    _ => table.replaceAll('_', ' '),
  };

  /// Burns the server copy and makes the phone forget the server it knew:
  /// queued writes, remote id mappings, the pull cursor, the adoption flag.
  /// Returns null when it worked, a sentence when it did not.
  Future<String?> _burnServerCopy(BbxConfig server) async {
    final client = BbxClient(server);
    try {
      await client.post('/v1/book/erase', {});
    } on BbxOffline catch (e) {
      return 'could not reach it — ${e.detail}';
    } on BbxProblem catch (e) {
      return 'the server refused — ${e.detail}';
    } finally {
      client.close();
    }
    final db = ref.read(dbProvider);
    await db.delete(db.outbox).go();
    await db.delete(db.remoteIds).go();
    await (db.delete(
      db.settings,
    )..where((s) => s.key.isIn(['sync.cursor', 'sync.adopted']))).go();
    return null;
  }

  Future<void> _erase() async {
    final server = _server;
    final counts = _counts;
    if (server == null || !server.wired) return;
    final total = counts?.values.fold(0, (a, b) => a + b) ?? 0;
    // The old single "erase" was a lie by omission: the server emptied, and
    // then the very next sync quietly re-uploaded the whole phone — so the
    // rows looked immortal. Now the erase *is* the decision about what
    // happens next, and both outcomes are said out loud.
    final choice = await showLedgerSheet<_EraseChoice>(
      context,
      builder: (context) {
        final c = LedgerColors.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Text(
                'Erase the server copy?',
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: 4),
              Text(
                '${total > 0 ? '$total rows go' : 'Everything there goes'}, '
                'permanently — there is no undo on the server. The book on '
                'this phone is untouched either way. What happens after?',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x4),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.seal),
                onPressed: () =>
                    Navigator.of(context).pop(_EraseChoice.reupload),
                child: const Text('Erase, then upload this book fresh'),
              ),
              const SizedBox(height: Gap.x1),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.inkFaint),
                onPressed: () =>
                    Navigator.of(context).pop(_EraseChoice.disconnect),
                child: const Text('Erase and stop syncing'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep it'),
              ),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;

    HapticFeedback.heavyImpact();
    final problem = await _burnServerCopy(server);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _note = problem);
      return;
    }

    if (choice == _EraseChoice.disconnect) {
      // The server is empty and *stays* empty: nothing is wired to refill it.
      await ref.read(settingsRepoProvider).clearServer();
      if (!mounted) return;
      ref.read(syncEngineProvider).reconfigure(BbxConfig.none);
      setState(() {
        _server = BbxConfig.none;
        _counts = null;
        _note =
            'erased — the server holds nothing, and this book now syncs '
            'with nothing';
      });
      return;
    }

    setState(() {
      _counts = {};
      _note = 'erased — uploading this book fresh…';
    });
    final engine = ref.read(syncEngineProvider);
    await engine.syncNow();
    if (!mounted) return;
    setState(
      () => _note = engine.status.value.phase == SyncPhase.idle
          ? 'erased — this book stands whole on the server now'
          : 'erased — the upload finishes when ${server.host} answers',
    );
    unawaited(_fetchCounts());
  }

  Future<void> _editServer() async {
    final current = _server ?? BbxConfig.none;
    final outcome = await showLedgerSheet<_ServerOutcome>(
      context,
      builder: (_) => _ServerSheet(current: current),
    );
    if (!mounted || outcome == null) return;
    final settings = ref.read(settingsRepoProvider);
    final next = switch (outcome) {
      _ServerCleared() => BbxConfig.none,
      _ServerChosen(:final config) => config,
    };

    if (next.wired) {
      // Both sides may already hold a book. Whose survives is decided
      // *before* the address is even saved — the first sync used to fire
      // blind and pour one book into the other, doubling what both held.
      var choice = _FirstSyncChoice.merge;
      if (await _needsFirstSyncChoice(next)) {
        if (!mounted) return;
        final picked = await showLedgerSheet<_FirstSyncChoice>(
          context,
          builder: (_) => const _FirstSyncSheet(),
        );
        // Dismissed means undecided: nothing saved, nothing synced.
        if (picked == null || !mounted) return;
        choice = picked;
      }
      if (!mounted) return;
      switch (choice) {
        case _FirstSyncChoice.keepPhone:
          final problem = await _burnServerCopy(next);
          if (!mounted) return;
          if (problem != null) {
            setState(() => _note = problem);
            return;
          }
        case _FirstSyncChoice.takeServer:
          await ref.read(dbProvider).eraseForServerCopy();
        case _FirstSyncChoice.merge:
          break;
      }
      if (!mounted) return;
      await settings.setServer(next.baseUrl, next.token);
    } else {
      await settings.clearServer();
    }
    if (!mounted) return;
    final engine = ref.read(syncEngineProvider)..reconfigure(next);
    setState(() {
      _server = next;
      _counts = null;
      _note = null;
    });
    if (next.wired) {
      // Counts only after the round settles — counting mid-sync showed a
      // shelf that was still being stocked.
      unawaited(
        engine.syncNow().then((_) {
          if (mounted) unawaited(_fetchCounts());
        }),
      );
    }
  }

  /// True only when this phone and that server each hold a book of their
  /// own — the one situation where syncing without asking invents a third
  /// book neither side ever wrote.
  Future<bool> _needsFirstSyncChoice(BbxConfig next) async {
    final db = ref.read(dbProvider);
    // A book already married to this same address is one book in two places,
    // not two books — re-saving the token must not offer to erase anything.
    final current = _server;
    if (current != null && current.wired && current.baseUrl == next.baseUrl) {
      final married = await (db.select(db.remoteIds)..limit(1)).get();
      if (married.isNotEmpty) return false;
    }
    final localRow = await db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM accounts) + '
          '(SELECT COUNT(*) FROM txns) + '
          '(SELECT COUNT(*) FROM goals) + '
          '(SELECT COUNT(*) FROM budgets) + '
          '(SELECT COUNT(*) FROM recurrings) + '
          '(SELECT COUNT(*) FROM pinneds) + '
          '(SELECT COUNT(*) FROM notes) + '
          '(SELECT COUNT(*) FROM journal_entries) + '
          '(SELECT COUNT(*) FROM events) + '
          '(SELECT COUNT(*) FROM focus_sessions) + '
          '(SELECT COUNT(*) FROM vault_items) + '
          '(SELECT COUNT(*) FROM day_seals) AS n',
        )
        .getSingle();
    if (localRow.read<int>('n') == 0) return false;

    final client = BbxClient(next);
    try {
      final body = await client.get('/v1/book/stats');
      final counts = ((body as Map)['counts'] as Map).cast<String, int>();
      var remote = 0;
      counts.forEach((table, n) {
        // Categories are seeded on both sides and settings are preferences,
        // not a book; the change log is an echo of rows, not rows.
        if (table != 'categories' &&
            table != 'settings' &&
            table != 'change_events') {
          remote += n;
        }
      });
      return remote > 0;
    } on Object {
      // Could not see the shelf. Falling through to a plain sync is right:
      // if the server is unreachable the sync fails softly too, and an
      // empty-but-unreadable server has nothing to conflict with.
      return false;
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final server = _server;
    final counts = _counts;
    final total = counts?.values.fold(0, (a, b) => a + b) ?? 0;
    return ModuleScaffold(
      title: 'Server',
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        children: [
          const SizedBox(height: Gap.x3),
          // The live word from the engine — same truth the settings row tells.
          ValueListenableBuilder<SyncStatus>(
            valueListenable: ref.read(syncEngineProvider).status,
            builder: (context, s, _) {
              final String line;
              if (server == null) {
                line = 'reading the book…';
              } else if (!server.wired) {
                line = 'not set — this book syncs with nothing';
              } else {
                line = switch (s.phase) {
                  SyncPhase.syncing => 'talking to ${server.host}…',
                  SyncPhase.offline =>
                    'can\'t reach ${server.host} — will retry',
                  SyncPhase.blocked =>
                    (s.lastError?.contains('token') ?? false)
                        ? '${server.host} refused the token'
                        : '${server.host} answered wrongly',
                  SyncPhase.idle when s.lastSyncedAt != null =>
                    'settled with ${server.host} · ${_hhmm(s.lastSyncedAt!)}',
                  SyncPhase.idle =>
                    'wired to ${server.host} — first sync pending',
                };
              }
              return Text(
                line,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              );
            },
          ),
          const RuleHeader('the address'),
          _Row(
            server?.wired == true ? server!.host : 'no server set',
            'change the address or token',
            onTap: _editServer,
          ),
          const RuleHeader('on the server'),
          if (server != null && !server.wired)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x2),
              child: Text(
                'Nothing — no server is wired.',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            )
          else if (_countsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x2),
              child: Text(
                _countsError!,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.warn,
                ),
              ),
            )
          else if (counts == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x2),
              child: Text(
                _fetching ? 'counting…' : 'not counted yet',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            )
          else if (counts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x2),
              child: Text(
                'The server holds nothing.',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            )
          else ...[
            for (final (i, e)
                in (counts.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                    .indexed)
              LedgerLine(
                title: _plain(e.key),
                amount: '${e.value}',
                last: i == counts.length - 1,
              ),
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Text(
                '$total rows in all',
                style: LedgerType.amount.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
          ],
          if (server?.wired == true) ...[
            const SizedBox(height: Gap.x2),
            Pressable(
              onTap: _fetchCounts,
              child: Text(
                _fetching ? 'counting…' : 'count again ›',
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 12,
                  color: c.quill,
                ),
              ),
            ),
            const RuleHeader('the fire'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x2),
              child: Text(
                'Erasing deletes every row above from the server, forever. '
                'This phone\'s book is untouched — you choose whether it '
                'then uploads itself fresh, or stops syncing altogether.',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 13,
                  color: c.inkFaint,
                ),
              ),
            ),
            Pressable(
              onTap: _erase,
              child: Text(
                'erase the server copy',
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 14,
                  color: c.seal,
                ),
              ),
            ),
            if (_note != null) ...[
              const SizedBox(height: Gap.x2),
              Text(
                _note!,
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ],
          ],
          const SizedBox(height: Gap.x8),
        ],
      ),
    );
  }
}
