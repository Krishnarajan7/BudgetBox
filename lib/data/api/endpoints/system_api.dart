import '../api_client.dart';
import 'wire.dart';

/// Is anyone there, and do they know us?
class SystemApi {
  const SystemApi(this._c);

  final BbxClient _c;

  /// Connectivity and auth in one probe. Reachable-but-unauthorised throws
  /// [BbxProblem] with `isAuth` set rather than returning false — a wrong
  /// token is not the same condition as a tunnel, and the sync engine treats
  /// them differently.
  Future<bool> ping() async {
    final body = wireObject(await _c.get('/v1/ping'));
    return body['ok'] == true;
  }
}
