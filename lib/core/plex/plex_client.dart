import 'dart:convert';

import 'package:http/http.dart' as http;

import 'plex_identity.dart';
import 'plex_models.dart';
import 'plex_server.dart';
import 'transcode.dart';

/// One page of results, with the total the server reports.
///
/// [totalSize] is what makes a real progress indicator possible — without it a
/// first sync of tens of thousands of tracks can only show a spinner.
class PlexPage<T> {
  const PlexPage({required this.items, required this.totalSize});

  final List<T> items;
  final int totalSize;
}

/// Plex Media Server API client.
///
/// Everything here talks to a specific server via [PlexServer.baseUrl]. Account
/// level calls (auth, discovery) live in `plex_auth.dart` / `plex_server.dart`.
class PlexClient {
  PlexClient({
    required PlexServer server,
    required PlexIdentity identity,
    http.Client? httpClient,
  }) : _server = server,
       _identity = identity,
       _http = httpClient ?? http.Client();

  final PlexServer _server;
  final PlexIdentity _identity;
  final http.Client _http;

  PlexServer get server => _server;

  /// Releases the underlying HTTP connections.
  ///
  /// Providers that construct a client must call this on dispose — otherwise
  /// every reconnection leaks a connection pool.
  void close() => _http.close();

  /// Plex metadata type numbers. Used as `?type=` on section listings.
  static const typeArtist = 8;
  static const typeAlbum = 9;
  static const typeTrack = 10;

  /// All library sections. Cheap, and the `updatedAt`/`scannedAt` fields drive
  /// the change-detection tier of the sync design.
  Future<List<PlexSection>> sections() async {
    final container = await _getContainer('/library/sections');
    return _listOf(container, 'Directory').map(PlexSection.fromJson).toList();
  }

  /// The music section, or null if the server has none.
  ///
  /// If there are several, the first wins — v1 assumes a single music library.
  Future<PlexSection?> musicSection() async {
    final all = await sections();
    for (final section in all) {
      if (section.isMusic) return section;
    }
    return null;
  }

  /// Asks the server directly, for things the cache has not reached.
  ///
  /// The cache is additive and never authoritative about absence (invariant
  /// 1), and search is where that rule earns its keep: an album added five
  /// minutes ago must be findable even though no sync has stored it. Local
  /// results render first and this merges in behind them.
  ///
  /// Returns empty rather than throwing. A search that works offline for the
  /// library you have is worth more than one that shows an error because
  /// plex.tv was briefly unreachable.
  Future<(List<PlexAlbum>, List<PlexTrack>)> searchHubs(String query) async {
    try {
      final container = await _getContainer(
        '/hubs/search',
        query: {'query': query, 'limit': '20'},
      );

      final albums = <PlexAlbum>[];
      final tracks = <PlexTrack>[];
      for (final hub in _listOf(container, 'Hub')) {
        // Plex returns every media type in one response; the type says which
        // list a hub's items belong in. 9 is album, 10 is track.
        final type = hub['type'];
        final items = _listOf(hub, 'Metadata');
        if (type == 'album') {
          albums.addAll(items.map(PlexAlbum.fromJson));
        } else if (type == 'track') {
          tracks.addAll(items.map(PlexTrack.fromJson));
        }
      }
      return (albums, tracks);
    } on Object {
      return (const <PlexAlbum>[], const <PlexTrack>[]);
    }
  }

  /// Albums in a section, newest first.
  ///
  /// Paginated via Plex's container headers rather than query parameters, which
  /// is what the server actually honours.
  Future<List<PlexAlbum>> albums(
    String sectionKey, {
    int start = 0,
    int size = 100,
  }) async {
    final container = await _getContainer(
      '/library/sections/$sectionKey/all',
      query: {'type': '$typeAlbum', 'sort': 'addedAt:desc'},
      extraHeaders: {
        'X-Plex-Container-Start': '$start',
        'X-Plex-Container-Size': '$size',
      },
    );
    return _listOf(container, 'Metadata').map(PlexAlbum.fromJson).toList();
  }

  /// The delta filter this server actually applies.
  ///
  /// **Measured, not assumed.** `updatedAt>=` was sent from #18 until #51 and
  /// did nothing at all: Plex accepts a filter parameter it does not recognise,
  /// answers 200, and returns the whole section, so every launch refetched
  /// 11,492 tracks while looking perfectly healthy. `DeltaFilterProbe` settled
  /// it against the real server: `>=` and `>>=` are both ignored, `>` and `>>`
  /// both work. Re-run the probe (Sync status → Delta filter probe) after a
  /// server upgrade rather than trusting this constant.
  ///
  /// **It is strict, hence the `- 1` below.** The stored cursor is the newest
  /// `updatedAt` already held, so asking for strictly-newer would skip a row
  /// sharing that exact second which we have not seen yet. A bulk edit stamps
  /// many rows with one timestamp, so that is a real case rather than a
  /// theoretical one, and the cost of the alternative is one already-cached row
  /// coming back per pass, which upserts to itself.
  static const deltaFilter = 'updatedAt>';

  /// One page of a section's contents, for bulk sync.
  ///
  /// Sorted by `addedAt` ascending and paginated by container headers. Ordering
  /// matters: a stable sort means an interrupted sync can resume from an offset
  /// without skipping or repeating rows, which a default (unspecified) order
  /// would not guarantee.
  ///
  /// [minUpdatedAt] restricts the page to rows Plex changed at or after that
  /// timestamp, which is what turns this into a delta sync rather than a full
  /// one.
  Future<PlexPage<T>> sectionPage<T>(
    String sectionKey, {
    required int type,
    required T Function(Map<String, dynamic>) parse,
    int start = 0,
    int size = 200,
    int? minUpdatedAt,
  }) async {
    final container = await _getContainer(
      '/library/sections/$sectionKey/all',
      query: {
        'type': '$type',
        'sort': 'addedAt:asc',
        if (minUpdatedAt != null && minUpdatedAt > 0)
          deltaFilter: '${minUpdatedAt - 1}',
      },
      extraHeaders: {
        'X-Plex-Container-Start': '$start',
        'X-Plex-Container-Size': '$size',
      },
    );

    return PlexPage<T>(
      items: _listOf(container, 'Metadata').map(parse).toList(),
      // totalSize appears when container headers are used; fall back to size
      // so a server that omits it still terminates the loop correctly.
      totalSize:
          _asInt(container['totalSize']) ?? _asInt(container['size']) ?? 0,
    );
  }

  /// How many rows a section holds, optionally through a filter, without
  /// fetching any of them.
  ///
  /// `X-Plex-Container-Size: 0` makes the server report `totalSize` and send no
  /// metadata, so this costs one small response whatever the library's size.
  ///
  /// [filter] is a raw Plex filter parameter name such as `updatedAt>=`,
  /// deliberately unvalidated: the whole point of [DeltaFilterProbe] is to find
  /// out which spellings the server actually acts on, and a helper that only
  /// permitted the ones already known to work could not discover a new one.
  Future<int> sectionCount(
    String sectionKey, {
    required int type,
    String? filter,
    int? filterValue,
  }) async {
    final container = await _getContainer(
      '/library/sections/$sectionKey/all',
      query: {
        'type': '$type',
        if (filter != null && filterValue != null) filter: '$filterValue',
      },
      extraHeaders: {
        'X-Plex-Container-Start': '0',
        'X-Plex-Container-Size': '0',
      },
    );
    return _asInt(container['totalSize']) ?? _asInt(container['size']) ?? 0;
  }

  /// Sets or clears an item's star rating.
  ///
  /// [rating] is Plex's 0–10 scale. Pass [PlexRating.clear] to unrate — Plex
  /// treats -1 as "remove", whereas 0 would store an explicit zero-star rating,
  /// which is a different thing and would then match rating filters.
  ///
  /// Works for tracks, albums and artists; they all share the endpoint.
  Future<void> rate(String ratingKey, int rating) async {
    final uri = Uri.parse('${_server.baseUrl}/:/rate').replace(
      queryParameters: {
        'identifier': 'com.plexapp.plugins.library',
        'key': ratingKey,
        'rating': '$rating',
      },
    );

    final response = await _http.put(
      uri,
      headers: _identity.headers(token: _server.token),
    );

    if (response.statusCode >= 400) {
      throw PlexClientException(
        'Could not save your rating (HTTP ${response.statusCode})',
      );
    }
  }

  /// Reports what we are playing, and where we are in it.
  ///
  /// This is what puts Plexify in the server's "Now Playing" list and what
  /// keeps `viewOffset` current, so a track abandoned halfway can be resumed
  /// from any client. Plex expects these every few seconds during playback and
  /// treats their absence as the session having ended.
  ///
  /// [state] is `playing`, `paused` or `stopped`.
  Future<void> reportTimeline({
    required String ratingKey,
    required String state,
    required Duration position,
    required Duration duration,
  }) async {
    final uri = Uri.parse('${_server.baseUrl}/:/timeline').replace(
      queryParameters: {
        'identifier': 'com.plexapp.plugins.library',
        'ratingKey': ratingKey,
        // Plex wants both the bare key and the full metadata path; sending only
        // one gets a 200 that quietly does nothing.
        'key': '/library/metadata/$ratingKey',
        'state': state,
        'time': '${position.inMilliseconds}',
        'duration': '${duration.inMilliseconds}',
      },
    );

    final response = await _http.get(
      uri,
      headers: _identity.headers(token: _server.token),
    );

    if (response.statusCode >= 400) {
      throw PlexClientException(
        'Timeline report rejected (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }

  /// Marks an item as played, incrementing its play count.
  ///
  /// Separate from [reportTimeline] because Plex does not derive a play from
  /// timeline events — a track can be reported to the end without ever counting
  /// as listened to.
  Future<void> scrobble(String ratingKey) async {
    final uri = Uri.parse('${_server.baseUrl}/:/scrobble').replace(
      queryParameters: {
        'identifier': 'com.plexapp.plugins.library',
        'key': ratingKey,
      },
    );

    final response = await _http.get(
      uri,
      headers: _identity.headers(token: _server.token),
    );

    if (response.statusCode >= 400) {
      throw PlexClientException(
        'Could not record the play (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }

  /// Asks Plex to rescan a section.
  ///
  /// Returns as soon as the scan is queued, not when it finishes — the results
  /// arrive later over the notification socket or on the next poll. This is the
  /// server-side half of pull-to-refresh: without it, refreshing would only
  /// re-read what Plex already knew, which is exactly the "scan, then check,
  /// then check again" dance this app exists to remove.
  Future<void> refreshSection(String sectionKey) async {
    final uri = Uri.parse(
      '${_server.baseUrl}/library/sections/$sectionKey/refresh',
    );
    final response = await _http.get(
      uri,
      headers: _identity.headers(token: _server.token),
    );

    // The body is empty on success, so this deliberately does not go through
    // _getContainer — there is no MediaContainer to parse.
    if (response.statusCode >= 400) {
      throw PlexClientException(
        'Could not start a library scan (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
  }

  /// Raw metadata for a single item, or null if the server no longer has it.
  ///
  /// Push notifications carry a ratingKey and a type, never the metadata, so
  /// this is what turns an event into something storable.
  ///
  /// A 404 becomes null — the item is genuinely gone. Every other failure
  /// throws, and that distinction matters: treating a timeout as "deleted"
  /// would let a network blip silently empty the cache.
  Future<Map<String, dynamic>?> metadataItem(String ratingKey) async {
    try {
      final container = await _getContainer('/library/metadata/$ratingKey');
      final items = _listOf(container, 'Metadata');
      return items.isEmpty ? null : items.first;
    } on PlexClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// One artist's albums, via the metadata children endpoint.
  Future<List<PlexAlbum>> albumsForArtist(String artistRatingKey) async {
    final container = await _getContainer(
      '/library/metadata/$artistRatingKey/children',
    );
    return _listOf(container, 'Metadata').map(PlexAlbum.fromJson).toList();
  }

  /// The hubs this server offers for a section.
  ///
  /// Diagnostic only. `includeStations=1` is what Plexamp sends and is the
  /// suspected source of its sonic rows; Plex drops query parameters it does
  /// not recognise rather than rejecting them (the same behaviour that let
  /// `updatedAt>=` do nothing for thirty-odd commits), so asking costs nothing
  /// on a server that has never heard of it.
  ///
  /// Returns empty rather than throwing. Nothing depends on this yet, and a
  /// server that will not answer it is itself the finding.
  Future<List<PlexHub>> sectionHubs(String sectionKey) async {
    try {
      final container = await _getContainer(
        '/hubs/sections/$sectionKey',
        query: {'includeStations': '1'},
      );
      return _listOf(container, 'Hub').map(PlexHub.fromJson).toList();
    } on Object {
      return const [];
    }
  }

  /// The server's own play history for a section, newest first.
  ///
  /// **Deliberately unfiltered by date.** A `viewedAt>` parameter would be the
  /// obvious thing to send and is exactly the shape Plex silently ignores; an
  /// ignored filter here would not error, it would quietly return the whole
  /// history and make every month look identical. Newest-first plus a bounded
  /// page is a filter the server cannot get wrong, and the caller cuts the
  /// window itself.
  ///
  /// Requires server-owner access. Returns empty for anyone else, and for any
  /// other failure, because a Home shelf must never be the thing that shows an
  /// error.
  Future<List<PlexPlay>> playHistory(
    String sectionKey, {
    int limit = 1000,
  }) async {
    try {
      return await playHistoryRaw(
        sectionKey: sectionKey,
        // See PlexPlay.type. Asking the server to do this returns an empty
        // history from a server that has one.
        tracksOnly: false,
        limit: limit,
      );
    } on Object {
      return const [];
    }
  }

  /// The same request, without the swallowing, and with each narrowing
  /// optional.
  ///
  /// **Exists because "no plays" and "asked wrongly" arrive identical.** The
  /// endpoint answered zero rows against a server with years of listening on
  /// it, and [playHistory] cannot say whether that was a refusal, a genuinely
  /// empty history, or one of its own query parameters being wrong. Every
  /// narrowing here is separately removable, so the probe can ask the same
  /// question several ways and report which of them the server answers.
  ///
  /// `type` is the leading suspect. It is the metadata type on a *section
  /// listing*, and nothing says the history endpoint means the same thing by
  /// it, or means anything by it at all.
  Future<List<PlexPlay>> playHistoryRaw({
    String? sectionKey,
    bool tracksOnly = true,
    String? accountId,
    int limit = 1000,
  }) async {
    final container = await _getContainer(
      '/status/sessions/history/all',
      query: {
        'librarySectionID': ?sectionKey,
        'sort': 'viewedAt:desc',
        // **Only the probe sets this, and only to prove it is fatal.** It is
        // how a section listing is narrowed to tracks and it returns nothing
        // at all from here: 200, empty container, no error. Rollup rows are
        // dropped after parsing instead, on `PlexPlay.isTrack`.
        if (tracksOnly) 'type': '$typeTrack',
        'accountID': ?accountId,
      },
      extraHeaders: {
        'X-Plex-Container-Start': '0',
        'X-Plex-Container-Size': '$limit',
      },
    );
    return _listOf(
      container,
      'Metadata',
    ).map(PlexPlay.fromJson).where((p) => p.viewedAt > 0 && p.isTrack).toList();
  }

  /// Audio playlists on the server.
  ///
  /// Not scoped to a library section — playlists live at the account level, so
  /// this is a separate sync pass from the section walk.
  Future<List<PlexPlaylist>> playlists() async {
    final container = await _getContainer(
      '/playlists',
      query: {'playlistType': 'audio'},
    );
    return _listOf(container, 'Metadata').map(PlexPlaylist.fromJson).toList();
  }

  /// Tracks in a playlist, in playlist order.
  ///
  /// Order is significant and must be preserved as given: playlists are
  /// arranged, not sorted.
  Future<List<PlexTrack>> playlistItems(String playlistRatingKey) async {
    final container = await _getContainer(
      '/playlists/$playlistRatingKey/items',
    );
    return _listOf(container, 'Metadata').map(PlexTrack.fromJson).toList();
  }

  /// Tracks on an album, in disc/track order as Plex returns them.
  Future<List<PlexTrack>> tracks(String albumRatingKey) async {
    final container = await _getContainer(
      '/library/metadata/$albumRatingKey/children',
    );
    return _listOf(container, 'Metadata').map(PlexTrack.fromJson).toList();
  }

  /// Any path on this server, unparsed, for [DiscoveryProbe].
  ///
  /// **The probe has to be able to ask questions the client does not know how
  /// to ask**, which is the whole point of having one: everything the typed
  /// methods do to make a response usable also destroys the evidence for why a
  /// response was not usable.
  ///
  /// Throws rather than swallowing, because which paths fail and how is the
  /// finding.
  Future<List<Map<String, dynamic>>> rawRows(
    String path, {
    Map<String, String>? query,
  }) async {
    final container = await _getContainer(path, query: query);
    return _listOf(container, 'Metadata');
  }

  /// Creates a server-side play queue from [sourceKey] and returns its tracks.
  ///
  /// **The only way to play one of Plex's own stations.** A station's key is a
  /// play queue source rather than a fetchable path, so `GET`ting it 404s; this
  /// hands the same key to `/playQueues` and plays whatever the server decides
  /// belongs in it.
  ///
  /// The `uri` is `server://{machineIdentifier}/com.plexapp.plugins.library` and
  /// then the key. The machine identifier is [PlexServer.clientIdentifier],
  /// which plex.tv already gave us during discovery — a server addressed by its
  /// own URL still has to be *named* in the source URI, because a play queue
  /// can in principle draw from more than one.
  ///
  /// Filtered to tracks on each row's declared type rather than by asking for
  /// one, for the reason every other call here gives.
  ///
  /// **Throws rather than returning empty**, unlike its neighbours. A station
  /// is something the user just pressed, so a failure has somewhere to go and
  /// saying nothing would be the third time this feature looked like a dead
  /// button.
  Future<List<PlexTrack>> playQueueTracks(String sourceKey) async {
    final container = await _postContainer(
      '/playQueues',
      query: {
        'type': 'audio',
        'uri':
            'server://${_server.clientIdentifier}'
            '/com.plexapp.plugins.library$sourceKey',
        'shuffle': '0',
        'repeat': '0',
        'continuous': '0',
      },
    );

    return [
      for (final row in _listOf(container, 'Metadata'))
        if (row['type'] == 'track') PlexTrack.fromJson(row),
    ];
  }

  /// Artists this server considers similar to [artistRatingKey].
  ///
  /// **The only sonic endpoint that answers.** Measured across eleven request
  /// shapes on 12 August 2026: `/nearest` returns an empty 200 for a track, an
  /// album and an artist alike; `/library/metadata/{key}/station/{n}` and
  /// `/library/sections/{id}/stations/{n}` all 404 even though the Stations hub
  /// publishes those exact keys. This one returned rows.
  ///
  /// **Which is why radio is per artist and not per track.** Plexamp greys its
  /// own sonic radio out on a song and offers it on an artist, and that is the
  /// same fact seen from the other side: the model this server holds relates
  /// artists to artists, and nothing relates one track to another.
  ///
  /// Filtered on each row's declared type rather than by asking for one, for
  /// the usual reason — Plex drops parameters it does not implement rather than
  /// rejecting them, so a filter that did nothing would be invisible.
  ///
  /// Returns empty rather than throwing. A server without the endpoint and a
  /// library with no similarity data are both ordinary states, and neither is
  /// worth an exception thrown through a tap handler.
  Future<List<PlexArtist>> similarArtists(String artistRatingKey) async {
    try {
      final container = await _getContainer(
        '/library/metadata/$artistRatingKey/similar',
      );
      return [
        for (final row in _listOf(container, 'Metadata'))
          if (row['type'] == 'artist') PlexArtist.fromJson(row),
      ];
    } on PlexClientException {
      return const [];
    }
  }

  /// A displayable artwork URL for a `thumb` path.
  ///
  /// Plex's thumb paths aren't directly fetchable — they must go through the
  /// photo transcoder, which also lets us request a sensible size instead of
  /// pulling full-resolution art into a list cell.
  /// **The `url` parameter is relative, and that is not cosmetic.** It used to
  /// be absolute — `{baseUrl}{thumb}` — which asks the server to fetch the
  /// image *from itself over the address this client happens to be using*. On
  /// the LAN that is harmless. Off it, the server is told to reach its own
  /// public address, which needs hairpin NAT, or its plex.tv relay address,
  /// which it has no business dialling at all. Either way the transcoder
  /// fails, and it fails the same way every time — so artwork for anything
  /// synced while away never appeared, and never appeared later either,
  /// because there was nothing transient about it.
  ///
  /// A relative path is resolved inside the server with no network hop, which
  /// is what Plex's own clients send.
  String? artworkUrl(String? thumb, {int width = 300, int height = 300}) {
    if (thumb == null || thumb.isEmpty) return null;
    final uri = Uri.parse('${_server.baseUrl}/photo/:/transcode').replace(
      queryParameters: {
        'width': '$width',
        'height': '$height',
        'minSize': '1',
        'upscale': '1',
        'url': thumb,
        'X-Plex-Token': _server.token,
      },
    );
    return uri.toString();
  }

  /// Direct-play URL for [track] — the original file, untouched.
  ///
  /// The token goes in the query string rather than a header because this URL
  /// is handed to the audio engine (ExoPlayer / libmpv), which does its own
  /// HTTP and won't carry our headers.
  ///
  /// Returns null for tracks with no playable part.
  String? directPlayUrl(PlexTrack track) => directPlayUrlFor(track.partKey);

  /// The same, from a bare part key.
  ///
  /// Separate because a queue rebuilt after the connection re-resolves has the
  /// part key but no longer has the [PlexTrack] it came from — and fetching one
  /// back is a network read at the exact moment the network has just failed.
  String? directPlayUrlFor(String? partKey) {
    if (partKey == null || partKey.isEmpty) return null;
    final uri = Uri.parse(
      '${_server.baseUrl}$partKey',
    ).replace(queryParameters: {'X-Plex-Token': _server.token});
    return uri.toString();
  }

  /// Progressive transcode URL for the track [ratingKey].
  ///
  /// `start.mp3` rather than `start.m3u8` deliberately. Both forms exist and
  /// both play, but `LockCachingAudioSource` caches progressive HTTP only —
  /// choosing HLS would mean transcoded playback could never be cached, which
  /// is precisely the listening (cellular, remote) that most needs it.
  ///
  /// `directPlay=0` and `directStream=0` force an actual transcode. Without
  /// them Plex is free to decide the original is fine and hand back the source
  /// file, so a bitrate cap can appear to work while doing nothing at all.
  ///
  /// [session] identifies the server-side transcode. It must be stable for the
  /// life of one playback — a new value mid-track starts a second transcode and
  /// abandons the first — and must be handed to [stopTranscodeSession] when
  /// playback ends.
  ///
  /// [bitrate] and [profile] are both live questions rather than preferences;
  /// see [TranscodeBitrateMechanism] and [TranscodeProfile]. Omitting
  /// [bitrate] asks for whatever the server produces unprompted, which is the
  /// only honest baseline to compare a cap against.
  String transcodeUrl(
    String ratingKey, {
    required String session,
    int? bitrateKbps,
    TranscodeBitrateMechanism? bitrate,
    TranscodeProfile? profile,
    Duration offset = Duration.zero,
  }) {
    final uri =
        Uri.parse(
          '${_server.baseUrl}/music/:/transcode/universal/start.mp3',
        ).replace(
          queryParameters: {
            'path': '/library/metadata/$ratingKey',
            'mediaIndex': '0',
            'partIndex': '0',
            'offset': '${offset.inSeconds}',
            'directPlay': '0',
            'directStream': '0',
            // Layered over the base so a profile can override the decision
            // flags as well as add to them.
            ...(profile ?? TranscodeProfile.identified).build(_identity),
            // Layered over the profile in turn: one mechanism expresses the
            // cap inside the device profile, so it must win over any profile
            // string already there.
            if (bitrate != null && bitrateKbps != null)
              ...bitrate.apply(bitrateKbps),
            'session': session,
            // Credentials go in the query string because this URL is handed to
            // the audio engine, which does its own HTTP and carries none of our
            // headers. Same reasoning as directPlayUrl.
            'X-Plex-Client-Identifier': _identity.clientIdentifier,
            'X-Plex-Token': _server.token,
          },
        );
    return uri.toString();
  }

  /// Tears down a server-side transcode session.
  ///
  /// Abandoned sessions do not stop promptly on their own: the server keeps
  /// transcoding into a buffer nobody is reading, and several of them at once
  /// is the difference between an idle NAS and a pegged one.
  ///
  /// The server's own account of the transcodes it is running.
  ///
  /// Worth having because the bytes only say what arrived, not what Plex
  /// believed it was asked for. When a request and its result disagree, this is
  /// the only thing that says which of the two the server misread.
  ///
  /// Returns an empty list rather than throwing — it is diagnostic, and a
  /// server that will not answer it is itself the finding.
  Future<List<Map<String, dynamic>>> transcodeSessions() async {
    try {
      final container = await _getContainer('/transcode/sessions');
      return _listOf(container, 'TranscodeSession');
    } on Object {
      return const [];
    }
  }

  /// Returns the status Plex answered with, or 0 if it could not be reached.
  /// The code rather than a bool because a refusal and an unreachable server
  /// are different problems, and the spike needs to tell them apart.
  ///
  /// Deliberately does not throw. This is called on the way out of playback,
  /// where there is nothing useful to do about a failure and an exception would
  /// only propagate into a teardown path.
  Future<int> stopTranscodeSession(String session) async {
    try {
      final uri = Uri.parse(
        '${_server.baseUrl}/music/:/transcode/universal/stop',
      ).replace(queryParameters: {'session': session});

      final response = await _http.get(
        uri,
        headers: _identity.headers(token: _server.token),
      );
      return response.statusCode;
    } on Object {
      return 0;
    }
  }

  // -------------------------------------------------------------------------

  Future<Map<String, dynamic>> _getContainer(
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) => _container('GET', path, query: query, extraHeaders: extraHeaders);

  /// `POST` with everything in the query string, which is how Plex takes it.
  ///
  /// No body: `/playQueues` reads its parameters off the URL exactly as a GET
  /// would, and sending them as a form gets an empty queue back rather than an
  /// error.
  Future<Map<String, dynamic>> _postContainer(
    String path, {
    Map<String, String>? query,
  }) => _container('POST', path, query: query);

  Future<Map<String, dynamic>> _container(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse(
      '${_server.baseUrl}$path',
    ).replace(queryParameters: query);

    final headers = {
      ..._identity.headers(token: _server.token),
      ...?extraHeaders,
    };
    final response = method == 'POST'
        ? await _http.post(uri, headers: headers)
        : await _http.get(uri, headers: headers);

    if (response.statusCode == 401) {
      throw const PlexClientException(
        'Plex rejected the token. You may need to sign in again.',
      );
    }
    if (response.statusCode != 200) {
      throw PlexClientException(
        'Plex request failed: $path (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw PlexClientException('Unexpected response shape from $path');
    }
    final container = decoded['MediaContainer'];
    if (container is! Map<String, dynamic>) {
      throw PlexClientException('No MediaContainer in response from $path');
    }
    return container;
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Plex omits list keys entirely when empty rather than returning `[]`, so an
  /// absent key is a normal empty result, not an error.
  static List<Map<String, dynamic>> _listOf(
    Map<String, dynamic> container,
    String key,
  ) {
    final raw = container[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList();
  }
}

class PlexClientException implements Exception {
  const PlexClientException(this.message, {this.statusCode});
  final String message;

  /// The HTTP status, when the failure came from a response rather than the
  /// transport. Callers distinguish 404 — the item is genuinely gone — from
  /// everything else, which is a reason to leave the cache alone.
  final int? statusCode;

  @override
  String toString() => message;
}
