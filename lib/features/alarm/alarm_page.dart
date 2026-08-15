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
import '../../core/widgets/sheets.dart';
import '../../data/db.dart';
import '../../data/repos/alarm_repo.dart';

/// The alarms: the one page in this book that is allowed to wake you.
///
/// It leads with the next one — the only alarm fact that matters at the
/// moment you look — and keeps the rest as a list of hours you can read down
/// like a timetable. Nothing rings quietly here: an alarm takes the lock
/// screen and the alarm volume, and answers a snooze even with the app shut.
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
      fab: Pressable(
        onTap: () => _edit(null),
        haptic: false,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: c.quill,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: c.ink.withValues(alpha: 0.28),
                offset: const Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(child: PenPlus(size: 18, color: c.paper)),
        ),
      ),
      child: StreamBuilder<List<Alarm>>(
        stream: repo.watchAll(),
        builder: (context, snap) {
          final alarms = snap.data ?? const <Alarm>[];
          if (alarms.isEmpty) {
            return EmptyPage(
              line: 'Nothing is set to wake you.',
              sub: 'Add the one you actually need — the 6:30 you keep '
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
            );
          }

          // The next one to ring, whichever row it lives on.
          ({Alarm alarm, DateTime at})? next;
          for (final a in alarms) {
            final at = nextRing(a, _now);
            if (at == null) continue;
            if (next == null || at.isBefore(next.at)) {
              next = (alarm: a, at: at);
            }
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(
              Gap.page,
              0,
              Gap.page,
              MediaQuery.paddingOf(context).bottom + 96,
            ),
            children: [
              const SizedBox(height: Gap.x3),
              _NextAlarm(next: next, now: _now),
              const SizedBox(height: Gap.x4),
              const RuleHeader('set'),
              for (final (i, a) in alarms.indexed)
                _AlarmRow(
                  alarm: a,
                  now: _now,
                  last: i == alarms.length - 1,
                  onToggle: (on) {
                    HapticFeedback.selectionClick();
                    repo.update(a.id, enabled: on);
                  },
                  onTap: () => _edit(a),
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

/// The hero: the next ring, large, with how long is left under it. When
/// every alarm is switched off it says so plainly rather than showing a
/// time that isn't going to happen.
class _NextAlarm extends StatelessWidget {
  const _NextAlarm({required this.next, required this.now});

  final ({Alarm alarm, DateTime at})? next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final n = next;
    if (n == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'next alarm',
            style: LedgerType.label.copyWith(color: c.inkFaint),
          ),
          const SizedBox(height: 2),
          Text(
            'none set to ring',
            style: LedgerType.heroAmount.copyWith(fontSize: 34, color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            'every alarm below is switched off',
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ],
      );
    }
    final label = n.alarm.label.trim();
    final tomorrow = n.at.day != now.day;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'next alarm',
          style: LedgerType.label.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 2),
        Text(
          clockLabel(n.alarm.minuteOfDay),
          style: LedgerType.heroAmount.copyWith(fontSize: 56, color: c.ink),
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (label.isNotEmpty) label,
            untilPhrase(n.at.difference(now)),
            if (tomorrow) 'to-morrow',
          ].join(' · '),
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
      ],
    );
  }
}

/// One alarm: the hour large on the left, what it is and when it repeats
/// underneath, and the switch on the right. A switched-off alarm fades
/// rather than disappearing — it's still a thing you set once.
class _AlarmRow extends StatelessWidget {
  const _AlarmRow({
    required this.alarm,
    required this.now,
    required this.last,
    required this.onToggle,
    required this.onTap,
  });

  final Alarm alarm;
  final DateTime now;
  final bool last;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final on = alarm.enabled;
    final ink = on ? c.ink : c.inkFaint;
    final label = alarm.label.trim();
    final at = nextRing(alarm, now);
    return Pressable(
      haptic: false,
      scale: 0.99,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clockLabel(alarm.minuteOfDay),
                    style: LedgerType.heroAmount.copyWith(
                      fontSize: 30,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (label.isNotEmpty) label,
                      repeatLabel(alarm.days, onceOn: at),
                    ].join(' · '),
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            _InkSwitch(on: on, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

/// The switch, drawn rather than borrowed: a hard-cornered track and a block
/// that slides across it. Material's pill would be the only pill in the app.
class _InkSwitch extends StatelessWidget {
  const _InkSwitch({required this.on, required this.onChanged});

  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Semantics(
      toggled: on,
      child: Pressable(
        haptic: false,
        scale: 0.94,
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: Motion.quick,
          curve: Motion.curve,
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: on ? c.quill.withValues(alpha: 0.18) : null,
            border: Border.all(color: on ? c.quill : c.rule, width: 1.2),
            borderRadius: BorderRadius.circular(Corner.stamp),
          ),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: on ? c.quill : c.rule,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}

// ————— setting one —————

/// Writing an alarm: the hours and minutes on two wheels you actually spin,
/// the days as seven stamps, and the two questions worth asking after that.
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
              Text(
                widget.existing == null ? 'A new alarm' : 'This alarm',
                style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
              ),
              const SizedBox(height: Gap.x3),
              _Wheels(
                hour: _hour,
                minute: _minute,
                onHour: (h) => setState(() => _hour = h),
                onMinute: (m) => setState(() => _minute = m),
              ),
              const SizedBox(height: Gap.x2),
              Center(
                child: Text(
                  preview == null
                      ? 'pick the days it should ring'
                      : untilPhrase(preview.difference(DateTime.now())),
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 12,
                    color: c.inkFaint,
                  ),
                ),
              ),
              const SizedBox(height: Gap.x4),
              Text(
                'repeats',
                style: LedgerType.label.copyWith(color: c.inkFaint),
              ),
              const SizedBox(height: Gap.x2),
              Row(
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++) ...[
                    Expanded(
                      child: _DayStamp(
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
              Text(
                _days == 0
                    ? 'no days chosen — it rings once, then switches itself off'
                    : repeatLabel(_days),
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
              const SizedBox(height: Gap.x4),
              TextField(
                controller: _label,
                textCapitalization: TextCapitalization.sentences,
                style: LedgerType.bodyText.copyWith(fontSize: 16, color: c.ink),
                cursorColor: c.quill,
                decoration: InputDecoration(
                  hintText: 'what it\'s for — gym, the 7:40 bus',
                  hintStyle: LedgerType.bodyText.copyWith(color: c.inkFaint),
                  border: UnderlineInputBorder(
                    borderSide: BorderSide(color: c.rule),
                  ),
                ),
              ),
              const SizedBox(height: Gap.x4),
              Row(
                children: [
                  Text(
                    'snooze',
                    style: LedgerType.label.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(width: Gap.x3),
                  for (final m in [5, 9, 15]) ...[
                    Pressable(
                      haptic: false,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _snooze = m);
                      },
                      child: _Chip(label: '${m}m', on: _snooze == m),
                    ),
                    const SizedBox(width: Gap.x2),
                  ],
                ],
              ),
              const SizedBox(height: Gap.x3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'buzz as well as ring',
                      style: LedgerType.bodyText.copyWith(color: c.ink),
                    ),
                  ),
                  _InkSwitch(
                    on: _vibrate,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      setState(() => _vibrate = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: Gap.x6),
              FilledButton(
                onPressed: _save,
                child: Text(widget.existing == null ? 'Set it' : 'Save'),
              ),
              if (widget.existing != null)
                TextButton(
                  onPressed: _delete,
                  child: Text(
                    'Remove this alarm',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 13,
                      color: c.seal,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two wheels of figures with one ruled window across them — a clock you set
/// with your thumb, in the ledger's own mono, rather than a dialog.
class _Wheels extends StatelessWidget {
  const _Wheels({
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
    return SizedBox(
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The window: two hairlines, the width of the wheels.
          Container(
            height: 52,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: c.rule),
                bottom: BorderSide(color: c.rule),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Wheel(count: 24, value: hour, onChanged: onHour),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.x2),
                child: Text(
                  ':',
                  style: LedgerType.heroAmount.copyWith(
                    fontSize: 34,
                    color: c.inkFaint,
                  ),
                ),
              ),
              _Wheel(count: 60, value: minute, onChanged: onMinute),
            ],
          ),
        ],
      ),
    );
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({
    required this.count,
    required this.value,
    required this.onChanged,
  });

  final int count;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final _controller = FixedExtentScrollController(
    initialItem: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return SizedBox(
      width: 76,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: 52,
        perspective: 0.003,
        diameterRatio: 1.5,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (i) {
          HapticFeedback.selectionClick();
          widget.onChanged(i);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.count,
          builder: (context, i) => Center(
            child: Text(
              i.toString().padLeft(2, '0'),
              style: LedgerType.heroAmount.copyWith(
                fontSize: 38,
                color: i == widget.value ? c.ink : c.inkFaint,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One weekday, as a stamp that takes the quill wash when it's chosen.
class _DayStamp extends StatelessWidget {
  const _DayStamp({
    required this.letter,
    required this.on,
    required this.onTap,
  });

  final String letter;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      haptic: false,
      scale: 0.92,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.quick,
        curve: Motion.curve,
        height: 42,
        decoration: BoxDecoration(
          color: on ? c.quill.withValues(alpha: 0.16) : null,
          border: Border.all(color: on ? c.quill : c.rule),
          borderRadius: BorderRadius.circular(Corner.stamp),
        ),
        child: Center(
          child: Text(
            letter,
            style: LedgerType.bodyStrong.copyWith(
              fontSize: 13,
              color: on ? c.ink : c.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on});

  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return AnimatedContainer(
      duration: Motion.quick,
      curve: Motion.curve,
      padding: const EdgeInsets.symmetric(horizontal: Gap.x3, vertical: 6),
      decoration: BoxDecoration(
        color: on ? c.quill.withValues(alpha: 0.16) : null,
        border: Border.all(color: on ? c.quill : c.rule),
        borderRadius: BorderRadius.circular(Corner.stamp),
      ),
      child: Text(
        label,
        style: LedgerType.amount.copyWith(
          fontSize: 12,
          color: on ? c.ink : c.inkFaint,
        ),
      ),
    );
  }
}
