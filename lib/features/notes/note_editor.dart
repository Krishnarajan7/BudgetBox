import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
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

DateTime suggestedNoteReminder([DateTime? clock]) {
  final now = clock ?? DateTime.now();
  final tonight = DateTime(now.year, now.month, now.day, 19);
  return tonight.isAfter(now)
      ? tonight
      : DateTime(now.year, now.month, now.day + 1, 9);
}

String noteReminderLabel(DateTime at, {DateTime? clock}) {
  final now = clock ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final distance = day.difference(today).inDays;
  final date = switch (distance) {
    0 => 'to-day',
    1 => 'to-morrow',
    _ => relativeDayLabel(at),
  };
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final period = at.hour < 12 ? 'am' : 'pm';
  final time = '$hour:$minute $period';
  if (at.isBefore(now)) {
    return distance == 0 ? 'overdue · $time' : 'overdue · $date · $time';
  }
  return '$date · $time';
}

Future<DateTime?> pickNoteReminder(
  BuildContext context, {
  DateTime? initial,
}) async {
  final now = DateTime.now();
  final seed = initial ?? suggestedNoteReminder(now);
  final date = await showDatePicker(
    context: context,
    initialDate: seed.isBefore(now) ? suggestedNoteReminder(now) : seed,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5, 12, 31),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  if (time == null) return null;
  final result = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (!result.isAfter(DateTime.now()) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Choose a time that is still ahead.')),
    );
    return null;
  }
  final allowed = await LedgerReminders.requestPermission();
  if (!allowed && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reminder saved, but notifications are off for Krish Space.',
        ),
      ),
    );
  }
  if (allowed) {
    final precise = await LedgerReminders.requestPreciseAlarmPermission();
    if (!precise && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reminder saved. Android may deliver it a little late without precise alarms.',
          ),
        ),
      );
    }
  }
  return result;
}

/// One note, full page. No save button — the ink dries on its own: writes
/// are debounced ~500ms and flushed when the page is left.
class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, required this.note, this.startWriting = false});

  final Note note;

  /// True when the page opens straight off the capture line: the headline
  /// is already down, so the pen lands in the body with the keyboard up.
  final bool startWriting;

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
  late DateTime? _remindAt;
  late bool _completed;
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
    _remindAt = widget.note.remindAt;
    _completed = widget.note.completed;
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

  Future<void> _pickReminder() async {
    final picked = await pickNoteReminder(context, initial: _remindAt);
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _remindAt = picked;
      _completed = false;
      _updatedAt = DateTime.now();
    });
    await _repo.setReminder(widget.note.id, picked);
  }

  Future<void> _clearReminder() async {
    HapticFeedback.selectionClick();
    setState(() {
      _remindAt = null;
      _completed = false;
      _updatedAt = DateTime.now();
    });
    await _repo.setReminder(widget.note.id, null);
  }

  Future<void> _toggleCompleted() async {
    HapticFeedback.mediumImpact();
    final next = !_completed;
    setState(() {
      _completed = next;
      _updatedAt = DateTime.now();
    });
    await _repo.setCompleted(widget.note.id, next);
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
                padding: const EdgeInsets.fromLTRB(
                  Gap.page,
                  Gap.x2,
                  Gap.page,
                  0,
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        _flush();
                        Navigator.of(context).pop();
                      },
                      child: Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: c.inkFaint,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'edited ${relativeDayLabel(_updatedAt)}',
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 12,
                            color: c.inkFaint,
                          ),
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
                      child: Icon(
                        Icons.archive_outlined,
                        size: 18,
                        color: c.inkFaint,
                      ),
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
                    autofocus: widget.startWriting,
                    onChanged: (_) => _changed(),
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 15,
                      height: 1.5,
                      color: c.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: '…',
                      hintStyle: LedgerType.bodyText.copyWith(
                        fontSize: 15,
                        height: 1.5,
                        color: c.inkFaint,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              _reminderLine(c),
              _metaLine(c),
              const SizedBox(height: Gap.x4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reminderLine(LedgerColors c) {
    final at = _remindAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.only(top: Gap.x3),
        child: Row(
          children: [
            Icon(
              at == null
                  ? Icons.notifications_none
                  : Icons.notifications_active_outlined,
              size: 17,
              color: at == null ? c.inkFaint : c.quill,
            ),
            const SizedBox(width: Gap.x2),
            Expanded(
              child: InkWell(
                onTap: _pickReminder,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gap.x1),
                  child: Text(
                    at == null ? 'add a reminder' : noteReminderLabel(at),
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 13,
                      color: at == null ? c.inkFaint : c.ink,
                      decoration: _completed
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            if (at != null) ...[
              TextButton(
                onPressed: _toggleCompleted,
                child: Text(_completed ? 'undo' : 'mark done'),
              ),
              IconButton(
                tooltip: 'Remove reminder',
                visualDensity: VisualDensity.compact,
                onPressed: _clearReminder,
                icon: Icon(Icons.close, size: 16, color: c.inkFaint),
              ),
            ],
          ],
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
