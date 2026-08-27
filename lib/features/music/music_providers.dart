import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/endpoints/endpoints.dart';
import '../../data/providers.dart';
import '../../data/repos/settings_repo.dart';
import 'room.dart';

/// The music book lives on the server (Spotify's API forgets everything past
/// 50 plays; the backend is what remembers). The phone holds no music tables
/// — every provider here is a straight question over the wire.

/// What the room finds when the door opens.
sealed class MusicGate {
  const MusicGate();
}

/// No server configured — the book has nowhere to live.
class MusicUnwired extends MusicGate {
  const MusicUnwired();
}

/// The server didn't answer.
class MusicAway extends MusicGate {
  const MusicAway(this.detail);

  final String detail;
}

/// Reachable, but Spotify was never connected and nothing has been imported:
/// the room exists and has heard nothing.
class MusicSilent extends MusicGate {
  const MusicSilent();
}

/// The room is open. [overview] carries the header; when [connected] is
/// false the plays came from an import and a connect nudge belongs on the
/// page — the record stands either way.
class MusicOpen extends MusicGate {
  const MusicOpen(this.overview);

  final MusicOverview overview;
}

Future<T> _ask<T>(
  SettingsRepo settings,
  Future<T> Function(MusicApi api) question,
) async {
  final config = await settings.serverConfig();
  if (!config.wired) throw const BbxOffline('not wired');
  final client = BbxClient(config);
  try {
    return await question(MusicApi(client));
  } finally {
    client.close();
  }
}

final musicGateProvider = FutureProvider.autoDispose<MusicGate>((ref) async {
  final settings = ref.read(settingsRepoProvider);
  final config = await settings.serverConfig();
  if (!config.wired) return const MusicUnwired();
  final MusicOverview overview;
  try {
    overview = await _ask(settings, (api) => api.overview());
  } on BbxOffline catch (e) {
    return MusicAway(e.detail);
  } on BbxProblem catch (e) {
    return MusicAway(e.detail);
  }
  // The shelf's spine line — written here so the shelf can speak without a
  // network call of its own.
  final line = overview.totalPlays == 0
      ? (overview.connected ? 'listening for the first play' : 'silent')
      : '${hoursFigure(overview.totalMs)} hrs · '
            '${groupCount(overview.totalPlays)} plays';
  await settings.setMusicLine(line);
  if (!overview.connected && overview.totalPlays == 0) {
    return const MusicSilent();
  }
  return MusicOpen(overview);
});

/// Both top lists for one range, asked together. [range] is 'month', 'year'
/// or 'all'.
final musicTopProvider = FutureProvider.autoDispose
    .family<({List<MusicEntry> tracks, List<MusicEntry> artists}), String>((
      ref,
      range,
    ) async {
      final results = await _ask(
        ref.read(settingsRepoProvider),
        (api) => Future.wait([
          api.top(kind: 'tracks', range: range, limit: 10),
          api.top(kind: 'artists', range: range, limit: 7),
        ]),
      );
      return (tracks: results[0], artists: results[1]);
    });

final musicMonthsProvider = FutureProvider.autoDispose<List<MusicMonth>>(
  (ref) => _ask(ref.read(settingsRepoProvider), (api) => api.months()),
);

final musicMonthDetailProvider = FutureProvider.autoDispose
    .family<MusicMonthDetail, String>(
      (ref, month) =>
          _ask(ref.read(settingsRepoProvider), (api) => api.monthDetail(month)),
    );

/// The live tile. Failure is silence, never an error — garnish doesn't get
/// to break the page.
final musicNowProvider = FutureProvider.autoDispose<MusicNow>((ref) async {
  try {
    return await _ask(ref.read(settingsRepoProvider), (api) => api.now());
  } on BbxOffline {
    return const MusicNow(
      playing: false,
      track: null,
      artist: null,
      imageUrl: null,
      progressMs: null,
      durationMs: null,
    );
  } on BbxProblem {
    return const MusicNow(
      playing: false,
      track: null,
      artist: null,
      imageUrl: null,
      progressMs: null,
      durationMs: null,
    );
  }
});

/// Begins the Spotify handshake and hands back the consent URL — opened in
/// a real browser, once, ever. Takes the repo, not a ref, so the page can
/// call it from a tap handler.
Future<String> musicConnectUrl(SettingsRepo settings) =>
    _ask(settings, (api) => api.connectUrl());
