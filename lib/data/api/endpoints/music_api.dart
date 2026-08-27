import '../api_client.dart';
import 'wire.dart';

/// The record of listening, kept on the server because Spotify won't keep it:
/// its API shows the last 50 plays and nothing older. The backend polls that
/// window every half hour and holds the GDPR backfill; the phone only asks
/// questions.
class MusicApi {
  const MusicApi(this._c);

  final BbxClient _c;

  Future<MusicOverview> overview() async =>
      MusicOverview.fromJson(wireObject(await _c.get('/v1/music/overview')));

  /// [kind] is 'tracks' or 'artists'; [range] is 'month', 'year' or 'all'.
  Future<List<MusicEntry>> top({
    required String kind,
    required String range,
    int limit = 10,
  }) async => wireList(
    await _c.get('/v1/music/top', {
      'kind': kind,
      'range': range,
      'limit': '$limit',
    }),
    MusicEntry.fromJson,
  );

  Future<List<MusicMonth>> months() async =>
      wireList(await _c.get('/v1/music/months'), MusicMonth.fromJson);

  /// [month] is a month key, 'yyyy-MM'.
  Future<MusicMonthDetail> monthDetail(String month) async =>
      MusicMonthDetail.fromJson(
        wireObject(await _c.get('/v1/music/months/$month')),
      );

  Future<MusicNow> now() async =>
      MusicNow.fromJson(wireObject(await _c.get('/v1/music/now')));

  /// Begins the Spotify handshake; the returned URL is opened in a browser
  /// once, ever.
  Future<String> connectUrl() async =>
      wireObject(await _c.post('/v1/music/spotify/connect')).text('url');
}

class MusicOverview {
  const MusicOverview({
    required this.connected,
    required this.since,
    required this.recordingSince,
    required this.totalPlays,
    required this.totalMs,
    required this.distinctTracks,
    required this.distinctArtists,
    required this.thisMonthPlays,
    required this.thisMonthMs,
  });

  final bool connected;

  /// The very first play on record; null until anything has been heard.
  final DateTime? since;

  /// When the half-hour poll started keeping the book — the boundary between
  /// "recorded live" and "recovered from the export".
  final DateTime? recordingSince;
  final int totalPlays;
  final int totalMs;
  final int distinctTracks;
  final int distinctArtists;
  final int thisMonthPlays;
  final int thisMonthMs;

  factory MusicOverview.fromJson(Map<String, dynamic> json) => MusicOverview(
    connected: json.flag('connected'),
    since: json.instantOrNull('since'),
    recordingSince: json.instantOrNull('recording_since'),
    totalPlays: json.whole('total_plays'),
    totalMs: json.whole('total_ms'),
    distinctTracks: json.whole('distinct_tracks'),
    distinctArtists: json.whole('distinct_artists'),
    thisMonthPlays: json.whole('this_month_plays'),
    thisMonthMs: json.whole('this_month_ms'),
  );
}

/// One line of a top list — a track or an artist, depending on what was
/// asked. [artist] is the performer on track entries and null on artist
/// entries.
class MusicEntry {
  const MusicEntry({
    required this.rank,
    required this.name,
    required this.artist,
    required this.imageUrl,
    required this.plays,
    required this.ms,
  });

  final int rank;
  final String name;
  final String? artist;
  final String? imageUrl;
  final int plays;
  final int ms;

  factory MusicEntry.fromJson(Map<String, dynamic> json) => MusicEntry(
    rank: json.whole('rank'),
    name: json.text('name'),
    artist: json.textOrNull('artist'),
    imageUrl: json.textOrNull('image_url'),
    plays: json.whole('plays'),
    ms: json.whole('ms'),
  );
}

class MusicMonthTop {
  const MusicMonthTop({
    required this.name,
    required this.artist,
    required this.imageUrl,
    required this.plays,
  });

  final String name;
  final String? artist;
  final String? imageUrl;
  final int plays;

  factory MusicMonthTop.fromJson(Map<String, dynamic> json) => MusicMonthTop(
    name: json.text('name'),
    artist: json.textOrNull('artist'),
    imageUrl: json.textOrNull('image_url'),
    plays: json.whole('plays'),
  );
}

class MusicMonth {
  const MusicMonth({
    required this.month,
    required this.plays,
    required this.ms,
    required this.topTrack,
    required this.topArtist,
  });

  /// 'yyyy-MM', IST months.
  final String month;
  final int plays;
  final int ms;
  final MusicMonthTop? topTrack;
  final MusicMonthTop? topArtist;

  factory MusicMonth.fromJson(Map<String, dynamic> json) => MusicMonth(
    month: json.text('month'),
    plays: json.whole('plays'),
    ms: json.whole('ms'),
    topTrack: json.objectOrNull('top_track', MusicMonthTop.fromJson),
    topArtist: json.objectOrNull('top_artist', MusicMonthTop.fromJson),
  );
}

class MusicMonthDetail {
  const MusicMonthDetail({
    required this.month,
    required this.plays,
    required this.ms,
    required this.tracks,
    required this.artists,
  });

  final String month;
  final int plays;
  final int ms;
  final List<MusicEntry> tracks;
  final List<MusicEntry> artists;

  factory MusicMonthDetail.fromJson(Map<String, dynamic> json) =>
      MusicMonthDetail(
        month: json.text('month'),
        plays: json.whole('plays'),
        ms: json.whole('ms'),
        tracks: json.objects('tracks', MusicEntry.fromJson),
        artists: json.objects('artists', MusicEntry.fromJson),
      );
}

/// The live tile. Every server-side failure shape arrives as "nothing
/// playing" — garnish never gets an error state.
class MusicNow {
  const MusicNow({
    required this.playing,
    required this.track,
    required this.artist,
    required this.imageUrl,
    required this.progressMs,
    required this.durationMs,
  });

  final bool playing;
  final String? track;
  final String? artist;
  final String? imageUrl;
  final int? progressMs;
  final int? durationMs;

  factory MusicNow.fromJson(Map<String, dynamic> json) => MusicNow(
    playing: json.flag('playing'),
    track: json.textOrNull('track'),
    artist: json.textOrNull('artist'),
    imageUrl: json.textOrNull('image_url'),
    progressMs: json.wholeOrNull('progress_ms'),
    durationMs: json.wholeOrNull('duration_ms'),
  );
}
