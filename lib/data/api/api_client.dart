import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// The one place the app talks to the network. Everything above it deals in
/// maps and exceptions, never in status codes.
///
/// Two failure shapes, kept apart on purpose: [BbxOffline] means the write is
/// still owed and should stay in the outbox; [BbxProblem] means the server
/// understood and refused, so retrying the same body forever is pointless.
class BbxClient {
  BbxClient(this.config, {http.Client? inner})
      : _http = inner ?? http.Client();

  final BbxConfig config;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Map<String, String> get _headers => {
        'authorization': 'Bearer ${config.token}',
        'accept': 'application/json',
        'content-type': 'application/json',
      };

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) =>
      _send('GET', path, query: query);

  /// The idempotent write: same uuid7, same body, any number of times.
  Future<dynamic> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body: body);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = config.resolve(path, query);
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const BbxOffline('the server did not answer in time');
    } on SocketException catch (e) {
      throw BbxOffline(e.message);
    } on http.ClientException catch (e) {
      throw BbxOffline(e.message);
    }

    // An empty body only means "nothing to say" when the server was happy.
    // A proxy handing back a bodiless 502, or a 400 with nothing in it, must
    // never read as a successful null — that way lies a sync that believes
    // it pulled an empty world and quietly agrees with it.
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (ok && (response.statusCode == 204 || response.body.isEmpty)) {
      return null;
    }

    final decoded = _decode(response);
    if (ok) return decoded;
    // 5xx is the server having a bad day, not a bad request — worth keeping
    // in the queue, so it reads as offline to the caller.
    if (response.statusCode >= 500) {
      throw BbxOffline('server said ${response.statusCode}');
    }
    throw BbxProblem.from(response.statusCode, decoded);
  }

  dynamic _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return null;
    }
  }

  void close() => _http.close();
}

/// The network could not be reached, or the server is unwell. The write is
/// still owed; the queue keeps it.
class BbxOffline implements Exception {
  const BbxOffline(this.detail);
  final String detail;

  @override
  String toString() => 'offline: $detail';
}

/// RFC 9457 problem+json: the server understood and said no. Retrying the
/// same body will get the same answer, so the queue must not spin on it.
class BbxProblem implements Exception {
  const BbxProblem({
    required this.status,
    required this.slug,
    required this.detail,
  });

  final int status;

  /// The stable tail of `urn:budgetbox:problem:<slug>`, or `unknown`.
  final String slug;
  final String detail;

  factory BbxProblem.from(int status, dynamic body) {
    if (body is! Map) {
      return BbxProblem(
        status: status,
        slug: 'unknown',
        detail: 'the server refused with $status',
      );
    }
    final type = '${body['type'] ?? ''}';
    final slug = type.startsWith('urn:budgetbox:problem:')
        ? type.split(':').last
        : 'unknown';
    return BbxProblem(
      status: status,
      slug: slug,
      detail: '${body['detail'] ?? body['title'] ?? 'refused'}',
    );
  }

  /// The token is missing or wrong — no amount of retrying fixes it.
  bool get isAuth => status == 401 || status == 403;

  @override
  String toString() => 'problem($status/$slug): $detail';
}
