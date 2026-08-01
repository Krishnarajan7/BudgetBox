import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../data/db.dart';
import '../../data/repos/note_repo.dart';
import 'note_editor.dart';

/// The Notes book: one ruled line to catch a thought, and the thoughts
/// beneath it — pinned ones first, the rest in order of last touch.
class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _capture = TextEditingController();

  /// Ids already on the page — anything new fades and slides in; nothing
  /// animates on first open.
  final _seen = <int>{};
  bool _primed = false;

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  Future<void> _quickCapture(String text) async {
    final line = text.trim();
    if (line.isEmpty) return;
    HapticFeedback.selectionClick();
    _capture.clear();
    await ref.read(noteRepoProvider).create(title: line);
  }

  void _open(Note note) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) => NoteEditorPage(note: note),
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
    final repo = ref.watch(noteRepoProvider);

    return ModuleScaffold(
      title: 'Notes',
      child: StreamBuilder<List<Note>>(
        stream: repo.watchAll(),
        builder: (context, snapshot) {
          final notes = snapshot.data ?? const <Note>[];
          final fresh = <int>{
            if (_primed)
              for (final n in notes)
                if (!_seen.contains(n.id)) n.id,
          };
          if (snapshot.hasData) {
            _primed = true;
            _seen.addAll(notes.map((n) => n.id));
          }

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: Gap.page),
            children: [
              const SizedBox(height: Gap.x3),
              _captureLine(c),
              const SizedBox(height: Gap.x4),
              if (snapshot.hasData && notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x8),
                  child: Text(
                    'Nothing here yet. First thought goes on top.',
                    style: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  ),
                )
              else
                for (final (i, n) in notes.indexed)
                  _Entrance(
                    key: ValueKey('note-entrance-${n.id}'),
                    animate: fresh.contains(n.id),
                    child: Dismissible(
                      key: ValueKey('note-${n.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: c.seal.withValues(alpha: 0.12),
                        padding: const EdgeInsets.only(right: Gap.x4),
                        child: Icon(Icons.close, size: 16, color: c.seal),
                      ),
                      onDismissed: (_) {
                        HapticFeedback.mediumImpact();
                        repo.archive(n.id);
                      },
                      child: _NoteLine(
                        note: n,
                        last: i == notes.length - 1,
                        onTap: () => _open(n),
                        onLongPress: () {
                          HapticFeedback.lightImpact();
                          repo.setPinned(n.id, !n.pinned);
                        },
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

  /// The quick-capture rule: one line, saves on submit, stays put.
  Widget _captureLine(LedgerColors c) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.rule)),
      ),
      child: TextField(
        controller: _capture,
        onSubmitted: _quickCapture,
        textInputAction: TextInputAction.done,
        style: LedgerType.bodyText.copyWith(fontSize: 14, color: c.ink),
        decoration: InputDecoration(
          hintText: 'write it down',
          hintStyle:
              LedgerType.bodyText.copyWith(fontSize: 14, color: c.inkFaint),
          icon: Icon(Icons.edit_outlined, size: 16, color: c.inkFaint),
          border: InputBorder.none,
          isDense: true,
        ),
      ),
    );
  }
}

/// One note on the ruled page: its first line strong, its trace faint below.
class _NoteLine extends StatelessWidget {
  const _NoteLine({
    required this.note,
    required this.last,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

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
    final snippet = _snippet;
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
              children: [
                if (note.pinned) ...[
                  Icon(Icons.push_pin_outlined, size: 12, color: c.inkFaint),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    _title,
                    style: LedgerType.bodyStrong
                        .copyWith(fontSize: 15, color: c.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              snippet.isEmpty
                  ? relativeDayLabel(note.updatedAt)
                  : '${relativeDayLabel(note.updatedAt)} · $snippet',
              style:
                  LedgerType.bodyText.copyWith(fontSize: 12, color: c.inkFaint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fade + small slide for a line that has just been written — ~250ms,
/// eased out, short enough to stay out of the way.
class _Entrance extends StatelessWidget {
  const _Entrance({super.key, required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}
