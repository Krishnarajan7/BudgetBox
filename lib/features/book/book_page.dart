import 'dart:async';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cat_inks.dart';
import '../../core/widgets/particles.dart';
import '../../core/undo_banner.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/cat_mark.dart';
import '../../core/widgets/ledger_app_bar.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/providers.dart';
import '../add/add_sheet.dart';
import '../../data/repos/txn_repo.dart';
import '../today/widgets/ledger_rows.dart';
import '../today/widgets/sections.dart';
import 'txn_editor.dart';

/// How long the undo toast stays offered after a struck line has dissolved
/// off the page. Only when this runs out does the delete land.
const bookStrikeGrace = Duration(seconds: 4);

/// The strike's beats: the pen crosses the line, the line dissolves to
/// particles (slow enough to watch), a kept line reassembles. Each phase
/// timer runs a hair past its animation so nothing is ever cut off.
const _strokeBeat = Duration(milliseconds: 340);
const _dissolveAnim = Duration(milliseconds: 1050);
const _dissolveBeat = Duration(milliseconds: 1150);
const _reformAnim = Duration(milliseconds: 680);
const _reformBeat = Duration(milliseconds: 760);

/// The month [delta] pages away — flipping past a year boundary just works.
DateTime bookMonthShift(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta);

/// A count as the book says it: small numbers are spelled out, larger ones
/// stay as figures — and figures are set in mono, never mid-sentence prose.
({String text, bool mono}) bookCount(int n) {
  const words = [
    'no',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
  ];
  return (n >= 0 && n < words.length)
      ? (text: words[n], mono: false)
      : (text: '$n', mono: true);
}

/// '12th' — the day of the month as the book would write it.
String bookOrdinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

/// How much of the month one single entry carried, in words — null when the
/// heaviest line isn't worth remarking on. A whisper has to earn its space.
String? shareOfMonth(int biggestPaise, int monthSpentPaise) {
  if (biggestPaise <= 0 || monthSpentPaise <= 0) return null;
  final share = biggestPaise / monthSpentPaise;
  if (share < 0.18) return null;
  if (share >= 0.45) return 'nearly half';
  if (share >= 0.30) return 'about a third';
  if (share >= 0.22) return 'about a quarter';
  return 'about a fifth';
}

/// One line of the "where it went" bar-list.
class WhereSlice {
  const WhereSlice({
    required this.categoryId,
    required this.paise,
    this.isOther = false,
  });

  /// Null for uncategorised spending (and for the folded remainder).
  final int? categoryId;
  final int paise;

  /// True only for the "everything else" line.
  final bool isOther;
}

/// Category totals for a month's expenses, heaviest first: the top [top]
/// categories plus one "everything else" line folding up the rest.
List<WhereSlice> whereItWent(Iterable<(int?, int)> expenses, {int top = 6}) {
  final totals = <int?, int>{};
  for (final (id, paise) in expenses) {
    totals[id] = (totals[id] ?? 0) + paise;
  }
  final entries = totals.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final out = <WhereSlice>[
    for (final e in entries.take(top))
      WhereSlice(categoryId: e.key, paise: e.value),
  ];
  if (entries.length > top) {
    final rest = entries.skip(top).fold(0, (s, e) => s + e.value);
    out.add(WhereSlice(categoryId: null, paise: rest, isOther: true));
  }
  return out;
}

/// What came in, what went out, and what the month kept. Transfers move
/// money between pockets — they stay out of all three.
({int inPaise, int outPaise, int keptPaise}) inOutKept(
  Iterable<(TxnType, int)> rows,
) {
  var inP = 0;
  var outP = 0;
  for (final (type, paise) in rows) {
    switch (type) {
      case TxnType.income:
        inP += paise;
      case TxnType.expense:
        outP += paise;
      case TxnType.transfer:
        break;
    }
  }
  return (inPaise: inP, outPaise: outP, keptPaise: inP - outP);
}

/// A struck line's journey: the stroke lands, the line dissolves into
/// particles and the gap closes; the undo toast (down in the nav's slot)
/// waits out [bookStrikeGrace], and only then does the deletion actually
/// land. Undo at any point reassembles the line from the same particles.
enum _StrikePhase { struck, dissolving, hidden, reforming }

class _Strike {
  _StrikePhase phase = _StrikePhase.struck;
  Timer? next;

  /// A photograph of the untouched line, taken the instant the strike
  /// landed — the dissolve tears up this picture and the undo puts it
  /// back together.
  ui.Image? image;
  Size? size;
  bool committed = false;

  void cancel() => next?.cancel();

  void dispose() {
    next?.cancel();
    image?.dispose();
    image = null;
  }
}

/// The transactions list IS the ledger: day-ruled pages, running totals,
/// swipe to strike an entry out (it waits, struck, before it goes), a heat
/// view where quiet days stay pale, and pages that turn back through the
/// months of the book.
class BookPage extends ConsumerStatefulWidget {
  const BookPage({super.key});

  @override
  ConsumerState<BookPage> createState() => _BookPageState();
}

class _BookPageState extends ConsumerState<BookPage> {
  bool _heat = false;
  int? _categoryFilter;
  String _query = '';
  final _searchFocus = FocusNode();

  /// The month being read — always the first of a month.
  DateTime _month = LedgerDates.monthStart(DateTime.now());
  Stream<List<Txn>>? _txnStream;
  Stream<List<DaySeal>>? _sealStream;
  DateTime? _streamMonth;

  /// Ids already written on the page — only genuinely new entries ink in;
  /// the first load plays nothing. (The Notes page pattern.)
  final _seen = <int>{};
  bool _primed = false;

  /// Struck lines waiting out their grace, and how many times each entry has
  /// been brought back (the seq re-inks the line when it returns).
  final _struck = <int, _Strike>{};
  final _reinked = <int, int>{};

  /// One repaint boundary per visible row, so a strike can photograph the
  /// line it is about to dissolve.
  final _boundaryKeys = <int, GlobalKey>{};

  /// Held so a struck line can still be let go while the page is leaving.
  TxnRepo? _strikeRepo;

  /// The page turn: which way the last flip went, and a seq so the switcher
  /// knows a new page arrived even when the month name repeats.
  double _flipDx = 0;
  int _flipSeq = 0;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() => setState(() {});

  @override
  void dispose() {
    _searchFocus.removeListener(_onFocusChanged);
    _searchFocus.dispose();
    // A struck line was already let go — leaving the page just settles it.
    final repo = _strikeRepo;
    if (repo != null) {
      for (final entry in _struck.entries) {
        entry.value.dispose();
        unawaited(repo.deleteTxn(entry.key));
      }
      _struck.clear();
    }
    super.dispose();
  }

  /// AnimatedSwitcher layout that keeps both views pinned to the top so the
  /// page never jumps mid-fade.
  static Widget _topAligned(Widget? current, List<Widget> previous) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    );
  }

  /// Turn to another page of the book. [direction] is +1 forward (towards
  /// now) and −1 back; left alone it follows the dates.
  void _flipMonth(DateTime m, {int? direction}) {
    final current = LedgerDates.monthStart(DateTime.now());
    var target = LedgerDates.monthStart(m);
    if (target.isAfter(current)) target = current;
    if (target == _month) return;
    final dir = direction ?? (target.isAfter(_month) ? 1 : -1);
    setState(() {
      _flipDx = dir.toDouble();
      _month = target;
      _flipSeq++;
    });
  }

  // ————— striking a line out, the ledger way —————

  /// Swiping doesn't tear the line out politely: the pen crosses it, the
  /// line dissolves into particles, and an in-place undo waits five
  /// seconds. Nothing leaves the database until the undo goes unused.
  void _strike(Txn t) {
    HapticFeedback.mediumImpact();
    final TxnRepo repo = ref.read(txnRepoProvider);
    _strikeRepo = repo;
    _struck.remove(t.id)?.dispose();
    final strike = _Strike();
    _struck[t.id] = strike;
    // Photograph the line before anything touches it — synchronously, while
    // its render object is still the live row.
    unawaited(_captureRow(t.id, strike));

    void commit() {
      strike.committed = true;
      _struck.remove(t.id)?.dispose();
      _boundaryKeys.remove(t.id);
      unawaited(repo.deleteTxn(t.id));
      if (mounted) setState(() {});
    }

    strike.next = Timer(_strokeBeat, () {
      if (!mounted) {
        commit();
        return;
      }
      setState(() => strike.phase = _StrikePhase.dissolving);
      strike.next = Timer(_dissolveBeat, () {
        if (!mounted) {
          commit();
          return;
        }
        setState(() => strike.phase = _StrikePhase.hidden);
        // The line is off the page; the nav steps aside and the undo
        // toast takes its slot for the length of the grace.
        ref
            .read(undoBannerProvider.notifier)
            .offer(
              UndoBanner(
                id: t.id,
                label: '${t.title} · ${Inr.format(t.amountPaise)} struck',
                duration: bookStrikeGrace,
                onUndo: () => _undoStrike(t),
              ),
            );
        strike.next = Timer(bookStrikeGrace, () {
          if (mounted) ref.read(undoBannerProvider.notifier).clear(t.id);
          commit();
        });
      });
    });
    setState(() {});
  }

  Future<void> _captureRow(int id, _Strike strike) async {
    try {
      final boundary =
          _boundaryKeys[id]?.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      strike.size = boundary.size;
      final image = await boundary.toImage(pixelRatio: dpr);
      // The strike may already be over (a fast undo, a disposed page).
      if (strike.committed || _struck[id] != strike) {
        image.dispose();
        return;
      }
      strike.image = image;
    } on Object {
      // No photograph, no particles — the dissolve falls back to a fade.
    }
  }

  /// The undo: the toast steps down, and the line reassembles from its own
  /// particles right where it was struck.
  Future<void> _undoStrike(Txn t) async {
    HapticFeedback.selectionClick();
    if (mounted) ref.read(undoBannerProvider.notifier).clear(t.id);
    final strike = _struck[t.id];
    if (strike == null || strike.committed) {
      await ref.read(txnRepoProvider).undoLastDelete();
      return;
    }
    strike.cancel();
    if (strike.image == null || Motion.reduced(context)) {
      _struck.remove(t.id)?.dispose();
      if (mounted) {
        setState(() => _reinked[t.id] = (_reinked[t.id] ?? 0) + 1);
      }
      return;
    }
    setState(() => strike.phase = _StrikePhase.reforming);
    strike.next = Timer(_reformBeat, () {
      HapticFeedback.lightImpact();
      _struck.remove(t.id)?.dispose();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final txns = ref.watch(txnRepoProvider);
    final db = ref.watch(dbProvider);
    final now = DateTime.now();
    final onNow = _month == LedgerDates.monthStart(now);
    _sealStream ??= db.select(db.daySeals).watch();

    // A flipped month reads as an already-written page: reset the seen-ids
    // book-keeping so nothing inks in on its first load.
    if (_streamMonth != _month) {
      _streamMonth = _month;
      _txnStream = txns.watchRange(_month, LedgerDates.monthEnd(_month));
      _seen.clear();
      _primed = false;
    }

    return StreamBuilder<List<Txn>>(
      stream: _txnStream,
      builder: (context, txnSnap) {
        final all = txnSnap.data ?? const [];
        final fresh = <int>{
          if (_primed)
            for (final t in all)
              if (!_seen.contains(t.id)) t.id,
        };
        if (txnSnap.hasData) {
          _primed = true;
          _seen.addAll(all.map((t) => t.id));
        }

        return StreamBuilder<List<Category>>(
          stream: db.select(db.categories).watch(),
          builder: (context, catSnap) {
            final cats = catSnap.data ?? const [];
            final catById = {for (final x in cats) x.id: x};

            return StreamBuilder<List<DaySeal>>(
              stream: _sealStream,
              builder: (context, sealSnap) {
                final sealed = {
                  for (final s in sealSnap.data ?? const <DaySeal>[]) s.date,
                };
                return _page(c, now, onNow, all, cats, catById, fresh, sealed);
              },
            );
          },
        );
      },
    );
  }

  Widget _page(
    LedgerColors c,
    DateTime now,
    bool onNow,
    List<Txn> all,
    List<Category> cats,
    Map<int, Category> catById,
    Set<int> fresh,
    Set<String> sealedDays,
  ) {
    var rows = all;
    if (_categoryFilter != null) {
      rows = rows.where((t) => t.categoryId == _categoryFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      rows = rows.where((t) => t.title.toLowerCase().contains(q)).toList();
    }

    final expensesOnly = all.where((t) => t.type == TxnType.expense).toList();
    final monthSpent = expensesOnly.fold(0, (s, t) => s + t.amountPaise);
    // The month's color language — same map Today uses, so an entry's ink
    // is identical on both pages.
    final catColor = catInks([
      for (final t in expensesOnly) (t.categoryId, t.amountPaise),
    ], c.chartInks);

    return ListView(
      // Room for the floating glass bar: the page scrolls under it, but
      // its last line must still be able to rise above it.
      padding: EdgeInsets.fromLTRB(
        Gap.page,
        0,
        Gap.page,
        MediaQuery.paddingOf(context).bottom + Gap.x4,
      ),
      children: [
        LedgerAppBar(
          title: 'Book',
          trailing: InkWell(
            onTap: () => setState(() => _heat = !_heat),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _heat
                    ? PenLines(size: 14, color: c.quill)
                    : PenGrid(size: 14, color: c.quill),
                const SizedBox(width: 4),
                Text(
                  _heat ? 'list' : 'month',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: c.quill,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Gap.x3),
        _monthNav(c, now, onNow),
        _inOutKeptLine(c, all),
        const SizedBox(height: Gap.x3),
        // A horizontal drag anywhere off a row turns the page. (On a row the
        // strike swipe wins the gesture — the nearer hand gets the pen.)
        GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 220) return;
            if (v < 0) {
              if (!onNow) _flipMonth(bookMonthShift(_month, 1), direction: 1);
            } else {
              _flipMonth(bookMonthShift(_month, -1), direction: -1);
            }
          },
          child: AnimatedSize(
            duration: Motion.spring,
            curve: Motion.curve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              // The page turn: the new month slides in from the side it was
              // reached from, the old one leaves the other way.
              duration: Motion.reduced(context) ? Duration.zero : Motion.spring,
              switchInCurve: Motion.curve,
              switchOutCurve: Motion.curve,
              layoutBuilder: _topAligned,
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey('month-$_flipSeq');
                final dx = (incoming ? _flipDx : -_flipDx) * 0.06;
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset(dx, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey('month-$_flipSeq'),
                // List ↔ heat: a fade-through, not a cross-fade. The two
                // views are dense and nothing alike — painted over each
                // other mid-fade they turn to mud — so the old one leaves
                // the page entirely before the new one inks in.
                child: AnimatedSwitcher(
                  duration: Motion.reduced(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 380),
                  switchInCurve: const Interval(
                    0.45,
                    1,
                    curve: Curves.easeOutCubic,
                  ),
                  switchOutCurve: const Interval(0.55, 1, curve: Curves.easeIn),
                  layoutBuilder: _topAligned,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.015),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _heat
                      ? Column(
                          key: const ValueKey('view-heat'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _heatView(
                            c,
                            now,
                            all,
                            expensesOnly,
                            monthSpent,
                            catById,
                            catColor,
                            onNow,
                          ),
                        )
                      : Column(
                          key: const ValueKey('view-list'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _filters(c, cats),
                            _monthLine(c, monthSpent, all.length, onNow),
                            // Matched rows re-filter with a soft fade.
                            AnimatedSwitcher(
                              duration: Motion.quick,
                              switchInCurve: Motion.curve,
                              switchOutCurve: Motion.curve,
                              layoutBuilder: _topAligned,
                              child: Column(
                                key: ValueKey('book-$_query'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _ledgerView(
                                  c,
                                  now,
                                  rows,
                                  catById,
                                  catColor,
                                  fresh,
                                  onNow,
                                  sealedDays,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Gap.x6),
      ],
    );
  }

  /// Chevrons flip a page at a time; the month name opens the whole stack.
  Widget _monthNav(LedgerColors c, DateTime now, bool onNow) {
    final label = _month.year == now.year
        ? _monthName(_month.month)
        : '${_monthName(_month.month)} ${_month.year}';
    return Row(
      children: [
        Pressable(
          onTap: () => _flipMonth(bookMonthShift(_month, -1), direction: -1),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: RotatedBox(
              quarterTurns: 1,
              child: PenChevron(size: 15, color: c.inkFaint),
            ),
          ),
        ),
        const SizedBox(width: Gap.x1),
        Pressable(
          onTap: _pickMonth,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 14,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 2),
              PenChevron(size: 12, color: c.inkFaint),
            ],
          ),
        ),
        const SizedBox(width: Gap.x1),
        Pressable(
          onTap: onNow
              ? null
              : () => _flipMonth(bookMonthShift(_month, 1), direction: 1),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: RotatedBox(
              quarterTurns: 3,
              child: PenChevron(size: 15, color: onNow ? c.rule : c.inkFaint),
            ),
          ),
        ),
        const Spacer(),
        if (!onNow)
          Pressable(
            onTap: () => _flipMonth(DateTime.now(), direction: 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.x2,
                vertical: Gap.x1,
              ),
              child: Text(
                'back to now',
                style: LedgerType.bodyStrong.copyWith(
                  fontSize: 12,
                  color: c.quill,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// The stack of recent pages — the last twelve months, newest first.
  Future<void> _pickMonth() async {
    final current = LedgerDates.monthStart(DateTime.now());
    final picked = await showLedgerSheet<DateTime>(
      context,
      builder: (sheetContext) {
        final c = LedgerColors.of(sheetContext);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHandle(),
                Padding(
                  padding: const EdgeInsets.only(top: Gap.x2, bottom: Gap.x2),
                  child: Text(
                    'flip back to',
                    style: LedgerType.title.copyWith(
                      fontSize: 18,
                      color: c.ink,
                    ),
                  ),
                ),
                for (var i = 0; i < 12; i++)
                  Builder(
                    builder: (context) {
                      final m = bookMonthShift(current, -i);
                      final selected = m == _month;
                      final label = m.year == current.year
                          ? _monthName(m.month)
                          : '${_monthName(m.month)} ${m.year}';
                      return InkIn(
                        delay: Duration(milliseconds: 18 * i),
                        child: LedgerLine(
                          title: label,
                          detail: i == 0 ? 'now' : null,
                          amountWidget: selected
                              ? PenTick(size: 15, color: c.quill)
                              : const SizedBox.shrink(),
                          last: i == 11,
                          onTap: () => Navigator.of(sheetContext).pop(m),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) _flipMonth(picked);
  }

  /// The month's balance sheet in one breath: in, out, kept.
  Widget _inOutKeptLine(LedgerColors c, List<Txn> all) {
    final k = inOutKept([for (final t in all) (t.type, t.amountPaise)]);
    final faint = LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint);
    TextStyle mono(Color color) =>
        LedgerType.amount.copyWith(fontSize: 12, color: color);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Text('in ', style: faint),
            CountUp(
              value: k.inPaise,
              format: Inr.format,
              style: mono(c.ink),
              duration: const Duration(milliseconds: 400),
            ),
            Text(' · out ', style: faint),
            CountUp(
              value: k.outPaise,
              format: Inr.format,
              style: mono(c.ink),
              duration: const Duration(milliseconds: 400),
            ),
            Text(' · kept ', style: faint),
            CountUp(
              value: k.keptPaise,
              format: Inr.format,
              style: mono(k.keptPaise > 0 ? c.jama : c.inkFaint),
              duration: const Duration(milliseconds: 400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(LedgerColors c, List<Category> cats) {
    final used = cats
        .where((x) => x.kind == CategoryKind.expense)
        .take(3)
        .toList();
    // A category picked from the bar-list still gets its chip.
    if (_categoryFilter != null && !used.any((x) => x.id == _categoryFilter)) {
      used.addAll(cats.where((x) => x.id == _categoryFilter));
    }
    final focused = _searchFocus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              QuillTab(
                'all',
                selected: _categoryFilter == null,
                onTap: () => setState(() => _categoryFilter = null),
              ),
              const SizedBox(width: Gap.x2),
              for (final x in used) ...[
                QuillTab(
                  x.name.split(' ').first.toLowerCase(),
                  icon: LedgerIcons.resolve(x.icon),
                  selected: _categoryFilter == x.id,
                  onTap: () => setState(
                    () =>
                        _categoryFilter = _categoryFilter == x.id ? null : x.id,
                  ),
                ),
                const SizedBox(width: Gap.x2),
              ],
            ],
          ),
        ),
        // The underline takes the quill while the pen is in the field.
        AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          margin: const EdgeInsets.only(top: Gap.x3),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: focused ? c.quill : c.rule,
                width: focused ? 2 : 1,
              ),
            ),
          ),
          child: TextField(
            focusNode: _searchFocus,
            onChanged: (v) => setState(() => _query = v),
            style: LedgerType.bodyText.copyWith(color: c.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'search the book…',
              hintStyle: LedgerType.bodyText.copyWith(
                fontSize: 14,
                color: c.inkFaint,
              ),
              icon: AnimatedSwitcher(
                duration: Motion.quick,
                switchInCurve: Motion.curve,
                switchOutCurve: Motion.curve,
                child: Padding(
                  key: ValueKey('search-icon-$focused'),
                  padding: const EdgeInsets.only(right: 4),
                  child: PenSearch(
                    size: 16,
                    color: focused ? c.quill : c.inkFaint,
                  ),
                ),
              ),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  /// One quiet line under the filters — the month keeps score in the margin.
  Widget _monthLine(
    LedgerColors c,
    int monthSpent,
    int entryCount,
    bool onNow,
  ) {
    final style = LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x3),
      child: Row(
        children: [
          Text(onNow ? 'month so far · ' : 'the whole month · ', style: style),
          CountUp(
            value: monthSpent,
            format: Inr.format,
            style: LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint),
            duration: const Duration(milliseconds: 400),
          ),
          Text(
            ' across $entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
            style: style,
          ),
        ],
      ),
    );
  }

  /// The ledger itself: a header per day, then its entries as ruled lines,
  /// each carrying its category mark. Struck lines stay in place until their
  /// grace runs out.
  List<Widget> _ledgerView(
    LedgerColors c,
    DateTime now,
    List<Txn> rows,
    Map<int, Category> cats,
    Map<int?, Color> catColor,
    Set<int> fresh,
    bool onNow,
    Set<String> sealedDays,
  ) {
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.x8),
          child: Text(
            _query.isEmpty
                ? (onNow
                      ? 'This month\'s pages are blank so far.'
                      : 'Nothing was written in ${_monthName(_month.month)}.')
                : 'Nothing in the book matches "$_query".',
            style: LedgerType.bodyText.copyWith(color: c.inkFaint),
          ),
        ),
      ];
    }

    final byDay = <int, List<Txn>>{};
    for (final t in rows) {
      byDay.putIfAbsent(t.at.day, () => []).add(t);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    final widgets = <Widget>[];
    for (final day in days) {
      final list = byDay[day]!;
      final spent = list
          .where((t) => t.type == TxnType.expense)
          .fold(0, (s, t) => s + t.amountPaise);
      final date = DateTime(_month.year, _month.month, day);
      widgets.add(
        _CountingDayHeader(
          key: ValueKey('day-header-$day'),
          label: onNow && day == now.day
              ? 'Today · ${LedgerDates.weekdays[date.weekday - 1]} $day'
              : '${LedgerDates.weekdays[date.weekday - 1]} $day',
          totalPaise: spent,
          sealed: sealedDays.contains(LedgerDates.dayKey(date)),
          onLongPress: () => _openDayPage(date, list, cats),
        ),
      );
      for (final (i, t) in list.indexed) {
        final strike = _struck[t.id];
        final reink = _reinked[t.id] ?? 0;
        // The category's ink rides ahead of its mark — the same color this
        // category wears on Today and in the month view.
        final ink = t.type == TxnType.income ? c.jama : catColor[t.categoryId];
        final mark = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: ink ?? c.rule,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: Gap.x2),
            CatMark(cats[t.categoryId]?.icon, size: 14),
          ],
        );
        final amount = t.type == TxnType.income
            ? Inr.format(t.amountPaise, signed: true)
            : Inr.format(t.amountPaise);
        widgets.add(
          // The payoff after the add sheet pops: only a genuinely new
          // entry inks itself onto the page — and a line brought back from
          // the strike inks itself in again.
          InkIn(
            key: ValueKey('txn-ink-${t.id}-$reink'),
            play: fresh.contains(t.id) || reink > 0,
            child: strike != null
                ? _StrikeStages(
                    key: ValueKey('struck-${t.id}'),
                    strike: strike,
                    leading: _time(t.at),
                    mark: mark,
                    title: t.title,
                    amount: amount,
                    last: i == list.length - 1,
                  )
                : _StrikeSwipe(
                    rowKey: ValueKey('swipe-${t.id}'),
                    onEdit: () => showTxnEditor(context, t),
                    onStrike: () => _strike(t),
                    child: RepaintBoundary(
                      key: _boundaryKeys.putIfAbsent(t.id, GlobalKey.new),
                      child: LedgerLine(
                        leading: _time(t.at),
                        mark: mark,
                        title: t.title,
                        amount: amount,
                        amountColor: t.type == TxnType.income ? c.jama : null,
                        last: i == list.length - 1,
                        onTap: () => showTxnEditor(context, t),
                        onLongPress: () => showTxnActions(context, ref, t),
                      ),
                    ),
                  ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _heatView(
    LedgerColors c,
    DateTime now,
    List<Txn> all,
    List<Txn> expensesOnly,
    int monthSpent,
    Map<int, Category> catById,
    Map<int?, Color> catColor,
    bool onNow,
  ) {
    final days = List<int>.filled(LedgerDates.daysInMonth(_month), 0);
    for (final t in expensesOnly) {
      days[t.at.day - 1] += t.amountPaise;
    }
    final elapsed = onNow ? now.day : days.length;
    final quiet = days.take(elapsed).where((v) => v == 0).length;

    final slices = whereItWent([
      for (final t in expensesOnly) (t.categoryId, t.amountPaise),
    ], top: 4);

    final byDay = <int, List<Txn>>{};
    for (final t in all) {
      byDay.putIfAbsent(t.at.day, () => []).add(t);
    }

    final whisper = _biggestEntryWhisper(c, all, monthSpent);

    return [
      HeroAmount(
        caption: _monthName(_month.month),
        amount: Inr.format(monthSpent),
        size: 30,
      ),
      // The same calendar and category bar Today draws for the current
      // month — here they read any page of the book. A finished month has
      // no ring, no future days, no catch-up offer.
      CalendarSection(
        expenses: expensesOnly,
        monthTxns: all,
        month: _month,
        today: onNow ? now.day : null,
        catColor: catColor,
        onDayTap: (d) => _openDayPage(
          DateTime(_month.year, _month.month, d),
          byDay[d] ?? const [],
          catById,
        ),
      ),
      WhereSection(
        slices: slices,
        monthPaise: monthSpent,
        catColor: catColor,
        // Tapping a category folds the month view back into the ledger,
        // filtered to that ink.
        onSliceTap: (s) => setState(() {
          _heat = false;
          _categoryFilter = s.categoryId;
        }),
      ),
      const SectionHead('what the month looks like'),
      _monthShapeLine(c, quiet, all.length, 0, false),
      ?whisper,
    ];
  }

  /// The month's shape, said in one breath — figures set in mono where the
  /// number is too large to spell.
  Widget _monthShapeLine(
    LedgerColors c,
    int quiet,
    int entries,
    int heaviestDay,
    bool hasSpend,
  ) {
    final faint = LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint);
    final mono = LedgerType.amount.copyWith(fontSize: 12, color: c.inkFaint);

    TextSpan count(int n, {bool capital = false}) {
      final w = bookCount(n);
      final text = capital
          ? '${w.text[0].toUpperCase()}${w.text.substring(1)}'
          : w.text;
      return TextSpan(text: text, style: w.mono ? mono : faint);
    }

    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Text.rich(
        TextSpan(
          style: faint,
          children: [
            count(quiet, capital: true),
            TextSpan(text: quiet == 1 ? ' quiet day; ' : ' quiet days; '),
            count(entries),
            TextSpan(
              text: entries == 1 ? ' entry written' : ' entries written',
            ),
            if (hasSpend) ...[
              const TextSpan(text: ' — the '),
              TextSpan(text: bookOrdinal(heaviestDay), style: mono),
              const TextSpan(text: ' carried the most'),
            ],
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }

  /// One line took an outsized share of the month — worth saying out loud,
  /// and only then.
  Widget? _biggestEntryWhisper(LedgerColors c, List<Txn> all, int monthSpent) {
    final expenses = all.where((t) => t.type == TxnType.expense).toList();
    if (expenses.length < 3) return null;
    var big = expenses.first;
    for (final t in expenses) {
      if (t.amountPaise > big.amountPaise) big = t;
    }
    final share = shareOfMonth(big.amountPaise, monthSpent);
    if (share == null) return null;

    final faint = LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint);
    final mono = LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x1),
      child: InkIn(
        delay: const Duration(milliseconds: 220),
        child: Text.rich(
          TextSpan(
            style: faint,
            children: [
              TextSpan(text: '${big.title} on ${LedgerDates.ddMmm(big.at)} '),
              const TextSpan(text: 'carried '),
              TextSpan(text: Inr.format(big.amountPaise), style: mono),
              TextSpan(text: ' of it — $share of the month.'),
            ],
          ),
        ),
      ),
    );
  }

  /// A single day, lifted off the page: what was written on it, and the
  /// stamp that closes it. Reached by long-pressing a day header or tapping
  /// a heat cell.
  Future<void> _openDayPage(
    DateTime date,
    List<Txn> entries,
    Map<int, Category> cats,
  ) async {
    HapticFeedback.selectionClick();
    final db = ref.read(dbProvider);
    final key = LedgerDates.dayKey(date);
    final row = await (db.select(
      db.daySeals,
    )..where((s) => s.date.equals(key))).getSingleOrNull();
    if (!mounted) return;

    Txn? toEdit;
    var addHere = false;
    await showLedgerSheet<void>(
      context,
      builder: (sheetContext) => _DayPage(
        date: date,
        entries: entries,
        cats: cats,
        sealed: row != null,
        onOpenEntry: (t) {
          toEdit = t;
          Navigator.of(sheetContext).pop();
        },
        onAdd: () {
          addHere = true;
          Navigator.of(sheetContext).pop();
        },
        onSeal: () async {
          await db
              .into(db.daySeals)
              .insert(
                DaySealsCompanion(date: Value(key)),
                mode: InsertMode.insertOrIgnore,
              );
          if (key == LedgerDates.dayKey(DateTime.now())) {
            unawaited(ref.read(nudgesProvider).resync());
          }
        },
        onUnseal: () async {
          await (db.delete(db.daySeals)..where((s) => s.date.equals(key))).go();
          if (key == LedgerDates.dayKey(DateTime.now())) {
            unawaited(ref.read(nudgesProvider).resync());
          }
        },
      ),
    );
    if (!mounted) return;
    // Noon, like the catch-up sheet writes: a remembered day rarely
    // remembers its o'clock.
    if (addHere) {
      await showAddSheet(
        context,
        at: DateTime(date.year, date.month, date.day, 12),
      );
      return;
    }
    final open = toEdit;
    if (open != null) await showTxnEditor(context, open);
  }

  static String _time(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  static String _monthName(int m) =>
      LedgerDates.monthsFull[m - 1].toLowerCase();
}

/// The book's own swipe. [SwipeRow] tears the line out of the page; here a
/// struck line has to stay put while its grace runs, so the row springs back
/// instead of dismissing — same reveal, same words, different ending.
/// Crossing the commit threshold ticks under the finger, both ways: the hand
/// knows the moment the swipe would land without watching for it.
class _StrikeSwipe extends StatefulWidget {
  const _StrikeSwipe({
    required this.rowKey,
    required this.child,
    required this.onEdit,
    required this.onStrike,
  });

  final Key rowKey;
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onStrike;

  @override
  State<_StrikeSwipe> createState() => _StrikeSwipeState();
}

class _StrikeSwipeState extends State<_StrikeSwipe> {
  bool _reached = false;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Dismissible(
      key: widget.rowKey,
      direction: DismissDirection.horizontal,
      onUpdate: (details) {
        if (details.reached != _reached) {
          _reached = details.reached;
          HapticFeedback.selectionClick();
        }
      },
      background: Container(
        color: c.paperRaised,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: Gap.x4),
        child: Text(
          'correct',
          style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.quill),
        ),
      ),
      secondaryBackground: Container(
        color: c.paperRaised,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Gap.x4),
        child: Text(
          'strike',
          style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.seal),
        ),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          HapticFeedback.selectionClick();
          widget.onEdit();
        } else {
          widget.onStrike();
        }
        // The line never leaves this way — it springs back, struck or intact.
        return false;
      },
      child: widget.child,
    );
  }
}

/// A struck line through its phases. The pen crosses it in vermilion,
/// then the line dissolves into particles of its own image — torn off the
/// page in a left-to-right wave. What remains is a quiet in-place undo for
/// five seconds; taking it runs the particles backwards until the line
/// stands whole again. Heights hand over through [AnimatedSize], so the
/// page never pops.
class _StrikeStages extends StatelessWidget {
  const _StrikeStages({
    super.key,
    required this.strike,
    required this.leading,
    required this.mark,
    required this.title,
    required this.amount,
    required this.last,
  });

  final _Strike strike;
  final String leading;
  final Widget mark;
  final String title;
  final String amount;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final rowH = strike.size?.height ?? 38;
    final child = switch (strike.phase) {
      _StrikePhase.struck => _struckRow(c),
      _StrikePhase.dissolving => _particles(context, rowH, reverse: false),
      // The ash has blown away: the gap closes and the undo lives down in
      // the nav's slot, not here.
      _StrikePhase.hidden => const SizedBox(width: double.infinity),
      _StrikePhase.reforming => _particles(context, rowH, reverse: true),
    };
    return AnimatedSize(
      duration: Motion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child,
    );
  }

  /// The instant after the swipe: the pen crosses the whole line, once.
  Widget _struckRow(LedgerColors c) {
    return Container(
      decoration: last
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: c.rule)),
            ),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  leading,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
              Baseline(
                baseline: 11,
                baselineType: TextBaseline.alphabetic,
                child: Opacity(opacity: 0.55, child: mark),
              ),
              const SizedBox(width: Gap.x2),
              Expanded(
                child: Text(
                  title,
                  style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                amount,
                style: LedgerType.amount.copyWith(color: c.inkFaint),
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: LayoutBuilder(
                  builder: (context, box) => DrawIn(
                    duration: const Duration(milliseconds: 280),
                    builder: (context, p) => QuillStroke(
                      width: box.maxWidth,
                      thickness: 1.8,
                      color: c.seal,
                      progress: p,
                      seed: 11,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _particles(
    BuildContext context,
    double height, {
    required bool reverse,
  }) {
    final image = strike.image;
    if (image == null || Motion.reduced(context)) {
      // No photograph (or no motion): the beat passes as blank space and
      // the timers carry the flow.
      return SizedBox(height: height, width: double.infinity);
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ParticleField(
        image: image,
        reverse: reverse,
        duration: reverse ? _reformAnim : _dissolveAnim,
      ),
    );
  }
}

/// [DayHeader] with a settling total — adding an entry visibly bumps the day.
/// The layout is the shared header's; only the number moves.
class _CountingDayHeader extends StatefulWidget {
  const _CountingDayHeader({
    super.key,
    required this.label,
    required this.totalPaise,
    this.sealed = false,
    this.onLongPress,
  });

  final String label;
  final int totalPaise;
  final bool sealed;
  final VoidCallback? onLongPress;

  @override
  State<_CountingDayHeader> createState() => _CountingDayHeaderState();
}

class _CountingDayHeaderState extends State<_CountingDayHeader> {
  late int _from = widget.totalPaise;

  @override
  void didUpdateWidget(_CountingDayHeader old) {
    super.didUpdateWidget(old);
    if (old.totalPaise != widget.totalPaise) _from = old.totalPaise;
  }

  @override
  Widget build(BuildContext context) {
    Widget header(int paise) => DayHeader(
      label: widget.label,
      total: Inr.format(paise),
      sealed: widget.sealed,
    );

    final child = Motion.reduced(context)
        ? header(widget.totalPaise)
        : TweenAnimationBuilder<double>(
            key: ValueKey(widget.totalPaise),
            tween: Tween(
              begin: _from.toDouble(),
              end: widget.totalPaise.toDouble(),
            ),
            duration: const Duration(milliseconds: 400),
            curve: Motion.curve,
            builder: (context, v, _) => header(v.round()),
          );

    return widget.onLongPress == null
        ? child
        : Pressable(onLongPress: widget.onLongPress, child: child);
  }
}

/// A single day lifted out of the book: its lines, and the stamp that closes
/// it. The seal is earned once per day and can always be lifted again —
/// nothing here is permanent.
class _DayPage extends StatefulWidget {
  const _DayPage({
    required this.date,
    required this.entries,
    required this.cats,
    required this.sealed,
    required this.onOpenEntry,
    required this.onAdd,
    required this.onSeal,
    required this.onUnseal,
  });

  final DateTime date;
  final List<Txn> entries;
  final Map<int, Category> cats;
  final bool sealed;
  final ValueChanged<Txn> onOpenEntry;

  /// Opens the add sheet dated to this day — the way back onto any page
  /// once the catch-up sheet has stopped offering it.
  final VoidCallback onAdd;
  final Future<void> Function() onSeal;
  final Future<void> Function() onUnseal;

  @override
  State<_DayPage> createState() => _DayPageState();
}

class _DayPageState extends State<_DayPage> {
  late bool _sealed = widget.sealed;
  bool _stamping = false;

  Future<void> _toggle() async {
    if (_stamping) return;
    HapticFeedback.selectionClick();
    if (_sealed) {
      await widget.onUnseal();
      if (!mounted) return;
      setState(() => _sealed = false);
      return;
    }
    setState(() => _stamping = true);
    await widget.onSeal();
    if (!mounted) return;
    setState(() => _sealed = true);
    await Future<void>.delayed(const Duration(milliseconds: 520));
    if (mounted) setState(() => _stamping = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final spent = widget.entries
        .where((t) => t.type == TxnType.expense)
        .fold(0, (s, t) => s + t.amountPaise);
    final future = widget.date.isAfter(DateTime.now());
    final count = bookCount(widget.entries.length);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Text(
                LedgerDates.dayLabel(widget.date),
                style: LedgerType.title.copyWith(fontSize: 18, color: c.ink),
              ),
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
                children: widget.entries.isEmpty
                    ? [const TextSpan(text: 'Nothing was written here.')]
                    : [
                        TextSpan(
                          text: Inr.format(spent),
                          style: LedgerType.amount.copyWith(
                            fontSize: 12,
                            color: c.inkFaint,
                          ),
                        ),
                        const TextSpan(text: ' across '),
                        TextSpan(
                          text: count.text,
                          style: count.mono
                              ? LedgerType.amount.copyWith(
                                  fontSize: 12,
                                  color: c.inkFaint,
                                )
                              : null,
                        ),
                        TextSpan(
                          text: widget.entries.length == 1
                              ? ' entry.'
                              : ' entries.',
                        ),
                      ],
              ),
            ),
            const SizedBox(height: Gap.x3),
            for (final (i, t) in widget.entries.indexed)
              InkIn(
                delay: Duration(milliseconds: 24 * i),
                child: LedgerLine(
                  mark: CatMark(widget.cats[t.categoryId]?.icon, size: 14),
                  title: t.title,
                  amount: t.type == TxnType.income
                      ? Inr.format(t.amountPaise, signed: true)
                      : Inr.format(t.amountPaise),
                  amountColor: t.type == TxnType.income ? c.jama : null,
                  last: i == widget.entries.length - 1,
                  onTap: () => widget.onOpenEntry(t),
                ),
              ),
            if (!future) ...[
              const SizedBox(height: Gap.x3),
              // A day that fell off the catch-up sheet is still writable
              // from here — remembering late is not a locked door.
              Center(
                child: Pressable(
                  onTap: widget.onAdd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                    child: Text(
                      '+ write onto this day',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 14,
                        color: c.quill,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gap.x1),
              if (_stamping)
                Center(child: StampIn(size: 40, delay: Motion.quick))
              else
                Center(
                  child: Pressable(
                    onTap: _toggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.x2),
                      child: Text(
                        _sealed ? 'reopen this page' : 'close this day',
                        style: LedgerType.bodyStrong.copyWith(
                          fontSize: 14,
                          color: c.quill,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_sealed && !_stamping)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.x1),
                  child: Text(
                    'Closed. Nothing stops you writing on it again.',
                    textAlign: TextAlign.center,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 11,
                      color: c.inkFaint,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
