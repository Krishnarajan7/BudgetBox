import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The book's voice, when the app is closed: a handful of quiet local
/// notifications — never a nag ladder, never marketing, never a badge left
/// burning. Everything here is wrapped so that a platform without the
/// plugin (widget tests, desktop) degrades to silence instead of an
/// exception: a reminder is not worth a crash.
///
/// The id ledger: 1 = tonight's voiced nudge (one-shot, knows the day),
/// 2 = the retired repeating evening nudge (kept only so upgrades cancel it),
/// 3 = salary morning, 4 = the focus session's finish line, 20–33 = the next
/// fourteen standing evening nudges, 1000+ = calendar days
/// ([scheduleEventDay]), 2000+ = recurring charges, 1000000+ = note reminders.
class LedgerReminders {
  LedgerReminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _unavailable = false;

  static const _idTonight = 1;
  static const _idStanding = 2;
  static const _idSalary = 3;
  static const _idFocus = 4;
  static const _standingBase = 20;
  static const _standingDays = 14;
  static const _dueBase = 2000;
  static const _noteBase = 1000000;
  static const _channel = AndroidNotificationDetails(
    'close-the-day',
    'Evening nudge',
    channelDescription: 'One quiet reminder to close the day',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  static const _noteChannel = AndroidNotificationDetails(
    'notes-and-reminders',
    'Notes and reminders',
    channelDescription: 'Reminders attached to notes and daily tasks',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Alarms are the one voice in this book allowed to be rude: they take the
  /// lock screen, they use the alarm stream rather than the notification
  /// one (so silent mode doesn't swallow the morning), and they carry their
  /// own two words of reply.
  static const _alarmActions = [
    AndroidNotificationAction(
      'snooze',
      'Snooze',
      cancelNotification: true,
    ),
    AndroidNotificationAction(
      'stop',
      'Stop',
      cancelNotification: true,
    ),
  ];
  static const _alarmChannel = AndroidNotificationDetails(
    'alarms',
    'Alarms',
    channelDescription: 'Alarms set on the Alarms page',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    fullScreenIntent: true,
    autoCancel: false,
    playSound: true,
    enableVibration: true,
    actions: _alarmActions,
  );
  static const _alarmChannelQuiet = AndroidNotificationDetails(
    'alarms',
    'Alarms',
    channelDescription: 'Alarms set on the Alarms page',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    fullScreenIntent: true,
    autoCancel: false,
    playSound: true,
    enableVibration: false,
    actions: _alarmActions,
  );

  /// iOS needs the two buttons declared up front, by category id.
  static final _alarmCategory = DarwinNotificationCategory(
    'alarm',
    actions: [
      DarwinNotificationAction.plain('snooze', 'Snooze'),
      DarwinNotificationAction.plain('stop', 'Stop'),
    ],
    options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
  );

  /// Idempotent: safe to call at every launch.
  static Future<bool> _init() async {
    if (_ready) return true;
    if (_unavailable) return false;
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // UTC fallback: the nudge drifts, the app does not.
      }
      await _plugin.initialize(
        InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            notificationCategories: [_alarmCategory],
          ),
        ),
        onDidReceiveNotificationResponse: _onResponse,
        onDidReceiveBackgroundNotificationResponse: alarmResponseInBackground,
      );
      _ready = true;
    } catch (e) {
      _unavailable = true;
      debugPrint('reminders unavailable: $e');
    }
    return _ready;
  }

  /// Ask the platform's permission. True when notifications may be shown.
  static Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
    } catch (e) {
      debugPrint('permission ask failed: $e');
    }
    return false;
  }

  /// Android gates alarms that must land at the chosen minute behind a
  /// separate user decision. Other platforms already schedule precisely.
  static Future<bool> requestPreciseAlarmPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true;
      if (await android.canScheduleExactNotifications() ?? false) return true;
      return await android.requestExactAlarmsPermission() ?? false;
    } catch (e) {
      debugPrint('precise reminder permission failed: $e');
      return false;
    }
  }

  static const _details = NotificationDetails(
    android: _channel,
    iOS: DarwinNotificationDetails(),
  );

  /// One-shot at a local wall-clock instant; silently skipped if [at] has
  /// already passed. Same id replaces, so callers stay idempotent.
  static Future<void> _once(
    int id,
    String title,
    String body,
    DateTime at, {
    NotificationDetails details = _details,
    AndroidScheduleMode androidMode = AndroidScheduleMode.inexactAllowWhileIdle,
    String? payload,
  }) async {
    if (!await _init()) return;
    try {
      final when = tz.TZDateTime(
        tz.local,
        at.year,
        at.month,
        at.day,
        at.hour,
        at.minute,
      );
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: androidMode,
          payload: payload,
        );
      } catch (_) {
        if (androidMode == AndroidScheduleMode.inexactAllowWhileIdle) rethrow;
        // Permission can be revoked after the reminder was written. Losing
        // the alert entirely is worse than allowing Android a little drift.
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }
    } catch (e) {
      debugPrint('reminder $id not scheduled: $e');
    }
  }

  // ————— alarms —————

  /// Ids 3000–3007 belong to alarm 0, 3008–3015 to alarm 1, and so on: one
  /// slot for the one-shot form and seven for the weekdays a repeating alarm
  /// can own. Snoozes live in their own range so a snooze cancelled by the
  /// morning's real ring never takes the real ring with it.
  static const _alarmBase = 3000;
  static const _alarmStride = 8;
  static const _snoozeBase = 500000;

  static int _alarmId(int alarmId, int weekday) =>
      _alarmBase + alarmId * _alarmStride + weekday;

  /// What the notification carries so a snooze can be honoured with the app
  /// closed and the database untouched: `alarm|id|snoozeMinutes|label`.
  static String alarmPayload(int id, int snoozeMinutes, String label) =>
      'alarm|$id|$snoozeMinutes|${label.replaceAll('|', ' ')}';

  /// Lays down one alarm's whole schedule, replacing whatever it had.
  ///
  /// A repeating alarm becomes one weekly notification per chosen day, which
  /// is the only repeat Android and iOS both keep across reboots without the
  /// app ever running again. A one-shot becomes a single exact schedule.
  static Future<void> scheduleAlarm({
    required int id,
    required String label,
    required int minuteOfDay,
    required int days,
    required bool enabled,
    required int snoozeMinutes,
    required bool vibrate,
    required DateTime from,
  }) async {
    await cancelAlarm(id);
    if (!enabled) return;
    if (!await _init()) return;

    final title = label.trim().isEmpty ? 'Alarm' : label.trim();
    final body = _clock(minuteOfDay);
    final payload = alarmPayload(id, snoozeMinutes, title);
    final details = NotificationDetails(
      android: vibrate ? _alarmChannel : _alarmChannelQuiet,
      iOS: const DarwinNotificationDetails(
        categoryIdentifier: 'alarm',
        interruptionLevel: InterruptionLevel.timeSensitive,
        presentSound: true,
      ),
    );

    if (days == 0) {
      final today = DateTime(from.year, from.month, from.day);
      var at = today.add(Duration(minutes: minuteOfDay));
      if (!at.isAfter(from)) at = at.add(const Duration(days: 1));
      await _once(
        _alarmId(id, 0),
        title,
        body,
        at,
        details: details,
        androidMode: AndroidScheduleMode.alarmClock,
        payload: payload,
      );
      return;
    }

    for (var weekday = 1; weekday <= 7; weekday++) {
      if (days & (1 << (weekday - 1)) == 0) continue;
      final at = _nextWeekday(from, weekday, minuteOfDay);
      await _weekly(
        _alarmId(id, weekday),
        title,
        body,
        at,
        details: details,
        payload: payload,
      );
    }
  }

  /// Every slot this alarm could own, whatever shape it used to have.
  static Future<void> cancelAlarm(int id) async {
    if (!await _init()) return;
    try {
      for (var slot = 0; slot < _alarmStride; slot++) {
        await _plugin.cancel(_alarmBase + id * _alarmStride + slot);
      }
      await _plugin.cancel(_snoozeBase + id);
    } catch (e) {
      debugPrint('alarm $id not cancelled: $e');
    }
  }

  /// The same alarm again, a few minutes later. Scheduled from the payload
  /// alone so it works in the background isolate, where there is no app,
  /// no database and no Flutter engine to ask.
  static Future<void> snooze(String payload) async {
    final parts = payload.split('|');
    if (parts.length < 4 || parts.first != 'alarm') return;
    final id = int.tryParse(parts[1]);
    final minutes = int.tryParse(parts[2]);
    if (id == null || minutes == null || minutes <= 0) return;
    final label = parts.sublist(3).join('|');
    if (!await _init()) return;
    await _once(
      _snoozeBase + id,
      label.isEmpty ? 'Alarm' : label,
      'snoozed $minutes ${minutes == 1 ? 'minute' : 'minutes'}',
      DateTime.now().add(Duration(minutes: minutes)),
      details: NotificationDetails(
        android: _alarmChannel,
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: 'alarm',
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentSound: true,
        ),
      ),
      androidMode: AndroidScheduleMode.alarmClock,
      payload: payload,
    );
  }

  /// Weekly at a wall-clock time — the plugin matches on weekday + time, so
  /// one schedule survives reboots and keeps ringing every week.
  static Future<void> _weekly(
    int id,
    String title,
    String body,
    DateTime first, {
    required NotificationDetails details,
    String? payload,
  }) async {
    if (!await _init()) return;
    try {
      final when = tz.TZDateTime(
        tz.local,
        first.year,
        first.month,
        first.day,
        first.hour,
        first.minute,
      );
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('weekly alarm $id not scheduled: $e');
    }
  }

  static DateTime _nextWeekday(DateTime from, int weekday, int minuteOfDay) {
    final today = DateTime(from.year, from.month, from.day);
    for (var i = 0; i < 8; i++) {
      final day = today.add(Duration(days: i));
      if (day.weekday != weekday) continue;
      final at = day.add(Duration(minutes: minuteOfDay));
      if (at.isAfter(from)) return at;
    }
    return today.add(Duration(days: 7, minutes: minuteOfDay));
  }

  static String _clock(int minuteOfDay) =>
      '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
      '${(minuteOfDay % 60).toString().padLeft(2, '0')}';

  /// A tap or a button press on any notification, app running.
  static void _onResponse(NotificationResponse response) {
    if (response.actionId == 'snooze' && response.payload != null) {
      unawaited(snooze(response.payload!));
    }
  }

  /// Tonight's voiced nudge: it knows what the day wrote. One-shot — if the
  /// hour already passed (or the day is sealed) the caller cancels instead.
  static Future<void> scheduleTonight(
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    final now = DateTime.now();
    await _once(
      _idTonight,
      title,
      body,
      DateTime(now.year, now.month, now.day, hour, minute),
    );
  }

  static Future<void> cancelTonight() async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(_idTonight);
      // A seal must also silence whichever fallback was assigned to today.
      // The next scheduleStanding call rebuilds tomorrow onward.
      await _plugin.cancel(_idStanding);
      for (var i = 0; i < _standingDays; i++) {
        await _plugin.cancel(_standingBase + i);
      }
    } catch (_) {}
  }

  /// One-shot fallbacks for the next fortnight. They start to-morrow so they
  /// never double tonight's evidence-aware nudge. One notification per day
  /// lets the wording rotate, and lets sealing a day cancel that day's alert;
  /// a repeating platform alarm cannot do either reliably.
  static Future<void> scheduleStanding(
    int hour,
    int minute,
    List<(String title, String body)> copies,
  ) async {
    if (!await _init()) return;
    try {
      // Remove the old repeating alarm from installations upgrading from the
      // first implementation, then replace the whole rolling horizon.
      await _plugin.cancel(_idStanding);
      for (var i = 0; i < _standingDays; i++) {
        await _plugin.cancel(_standingBase + i);
      }
      final now = tz.TZDateTime.now(tz.local);
      for (var i = 0; i < copies.length && i < _standingDays; i++) {
        final day = now.add(Duration(days: i + 1));
        final at = tz.TZDateTime(
          tz.local,
          day.year,
          day.month,
          day.day,
          hour,
          minute,
        );
        final (title, body) = copies[i];
        await _plugin.zonedSchedule(
          _standingBase + i,
          title,
          body,
          at,
          _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('nudge not scheduled: $e');
    }
  }

  /// Salary morning, one-shot.
  static Future<void> scheduleSalary(String title, String body, DateTime at) =>
      _once(_idSalary, title, body, at);

  /// The focus session's finish line — it fires even if the app was killed
  /// with the clock still running, so a session never ends in silence.
  /// Cancelled on pause, give-up, or an in-app finish.
  static Future<void> scheduleFocusEnd(int minutes, DateTime at) =>
      _once(_idFocus, 'time\'s up', '$minutes minutes, yours.', at);

  static Future<void> cancelFocusEnd() async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(_idFocus);
    } catch (_) {}
  }

  /// Upcoming recurring charges, keyed by recurring row id. Stale pending
  /// ones (a charge deleted, paid early, or slid out of the horizon) are
  /// cancelled so the shelf and the phone never disagree.
  static Future<void> scheduleDues(
    Map<int, (String title, String body, DateTime at)> byId,
  ) async {
    if (!await _init()) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        final rid = p.id - _dueBase;
        if (p.id >= _dueBase && !byId.containsKey(rid)) {
          await _plugin.cancel(p.id);
        }
      }
    } catch (_) {}
    for (final MapEntry(key: id, value: (title, body, at)) in byId.entries) {
      await _once(_dueBase + id, title, body, at);
    }
  }

  /// Notes can become one-shot actions without being copied into Calendar.
  /// Rebuilding the complete set makes edits, completion and archiving
  /// idempotent: anything no longer present is cancelled first.
  static Future<void> scheduleNotes(
    Map<int, (String title, String body, DateTime at)> byId,
  ) async {
    if (!await _init()) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        final noteId = p.id - _noteBase;
        if (p.id >= _noteBase && !byId.containsKey(noteId)) {
          await _plugin.cancel(p.id);
        }
      }
    } catch (_) {}
    for (final MapEntry(key: id, value: (title, body, at)) in byId.entries) {
      await _once(
        _noteBase + id,
        title,
        body,
        at,
        details: const NotificationDetails(
          android: _noteChannel,
          iOS: DarwinNotificationDetails(),
        ),
        androidMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  static Future<void> cancelNote(int noteId) async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(_noteBase + noteId);
    } catch (_) {}
  }

  /// The book goes quiet: every money reminder down — tonight, standing,
  /// salary, dues. Calendar days ([scheduleEventDay]) are the calendar's
  /// business and stay.
  static Future<void> quiet() async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(_idTonight);
      await _plugin.cancel(_idStanding);
      await _plugin.cancel(_idSalary);
      for (var i = 0; i < _standingDays; i++) {
        await _plugin.cancel(_standingBase + i);
      }
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _dueBase && p.id < _noteBase) {
          await _plugin.cancel(p.id);
        }
      }
    } catch (_) {}
  }

  /// A calendar day's notification: 9 a.m. on the day, one-shot. Ids ride
  /// at 1000+event so they never collide with the nudge.
  static Future<void> scheduleEventDay(
    int eventId,
    String title,
    DateTime at,
  ) async {
    if (!await _init()) return;
    try {
      final when = tz.TZDateTime(
        tz.local,
        at.year,
        at.month,
        at.day,
        at.hour,
        at.minute,
      );
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        1000 + eventId,
        title,
        "to-day, says the calendar",
        when,
        const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('event reminder not scheduled: $e');
    }
  }

  static Future<void> cancelEvent(int eventId) async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(1000 + eventId);
    } catch (_) {}
  }
}

/// The snooze button, pressed while the app is not running.
///
/// Android hands this to a fresh Dart isolate with nothing in it, so it must
/// be a top-level function and it must not assume the app exists. Everything
/// it needs travels in the notification's own payload.
@pragma('vm:entry-point')
void alarmResponseInBackground(NotificationResponse response) {
  if (response.actionId != 'snooze') return;
  final payload = response.payload;
  if (payload == null) return;
  unawaited(LedgerReminders.snooze(payload));
}
