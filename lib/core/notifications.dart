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
/// ([scheduleEventDay]), 2000+ = recurring charges.
class LedgerReminders {
  LedgerReminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _idTonight = 1;
  static const _idStanding = 2;
  static const _idSalary = 3;
  static const _idFocus = 4;
  static const _standingBase = 20;
  static const _standingDays = 14;
  static const _dueBase = 2000;
  static const _channel = AndroidNotificationDetails(
    'close-the-day',
    'Evening nudge',
    channelDescription: 'One quiet reminder to close the day',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Idempotent: safe to call at every launch.
  static Future<bool> _init() async {
    if (_ready) return true;
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (_) {
        // UTC fallback: the nudge drifts, the app does not.
      }
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _ready = true;
    } catch (e) {
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
        id,
        title,
        body,
        when,
        _details,
        // Inexact keeps us clear of the exact-alarm permission; a nudge a
        // few minutes late is still a nudge.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('reminder $id not scheduled: $e');
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
        if (p.id >= _dueBase) await _plugin.cancel(p.id);
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
