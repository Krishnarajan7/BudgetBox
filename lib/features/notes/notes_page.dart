import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../data/db.dart';
import '../../data/repos/note_repo.dart';
import 'note_editor.dart';

/// Case-insensitive search across title and body. An empty query reads as
/// no search at all — the whole book comes back.
List<Note> filterNotes(List<Note> notes, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return notes;
  return [
    for (final n in notes)
      if (n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q))
        n,
  ];
}

/// Tags by convention, not by schema: any `#word` written inside a note is a
/// tag. Returns the distinct tags across [notes], most-used first — the same
/// trick as the checklist lines: structure that costs nothing to type.
List<String> noteTags(List<Note> notes) {
  final pattern = RegExp(r'#([a-zA-Z0-9_]{2,24})');
  final counts = <String, int>{};
  for (final n in notes) {
    for (final m in pattern.allMatches('${n.title} ${n.body}')) {
      final tag = m.group(0)!.toLowerCase();
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final tags = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return tags;
}

/// One line of a note that reads as a checklist item — `- milk`, or
/// `- [x] milk` once it's ticked. [line] is the item's index in the body, so
/// a tick can rewrite that one line and leave every other word alone.
class ChecklistItem {
  const ChecklistItem({
    required this.line,
    required this.ticked,
    required this.text,
  });

  final int line;
  final bool ticked;
  final String text;
}

/// `- something`, with an optional `[ ]` / `[x]` box in front of it.
final _checklistLine = RegExp(r'^\s*-\s+(?:\[([ xX])\]\s*)?(.*)$');

/// Every checklist line in [body], in the order they were written. A bare
/// dash with nothing after it isn't an item yet — it's a line being started.
List<ChecklistItem> checklistItems(String body) {
  final items = <ChecklistItem>[];
  final lines = body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _checklistLine.firstMatch(lines[i]);
    if (m == null) continue;
    final text = (m.group(2) ?? '').trim();
    if (text.isEmpty) continue;
    items.add(
      ChecklistItem(
        line: i,
        ticked: (m.group(1) ?? ' ').toLowerCase() == 'x',
        text: text,
      ),
    );
  }
  return items;
}

/// The one item a note's row shows: the first still unticked, or the last
/// one when the whole list is done and the row can say so.
ChecklistItem? nextChecklistItem(String body) {
  final items = checklistItems(body);
  if (items.isEmpty) return null;
  for (final i in items) {
    if (!i.ticked) return i;
  }
  return items.last;
}

/// Ticks or unticks the item sitting on [line]. Returns [body] untouched
/// when that line isn't a checklist item — nothing else on the page moves.
String toggleChecklistLine(String body, int line) {
  final lines = body.split('\n');
  if (line < 0 || line >= lines.length) return body;
  final m = _checklistLine.firstMatch(lines[line]);
  if (m == null) return body;
  final text = (m.group(2) ?? '').trim();
  if (text.isEmpty) return body;
  final ticked = (m.group(1) ?? ' ').toLowerCase() == 'x';
  // Keep the writer's own indent; only the box changes.
  final indent = lines[line].substring(
    0,
    lines[line].length - lines[line].trimLeft().length,
  );
  lines[line] = '$indent- [${ticked ? ' ' : 'x'}] $text';
  return lines.join('\n');
}

/// The faint word at the end of a note's line: how the list is doing on a
/// checklist, or how many words are down. Empty for a note with nothing in
/// it — a blank row says enough on its own.
String noteWhisper(String title, String body) {
  final items = checklistItems(body);
  if (items.isNotEmpty) {
    final ticked = items.where((i) => i.ticked).length;
    return '$ticked of ${items.length} ticked';
  }
  final words = wordCount('$title\n$body');
  return words == 0 ? '' : '$words word${words == 1 ? '' : 's'}';
}

/// The Notes book: one ruled line to catch a thought, and the thoughts
/// beneath it — pinned ones first, the rest in order of last touch.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  late final NoteRepo _repo;
  final _capture = TextEditingController();

  /// Ids already on the page — anything new fades and slides in; nothing
  /// animates on first open.
  final _seen = <int>{};
  bool _primed = false;

  /// Pinned states as of the last emission, so only a genuine long-press
  /// toggle pops the pin — never a plain stream re-emission.
  final _pinnedSeen = <int, bool>{};

  /// Struck rows: swiped away, but still on the page. Nothing is archived
  /// until the grace runs out, and a tap in that window brings the row back.
  final _struck = <int>{};

  /// Struck rows whose grace has run out: held for one fade, then gone.
  final _leaving = <int>{};
  final _graceTimers = <int, Timer>{};

  /// Long enough to notice the strike and take it back; short enough that
  /// the page doesn't keep a graveyard.
  static const _grace = Duration(seconds: 4);

  /// Bumped each submit: the capture rule flashes quill and settles back —
  /// the pen lifting off the line.
  int _penLift = 0;

  /// Search: hidden until the trailing glass is tapped; the query filters
  /// the book live.
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repo = ref.read(noteRepoProvider);
    _searchFocus.addListener(_onSearchFocus);
  }

  void _onSearchFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final t in _graceTimers.values) {
      t.cancel();
    }
    _graceTimers.clear();
    // Leaving the page is an answer too: anything still struck goes.
    for (final id in _struck) {
      unawaited(_repo.archive(id));
    }
    _capture.dispose();
    _searchFocus.removeListener(_onSearchFocus);
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    HapticFeedback.selectionClick();
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _search.clear();
        _query = '';
      }
    });
  }

  Future<void> _quickCapture(String text) async {
    final line = text.trim();
    if (line.isEmpty) return;
    HapticFeedback.selectionClick();
    _capture.clear();
    setState(() => _penLift++);
    await _repo.create(title: line);
  }

  /// A swipe strikes the row out; it keeps its place, faint and crossed
  /// through, until the grace expires. No snackbar — the page is the undo.
  void _strike(int id) {
    _graceTimers.remove(id)?.cancel();
    setState(() {
      _leaving.remove(id);
      _struck.add(id);
    });
    _graceTimers[id] = Timer(_grace, () => _letGo(id));
  }

  /// Grace over: the row fades off the page, then the note is archived.
  void _letGo(int id) {
    if (!mounted) return;
    setState(() => _leaving.add(id));
    _graceTimers[id] = Timer(Motion.spring, () {
      _graceTimers.remove(id);
      unawaited(_repo.archive(id));
      if (!mounted) return;
      setState(() {
        _struck.remove(id);
        _leaving.remove(id);
      });
    });
  }

  /// Taken back: the line re-inks where it stood.
  void _unstrike(int id) {
    _graceTimers.remove(id)?.cancel();
    setState(() {
      _struck.remove(id);
      _leaving.remove(id);
    });
  }

  /// Ticking from the list rewrites that one line of the note's body — the
  /// note keeps its words, and the checklist keeps its place.
  Future<void> _toggleCheck(Note n, int line) async {
    final body = toggleChecklistLine(n.body, line);
    if (body == n.body) return;
    await _repo.update(n.id, body: body);
  }

  void _open(Note note) {
    Navigator.of(
      context,
    ).push(LedgerRoute<void>(builder: (_) => NoteEditorPage(note: note)));
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);

    return ModuleScaffold(
      title: 'Notes',
      trailing: Pressable(
        scale: 0.9,
        onTap: _toggleSearch,
        haptic: false,
        child: Padding(
          padding: const EdgeInsets.all(Gap.x1),
          child: AnimatedSwitcher(
            duration: Motion.quick,
            switchInCurve: Motion.curve,
            switchOutCurve: Motion.curve,
            child: Icon(
              _searching ? Icons.close : Icons.search,
              key: ValueKey('notes-search-$_searching'),
              size: 18,
              color: _searching ? c.quill : c.inkFaint,
            ),
          ),
        ),
      ),
      child: StreamBuilder<List<Note>>(
        stream: _repo.watchAll(),
        builder: (context, snapshot) {
          final notes = snapshot.data ?? const <Note>[];
          final fresh = <int>{
            if (_primed)
              for (final n in notes)
                if (!_seen.contains(n.id)) n.id,
          };
          // A pin pops only when its state actually flipped since the last
          // emission — a rebuild alone moves nothing.
          final pinFlipped = <int>{
            if (_primed)
              for (final n in notes)
                if (_pinnedSeen.containsKey(n.id) &&
                    _pinnedSeen[n.id] != n.pinned)
                  n.id,
          };
          if (snapshot.hasData) {
            _primed = true;
            _seen.addAll(notes.map((n) => n.id));
            for (final n in notes) {
              _pinnedSeen[n.id] = n.pinned;
            }
          }

          final shown = filterNotes(notes, _query);
          final pinned = [
            for (final n in shown)
              if (n.pinned) n,
          ];
          final rest = [
            for (final n in shown)
              if (!n.pinned) n,
          ];
          // Section headers only earn their ink when both kinds are present.
          final sectioned = pinned.isNotEmpty && rest.isNotEmpty;

          final tags = noteTags(notes);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const SizedBox(height: Gap.x3),
              _captureLine(c),
              _searchArea(c, shown.length, notes.length),
              // Any #word written in a note is a tag; one tap filters the
              // book to it, tapping again lets go.
              if (tags.isNotEmpty) ...[
                const SizedBox(height: Gap.x3),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final t in tags) ...[
                        LedgerChip(
                          t,
                          selected: _query.trim().toLowerCase() == t,
                          onTap: () => setState(() {
                            final was = _query.trim().toLowerCase() == t;
                            _query = was ? '' : t;
                            _search.text = _query;
                          }),
                        ),
                        const SizedBox(width: Gap.x2),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: Gap.x4),
              if (snapshot.hasData && notes.isEmpty)
                const EmptyPage(
                  line: 'Nothing here yet. First thought goes on top.',
                )
              else if (_query.trim().isNotEmpty && shown.isEmpty)
                const EmptyPage(
                  line: 'Nothing in the book matches.',
                  sub: 'Try fewer words.',
                )
              else ...[
                _SectionHeader(
                  'pinned',
                  shown: sectioned,
                  trailing: _heldCount(c, pinned.length),
                ),
                for (final (i, n) in pinned.indexed)
                  _noteRow(
                    c,
                    n,
                    last: i == pinned.length - 1,
                    fresh: fresh.contains(n.id),
                    pinPopped: pinFlipped.contains(n.id),
                  ),
                _SectionHeader('everything else', shown: sectioned),
                for (final (i, n) in rest.indexed)
                  _noteRow(
                    c,
                    n,
                    last: i == rest.length - 1,
                    fresh: fresh.contains(n.id),
                    pinPopped: pinFlipped.contains(n.id),
                  ),
              ],
              const _ArchivedDoor(),
              const SizedBox(height: Gap.x8),
            ],
          );
        },
      ),
    );
  }

  Widget _heldCount(LedgerColors c, int n) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$n',
            style: LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint),
          ),
          const TextSpan(text: ' held'),
        ],
      ),
      style: LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint),
    );
  }

  /// One note's row: entrance, swipe-to-strike, and — while struck — the
  /// same line kept faint and crossed through, waiting to be taken back.
  Widget _noteRow(
    LedgerColors c,
    Note n, {
    required bool last,
    required bool fresh,
    required bool pinPopped,
  }) {
    if (_struck.contains(n.id)) {
      return AnimatedOpacity(
        key: ValueKey('note-struck-${n.id}'),
        duration: Motion.reduced(context) ? Duration.zero : Motion.spring,
        curve: Motion.curve,
        opacity: _leaving.contains(n.id) ? 0 : 1,
        child: _NoteLine(
          note: n,
          last: last,
          pinPopped: false,
          struck: true,
          onTap: () => _unstrike(n.id),
          onLongPress: () => _unstrike(n.id),
        ),
      );
    }
    return InkIn(
      key: ValueKey('note-entrance-${n.id}'),
      play: fresh,
      child: Dismissible(
        key: ValueKey('note-${n.id}'),
        direction: DismissDirection.endToStart,
        // The strike is undoable, so the row must not actually leave here:
        // the swipe is refused and the line springs back already struck.
        confirmDismiss: (_) async {
          HapticFeedback.mediumImpact();
          _strike(n.id);
          return false;
        },
        background: Container(
          color: c.paperRaised,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: Gap.x4),
          child: Text(
            'archive',
            style: LedgerType.bodyStrong.copyWith(fontSize: 13, color: c.seal),
          ),
        ),
        child: _NoteLine(
          note: n,
          last: last,
          pinPopped: pinPopped,
          onTap: () => _open(n),
          onLongPress: () {
            HapticFeedback.lightImpact();
            _repo.setPinned(n.id, !n.pinned);
          },
          onToggleCheck: (line) => _toggleCheck(n, line),
        ),
      ),
    );
  }

  /// The search rule, revealed under quick-capture: the underline takes the
  /// quill while the pen is in the field, and a small "n of m notes" count
  /// keeps score while a query is written.
  Widget _searchArea(LedgerColors c, int shownCount, int totalCount) {
    final focused = _searchFocus.hasFocus;
    final active = _query.trim().isNotEmpty;
    return AnimatedSize(
      duration: Motion.quick,
      curve: Motion.curve,
      alignment: Alignment.topCenter,
      child: !_searching
          ? const SizedBox(width: double.infinity)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: Gap.x3),
                AnimatedContainer(
                  duration: Motion.quick,
                  curve: Motion.curve,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: focused ? c.quill : c.rule,
                        width: focused ? 2 : 1,
                      ),
                    ),
                  ),
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 14,
                      color: c.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'search the book…',
                      hintStyle: LedgerType.bodyText.copyWith(
                        fontSize: 14,
                        color: c.inkFaint,
                      ),
                      icon: Icon(
                        Icons.search,
                        size: 16,
                        color: focused ? c.quill : c.inkFaint,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (active)
                  Padding(
                    padding: const EdgeInsets.only(top: Gap.x2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$shownCount',
                            style: LedgerType.amount.copyWith(
                              fontSize: 11,
                              color: c.inkFaint,
                            ),
                          ),
                          const TextSpan(text: ' of '),
                          TextSpan(
                            text: '$totalCount',
                            style: LedgerType.amount.copyWith(
                              fontSize: 11,
                              color: c.inkFaint,
                            ),
                          ),
                          const TextSpan(text: ' notes'),
                        ],
                      ),
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 11,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  /// The quick-capture rule: one line, saves on submit, stays put. On
  /// submit its underline flashes quill and settles back to rule over
  /// 300ms — the pen lifting as the thought leaves for the list.
  Widget _captureLine(LedgerColors c) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('pen-lift-$_penLift'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Motion.curve,
      builder: (context, t, child) => Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: _penLift == 0 ? c.rule : Color.lerp(c.quill, c.rule, t)!,
            ),
          ),
        ),
        child: child,
      ),
      child: TextField(
        controller: _capture,
        onSubmitted: _quickCapture,
        textInputAction: TextInputAction.done,
        style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: 'write it down',
          hintStyle: LedgerType.bodyText.copyWith(
            fontSize: 14,
            color: c.inkFaint,
          ),
          icon: Icon(Icons.edit_outlined, size: 16, color: c.inkFaint),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

/// A section's rule, on the book's one spring: it grows and inks in when a
/// second section earns it, and shrinks away when it stops being true.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label, {required this.shown, this.trailing});

  final String label;
  final bool shown;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final d = Motion.reduced(context) ? Duration.zero : Motion.spring;
    return AnimatedSize(
      duration: d,
      curve: Motion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        switchInCurve: Motion.curve,
        switchOutCurve: Motion.curve,
        child: shown
            ? RuleHeader(
                label,
                key: ValueKey('rule-$label'),
                trailing: trailing,
              )
            : SizedBox(
                key: ValueKey('rule-none-$label'),
                width: double.infinity,
              ),
      ),
    );
  }
}

/// One note on the ruled page: its first line strong, its trace faint below,
/// and a whisper at the end of the rule saying how it stands.
class _NoteLine extends StatelessWidget {
  const _NoteLine({
    required this.note,
    required this.last,
    required this.pinPopped,
    required this.onTap,
    required this.onLongPress,
    this.onToggleCheck,
    this.struck = false,
  });

  final Note note;
  final bool last;

  /// True only on the emission where the pin state flipped: the icon does
  /// one 1.15 swell-and-back.
  final bool pinPopped;

  /// Struck out and waiting on its grace — faint, crossed through, and a
  /// tap away from coming back.
  final bool struck;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Ticks the checklist line at this index of the note's body.
  final void Function(int line)? onToggleCheck;

  String get _title {
    final t = note.title.trim();
    if (t.isNotEmpty) return t.split('\n').first;
    final b = note.body.trim();
    if (b.isNotEmpty) return b.split('\n').first;
    return 'Untitled';
  }

  String get _snippet {
    final lines = note.body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // When the body's first line is standing in as the title, the snippet
    // picks up from the line after it.
    if (note.title.trim().isEmpty && lines.isNotEmpty) lines.removeAt(0);
    return lines.isEmpty ? '' : lines.first;
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final item = nextChecklistItem(note.body);
    final faint = LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint);
    final strike = struck ? TextDecoration.lineThrough : null;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (note.pinned) ...[_pin(c), const SizedBox(width: 6)],
                Expanded(
                  child: Text(
                    _title,
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 15,
                      color: struck ? c.inkFaint : c.ink,
                      decoration: strike,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _whisper(c),
              ],
            ),
            const SizedBox(height: 2),
            if (item == null)
              Text(
                _snippet.isEmpty
                    ? relativeDayLabel(note.updatedAt)
                    : '${relativeDayLabel(note.updatedAt)} · $_snippet',
                style: faint.copyWith(decoration: strike),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              // A checklist note wears its next item behind a small box —
              // and the box takes a tap without opening the note.
              Row(
                children: [
                  Text('${relativeDayLabel(note.updatedAt)} · ', style: faint),
                  Pressable(
                    scale: 0.82,
                    onTap: struck || onToggleCheck == null
                        ? null
                        : () => onToggleCheck!(item.line),
                    child: Padding(
                      padding: const EdgeInsets.only(
                        right: 6,
                        top: 4,
                        bottom: 4,
                      ),
                      child: _CheckBox(ticked: item.ticked, size: 11),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      item.text,
                      style: faint.copyWith(
                        decoration: item.ticked || struck
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _pin(LedgerColors c) {
    const icon = Icons.push_pin_outlined;
    if (!pinPopped) return Icon(icon, size: 12, color: c.inkFaint);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.quick,
      curve: Motion.curve,
      child: Icon(icon, size: 12, color: c.inkFaint),
      builder: (context, t, child) => Transform.scale(
        scale: 1 + 0.15 * math.sin(math.pi * t),
        child: child,
      ),
    );
  }

  /// The end of the rule: ticks or words, or — while the row is struck —
  /// the one word that brings it back.
  Widget _whisper(LedgerColors c) {
    if (struck) {
      return Text(
        'tap to undo',
        style: LedgerType.bodyText.copyWith(fontSize: 11, color: c.quill),
      );
    }
    final line = noteWhisper(note.title, note.body);
    if (line.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: Gap.x3),
      child: Text(
        line,
        style: LedgerType.amount.copyWith(fontSize: 11, color: c.inkFaint),
      ),
    );
  }
}

/// The checklist's box: hollow, or ticked in quill.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.ticked, this.size = 13});

  final bool ticked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: ticked ? c.quill : c.inkFaint),
      ),
      child: ticked ? Icon(Icons.check, size: size - 2, color: c.quill) : null,
    );
  }
}

/// The quiet way into the notes that were slid off the page. Hidden until
/// something is actually in there — an empty archive is not a feature.
class _ArchivedDoor extends ConsumerWidget {
  const _ArchivedDoor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    return StreamBuilder<List<Note>>(
      stream: ref.watch(noteRepoProvider).watchArchived(),
      builder: (context, snap) {
        final n = (snap.data ?? const <Note>[]).length;
        if (n == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: Gap.x6),
          child: Pressable(
            onTap: () => Navigator.of(
              context,
            ).push(LedgerRoute<void>(builder: (_) => const _ArchivePage())),
            child: Text(
              'archived · $n — tap to look',
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The archive itself: everything slid off, most recent first. Tapping a
/// note brings it straight back onto the page — no menus, no second step.
class _ArchivePage extends ConsumerWidget {
  const _ArchivePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(noteRepoProvider);
    return ModuleScaffold(
      title: 'Archived',
      child: StreamBuilder<List<Note>>(
        stream: repo.watchArchived(),
        builder: (context, snap) {
          final notes = snap.data ?? const <Note>[];
          if (snap.hasData && notes.isEmpty) {
            return const EmptyPage(
              line: 'Nothing archived.',
              sub: 'Notes swiped off the page wait here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const SizedBox(height: Gap.x3),
              Text(
                'tap a note to bring it back',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x2),
              for (final (i, n) in notes.indexed)
                Pressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    repo.restore(n.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                    decoration: BoxDecoration(
                      border: i == notes.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: c.rule)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.title.trim().isEmpty
                              ? (n.body.trim().isEmpty
                                    ? 'Untitled'
                                    : n.body.trim().split('\n').first)
                              : n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LedgerType.bodyText.copyWith(color: c.ink),
                        ),
                        if (n.body.trim().isNotEmpty &&
                            n.title.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            n.body.trim().split('\n').first,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 12,
                              color: c.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: Gap.x8),
            ],
          );
        },
      ),
    );
  }
}
