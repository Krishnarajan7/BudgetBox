import '../api_client.dart';
import 'wire.dart';

/// A cheap cache-refresh affordance, not a sync protocol: which rows changed
/// since an instant, per resource. It says *what* moved, never *how* — the
/// caller still fetches the rows it cares about.
class ChangesApi {
  const ChangesApi(this._c);

  final BbxClient _c;

  /// [since] is normally the [ChangesOut.now] of the previous poll, which is
  /// the server's clock rather than the phone's — the only one that can't
  /// drift a window of edits into invisibility.
  Future<ChangesOut> since(DateTime since) async => ChangesOut.fromJson(
        wireObject(await _c.get('/v1/changes', {'since': wireInstant(since)})),
      );
}

class ChangesOut {
  const ChangesOut({required this.now, required this.changed});

  /// The server's clock at the moment of the answer — pass it back as the next
  /// [ChangesApi.since] so nothing falls between two polls.
  final DateTime now;

  /// Resource name to the ids that moved: 'txns', 'accounts', 'day_seals',
  /// 'settings'… A resource with nothing to report is absent, not empty, so
  /// iterate the keys rather than asking for one by name.
  final Map<String, List<String>> changed;

  factory ChangesOut.fromJson(Map<String, dynamic> json) => ChangesOut(
        now: json.instant('now'),
        changed: json.stringLists('changed'),
      );
}
