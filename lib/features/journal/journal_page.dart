import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/inr.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/db.dart';
import '../../data/repos/journal_repo.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Friday, 31 July" — the page's dateline.
String _longDate(DateTime d) =>
    '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// "12 Jul" — the earlier-pages column.
String _shortDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1].substring(0, 3)}';

/// Mood 1 (rough) … 5 (great), drawn as line icons only.
const _moodIcons = [
  Icons.sentiment_very_dissatisfied_outlined,
  Icons.sentiment_dissatisfied_outlined,
  Icons.sentiment_neutral_outlined,
  Icons.sentiment_satisfied_outlined,
  Icons.sentiment_very_satisfied_outlined,
];

/// The Journal book: today's page on top, half-written by the rest of the
/// box, with every earlier page ruled beneath it.
class JournalPage extends ConsumerWidget {
  const JournalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final todayKey = LedgerDates.dayKey(now);
    return ModuleScaffold(
      title: 'Journal',
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        children: [
          const SizedBox(height: Gap.x4),
          _PageEditor(dateKey: todayKey),
          const RuleHeader('the day, in facts'),
          _DayFacts(day: now),
          const RuleHeader('earlier pages'),
          _EarlierPages(todayKey: todayKey),
          const SizedBox(height: Gap.x8),
        ],
      ),
    );
  }
}

/// One day's writing surface: dateline, the mood row, the words. Used at the
/// top of the book for today and full-screen for any earlier page. Everything
/// autosaves quietly — the page itself is the confirmation.
class _PageEditor extends ConsumerStatefulWidget {
  const _PageEditor({required this.dateKey});

  final String dateKey;

  @override
  ConsumerState<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<_PageEditor> {
  final _controller = TextEditingController();
  late final JournalRepo _repo;
  Timer? _debounce;
  int? _mood;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(journalRepoProvider);
    // Seed once from the db; never clobber words already being typed.
    unawaited(_repo.watch(widget.dateKey).first.then((e) {
      if (!mounted || e == null) return;
      setState(() {
        _mood ??= e.mood;
        if (!_dirty && _controller.text.isEmpty) _controller.text = e.body;
      });
    }));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush();
    _controller.dispose();
    super.dispose();
  }

  void _onBodyChanged(String _) {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    if (!_dirty) return;
    _dirty = false;
    unawaited(_repo.upsert(widget.dateKey, body: _controller.text));
  }

  void _pickMood(int mood) {
    HapticFeedback.selectionClick();
    setState(() => _mood = mood);
    unawaited(_repo.upsert(widget.dateKey, mood: mood));
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final date = DateTime.parse(widget.dateKey);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_longDate(date), style: LedgerType.title.copyWith(color: c.ink)),
        const SizedBox(height: Gap.x3),
        Row(
          children: [
            for (var m = 1; m <= 5; m++) ...[
              GestureDetector(
                onTap: () => _pickMood(m),
                child: AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.all(Gap.x2),
                  decoration: BoxDecoration(
                    color: _mood == m ? c.quillSoft : null,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _moodIcons[m - 1],
                    size: 22,
                    color: _mood == m ? c.quill : c.inkFaint,
                  ),
                ),
              ),
              if (m < 5) const SizedBox(width: Gap.x2),
            ],
          ],
        ),
        const SizedBox(height: Gap.x2),
        TextField(
          controller: _controller,
          onChanged: _onBodyChanged,
          maxLines: null,
          minLines: 3,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          cursorColor: c.quill,
          style: LedgerType.bodyText.copyWith(
            fontSize: 15,
            height: 1.55,
            color: c.ink,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: 'How was it?',
            hintStyle: LedgerType.bodyText.copyWith(
              fontSize: 15,
              height: 1.55,
              color: c.inkFaint,
            ),
          ),
        ),
      ],
    );
  }
}

/// What the box already wrote on today's page — only the lines that happened.
class _DayFacts extends ConsumerStatefulWidget {
  const _DayFacts({required this.day});

  final DateTime day;

  @override
  ConsumerState<_DayFacts> createState() => _DayFactsState();
}

class _DayFactsState extends ConsumerState<_DayFacts> {
  late final Future<({int spentPaise, int txnCount, int focusMinutes, int notesCount})>
      _facts;

  @override
  void initState() {
    super.initState();
    _facts = ref.read(journalRepoProvider).dayFacts(widget.day);
  }

  static String _focus(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return FutureBuilder(
      future: _facts,
      builder: (context, snapshot) {
        final f = snapshot.data;
        if (f == null) return const SizedBox(height: Gap.x6);
        final lines = <(String, String)>[
          if (f.txnCount > 0)
            (
              'Spent',
              '${Inr.format(f.spentPaise)} across ${f.txnCount} '
                  '${f.txnCount == 1 ? 'entry' : 'entries'}',
            ),
          if (f.focusMinutes > 0) ('Focused', _focus(f.focusMinutes)),
          if (f.notesCount > 0) ('Notes written', '${f.notesCount}'),
        ];
        if (lines.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'A quiet day, so far.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final (i, line) in lines.indexed)
              LedgerLine(
                title: line.$1,
                amount: line.$2,
                amountColor: c.inkFaint,
                last: i == lines.length - 1,
              ),
          ],
        );
      },
    );
  }
}

/// Every page before today, newest first. Tap a row to reopen that day.
class _EarlierPages extends ConsumerWidget {
  const _EarlierPages({required this.todayKey});

  final String todayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<JournalEntry>>(
      stream: ref.watch(journalRepoProvider).watchAll(),
      builder: (context, snapshot) {
        final earlier = (snapshot.data ?? const <JournalEntry>[])
            .where((e) => e.date != todayKey)
            .toList();
        if (earlier.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.x3),
            child: Text(
              'The book starts to-day.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          );
        }
        return Column(
          children: [
            for (final (i, e) in earlier.indexed)
              _EarlierRow(entry: e, last: i == earlier.length - 1),
          ],
        );
      },
    );
  }
}

class _EarlierRow extends StatelessWidget {
  const _EarlierRow({required this.entry, required this.last});

  final JournalEntry entry;
  final bool last;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) => _EditorScreen(dateKey: entry.date),
        transitionsBuilder: (_, anim, _, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final firstLine = entry.body.trim().split('\n').first.trim();
    final wordless = firstLine.isEmpty;
    return InkWell(
      onTap: () => _open(context),
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                _shortDate(DateTime.parse(entry.date)),
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
            Expanded(
              child: Text(
                wordless ? '(no words, mood only)' : firstLine,
                style: LedgerType.bodyText.copyWith(
                  color: wordless ? c.inkFaint : c.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.mood != null) ...[
              const SizedBox(width: Gap.x2),
              Icon(_moodIcons[entry.mood! - 1], size: 14, color: c.inkFaint),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full page from an earlier day — same surface as today's, back to pop.
class _EditorScreen extends StatelessWidget {
  const _EditorScreen({required this.dateKey});

  final String dateKey;

  @override
  Widget build(BuildContext context) {
    return ModuleScaffold(
      title: 'Journal',
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Gap.page),
        children: [
          const SizedBox(height: Gap.x4),
          _PageEditor(dateKey: dateKey),
          const SizedBox(height: Gap.x8),
        ],
      ),
    );
  }
}
