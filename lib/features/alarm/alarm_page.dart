import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../core/widgets/plates.dart';
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/repos/alarm_repo.dart';

/// The alarms: the one page in this book that is allowed to wake you.
///
/// Rebuilt in September 2026 on the shape of the alarm apps that feel
/// alive rather than like a settings screen (Clucky was the reference): a
/// week strip up top that shows which mornings are spoken for, the next
/// wake-up as a plate with the time set huge and the wait under it, every
/// alarm as its own plate with a switch, and one big round button to add.
/// The editor is a dial — two curved wheels, hours left and minutes right,
/// the chosen time standing between them.
class AlarmPage extends ConsumerStatefulWidget {
  const AlarmPage({super.key});

  @override
  ConsumerState<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends ConsumerState<AlarmPage> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // The countdown is the page's one moving part; a minute is fine.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    // A one-shot whose hour has passed switches itself off rather than
    // sitting there implying to-morrow.
    unawaited(ref.read(alarmRepoProvider).retireSpent(DateTime.now()));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final repo = ref.watch(alarmRepoProvider);

    return ModuleScaffold(
      title: 'Alarms',
      child: StreamBuilder<List<Alarm>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          final alarms = snap.data ?? const <Alarm>[];
          // The next one to ring, whichever row it lives on.
          ({Alarm alarm, DateTime at})? next;
          for (final a in alarms) {
            final at = nextRing(a, _now);
            if (at == null) continue;
            if (next == null || at.isBefore(next.at)) {
              next = (alarm: a, at: at);
            }
          }
          final anyOn = alarms.any((a) => a.enabled);

          return Stack(
            children: [
              if (alarms.isEmpty)
                EmptyPage(
                  line: 'Nothing is set to wake you.',
                  sub:
                      'Add the one you actually need — the 6:30 you keep '
                      'setting on your phone every night.',
                  action: Pressable(
                    onTap: () => _edit(null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.x4,
                        vertical: 8,
                      ),
                      child: Text(
                        'set an alarm',
                        style: LedgerType.bodyStrong.copyWith(color: c.quill),
                      ),
                    ),
                  ),
                )
              else
                ListView(
                  padding: EdgeInsets.fromLTRB(
                    Gap.page,
                    Gap.x3,
                    Gap.page,
                    MediaQuery.paddingOf(context).bottom + 120,
                  ),
                  children: [
                    _WeekStrip(alarms: alarms, now: _now),
                    const SizedBox(height: Gap.x4),
                    Text(
                      'next wakeup',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 13,
                        color: c.ink,
                      ),
                    ),
                    _NextPlate(
                      next: next,
                      now: _now,
                      anyOn: anyOn,
                      onEdit: next == null ? null : () => _edit(next!.alarm),
                    ),
                    const SizedBox(height: Gap.x4),
                    Text(
                      'all alarms',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 13,
                        color: c.ink,
                      ),
                    ),
                    for (final a in alarms)
                      _AlarmPlate(
                        key: ValueKey('alarm-${a.id}'),
                        alarm: a,
                        now: _now,
                        onToggle: (on) {
                          HapticFeedback.selectionClick();
                          repo.update(a.id, enabled: on);
                        },
                        onTap: () => _edit(a),
                      ),
                  ],
                ),
              // The one big button: round, in the quill's light, unmistakable.
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + Gap.x6,
                child: Center(
                  child: Pressable(
                    key: const ValueKey('alarm-add'),
                    scale: 0.92,
                    onTap: () => _edit(null),
                    child: Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                        color: c.quill,
                        shape: BoxShape.circle,
                        // The chop's edge, not a glow: a hard shadow the
                        // press pushes into the page.
                        boxShadow: [
                          BoxShadow(
                            color: Color.lerp(
                              c.quill,
                              const Color(0xFF000000),
                              0.45,
                            )!,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(child: PenPlus(size: 26, color: c.paper)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _edit(Alarm? existing) async {
    final saved = await showLedgerSheet<bool>(
      context,
      builder: (_) => _AlarmEditor(existing: existing),
    );
    if (saved == true && mounted) {
      // Asked at the moment it means something, not at install time.
      await LedgerReminders.requestPermission();
      await LedgerReminders.requestPreciseAlarmPermission();
    }
  }
}

/// '7:30' and 'AM' — the clock as a person reads it, split so the meridiem
/// can sit small beside a large hour.
(String, String) clock12(int minuteOfDay) {
  final h24 = minuteOfDay ~/ 60;
  final m = minuteOfDay % 60;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return ('$h:${m.toString().padLeft(2, '0')}', h24 < 12 ? 'AM' : 'PM');
}

/// The week, Monday first: a filled disc on every day something is set to
/// ring, a faint one otherwise, and a dot under to-day.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.alarms, required this.now});

  final List<Alarm> alarms;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    bool ringsThatDay(int weekday) {
      for (final a in alarms) {
        if (!a.enabled) continue;
        if (a.days == 0) {
          final at = nextRing(a, now);
          if (at != null && at.weekday == weekday) return true;
        } else if (ringsOn(a.days, weekday)) {
          return true;
        }
      }
      return false;
    }

    return Row(
      children: [
        for (var d = 1; d <= 7; d++) ...[
          Expanded(
            child: Column(
              children: [
                Text(
                  weekdayInitials[d - 1],
                  style: LedgerType.label.copyWith(
                    fontSize: 10,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: Motion.spring,
                  curve: Motion.curve,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: ringsThatDay(d) ? c.quill : c.paperRaised,
                    shape: BoxShape.circle,
                  ),
                  child: ringsThatDay(d)
                      ? Center(
                          child: Icon(
                            Icons.alarm_rounded,
                            size: 14,
                            color: c.paper,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 5),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: now.weekday == d ? c.jama : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The next ring as a plate: when it is and how long is left on the left,
/// the time set huge on the right, and under both the label and the sound
/// as two small doors. When every alarm is off it says so plainly.
class _NextPlate extends StatelessWidget {
  const _NextPlate({
    required this.next,
    required this.now,
    required this.anyOn,
    this.onEdit,
  });

  final ({Alarm alarm, DateTime at})? next;
  final DateTime now;
  final bool anyOn;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final n = next;
    if (n == null) {
      return Plate(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'none set to ring',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: 2),
            Text(
              anyOn
                  ? 'the next one has no day left this week'
                  : 'every alarm below is switched off',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
          ],
        ),
      );
    }
    final today = DateTime(now.year, now.month, now.day);
    final ringDay = DateTime(n.at.year, n.at.month, n.at.day);
    final dayWord = ringDay == today
        ? 'To-day'
        : ringDay == today.add(const Duration(days: 1))
        ? 'To-morrow'
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][n.at.weekday - 1];
    final (time, ampm) = clock12(n.alarm.minuteOfDay);
    return Plate(
      onTap: onEdit,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayWord,
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 14,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'rings ${untilPhrase(n.at.difference(now))}',
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 12,
                        color: c.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                time,
                style: LedgerType.amountTotal.copyWith(
                  fontSize: 40,
                  color: c.ink,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  ampm,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.x3),
          Row(
            children: [
              Expanded(
                child: _MiniDoor(
                  caption: 'label',
                  value: n.alarm.label.isEmpty ? 'none' : n.alarm.label,
                  icon: Icons.sell_outlined,
                ),
              ),
              const SizedBox(width: Gap.x2),
              Expanded(
                child: _MiniDoor(
                  caption: 'sound',
                  value: n.alarm.vibrate ? 'ring + buzz' : 'ring only',
                  icon: n.alarm.vibrate
                      ? Icons.vibration_rounded
                      : Icons.notifications_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small inset on the next-wakeup plate: caption, value, glyph.
class _MiniDoor extends StatelessWidget {
  const _MiniDoor({
    required this.caption,
    required this.value,
    required this.icon,
  });

  final String caption;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.paper.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: LedgerType.label.copyWith(
                    fontSize: 9.5,
                    color: c.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 13,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 18, color: c.inkFaint),
        ],
      ),
    );
  }
}

/// One alarm as a plate: the time large with its meridiem, the switch on
/// the right, and under the time its facts as small tagged words —
/// when it repeats, what it's for, the snooze, the buzz.
class _AlarmPlate extends StatelessWidget {
  const _AlarmPlate({
    super.key,
    required this.alarm,
    required this.now,
    required this.onToggle,
    required this.onTap,
  });

  final Alarm alarm;
  final DateTime now;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final on = alarm.enabled;
    final (time, ampm) = clock12(alarm.minuteOfDay);
    final ink = on ? c.ink : c.inkFaint;
    final once = alarm.days == 0 ? nextRing(alarm, now) : null;
    return Plate(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      time,
                      style: LedgerType.amountTotal.copyWith(
                        fontSize: 30,
                        color: ink,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      ampm,
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 13,
                        color: ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: Gap.x3,
                  runSpacing: 4,
                  children: [
                    _Tag(
                      icon: alarm.days == 0
                          ? Icons.looks_one_outlined
                          : Icons.repeat_rounded,
                      text: repeatLabel(alarm.days, onceOn: once),
                      ink: c.inkFaint,
                    ),
                    if (alarm.label.isNotEmpty)
                      _Tag(
                        icon: Icons.sell_outlined,
                        text: alarm.label,
                        ink: c.inkFaint,
                      ),
                    _Tag(
                      icon: Icons.snooze_rounded,
                      text: '${alarm.snoozeMinutes}m',
                      ink: c.inkFaint,
                    ),
                    if (alarm.vibrate)
                      _Tag(
                        icon: Icons.vibration_rounded,
                        text: 'buzz',
                        ink: c.inkFaint,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.x3),
          _Switch(on: on, onChanged: onToggle),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text, required this.ink});

  final IconData icon;
  final String text;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: ink),
        const SizedBox(width: 3),
        Text(
          text,
          style: LedgerType.bodyText.copyWith(fontSize: 11.5, color: ink),
        ),
      ],
    );
  }
}

/// A switch: the track turns to the credit ink and the knob slides.
class _Switch extends StatelessWidget {
  const _Switch({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      key: ValueKey('alarm-switch-$on'),
      haptic: false,
      onTap: () => onChanged(!on),
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.curve,
        width: 50,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: on ? c.jama : c.rule,
          borderRadius: BorderRadius.circular(15),
        ),
        child: AnimatedAlign(
          duration: Motion.quick,
          curve: Motion.curve,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

// ————— the editor: a dial —————

class _AlarmEditor extends ConsumerStatefulWidget {
  const _AlarmEditor({this.existing});

  final Alarm? existing;

  @override
  ConsumerState<_AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends ConsumerState<_AlarmEditor> {
  late final _label = TextEditingController(text: widget.existing?.label ?? '');
  late int _hour = (widget.existing?.minuteOfDay ?? 6 * 60 + 30) ~/ 60;
  late int _minute = (widget.existing?.minuteOfDay ?? 6 * 60 + 30) % 60;
  late int _days = widget.existing?.days ?? 0;
  late int _snooze = widget.existing?.snoozeMinutes ?? 9;
  late bool _vibrate = widget.existing?.vibrate ?? true;
  bool _labelOpen = false;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    final repo = ref.read(alarmRepoProvider);
    final minuteOfDay = _hour * 60 + _minute;
    if (widget.existing == null) {
      await repo.create(
        minuteOfDay: minuteOfDay,
        label: _label.text,
        days: _days,
        snoozeMinutes: _snooze,
        vibrate: _vibrate,
      );
    } else {
      await repo.update(
        widget.existing!.id,
        minuteOfDay: minuteOfDay,
        label: _label.text,
        days: _days,
        snoozeMinutes: _snooze,
        vibrate: _vibrate,
        enabled: true,
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    HapticFeedback.mediumImpact();
    await ref.read(alarmRepoProvider).delete(widget.existing!.id);
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final preview = nextRing(
      Alarm(
        id: 0,
        label: '',
        minuteOfDay: _hour * 60 + _minute,
        days: _days,
        enabled: true,
        snoozeMinutes: _snooze,
        vibrate: _vibrate,
        createdAt: DateTime.now(),
      ),
      DateTime.now(),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.page,
          0,
          Gap.page,
          Gap.x4 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: Gap.x2),
              Row(
                children: [
                  Text(
                    widget.existing == null ? 'A new alarm' : 'This alarm',
                    style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
                  ),
                  const Spacer(),
                  Text(
                    preview == null
                        ? 'rings once'
                        : 'rings ${untilPhrase(preview.difference(DateTime.now()))}',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Gap.x3),
              _Dial(
                hour: _hour,
                minute: _minute,
                onHour: (h) => setState(() => _hour = h),
                onMinute: (m) => setState(() => _minute = m),
              ),
              const SizedBox(height: Gap.x3),
              // The days, as discs.
              Row(
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++) ...[
                    Expanded(
                      child: _DayDisc(
                        letter: weekdayInitials[weekday - 1],
                        on: ringsOn(_days, weekday),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _days = toggleDay(_days, weekday));
                        },
                      ),
                    ),
                    if (weekday < 7) const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: Gap.x2),
              Center(
                child: Text(
                  _days == 0
                      ? 'no days chosen — it rings once, then switches itself off'
                      : repeatLabel(_days),
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x3),
              // Snooze, as a pill.
              Row(
                children: [
                  Text(
                    'snooze',
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(width: Gap.x3),
                  Expanded(
                    child: PillSegments(
                      labels: const ['5m', '9m', '15m'],
                      index: [5, 9, 15].indexOf(_snooze).clamp(0, 2),
                      onSelect: (i) => setState(() => _snooze = [5, 9, 15][i]),
                      height: 30,
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: Motion.spring,
                curve: Motion.curve,
                alignment: Alignment.topLeft,
                child: _labelOpen || _label.text.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: Gap.x3),
                        child: TextField(
                          controller: _label,
                          autofocus: _labelOpen,
                          textCapitalization: TextCapitalization.sentences,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 16,
                            color: c.ink,
                          ),
                          cursorColor: c.quill,
                          decoration: InputDecoration(
                            hintText: 'what it\'s for — gym, the 7:40 bus',
                            hintStyle: LedgerType.bodyText.copyWith(
                              color: c.inkFaint,
                            ),
                            border: UnderlineInputBorder(
                              borderSide: BorderSide(color: c.rule),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: Gap.x6),
              // The bottom bar: label on the left, the big red set in the
              // middle, buzz on the right.
              Row(
                children: [
                  _RoundDoor(
                    icon: Icons.sell_outlined,
                    on: _label.text.isNotEmpty || _labelOpen,
                    onTap: () => setState(() => _labelOpen = !_labelOpen),
                  ),
                  const Spacer(),
                  Pressable(
                    key: const ValueKey('alarm-set'),
                    scale: 0.94,
                    onTap: _save,
                    child: Container(
                      width: 120,
                      height: 80,
                      decoration: BoxDecoration(
                        color: c.quill,
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: Color.lerp(
                              c.quill,
                              const Color(0xFF000000),
                              0.45,
                            )!,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PenPlus(size: 22, color: c.paper),
                          const SizedBox(height: 4),
                          Text(
                            widget.existing == null ? 'Set it' : 'Save',
                            style: LedgerType.bodyStrong.copyWith(
                              fontSize: 13,
                              color: c.paper,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  _RoundDoor(
                    icon: _vibrate
                        ? Icons.vibration_rounded
                        : Icons.notifications_outlined,
                    on: _vibrate,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _vibrate = !_vibrate);
                    },
                  ),
                ],
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: Gap.x4),
                Center(
                  child: Pressable(
                    haptic: false,
                    onTap: _delete,
                    child: Text(
                      'Remove this alarm',
                      style: LedgerType.bodyStrong.copyWith(
                        fontSize: 13,
                        color: c.inkFaint,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small round door on the editor's bottom bar.
class _RoundDoor extends StatelessWidget {
  const _RoundDoor({required this.icon, required this.on, required this.onTap});

  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      haptic: false,
      scale: 0.92,
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: c.paperRaised,
          shape: BoxShape.circle,
          border: Border.all(color: on ? c.quill : c.rule, width: 1.5),
        ),
        child: Icon(icon, size: 20, color: on ? c.quill : c.inkFaint),
      ),
    );
  }
}

/// The dial: hours curve down the left, minutes down the right, and the
/// chosen time stands between them in figures big enough to read from
/// the pillow. Each wheel bends away from the centre, so the numbers read
/// as arcs rather than columns; a small marker points at the row that
/// counts.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.hour,
    required this.minute,
    required this.onHour,
    required this.onMinute,
  });

  final int hour;
  final int minute;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final pm = hour >= 12;
    return SizedBox(
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: _Arc(
                  key: const ValueKey('dial-hours'),
                  count: 12,
                  labelFor: (i) => (i + 1).toString().padLeft(2, '0'),
                  index: h12 - 1,
                  offAxis: -1.35,
                  onChanged: (i) => onHour(((i + 1) % 12) + (pm ? 12 : 0)),
                ),
              ),
              const SizedBox(width: 140),
              Expanded(
                child: _Arc(
                  key: const ValueKey('dial-minutes'),
                  count: 12,
                  labelFor: (i) => (i * 5).toString().padLeft(2, '0'),
                  index: (minute / 5).round() % 12,
                  offAxis: 1.35,
                  onChanged: (i) => onMinute(i * 5),
                ),
              ),
            ],
          ),
          // The marker: a small diamond above the chosen time.
          Positioned(
            top: 62,
            child: Transform.rotate(
              angle: 0.785398,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c.quill,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // The chosen time.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                h12.toString().padLeft(2, '0'),
                style: LedgerType.amountTotal.copyWith(
                  fontSize: 44,
                  color: c.ink,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  ':',
                  style: LedgerType.amountTotal.copyWith(
                    fontSize: 36,
                    color: c.inkFaint,
                  ),
                ),
              ),
              Text(
                minute.toString().padLeft(2, '0'),
                style: LedgerType.amountTotal.copyWith(
                  fontSize: 44,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 6),
              Pressable(
                key: const ValueKey('dial-ampm'),
                haptic: false,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onHour((hour + 12) % 24);
                },
                child: Text(
                  pm ? 'PM' : 'AM',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 16,
                    color: c.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One curved wheel of figures.
class _Arc extends StatefulWidget {
  const _Arc({
    super.key,
    required this.count,
    required this.labelFor,
    required this.index,
    required this.offAxis,
    required this.onChanged,
  });

  final int count;
  final String Function(int) labelFor;
  final int index;

  /// Negative bends the wheel to the left, positive to the right.
  final double offAxis;
  final ValueChanged<int> onChanged;

  @override
  State<_Arc> createState() => _ArcState();
}

class _ArcState extends State<_Arc> {
  late final _ctl = FixedExtentScrollController(initialItem: widget.index);

  @override
  void didUpdateWidget(_Arc old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && _ctl.selectedItem != widget.index) {
      _ctl.animateToItem(
        widget.index,
        duration: Motion.quick,
        curve: Motion.curve,
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return ListWheelScrollView.useDelegate(
      controller: _ctl,
      itemExtent: 44,
      perspective: 0.004,
      diameterRatio: 1.6,
      offAxisFraction: widget.offAxis,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (i) {
        HapticFeedback.selectionClick();
        widget.onChanged(i);
      },
      childDelegate: ListWheelChildLoopingListDelegate(
        children: [
          for (var i = 0; i < widget.count; i++)
            Center(
              child: Text(
                widget.labelFor(i),
                style: LedgerType.amountTotal.copyWith(
                  fontSize: 26,
                  color: i == widget.index ? c.ink : c.inkFaint.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A day of the week as a disc: filled when the alarm rings on it.
class _DayDisc extends StatelessWidget {
  const _DayDisc({required this.letter, required this.on, required this.onTap});

  final String letter;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      haptic: false,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.curve,
        height: 38,
        decoration: BoxDecoration(
          color: on ? c.quill : c.paperRaised,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            letter,
            style: LedgerType.bodyStrong.copyWith(
              fontSize: 13,
              color: on ? c.paper : c.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}
