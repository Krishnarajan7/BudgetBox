import '../api/api_client.dart';
import '../db.dart';
import '../repos/settings_repo.dart';

/// The preferences half of a sync round.
///
/// Everything else in this layer is row-shaped: a local integer id bound to a
/// uuid7, queued through the outbox, ordered by dependency. Preferences are
/// none of that — a handful of named strings with no relationships and no
/// history worth replaying. Bending the outbox around six keys would have
/// cost more than it carried, so they travel on their own.
///
/// The rule is deliberately blunt, because a single person with a phone has
/// no real conflicts to arbitrate: **the phone is the author, the server is
/// the copy.** Local values go up on every round. A value only ever comes
/// *down* onto a key this phone has never set — so reinstalling gives Krish
/// his name, his salary day, his theme, his place in the kural and his
/// evening hour back, and no round trip can quietly overwrite a preference
/// he just changed.
class SettingsSync {
  SettingsSync(LedgerDb db) : _repo = SettingsRepo(db);

  final SettingsRepo _repo;

  /// Runs after the rows have settled. Failure here is reported but never
  /// fatal: a book whose theme did not reach the server is still a book whose
  /// ledger did.
  Future<void> run(BbxClient client) async {
    final local = await _repo.syncableValues();
    final remote = await _fetch(client);

    // Restoring is decided **per key, not per book**. The old rule only took
    // the server's copy when the phone had set nothing at all, which meant a
    // book wired up from Settings — after the setup ritual had already
    // written a name and a theme — silently kept none of what the server was
    // holding. It also meant a preference added to this list later could
    // never come down to a phone that predated it.
    //
    // A key the phone has never set is not a preference being overwritten,
    // so taking it is safe; a key the phone *has* set still wins and is
    // pushed up. The phone remains the author, the server the copy.
    for (final e in remote.entries) {
      if (local.containsKey(e.key)) continue;
      await _repo.adoptRemote(e.key, e.value);
    }

    for (final e in local.entries) {
      if (remote[e.key] == e.value) continue;
      await client.put('/v1/settings/${e.key}', {'value': e.value});
    }
  }

  Future<Map<String, String>> _fetch(BbxClient client) async {
    final body = await client.get('/v1/settings');
    if (body is! Map) return const {};
    return {
      for (final e in body.entries)
        if (e.value is String) '${e.key}': e.value as String,
    };
  }
}
