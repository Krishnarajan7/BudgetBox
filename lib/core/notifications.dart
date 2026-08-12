import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The book's one notification: an evening nudge to close the day.
///
/// One id, one channel, once a day at a chosen hour — never a nag ladder,
/// never marketing, never a badge left burning. Everything here is wrapped
/// so that a platform without the plugin (widget tests, desktop) degrades to
/// silence instead of an exception: a reminder is not worth a crash.
class LedgerReminders {
  LedgerReminders._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _id = 1;
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
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ??
            false;
      }
    } catch (e) {
      debugPrint('permission ask failed: $e');
    }
    return false;
  }

  /// Schedule (or move) the daily nudge. Same id every time, so this is
  /// naturally idempotent — call it on toggle and again on every launch.
  static Future<void> scheduleDaily(int hour, int minute) async {
    if (!await _init()) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, hour, minute);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        _id,
        'the page is still open',
        'a minute to close the day, if it\'s done being written',
        at,
        const NotificationDetails(
            android: _channel, iOS: DarwinNotificationDetails()),
        // Inexact keeps us clear of the exact-alarm permission; a nudge a
        // few minutes late is still a nudge.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('nudge not scheduled: $e');
    }
  }

  /// A calendar day's notification: 9 a.m. on the day, one-shot. Ids ride
  /// at 1000+event so they never collide with the nudge.
  static Future<void> scheduleEventDay(
      int eventId, String title, DateTime at) async {
    if (!await _init()) return;
    try {
      final when = tz.TZDateTime(
          tz.local, at.year, at.month, at.day, at.hour, at.minute);
      if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        1000 + eventId,
        title,
        "to-day, says the calendar",
        when,
        const NotificationDetails(
            android: _channel, iOS: DarwinNotificationDetails()),
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

  static Future<void> cancel() async {
    if (!await _init()) return;
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
  }
}
