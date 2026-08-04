import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/playback_handler.dart';
import '../../core/plex/plex_client.dart';
import '../../core/plex/plex_models.dart';
import '../../core/providers.dart';

/// Turns Plex tracks into something the audio engine can play.
///
/// This is the only place that knows how to get from a [PlexTrack] to a
/// playable URL, which keeps the URL-building decision (direct play now,
/// adaptive transcoding in Phase 3) in one spot.
class PlaybackController {
  PlaybackController({
    required PlexifyAudioHandler handler,
    required PlexClient client,
  }) : _handler = handler,
       _client = client;

  final PlexifyAudioHandler _handler;
  final PlexClient _client;

  /// Replaces the queue with [tracks] and starts at [startIndex].
  ///
  /// Unplayable tracks are dropped rather than left as gaps that would stall
  /// the queue, so [startIndex] is remapped onto the filtered list.
  Future<void> playTracks(List<PlexTrack> tracks, {int startIndex = 0}) async {
    final playable = <PlexTrack>[];
    var adjustedStart = 0;

    for (var i = 0; i < tracks.length; i++) {
      if (!tracks[i].isPlayable) continue;
      if (i <= startIndex) adjustedStart = playable.length;
      playable.add(tracks[i]);
    }

    if (playable.isEmpty) return;

    final items = <MediaItem>[];
    for (final track in playable) {
      final item = _toMediaItem(track);
      if (item != null) items.add(item);
    }

    await _handler.setQueueAndPlay(items, initialIndex: adjustedStart);
  }

  /// Phase 1 direct-plays the original file. Phase 3 replaces this with the
  /// adaptive quality policy — and when it does, the cache key must become
  /// `(ratingKey, qualityDecision)`, not just the ratingKey, or a copy
  /// transcoded for cellular will be served forever once back on the LAN.
  MediaItem? _toMediaItem(PlexTrack track) {
    final url = _client.directPlayUrl(track);
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
      // Keep the Plex identity around; scrobbling in Phase 3 needs it, and the
      // URL can't be reversed back into a ratingKey.
      extras: {'ratingKey': track.ratingKey},
    );
  }
}

/// Null until a server connection exists.
final playbackControllerProvider = Provider<PlaybackController?>((ref) {
  final client = ref.watch(plexClientProvider);
  if (client == null) return null;
  return PlaybackController(
    handler: ref.watch(audioHandlerProvider),
    client: client,
  );
});
