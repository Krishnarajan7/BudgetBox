import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../data/db.dart';
import '../../data/repos/note_repo.dart';

/// "to-day", "yesterday", else "12 Jul" — how the notes book speaks of time.
String relativeDayLabel(DateTime d) {
  const months = [
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
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final ago = today.difference(day).inDays;
  if (ago <= 0) return 'to-day';
  if (ago == 1) return 'yesterday';
  return '${d.day} ${months[d.month - 1]}';
}

/// Whitespace-separated runs of ink — the meta line's word count.
int wordCount(String text) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  return RegExp(r'\S+').allMatches(t).length;
}

/// One note, full page. No save button — the ink dries on its own: writes
/// are debounced ~500ms and flushed when the page is left.
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, required this.note});

  final Note note;

  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  late final NoteRepo _repo;
  late final TextEditingController _title;
  late final TextEditingController _body;
  Timer? _debounce;
  late String _savedTitle;
  late String _savedBody;
  late bool _pinned;
  late DateTime _updatedAt;

  /// True for the 800ms after a copy — the icon wears a check, then
  /// settles back on its own.
  bool _copied = false;
  int _copyStamp = 0;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(noteRepoProvider);
    _title = TextEditingController(text: widget.note.title);
    _body = TextEditingController(text: widget.note.body);
    _savedTitle = widget.note.title;
    _savedBody = widget.note.body;
    _pinned = widget.note.pinned;
    _updatedAt = widget.note.updatedAt;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  /// Fire-and-forget save for the moments the page can't wait (pop, dispose).
  void _flush() {
    _debounce?.cancel();
    if (_title.text == _savedTitle && _body.text == _savedBody) return;
    final title = _title.text;
    final body = _body.text;
    _savedTitle = title;
    _savedBody = body;
    unawaited(_repo.update(widget.note.id, title: title, body: body));
  }

  Future<void> _save() async {
    if (_title.text == _savedTitle && _body.text == _savedBody) return;
    _savedTitle = _title.text;
    _savedBody = _body.text;
    await _repo.update(widget.note.id, title: _savedTitle, body: _savedBody);
    if (mounted) setState(() => _updatedAt = DateTime.now());
  }

  /// The whole page onto the clipboard: title, a blank line, the body. No
  /// toast — the icon's brief check is the confirmation.
  void _copyAll() {
    final title = _title.text.trim();
    final body = _body.text;
    Clipboard.setData(
      ClipboardData(text: title.isEmpty ? body : '$title\n\n$body'),
    );
    HapticFeedback.lightImpact();
    final stamp = ++_copyStamp;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted && stamp == _copyStamp) setState(() => _copied = false);
    });
  }

  void _togglePin() {
    HapticFeedback.lightImpact();
    setState(() => _pinned = !_pinned);
    unawaited(_repo.setPinned(widget.note.id, _pinned));
  }

  void _archive() {
    HapticFeedback.mediumImpact();
    _flush();
    unawaited(_repo.archive(widget.note.id));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) => _flush(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        _flush();
                        Navigator.of(context).pop();
                      },
                      child: Icon(Icons.arrow_back, size: 18, color: c.inkFaint),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'edited ${relativeDayLabel(_updatedAt)}',
                          style: LedgerType.bodyText
                              .copyWith(fontSize: 12, color: c.inkFaint),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: _copyAll,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeOutCubic,
                        child: _copied
                            ? Icon(
                                Icons.check,
                                key: const ValueKey('copied'),
                                size: 18,
                                color: c.quill,
                              )
                            : Icon(
                                Icons.copy_all_outlined,
                                key: const ValueKey('copy'),
                                size: 18,
                                color: c.inkFaint,
                              ),
                      ),
                    ),
                    const SizedBox(width: Gap.x4),
                    InkWell(
                      onTap: _togglePin,
                      child: Icon(
                        _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        size: 18,
                        color: _pinned ? c.quill : c.inkFaint,
                      ),
                    ),
                    const SizedBox(width: Gap.x4),
                    InkWell(
                      onTap: _archive,
                      child: Icon(Icons.archive_outlined,
                          size: 18, color: c.inkFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.x4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                child: TextField(
                  controller: _title,
                  onChanged: (_) => _changed(),
                  textInputAction: TextInputAction.next,
                  style: LedgerType.title.copyWith(color: c.ink),
                  decoration: InputDecoration(
                    hintText: 'Untitled',
                    hintStyle: LedgerType.title.copyWith(color: c.inkFaint),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                  child: TextField(
                    controller: _body,
                    onChanged: (_) => _changed(),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 15, height: 1.5, color: c.ink),
                    decoration: InputDecoration(
                      hintText: '…',
                      hintStyle: LedgerType.bodyText.copyWith(
                          fontSize: 15, height: 1.5, color: c.inkFaint),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              _metaLine(c),
              const SizedBox(height: Gap.x4),
            ],
          ),
        ),
      ),
    );
  }

  /// The faint line at the page's foot: "312 words · edited to-day ·
  /// created 14 Jul". The count refreshes on the same debounce as the ink.
  Widget _metaLine(LedgerColors c) {
    final n = wordCount(_body.text);
    final style = LedgerType.bodyText.copyWith(fontSize: 11, color: c.inkFaint);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$n',
              style: LedgerType.amount.copyWith(
                fontSize: 11,
                color: c.inkFaint,
              ),
            ),
            TextSpan(
              text:
                  ' word${n == 1 ? '' : 's'}'
                  ' · edited ${relativeDayLabel(_updatedAt)}'
                  ' · created ${relativeDayLabel(widget.note.createdAt)}',
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
