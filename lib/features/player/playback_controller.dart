import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/audio/notification_permission.dart';
import '../../core/audio/playback_handler.dart';
import '../../core/audio/quality_policy.dart';
import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';

/// Turns Plex tracks into something the audio engine can play.
///
/// This is the only place that knows how to get from a [PlexTrack] to a
/// playable URL, which keeps the URL-building decision — direct play or
/// transcode, per [QualityPolicy] — in one spot.
class PlaybackController {
  PlaybackController({
    required PlexifyAudioHandler handler,
    required PlexClient client,
    QualityPolicy quality = const QualityPolicy(),
    Future<List<ConnectivityResult>> Function()? checkConnectivity,
    String Function() newSession = _defaultSession,
  }) : _handler = handler,
       _client = client,
       _quality = quality,
       _checkConnectivity =
           checkConnectivity ?? Connectivity().checkConnectivity,
       _newSession = newSession {
    // The handler knows a track is transcoded but not how to rebuild its URL,
    // which is this class's job and nobody else's.
    _handler.resolveSeekUrl = _seekUrl;
  }

  final PlexifyAudioHandler _handler;
  final PlexClient _client;
  final QualityPolicy _quality;
  final Future<List<ConnectivityResult>> Function() _checkConnectivity;
  final String Function() _newSession;

  static String _defaultSession() => const Uuid().v4();

  /// Transcode sessions this controller has opened and not yet torn down.
  ///
  /// Plex does not stop these on its own — see
  /// `PlexClient.stopTranscodeSession` — so whatever opens one must also
  /// close it, or the server keeps transcoding into a buffer nobody is
  /// reading. Replacing the queue is where the previous batch's sessions
  /// become unreachable, so that is where they are torn down.
  final _openSessions = <String>{};

  /// Replaces the queue with [tracks] and starts at [startIndex].
  ///
  /// Unplayable tracks are dropped rather than left as gaps that would stall
  /// the queue, so [startIndex] is remapped onto the filtered list.
  ///
  /// Quality is decided once for the whole batch, not re-evaluated per track
  /// as playback advances — connectivity read here is what the entire queue
  /// plays under, and a change mid-queue takes effect on the *next* call to
  /// this method, never mid-track.
  Future<void> playTracks(List<PlexTrack> tracks, {int startIndex = 0}) async {
    // Ask for notification permission at the moment its purpose is obvious.
    // Never gates playback — see NotificationPermission.
    await NotificationPermission.ensure();

    final playable = <PlexTrack>[];
    var adjustedStart = 0;

    for (var i = 0; i < tracks.length; i++) {
      if (!tracks[i].isPlayable) continue;
      if (i <= startIndex) adjustedStart = playable.length;
      playable.add(tracks[i]);
    }

    if (playable.isEmpty) return;

    final connectivity = await _checkConnectivity();

    final outgoingSessions = _openSessions.toList();
    _openSessions.clear();

    final items = <MediaItem>[];
    for (final track in playable) {
      final item = _toMediaItem(track, connectivity);
      if (item != null) items.add(item);
    }

    if (items.isEmpty) return;

    await _handler.setQueueAndPlay(items, initialIndex: adjustedStart);

    for (final session in outgoingSessions) {
      unawaited(_client.stopTranscodeSession(session));
    }
  }

  MediaItem? _toMediaItem(
    PlexTrack track,
    List<ConnectivityResult> connectivity,
  ) {
    final decision = _quality.decide(
      connectivity: connectivity,
      server: _client.server,
      sourceKbps: track.sourceKbps,
    );

    String? url;
    String? session;
    if (decision.isTranscode) {
      session = _newSession();
      _openSessions.add(session);
      url = _client.transcodeUrl(track.ratingKey, session: session);
    } else {
      url = _client.directPlayUrl(track);
    }
    if (url == null) return null;

    final art = _client.artworkUrl(track.thumb, width: 600, height: 600);

    return MediaItem(
      // audio_service uses id as the playback URL.
      id: url,
      title: track.title,
      album: track.album,
      artist: track.artist,
      duration: track.duration,
      artUri: art == null ? null : Uri.parse(art),
      extras: {
        // Kept around because scrobbling needs it and the URL can't be
        // reversed back into a ratingKey.
        'ratingKey': track.ratingKey,
        // #24's cache key: (ratingKey, qualityDecision). A copy transcoded
        // for cellular must never be served forever once back on the LAN,
        // which is what keying on ratingKey alone would do.
        'qualityDecision': decision.name,
        'transcodeSession': ?session,
      },
    );
  }

  /// The same transcode, restarted at [offset].
  ///
  /// Reuses the session the track is already playing under rather than opening
  /// a new one — Plex replaces the stream for a session it knows, where a
  /// fresh id would leave the old transcode running for nobody.
  Future<String?> _seekUrl(MediaItem item, Duration offset) async {
    final ratingKey = item.extras?['ratingKey'] as String?;
    final session = item.extras?['transcodeSession'] as String?;
    if (ratingKey == null || session == null) return null;
    return _client.transcodeUrl(ratingKey, session: session, offset: offset);
  }

  /// Stops every transcode session this controller still has open.
  ///
  /// Called when the connection this controller belongs to goes away — see
  /// [playbackControllerProvider] — so signing out or switching servers
  /// doesn't leave the old one transcoding for nobody.
  void disposeSessions() {
    // The handler outlives this controller, so a resolver left behind would
    // rebuild seek URLs against a server this app is no longer signed in to.
    if (_handler.resolveSeekUrl == _seekUrl) _handler.resolveSeekUrl = null;
    for (final session in _openSessions) {
      unawaited(_client.stopTranscodeSession(session));
    }
    _openSessions.clear();
  }
}

/// Null until a server connection exists.
final playbackControllerProvider = Provider<PlaybackController?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  final controller = PlaybackController(
    handler: ref.watch(audioHandlerProvider),
    client: client,
  );
  ref.onDispose(controller.disposeSessions);
  return controller;
});
