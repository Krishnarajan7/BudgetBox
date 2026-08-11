import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/sheets.dart';
import '../../data/api/api_config.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_engine.dart';
import '../setup/setup_flow.dart';
import 'account_manager.dart';
import 'activity_log.dart';
import 'category_manager.dart';
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
    final hasPin = await settings.hasPin();
    final server = await settings.serverConfig();
    final facts = await _countFacts();
    if (!mounted) return;
    setState(() {
      _salaryDay = day;
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
      await File('${dir.path}/$name').writeAsString(csv);
      if (!mounted) return;
      _say(true, _Note('${txns.length} entries written · $name', ok: true));
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
      _say(false, _Note('$kb KB copied · $name', ok: true));
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
                _Row(
                  'Year',
                  _yearFrame == null
                      ? 'reading the book…'
                      : yearFrameCaption(_yearFrame!),
                  onTap: _yearFrame == null ? null : _swapYearFrame,
                  goesSomewhere: false,
                  trailing: Text('swap',
                      style: LedgerType.bodyStrong
                          .copyWith(fontSize: 11, color: c.quill)),
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
                _Row('Server', switch (_server) {
                  null => 'reading the book…',
                  final s when s.wired => 'syncing with ${s.host}',
                  _ => 'not set — this book syncs with nothing',
                }, onTap: _server == null ? null : _setServer),
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

  /// Where the book syncs — typed once, kept in the book itself.
  ///
  /// The address used to be compiled in with `--dart-define`, which meant a
  /// rebuild to move servers or rotate a token, and a silent offline app if the
  /// flags were ever forgotten. Typing it here removes both.
  Future<void> _setServer() async {
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
      await settings.setServer(next.baseUrl, next.token);
    } else {
      await settings.clearServer();
    }
    if (!mounted) return;

    // The engine is long-lived and the app is already running: re-point it in
    // place rather than making Krish relaunch to be synced.
    final engine = ref.read(syncEngineProvider)..reconfigure(next);
    setState(() => _server = next);
    if (next.wired) unawaited(engine.syncNow());
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
          when pin.length == 4 && int.tryParse(pin) != null:
        await settings.setPin(pin);
      case _PinRemoved() when _hasPin == true:
        await settings.clearPin();
      // Dismissed, or four digits that weren't four digits: the book keeps
      // whatever it had.
      case _:
        break;
    }
    if (!mounted) return;
    await _refreshPin();
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
              onPressed: () =>
                  Navigator.of(context).pop(_ServerChosen(_typed)),
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
            'Four digits. Only your book, only you.',
            style: LedgerType.bodyStrong.copyWith(color: c.ink),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            maxLength: 4,
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
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11.5,
                      height: 1.25,
                      fontVariations: const [FontVariation('wght', 380)],
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
