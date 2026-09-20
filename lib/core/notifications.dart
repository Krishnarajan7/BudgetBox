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
/// 3 = salary morning, 4 = the focus session's finish line, 5 = rain coming,
/// 20–33 = the next
/// fourteen standing evening nudges, 1000+ = calendar days
/// ([scheduleEventDay]), 2000+ = recurring charges, 1000000+ = note reminders.
class LedgerReminders {
  LedgerReminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Where every reminder is written down as it is laid, replaced, or
  /// cancelled — the notification ledger. Null (tests, the background
  /// isolate) means nothing is recorded, and nothing else changes.
  static ReminderLog? log;

  /// Which book a notification id belongs to, from the id ledger above.
  /// The payload settles the one overlap: a snoozed alarm and a
  /// calendar eve share a lane.
  static String moduleFor(int id, {String? payload}) {
    if (payload != null && payload.startsWith('alarm|')) return 'alarm';
    if (id == _idFocus) return 'focus';
    if (id == _idRain) return 'sky';
    if (id == _idFelt || (id >= _feltBase && id < _feltBase + _feltDays)) {
      return 'felt';
    }
    if ((id >= _mealBase && id < _mealBase + _mealSlots) ||
        (id >= _mealStandingBase &&
            id < _mealStandingBase + _mealDays * _mealSlots)) {
      return 'diet';
    }
    if (id >= _noteBase) return 'notes';
    if (id >= _eveBase) return 'calendar';
    if (id >= _retainerBase && id < _retainerBase + _retainerSpan) {
      return 'work';
    }
    if (id >= _alarmBase && id < _retainerBase) return 'alarm';
    if (id >= _dueBase) return 'money';
    if (id >= 1000) return 'calendar';
    return 'money';
  }

  /// The plugin call and the ledger entry, together. Every schedule in
  /// this file goes through here so the ledger can never miss one.
  static Future<void> _schedule(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details, {
    required AndroidScheduleMode androidScheduleMode,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      androidScheduleMode: androidScheduleMode,
      matchDateTimeComponents: matchDateTimeComponents,
      payload: payload,
    );
    final sink = log;
    if (sink == null) return;
    try {
      await sink.scheduled(
        id: id,
        module: moduleFor(id, payload: payload),
        title: title,
        body: body,
        at: DateTime(when.year, when.month, when.day, when.hour, when.minute),
        repeat: matchDateTimeComponents == DateTimeComponents.dayOfWeekAndTime
            ? 'weekly'
            : null,
        payload: payload,
      );
    } catch (e) {
      debugPrint('notice $id not recorded: $e');
    }
  }

  static Future<void> _cancel(int id) async {
    await _plugin.cancel(id);
    final sink = log;
    if (sink == null) return;
    try {
      await sink.cancelled(id);
    } catch (e) {
      debugPrint('notice $id not struck: $e');
    }
  }

  static bool _ready = false;
  static bool _unavailable = false;

  static const _idTonight = 1;
  static const _idStanding = 2;
  static const _idSalary = 3;
  static const _idFocus = 4;

  /// The sky's one voice. A single id, because there is only ever one piece
  /// of weather news worth holding: the next rain. Re-scheduling replaces it.
  static const _idRain = 5;
  static const _standingBase = 20;
  static const _standingDays = 14;

  /// The felt field's own voice: to-day's one-shot, then a rolling fortnight
  /// of them. One per day rather than a repeating platform alarm, for the
  /// same reason the evening nudge works this way — a repeating alarm cannot
  /// be told to skip the days the word was already written.
  static const _idFelt = 6;
  static const _feltBase = 40;
  static const _feltDays = 14;

  /// The diet book's voice: one id per sitting for to-day (60 breakfast,
  /// 61 lunch, 62 dinner), each re-said whenever the ledger or the plate
  /// changes, and a rolling fortnight of stand-ins behind them (100 + day×3
  /// + sitting) for the days the app is never opened.
  static const _mealBase = 60;
  static const _mealStandingBase = 100;
  static const _mealDays = 14;
  static const _mealSlots = 3;

  /// The work book: one morning line per retainer that falls due unpaid,
  /// 4000 + the project's row number.
  static const _retainerBase = 4000;
  static const _retainerSpan = 1000;
  static const _dueBase = 2000;
  static const _noteBase = 1000000;
  static const _channel = AndroidNotificationDetails(
    'close-the-day',
    'Evening nudge',
    channelDescription: 'One quiet reminder to close the day',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Its own channel so it can be silenced on its own: a person who wants
  /// the evening nudge and not the sky should not have to choose.
  static const _skyChannel = AndroidNotificationDetails(
    'the-sky',
    'Rain coming',
    channelDescription: 'One heads-up before rain, on the days there is rain',
    importance: Importance.high,
    priority: Priority.high,
  );

  /// Its own channel, so the check-in can be silenced without silencing the
  /// evening nudge — they ask for different things half an hour apart.
  static const _feltChannel = AndroidNotificationDetails(
    'felt-field',
    'Mood check-in',
    channelDescription: 'One reminder to name the day, on days it went unnamed',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Its own channel: a missed lunch and an unclosed day are different
  /// asks, and a person may want one without the other.
  static const _mealChannel = AndroidNotificationDetails(
    'meals',
    'Meals',
    channelDescription: 'One question when a sitting goes unwritten',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const _mealDetails = NotificationDetails(
    android: _mealChannel,
    iOS: DarwinNotificationDetails(),
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
    AndroidNotificationAction('snooze', 'Snooze', cancelNotification: true),
    AndroidNotificationAction('stop', 'Stop', cancelNotification: true),
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
      // A tap that launched the app from cold never reaches the response
      // handler; the launch details are the only record of it.
      try {
        final launch = await _plugin.getNotificationAppLaunchDetails();
        final id = launch?.notificationResponse?.id;
        if ((launch?.didNotificationLaunchApp ?? false) && id != null) {
          await log?.opened(id);
        }
      } catch (_) {}
    } catch (e) {
      _unavailable = true;
      debugPrint('reminders unavailable: $e');
    }
    return _ready;
  }

  /// Asks the phone what became of the lines whose hour has passed. The
  /// platform never says "delivered", but it will say what is still
  /// pending and what is in the tray — enough to tell said from shown
  /// from stuck. Called when the app comes forward and when the
  /// Notifications page opens.
  static Future<void> reconcile() async {
    final sink = log;
    if (sink == null) return;
    if (!await _init()) return;
    try {
      final pending = <int>{
        for (final p in await _plugin.pendingNotificationRequests()) p.id,
      };
      final active = <int>{};
      try {
        for (final a in await _plugin.getActiveNotifications()) {
          if (a.id != null) active.add(a.id!);
        }
      } catch (_) {
        // Older platforms cannot list the tray; pending alone still tells
        // said from stuck.
      }
      await sink.reconcile(pending: pending, active: active);
    } catch (e) {
      debugPrint('notices not reconciled: $e');
    }
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

  static const _feltDetails = NotificationDetails(
    android: _feltChannel,
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
        await _schedule(
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
        await _schedule(
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

  // ————— the sky —————

  /// One heads-up, [at], that rain is coming. Replaces whatever the sky was
  /// last going to say, because a forecast that has moved makes the old
  /// warning wrong rather than additional.
  static Future<void> scheduleRain(
    String title,
    String body,
    DateTime at,
  ) async {
    await cancelRain();
    await _once(
      _idRain,
      title,
      body,
      at,
      details: const NotificationDetails(
        android: _skyChannel,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> cancelRain() async {
    if (!await _init()) return;
    try {
      await _cancel(_idRain);
    } catch (_) {}
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
        await _cancel(_alarmBase + id * _alarmStride + slot);
      }
      await _cancel(_snoozeBase + id);
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
      await _schedule(
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
    final id = response.id;
    final sink = log;
    if (id != null && sink != null) unawaited(sink.opened(id));
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
      await _cancel(_idTonight);
      // A seal must also silence whichever fallback was assigned to today.
      // The next scheduleStanding call rebuilds tomorrow onward.
      await _cancel(_idStanding);
      for (var i = 0; i < _standingDays; i++) {
        await _cancel(_standingBase + i);
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
      await _cancel(_idStanding);
      for (var i = 0; i < _standingDays; i++) {
        await _cancel(_standingBase + i);
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
        await _schedule(
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

  // ————— the felt field —————

  /// To-day's check-in, at [hour]:[minute]. Replaces itself, so calling this
  /// after every write is safe and is exactly how the reminder stays honest.
  static Future<void> scheduleFelt(
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    final now = DateTime.now();
    await _once(
      _idFelt,
      title,
      body,
      DateTime(now.year, now.month, now.day, hour, minute),
      details: _feltDetails,
    );
  }

  /// Silence to-day's check-in. Called the moment a word is written, which is
  /// the whole of "do not ask me for what I have already given".
  static Future<void> cancelFelt() async {
    if (!await _init()) return;
    try {
      await _cancel(_idFelt);
    } catch (_) {}
  }

  /// The rolling fortnight, starting to-morrow, so the reminder keeps coming
  /// on a phone that never opens the app. Each day is its own one-shot and
  /// each is replaced wholesale on the next resync — which is how a day that
  /// gets its word written can have its alert dropped while the rest stand.
  static Future<void> scheduleFeltStanding(
    String title,
    String body,
    int hour,
    int minute,
  ) async {
    if (!await _init()) return;
    try {
      for (var i = 0; i < _feltDays; i++) {
        await _cancel(_feltBase + i);
      }
      final now = tz.TZDateTime.now(tz.local);
      for (var i = 0; i < _feltDays; i++) {
        final day = now.add(Duration(days: i + 1));
        await _schedule(
          _feltBase + i,
          title,
          body,
          tz.TZDateTime(tz.local, day.year, day.month, day.day, hour, minute),
          _feltDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('felt reminder not scheduled: $e');
    }
  }

  /// Every trace of the check-in — to-day's and the whole horizon.
  static Future<void> quietFelt() async {
    if (!await _init()) return;
    try {
      await _cancel(_idFelt);
      for (var i = 0; i < _feltDays; i++) {
        await _cancel(_feltBase + i);
      }
    } catch (_) {}
  }

  // ————— the diet book —————

  /// To-day's question about one sitting ([slot] 0 breakfast, 1 lunch,
  /// 2 dinner), at [at]. Replaces itself, so re-saying it after every
  /// dish is how it stays true.
  static Future<void> scheduleMeal(
    int slot,
    String title,
    String body,
    DateTime at,
  ) => _once(_mealBase + slot, title, body, at, details: _mealDetails);

  static Future<void> cancelMeal(int slot) async {
    if (!await _init()) return;
    try {
      await _cancel(_mealBase + slot);
    } catch (_) {}
  }

  /// The fortnight of stand-ins, one per sitting per day from to-morrow:
  /// [copies] is indexed `[dayOffset - 1][slot]` and each carries its own
  /// wall-clock minute, because a weekend sitting runs later.
  static Future<void> scheduleMealsStanding(
    List<List<(String title, String body, DateTime at)?>> copies,
  ) async {
    if (!await _init()) return;
    try {
      for (var d = 0; d < _mealDays; d++) {
        for (var s = 0; s < _mealSlots; s++) {
          await _cancel(_mealStandingBase + d * _mealSlots + s);
        }
      }
      for (var d = 0; d < copies.length && d < _mealDays; d++) {
        for (var s = 0; s < _mealSlots && s < copies[d].length; s++) {
          final c = copies[d][s];
          if (c == null) continue;
          final (title, body, at) = c;
          final when = tz.TZDateTime(
            tz.local,
            at.year,
            at.month,
            at.day,
            at.hour,
            at.minute,
          );
          if (!when.isAfter(tz.TZDateTime.now(tz.local))) continue;
          await _schedule(
            _mealStandingBase + d * _mealSlots + s,
            title,
            body,
            when,
            _mealDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      debugPrint('meal nudges not scheduled: $e');
    }
  }

  static Future<void> quietMeals() async {
    if (!await _init()) return;
    try {
      for (var s = 0; s < _mealSlots; s++) {
        await _cancel(_mealBase + s);
      }
      for (var d = 0; d < _mealDays; d++) {
        for (var s = 0; s < _mealSlots; s++) {
          await _cancel(_mealStandingBase + d * _mealSlots + s);
        }
      }
    } catch (_) {}
  }

  /// A retainer's due morning, one-shot; replaced on every resync so a
  /// payment written the day before takes the line away.
  static Future<void> scheduleRetainer(
    int projectId,
    String title,
    String body,
    DateTime at,
  ) => _once(_retainerBase + (projectId % _retainerSpan), title, body, at);

  static Future<void> cancelRetainer(int projectId) async {
    if (!await _init()) return;
    try {
      await _cancel(_retainerBase + (projectId % _retainerSpan));
    } catch (_) {}
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
      await _cancel(_idFocus);
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
          await _cancel(p.id);
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
          await _cancel(p.id);
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
      await _cancel(_noteBase + noteId);
    } catch (_) {}
  }

  /// The book goes quiet: every money reminder down — tonight, standing,
  /// salary, dues. Calendar days ([scheduleEventDay]) are the calendar's
  /// business and stay.
  static Future<void> quiet() async {
    if (!await _init()) return;
    try {
      await _cancel(_idTonight);
      await _cancel(_idStanding);
      await _cancel(_idSalary);
      for (var i = 0; i < _standingDays; i++) {
        await _cancel(_standingBase + i);
      }
      // The felt check-in is part of the same voice: no hour set, no talking.
      await _cancel(_idFelt);
      for (var i = 0; i < _feltDays; i++) {
        await _cancel(_feltBase + i);
      }
      // So is the diet book's.
      for (var s = 0; s < _mealSlots; s++) {
        await _cancel(_mealBase + s);
      }
      for (var d = 0; d < _mealDays; d++) {
        for (var s = 0; s < _mealSlots; s++) {
          await _cancel(_mealStandingBase + d * _mealSlots + s);
        }
      }
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        // Dues stop where the alarms begin: an alarm is not a money
        // reminder and must ring whether the book is speaking or not.
        if ((p.id >= _dueBase && p.id < _alarmBase) ||
            (p.id >= _retainerBase && p.id < _retainerBase + _retainerSpan)) {
          await _cancel(p.id);
        }
      }
    } catch (_) {}
  }

  /// A calendar day's notification, one-shot. Ids ride at 1000+event so
  /// they never collide with the nudge. The default hour is 9 a.m.; an
  /// asked-for reminder passes its own time and its own words.
  static Future<void> scheduleEventDay(
    int eventId,
    String title,
    DateTime at, {
    String body = "to-day, says the calendar",
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
      await _schedule(
        1000 + eventId,
        title,
        body,
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

  /// The evening-before heads-up an asked-for reminder earns: its own id
  /// lane at 500000+event, so the day-of line and this one never fight.
  static const _eveBase = 500000;

  static Future<void> scheduleEventEve(
    int eventId,
    String title,
    String body,
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
      await _schedule(
        _eveBase + eventId,
        title,
        body,
        when,
        const NotificationDetails(
          android: _channel,
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('event eve reminder not scheduled: $e');
    }
  }

  static Future<void> cancelEventEve(int eventId) async {
    if (!await _init()) return;
    try {
      await _cancel(_eveBase + eventId);
    } catch (_) {}
  }

  static Future<void> cancelEvent(int eventId) async {
    if (!await _init()) return;
    try {
      await _cancel(1000 + eventId);
      await _cancel(_eveBase + eventId);
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

/// The notification ledger's side of the bargain — implemented by the
/// data layer, which this file must not import.
abstract interface class ReminderLog {
  Future<void> scheduled({
    required int id,
    required String module,
    required String title,
    required String body,
    required DateTime at,
    String? repeat,
    String? payload,
  });

  /// Struck before its hour: the row goes. A line already said stays.
  Future<void> cancelled(int id);

  /// He tapped it.
  Future<void> opened(int id);

  /// What the phone still holds ([pending]) and what sits in the tray
  /// ([active]) — the ledger settles each past line's fate from these.
  Future<void> reconcile({required Set<int> pending, required Set<int> active});
}
