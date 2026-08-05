import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_source.dart';

/// Enough of a track to rebuild it into a playable queue entry.
///
/// **No URL, deliberately** — the same trap as the artwork cache key and the
/// queue rebuild. A playback URL embeds the server address and the Plex token,
/// and both move: the address every time the connection re-races, the token
/// when it refreshes. A stored URL is reliably dead by the next launch, and
/// would fail in the least debuggable way possible — a queue that restores
/// looking perfect and will not play.
///
/// So the facts are stored and the URL is rebuilt, which also means quality is
/// decided fresh against whatever network the app has *now* rather than the
/// one it was closed on.
@immutable
class SavedTrack {
  const SavedTrack({
    required this.ratingKey,
    required this.title,
    this.album,
    this.artist,
    this.thumb,
    this.partKey,
    this.sourceKbps,
    this.durationMs,
    this.albumRatingKey,
  });

  final String ratingKey;
  final String title;
  final String? album;
  final String? artist;
  final String? thumb;
  final String? partKey;
  final int? sourceKbps;
  final int? durationMs;

  /// Kept so a restored queue can still offer the album as a destination.
  final String? albumRatingKey;

  Map<String, dynamic> toJson() => {
    'ratingKey': ratingKey,
    'title': title,
    if (album != null) 'album': album,
    if (artist != null) 'artist': artist,
    if (thumb != null) 'thumb': thumb,
    if (partKey != null) 'partKey': partKey,
    if (sourceKbps != null) 'sourceKbps': sourceKbps,
    if (durationMs != null) 'durationMs': durationMs,
    if (albumRatingKey != null) 'albumRatingKey': albumRatingKey,
  };

  static SavedTrack? fromJson(Object? json) {
    if (json is! Map) return null;
    final ratingKey = json['ratingKey'];
    final title = json['title'];
    if (ratingKey is! String || title is! String) return null;
    return SavedTrack(
      ratingKey: ratingKey,
      title: title,
      album: json['album'] as String?,
      artist: json['artist'] as String?,
      thumb: json['thumb'] as String?,
      partKey: json['partKey'] as String?,
      sourceKbps: json['sourceKbps'] as int?,
      durationMs: json['durationMs'] as int?,
      albumRatingKey: json['albumRatingKey'] as String?,
    );
  }
}

/// A queue, where it had got to, and what it was started from.
@immutable
class SavedPlayback {
  const SavedPlayback({
    required this.tracks,
    required this.index,
    required this.position,
    this.source,
  });

  final List<SavedTrack> tracks;
  final int index;
  final Duration position;
  final PlaybackSource? source;

  bool get isEmpty => tracks.isEmpty;

  Map<String, dynamic> toJson() => {
    'tracks': [for (final t in tracks) t.toJson()],
    'index': index,
    'positionMs': position.inMilliseconds,
    if (source != null) 'source': source!.encode(),
  };

  static SavedPlayback? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawTracks = json['tracks'];
    if (rawTracks is! List) return null;

    final tracks = <SavedTrack>[];
    for (final raw in rawTracks) {
      final track = SavedTrack.fromJson(raw);
      // One unreadable entry drops that track rather than the session. A
      // shorter queue is a far better outcome than losing the lot to a field
      // added in a later version.
      if (track != null) tracks.add(track);
    }
    if (tracks.isEmpty) return null;

    final index = json['index'];
    final positionMs = json['positionMs'];
    return SavedPlayback(
      tracks: tracks,
      index: index is int ? index.clamp(0, tracks.length - 1) : 0,
      position: Duration(milliseconds: positionMs is int ? positionMs : 0),
      source: PlaybackSource.decode(json['source']),
    );
  }
}

/// Where the last session is kept between launches.
///
/// `shared_preferences` rather than drift, for the same reason settings live
/// there: this must be readable before the library cache is open and must
/// survive the cache being wiped. Signing out clears the library; the queue
/// that goes with it is cleared explicitly, not incidentally.
class PlaybackStateStore {
  @visibleForTesting
  const PlaybackStateStore(this._prefs);

  static Future<PlaybackStateStore> load() async =>
      PlaybackStateStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _key = 'playback_last_session';

  /// Null when there is nothing to restore, or when what is stored can no
  /// longer be read. A session that will not parse is not worth an error on
  /// the launch path — the app opens with no queue, exactly as it used to.
  SavedPlayback? read() {
    final stored = _prefs.getString(_key);
    if (stored == null) return null;
    try {
      return SavedPlayback.fromJson(jsonDecode(stored));
    } on Object {
      return null;
    }
  }

  Future<void> write(SavedPlayback state) async {
    if (state.isEmpty) return clear();
    await _prefs.setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> clear() => _prefs.remove(_key);
}
