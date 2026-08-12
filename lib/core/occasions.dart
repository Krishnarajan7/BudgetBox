import '../data/db.dart';
import '../data/repos/event_repo.dart';
import '../data/repos/settings_repo.dart';
import 'notifications.dart';

/// The bridge between the two places a date can be written down.
///
/// A birthday set in Settings and a "my birthday" drawn on the Calendar are
/// the same fact; keeping them in separate boxes is how the book ends up
/// contradicting itself. Both entry points call through here, so writing the
/// fact in either place writes it in both — and every calendar event earns
/// its morning notification.
class Occasions {
  Occasions(this._db)
      : _events = EventRepo(_db),
        _settings = SettingsRepo(_db);

  final LedgerDb _db;
  final EventRepo _events;
  final SettingsRepo _settings;

  /// The calendar title Settings writes, and the phrases the Calendar
  /// understands as *Krish's own* birthday. "amma's birthday" stays a plain
  /// event — guessing whose day it is would be worse than asking.
  static const ownBirthdayTitle = 'my birthday';
  static const _ownPhrases = [
    'my birthday', 'my bday', 'என் பிறந்தநாள்', 'en birthday',
  ];

  static bool looksLikeOwnBirthday(String title) {
    final t = title.trim().toLowerCase();
    return _ownPhrases.any(t.contains);
  }

  /// Settings → Calendar: make the yearly event match the stored birthday.
  /// Idempotent — one "my birthday" event, moved rather than duplicated.
  Future<void> birthdaySetInSettings(int day, int month) async {
    final anchor = DateTime(DateTime.now().year, month, day);
    final active = await (_db.select(_db.events)
          ..where((e) => e.archived.equals(false)))
        .get();
    final existing = [
      for (final e in active)
        if (e.title.trim().toLowerCase() == ownBirthdayTitle) e,
    ];
    if (existing.isEmpty) {
      await _events.create(
        title: ownBirthdayTitle,
        date: anchor,
        repeat: EventRepeat.yearly,
      );
    } else {
      await _events.update(
        existing.first.id,
        date: anchor,
        repeat: EventRepeat.yearly,
      );
    }
    await resyncNotifications();
  }

  /// Calendar → Settings: an event that reads as Krish's own birthday sets
  /// the one in Settings too (the confetti, the greeting, the sync).
  Future<void> eventWritten(String title, DateTime date) async {
    if (looksLikeOwnBirthday(title)) {
      await _settings.setBirthday(date.day, date.month);
    }
    await resyncNotifications();
  }

  /// Every active event's NEXT occurrence gets its morning notification —
  /// called after any calendar write and on every launch, so reboots and
  /// app updates can't silently drop a birthday.
  Future<void> resyncNotifications() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final events = await (_db.select(_db.events)
          ..where((e) => e.archived.equals(false)))
        .get();
    for (final e in events) {
      final on = nextOccurrence(e, today);
      if (on == null) {
        await LedgerReminders.cancelEvent(e.id);
      } else {
        await LedgerReminders.scheduleEventDay(
          e.id,
          e.title,
          DateTime(on.year, on.month, on.day, 9),
        );
      }
    }
  }

  /// The event's next date on or after [from]; null when a one-off has
  /// already passed.
  static DateTime? nextOccurrence(Event e, DateTime from) {
    final anchor = DateTime.parse(e.date);
    switch (e.repeat) {
      case EventRepeat.none:
        final d = DateTime(anchor.year, anchor.month, anchor.day);
        return d.isBefore(from) ? null : d;
      case EventRepeat.yearly:
        var d = DateTime(from.year, anchor.month, anchor.day);
        if (d.isBefore(from)) d = DateTime(from.year + 1, anchor.month, anchor.day);
        return d;
    }
  }
}
