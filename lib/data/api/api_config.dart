/// Where the book's other half lives, and the one token that opens it.
///
/// Supplied at launch so nothing secret is compiled into the repo:
///
/// ```sh
/// flutter run \
///   --dart-define=BBX_URL=http://localhost:8000 \
///   --dart-define=BBX_TOKEN=bbx_xxx
/// ```
///
/// With no URL given the app stays exactly as it was — a local book that
/// syncs with nothing. That is the honest default: a phone with no server
/// configured should not pretend to be offline, it simply isn't wired yet.
class BbxConfig {
  const BbxConfig({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  static const _url = String.fromEnvironment('BBX_URL');
  static const _token = String.fromEnvironment('BBX_TOKEN');

  /// What the app was launched with.
  factory BbxConfig.fromEnvironment() =>
      const BbxConfig(baseUrl: _url, token: _token);

  /// A book that syncs with nothing.
  static const none = BbxConfig(baseUrl: '', token: '');

  /// True once there is somewhere to sync to and something to sign with.
  bool get wired => baseUrl.isNotEmpty && token.isNotEmpty;

  /// The host on its own, for a settings line that should never print a
  /// token: `https://bbx.example.in/` reads as `bbx.example.in`.
  String get host {
    final uri = Uri.tryParse(baseUrl);
    final h = uri?.host ?? '';
    if (h.isEmpty) return baseUrl;
    return uri!.hasPort ? '$h:${uri.port}' : h;
  }

  @override
  bool operator ==(Object other) =>
      other is BbxConfig &&
      other.baseUrl == baseUrl &&
      other.token == token;

  @override
  int get hashCode => Object.hash(baseUrl, token);

  /// `http://host:8000/` + `v1/txns` without doubling or dropping the slash.
  Uri resolve(String path, [Map<String, dynamic>? query]) {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final tail = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$root$tail');
    if (query == null || query.isEmpty) return uri;
    return uri.replace(
      queryParameters: {
        for (final e in query.entries)
          if (e.value != null) e.key: '${e.value}',
      },
    );
  }
}
